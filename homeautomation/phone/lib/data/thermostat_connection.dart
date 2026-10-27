import '../models/json_utils.dart';
import '../models/set_values.dart';
import '../models/thermostat_config.dart';
import '../models/thermostat_state.dart';

/// Którą drogą idą dane - pokazywane w UI.
enum ConnectionKind {
  local('Lokalnie'),
  cloud('Chmura');

  const ConnectionKind(this.label);

  final String label;
}

/// Stan łącza w ramach wybranej drogi.
enum LinkStatus {
  /// Pierwsze połączenie w toku.
  connecting,

  /// Dane płyną na żywo.
  online,

  /// Łącze zerwane, trwa ponawianie.
  reconnecting,

  /// Chmura działa, ale termostat dawno się nie odezwał (`lastSeen` > 3 min).
  offline,

  /// Urządzenie odrzuciło token.
  unauthorized,

  /// Połączenie zamknięte.
  closed,
}

/// Wspólny interfejs połączenia z urządzeniem: lokalnie (HTTP + WebSocket)
/// albo przez chmurę (Firebase Realtime Database). [S]/[C] to State/Config danego typu.
abstract class DeviceConnection<S, C> {
  ConnectionKind get kind;

  String get deviceId;

  /// Opis drogi do UI, np. `192.168.1.20` albo `Firebase`.
  String get routeDescription;

  /// Ostatnio otrzymany stan / konfiguracja (null przed pierwszym odczytem).
  S? get state;
  C? get config;
  LinkStatus get status;

  Stream<S> get states;
  Stream<C> get configs;
  Stream<LinkStatus> get statuses;

  /// Nawiązuje połączenie i pobiera pierwszy stan oraz konfigurację.
  /// Rzuca [ThermostatException] (w tym [UnauthorizedException]).
  Future<void> open();

  /// Wysyła zmianę (dowolny podzbiór pól Set danego typu). Błędne pola wracają w [SetResult.errors].
  Future<SetResult> sendSet(Json values);

  /// Opis punktów danych (pkt 14): lokalnie `GET /api/describe`, w chmurze `devices/{id}/describe`.
  Future<Json?> describeJson();

  Future<void> close();
}

typedef ThermostatConnection = DeviceConnection<ThermostatState, ThermostatConfig>;

extension ThermostatConnectionSet on DeviceConnection<ThermostatState, ThermostatConfig> {
  Future<SetResult> set(SetValues values) => sendSet(values.toJson());
}
