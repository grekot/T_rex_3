import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/device_type.dart';
import '../models/json_utils.dart';
import '../models/set_values.dart';
import 'errors.dart';
import 'local_api.dart';
import 'local_endpoint.dart';
import 'thermostat_connection.dart';

typedef WebSocketConnector = WebSocketChannel Function(Uri uri);

/// Połączenie w sieci lokalnej: HTTP (`Authorization: Bearer`) do odczytu
/// i jako zapas, WebSocket `/ws?token=` do stanu na żywo i wysyłania `set`.
class LocalConnection<S, C> implements DeviceConnection<S, C> {
  LocalConnection({
    required this.deviceId,
    required this.endpoint,
    required String token,
    required this.codec,
    http.Client? client,
    WebSocketConnector? connector,
    this.ackTimeout = const Duration(seconds: 5),
  }) : _token = token,
       _api = LocalApi(endpoint, token: token, client: client),
       _connector = connector ?? WebSocketChannel.connect;

  @override
  final String deviceId;
  final LocalEndpoint endpoint;
  final DeviceCodec<S, C> codec;
  final Duration ackTimeout;

  final String _token;
  final LocalApi _api;
  final WebSocketConnector _connector;

  final _states = StreamController<S>.broadcast();
  final _configs = StreamController<C>.broadcast();
  final _statuses = StreamController<LinkStatus>.broadcast();

  S? _state;
  C? _config;
  LinkStatus _status = LinkStatus.connecting;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _closed = false;

  int _nextId = 1;
  final _pending = <int, Completer<SetResult>>{};

  @override
  ConnectionKind get kind => ConnectionKind.local;

  @override
  String get routeDescription => endpoint.display;

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

  bool get _wsOpen => _channel != null && _status == LinkStatus.online;

  @override
  Future<void> open() async {
    _setStatus(LinkStatus.connecting);
    await _refreshOverHttp();
    await _connectWebSocket();
  }

  Future<void> _refreshOverHttp() async {
    try {
      final results = await Future.wait([_api.stateJson(), _api.configJson()]);
      _emitState(codec.state(results[0]));
      _emitConfig(codec.config(results[1]));
    } on UnauthorizedException {
      _setStatus(LinkStatus.unauthorized);
      rethrow;
    }
  }

  Future<void> _connectWebSocket() async {
    final channel = _connector(endpoint.ws('/ws', {'token': _token}));
    try {
      await channel.ready.timeout(const Duration(seconds: 5));
    } catch (_) {
      unawaited(channel.sink.close().catchError((_) {}));
      _scheduleReconnect();
      return;
    }
    if (_closed) {
      await channel.sink.close();
      return;
    }
    _channel = channel;
    _reconnectAttempt = 0;
    _sub = channel.stream.listen(
      _onMessage,
      onError: (_) => _onSocketClosed(channel),
      onDone: () => _onSocketClosed(channel),
      cancelOnError: true,
    );
    _setStatus(LinkStatus.online);
  }

  void _onSocketClosed(WebSocketChannel channel) {
    if (_channel != channel) return;
    _channel = null;
    _sub = null;
    _failPending();
    if (!_closed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _status == LinkStatus.unauthorized) return;
    _setStatus(LinkStatus.reconnecting);
    _reconnectTimer?.cancel();
    final seconds = [1, 2, 4, 8, 15][_reconnectAttempt.clamp(0, 4)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      if (_closed) return;
      try {
        // HTTP najpierw: wykrywa zły token (WebSocket nie podaje kodu 401)
        // i odświeża stan, gdyby gniazdo nie wstało.
        await _refreshOverHttp();
      } on UnauthorizedException {
        return;
      } on ThermostatException {
        _scheduleReconnect();
        return;
      }
      await _connectWebSocket();
    });
  }

  void _onMessage(dynamic raw) {
    final Json msg;
    try {
      final decoded = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } on FormatException {
      return;
    }
    try {
      switch (msg['type']) {
        case 'state':
          _emitState(codec.state(asObjectOrNull(msg['data'], 'data') ?? const {}));
        case 'config':
          _emitConfig(codec.config(asObjectOrNull(msg['data'], 'data') ?? const {}));
        case 'ack':
          final id = asIntOrNull(msg['id'], 'id');
          _pending.remove(id)?.complete(SetResult.fromJson(msg));
      }
    } on FormatException {
      // Pojedyncza zła wiadomość nie zrywa połączenia.
    }
  }

  /// Łączy urządzenie z chmurą jego własnym kontem (tylko w sieci lokalnej, pkt 8.2). Zwraca `deviceUid`.
  Future<String> linkCloud({
    required String apiKey,
    required String dbUrl,
    required String homeId,
    required Future<void> Function(String deviceUid) bind,
    void Function(CloudLinkStatus status)? onStatus,
  }) => _api.cloud(apiKey: apiKey, dbUrl: dbUrl, homeId: homeId, bind: bind, onStatus: onStatus);

  Future<CloudLinkStatus> cloudStatus() => _api.cloudStatus();

  /// Klient HTTP tego połączenia (OTA, /api/info).
  LocalApi get api => _api;

  Future<void> unlinkCloud() => _api.cloudDisconnect();

  @override
  Future<Json?> describeJson() async => (await _api.describeJson());

  @override
  Future<SetResult> sendSet(Json values) async {
    if (values.isEmpty) return const SetResult(ok: true);
    if (_wsOpen) {
      final id = _nextId++;
      final completer = Completer<SetResult>();
      _pending[id] = completer;
      try {
        _channel!.sink.add(jsonEncode({'type': 'set', 'id': id, 'values': values}));
        return await completer.future.timeout(ackTimeout);
      } on TimeoutException {
        _pending.remove(id);
        // Brak ack - powtarzamy przez HTTP. Set jest idempotentny (wartości bezwzględne).
      } on _SocketGone {
        // Gniazdo padło w trakcie - j.w.
      }
    }
    final result = await _api.setJson(values);
    if (result.stateJson != null) _emitState(codec.state(result.stateJson!));
    if (result.configJson != null) _emitConfig(codec.config(result.configJson!));
    if (result.stateJson == null && !_wsOpen) {
      // Odpowiedź z błędami nie niesie stanu, a poprawne pola zostały zastosowane.
      await _refreshOverHttp().catchError((_) {});
    }
    return result;
  }

  void _failPending() {
    for (final c in _pending.values) {
      c.completeError(const _SocketGone());
    }
    _pending.clear();
  }

  void _emitState(S s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  void _emitConfig(C c) {
    _config = c;
    if (!_configs.isClosed) _configs.add(c);
  }

  void _setStatus(LinkStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }

  @override
  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    _failPending();
    await _sub?.cancel();
    await _channel?.sink.close().catchError((_) {});
    _channel = null;
    _setStatus(LinkStatus.closed);
    _api.close();
    await Future.wait([_states.close(), _configs.close(), _statuses.close()]);
  }
}

class _SocketGone implements Exception {
  const _SocketGone();
}
