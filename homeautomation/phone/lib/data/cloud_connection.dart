import 'dart:async';

import '../models/device_type.dart';
import '../models/json_utils.dart';
import '../models/set_values.dart';
import 'cloud_store.dart';
import 'errors.dart';
import 'thermostat_connection.dart';

/// Termostat uznajemy za offline, gdy `lastSeen` jest starsze (kontrakt pkt 8.1).
const cloudOfflineAfter = Duration(minutes: 3);

/// Ścieżka urządzenia w Realtime Database: `homes/{homeId}/devices/{deviceId}` (pkt 8.1).
String cloudDevicePath(String homeId, String deviceId) => 'homes/$homeId/devices/$deviceId';

/// Polecenia leżą poza `devices/{id}`: `commands/{homeId}/{deviceId}/{push}` (pkt 8.1).
String cloudCommandsPath(String homeId, String deviceId) => 'commands/$homeId/$deviceId';

/// Połączenie przez Firebase Realtime Database (pkt 8 kontraktu):
/// `state`/`config` na żywo, polecenia przez push do `commands`, wynik z `lastCommand`,
/// stan łącza z `lastSeen` (termostat pisze co 60 s).
class CloudConnection<S, C> implements DeviceConnection<S, C> {
  CloudConnection({
    required this.store,
    required this.homeId,
    required this.by,
    required this.deviceId,
    required this.codec,
    this.openTimeout = const Duration(seconds: 15),
    this.commandTimeout = const Duration(seconds: 20),
    this.offlineAfter = cloudOfflineAfter,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CloudStore store;
  final String homeId;

  /// uid autora poleceń - reguły wymagają `by == auth.uid` (pkt 12).
  final String by;
  @override
  final String deviceId;
  final DeviceCodec<S, C> codec;
  final Duration openTimeout;
  final Duration commandTimeout;
  final Duration offlineAfter;
  final DateTime Function() _clock;

  String get _base => cloudDevicePath(homeId, deviceId);

  final _states = StreamController<S>.broadcast();
  final _configs = StreamController<C>.broadcast();
  final _statuses = StreamController<LinkStatus>.broadcast();
  final _commands = StreamController<Json>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _ticker;

  S? _state;
  C? _config;
  int? _lastSeenMs;
  LinkStatus _status = LinkStatus.connecting;
  bool _closed = false;

  @override
  ConnectionKind get kind => ConnectionKind.cloud;

  @override
  String get routeDescription => 'Firebase';

  @override
  S? get state => _state;

  @override
  C? get config => _config;

  @override
  LinkStatus get status => _status;

  /// Kiedy termostat ostatnio dał znak życia (null = nigdy).
  DateTime? get lastSeen => _lastSeenMs == null ? null : DateTime.fromMillisecondsSinceEpoch(_lastSeenMs!);

  @override
  Stream<S> get states => _states.stream;

  @override
  Stream<C> get configs => _configs.stream;

  @override
  Stream<LinkStatus> get statuses => _statuses.stream;

  @override
  Future<void> open() async {
    final firstState = Completer<void>();
    final firstConfig = Completer<void>();

    void fail(Object e) {
      for (final c in [firstState, firstConfig]) {
        if (!c.isCompleted) c.completeError(e);
      }
    }

    _subs
      ..add(
        store.watch('$_base/state').listen((v) {
          final j = toJsonObject(v);
          if (j == null) {
            if (!firstState.isCompleted) firstState.completeError(_notLinked());
            return;
          }
          try {
            final s = codec.state(j);
            _state = s;
            _states.add(s);
            if (!firstState.isCompleted) firstState.complete();
          } on FormatException catch (e) {
            if (!firstState.isCompleted) {
              firstState.completeError(ThermostatException('Zły stan w chmurze: ${e.message}'));
            }
          }
        }, onError: fail),
      )
      ..add(
        store.watch('$_base/config').listen((v) {
          final j = toJsonObject(v);
          if (j == null) {
            if (!firstConfig.isCompleted) firstConfig.completeError(_notLinked());
            return;
          }
          try {
            final c = codec.config(j);
            _config = c;
            _configs.add(c);
            if (!firstConfig.isCompleted) firstConfig.complete();
          } on FormatException catch (e) {
            if (!firstConfig.isCompleted) {
              firstConfig.completeError(ThermostatException('Zła konfiguracja w chmurze: ${e.message}'));
            }
          }
        }, onError: fail),
      )
      ..add(
        store.watch('$_base/lastSeen').listen((v) {
          _lastSeenMs = v is num ? v.toInt() : null;
          _updateStatus();
        }, onError: (_) {}),
      )
      ..add(
        store.watch('$_base/lastCommand').listen((v) {
          final j = toJsonObject(v);
          if (j != null) _commands.add(j);
        }, onError: (_) {}),
      );

    try {
      await Future.wait([firstState.future, firstConfig.future]).timeout(openTimeout);
    } on TimeoutException {
      await close();
      throw const NoRouteException('Brak odpowiedzi z chmury. Sprawdź połączenie z internetem.');
    } on Object catch (e) {
      await close();
      if (e is ThermostatException) rethrow;
      throw NoRouteException('Błąd chmury: $e');
    }
    _updateStatus();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _updateStatus());
  }

  ThermostatException _notLinked() => const NoRouteException(
    'Urządzenie nie wysyła danych do chmury. W sieci domowej otwórz jego ustawienia → Chmura i połącz je z kontem.',
  );

  void _updateStatus() {
    if (_closed) return;
    final seen = _lastSeenMs;
    final online = seen != null && _clock().millisecondsSinceEpoch - seen <= offlineAfter.inMilliseconds;
    final s = online ? LinkStatus.online : LinkStatus.offline;
    if (s == _status) return;
    _status = s;
    _statuses.add(s);
  }

  @override
  Future<Json?> describeJson() async => toJsonObject(await store.read('$_base/describe'));

  /// Push do `commands`, potem czekamy na `lastCommand` z tym samym kluczem.
  /// Bez potwierdzenia w [commandTimeout] zwracamy `error: "timeout"` - polecenie zostaje
  /// w chmurze i termostat wykona je, jeśli odezwie się w ciągu 10 min.
  @override
  Future<SetResult> sendSet(Json values) async {
    if (values.isEmpty) return const SetResult(ok: true);
    // Słuchamy przed wysłaniem, żeby nie przegapić szybkiej odpowiedzi.
    final pending = <Json>[];
    final sub = _commands.stream.listen(pending.add);
    try {
      final key = await store.push(cloudCommandsPath(homeId, deviceId), {
        'values': values,
        'ts': serverTimestamp,
        'by': by,
      });
      bool matches(Json j) => j['key'] == key;
      final early = pending.where(matches);
      final answer = early.isNotEmpty
          ? early.first
          : await _commands.stream.firstWhere(matches).timeout(commandTimeout);
      return SetResult.fromJson(answer);
    } on TimeoutException {
      return const SetResult(ok: false, error: 'timeout');
    } on StateError {
      return const SetResult(ok: false, error: 'timeout');
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ticker?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _status = LinkStatus.closed;
    await Future.wait([_states.close(), _configs.close(), _statuses.close(), _commands.close()]);
  }
}
