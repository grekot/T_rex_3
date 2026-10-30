import 'dart:async';
import 'dart:convert';

import '../models/device_type.dart';
import '../models/home.dart';
import '../models/hub.dart';
import '../models/json_utils.dart';
import '../models/set_values.dart';
import 'errors.dart';
import 'hub_api.dart';
import 'local_api.dart';
import 'thermostat_connection.dart';

/// Wspólne dla wszystkich urządzeń podrzędnych odpytywanie huba: jedno `GET /api/devices` zamiast
/// żądania na urządzenie (hub ma 16 gniazd, ARCHITEKTURA pkt 4.3).
class HubLink {
  HubLink({required this.hubId, required LocalApi api, this.interval = const Duration(seconds: 3), this.onIdle})
    : _local = api,
      api = HubApi(api);

  final String hubId;
  final HubApi api;
  final Duration interval;

  /// Nikt już nie korzysta - menedżer zapomina to łącze.
  final void Function()? onIdle;

  final LocalApi _local;
  final _updates = StreamController<List<HubChild>?>.broadcast();
  Timer? _timer;
  int _users = 0;
  bool _polling = false;

  /// Lista urządzeń po każdym odpytaniu; null = hub nie odpowiada.
  Stream<List<HubChild>?> get updates => _updates.stream;

  void retain() {
    if (_users++ == 0) _timer = Timer.periodic(interval, (_) => pollNow());
  }

  void release() {
    if (--_users > 0) return;
    _timer?.cancel();
    onIdle?.call();
    _local.close();
    _updates.close();
  }

  Future<void> pollNow() async {
    if (_polling) return;
    _polling = true;
    try {
      final list = await api.devices();
      if (!_updates.isClosed) _updates.add(list);
    } on Object {
      if (!_updates.isClosed) _updates.add(null);
    } finally {
      _polling = false;
    }
  }
}

/// Urządzenie podrzędne w sieci domowej, przez lokalne API huba (kontrakt pkt 11).
/// Bez WebSocketu: stan z [HubLink] co kilka sekund, po poleceniu od razu z odpowiedzi huba.
class HubChildConnection<S, C> implements DeviceConnection<S, C> {
  HubChildConnection({required this.deviceId, required this.link, required this.codec, required this.hubHost}) {
    link.retain();
  }

  @override
  final String deviceId;
  final HubLink link;
  final DeviceCodec<S, C> codec;
  final String hubHost;

  final _states = StreamController<S>.broadcast();
  final _configs = StreamController<C>.broadcast();
  final _statuses = StreamController<LinkStatus>.broadcast();
  StreamSubscription<List<HubChild>?>? _sub;

  S? _state;
  C? _config;
  String? _stateRaw;
  String? _name;
  LinkStatus _status = LinkStatus.connecting;
  bool _closed = false;

  String get _base => '/api/devices/$deviceId';

  @override
  ConnectionKind get kind => ConnectionKind.local;

  @override
  String get routeDescription => 'przez hub $hubHost';

  @override
  S? get state => _state;

  @override
  C? get config => _config;

  @override
  LinkStatus get status => _status;

  @override
  Stream<S> get states => _states.stream;

  @override
  Stream<C> get configs => _configs.stream;

  @override
  Stream<LinkStatus> get statuses => _statuses.stream;

  /// `404` (hub bez tego urządzenia albo ze starszym firmware bez `/config`) to [NoRouteException] - zostaje chmura.
  Future<Json> _get(String path) async {
    final v = await link.api.api.request('GET', path);
    if (v is! Map || v['ok'] == false) throw NoRouteException('Hub nie zna urządzenia $deviceId.');
    return v.cast<String, dynamic>();
  }

  @override
  Future<void> open() async {
    final results = await Future.wait([_get('$_base/state'), _get('$_base/config')]);
    _emitState(results[0]);
    _emitConfig(results[1]);
    _setStatus(results[0]['online'] == false ? LinkStatus.offline : LinkStatus.online);
    _sub = link.updates.listen(_onUpdate);
  }

  void _onUpdate(List<HubChild>? list) {
    if (list == null) {
      _setStatus(LinkStatus.reconnecting);
      return;
    }
    final c = list.where((x) => x.id == deviceId).firstOrNull;
    if (c == null) {
      _setStatus(LinkStatus.offline);
      return;
    }
    _emitState({...c.state, 'id': deviceId, 'online': c.online, 'error': ?c.error});
    _setStatus(c.online ? LinkStatus.online : LinkStatus.offline);
    if (_name != null && c.name != null && c.name != _name) unawaited(_refreshConfig());
  }

  Future<void> _refreshConfig() async {
    try {
      _emitConfig(await _get('$_base/config'));
    } on ThermostatException {
      // Następna zmiana albo połączenie pobierze ją znów.
    }
  }

  @override
  Future<Json?> describeJson() async {
    try {
      return await _get('$_base/describe');
    } on NoRouteException {
      return null;
    }
  }

  @override
  Future<SetResult> sendSet(Json values) async {
    if (values.isEmpty) return const SetResult(ok: true);
    final r = await link.api.setDevice(deviceId, values);
    final state = r.state;
    if (state != null) {
      _emitState(state);
    } else if (r.pending) {
      unawaited(link.pollNow());
    }
    if (!values.keys.every(isControlKey)) unawaited(_refreshConfig());
    return SetResult(ok: r.ok, errors: r.errors, stateJson: state);
  }

  void _emitState(Json j) {
    if (_closed) return;
    final raw = jsonEncode({...j}..removeWhere((k, _) => k == 'ts' || k == 'cloud'));
    if (raw == _stateRaw) return;
    try {
      final s = codec.state(j);
      _stateRaw = raw;
      _state = s;
      _states.add(s);
    } on FormatException {
      // Pojedynczy zły stan nie zrywa połączenia.
    }
  }

  void _emitConfig(Json j) {
    if (_closed) return;
    final c = codec.config(j);
    _name = codec.nameOf(c);
    _config = c;
    _configs.add(c);
  }

  void _setStatus(LinkStatus s) {
    if (_status == s || _closed) return;
    _status = s;
    _statuses.add(s);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _status = LinkStatus.closed;
    await _sub?.cancel();
    link.release();
    await Future.wait([_states.close(), _configs.close(), _statuses.close()]);
  }
}
