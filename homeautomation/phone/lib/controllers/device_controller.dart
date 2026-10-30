import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/connection_manager.dart';
import '../data/device_store.dart';
import '../data/errors.dart';
import '../data/local_api.dart';
import '../data/local_connection.dart';
import '../data/thermostat_connection.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import '../models/set_values.dart';
import 'field_errors.dart';

enum ConnectPhase { connecting, connected, failed }

/// Wspólna część ekranów i kafelków dowolnego urządzenia: wybór drogi (lokalnie → chmura),
/// dane na żywo, wysyłanie Set, chmura, OTA i zmiana sieci WiFi.
class DeviceController<S, C> extends ChangeNotifier {
  DeviceController({required PairedDevice device, required this.manager, required this.codec}) : _device = device;

  final ConnectionManager manager;
  final DeviceCodec<S, C> codec;

  PairedDevice _device;
  DeviceConnection<S, C>? _connection;
  final _subs = <StreamSubscription<dynamic>>[];

  ConnectPhase _phase = ConnectPhase.connecting;
  String? _step;
  String? _error;
  bool _needsPairing = false;
  String? _lastSendError;
  bool _disposed = false;
  int _generation = 0;

  PairedDevice get device => _device;
  DeviceConnection<S, C>? get connection => _connection;
  ConnectPhase get phase => _phase;

  /// Bieżący krok łączenia („Szukanie w sieci…”).
  String? get step => _step;

  /// Dlaczego nie udało się połączyć.
  String? get error => _error;

  /// Urządzenie odrzuciło token albo go nie mamy - trzeba sparować.
  bool get needsPairing => _needsPairing || _connection?.status == LinkStatus.unauthorized;

  /// Ostatni błąd wysyłania (np. brak łącza); czyszczony przy kolejnej udanej zmianie.
  String? get lastSendError => _lastSendError;

  S? get state => _connection?.state;
  C? get config => _connection?.config;

  /// State jako JSON (widżety pulpitów, ekran z `describe`).
  Json? get stateJson {
    final s = state;
    return s == null ? null : codec.stateToJson(s);
  }

  /// Poziom z `homes/{h}/access` (ustawia ekran domu); null = bez konta.
  HomeAccess? _homeAccess;

  set homeAccess(HomeAccess? access) {
    _homeAccess = access;
    notifyChanged();
  }

  /// Mój poziom dostępu do tego urządzenia (pkt 12): w domu - poziom tokenu telefonu,
  /// przez chmurę - z `access` domu. Urządzenie i tak sprawdza go samo (błąd `forbidden`).
  AccessLevel get access {
    final cloudLevel = _homeAccess?.levelFor(_device.id);
    // Uprawnienia domu jeszcze nieznane - nic nie ukrywamy (pilnują reguły i urządzenie).
    if (kind == ConnectionKind.cloud) return cloudLevel ?? AccessLevel.config;
    if (_device.access != AccessLevel.none) return _device.access;
    return cloudLevel ?? AccessLevel.config;
  }

  bool get canControl => access.canControl;
  bool get canConfig => access.canConfig;

  DeviceDescription? _description;
  Future<DeviceDescription?>? _describing;

  /// Rośnie, gdy opis może być nieaktualny (nowe połączenie, zmiana Config - np. nazwa kanału `chN`).
  int get descriptionVersion => _descriptionVersion;
  int _descriptionVersion = 0;

  /// Opis punktów danych (pkt 14), pobierany raz na połączenie i ponownie po zmianie Config (nazwy kanałów
  /// i wejść są w `describe`).
  Future<DeviceDescription?> description() {
    if (_description != null) return Future.value(_description);
    final conn = _connection;
    if (conn == null) return Future.value(null);
    return _describing ??= conn
        .describeJson()
        .then((j) {
          _description = j == null ? null : DeviceDescription.fromJson(j);
          return _description;
        }, onError: (_) => null)
        .whenComplete(() => _describing = null);
  }

  ConnectionKind? get kind => _connection?.kind;
  LinkStatus? get linkStatus => _connection?.status;

  /// Dane płyną (lokalnie albo z chmury i urządzenie nie jest offline).
  bool get live => _phase == ConnectPhase.connected && linkStatus == LinkStatus.online;

  /// Wybiera drogę i łączy się. Wołane przy starcie, z przycisku „Ponów” i po powrocie do aplikacji.
  Future<void> connect() async {
    final gen = ++_generation;
    await _dropConnection();
    _phase = ConnectPhase.connecting;
    _error = null;
    _needsPairing = false;
    notifyChanged();
    try {
      final conn = await manager.connectWith(
        _device,
        codec,
        onStep: (s) {
          if (gen != _generation) return;
          _step = s;
          notifyChanged();
        },
      );
      if (gen != _generation || _disposed) {
        await conn.close();
        return;
      }
      _attach(conn);
      _phase = ConnectPhase.connected;
      _step = null;
      _description = null;
      if (conn is LocalConnection<S, C>) unawaited(_refreshMyAccess(conn));
    } on UnauthorizedException catch (e) {
      if (gen != _generation) return;
      _needsPairing = true;
      _phase = ConnectPhase.failed;
      _error = e.message;
    } on ThermostatException catch (e) {
      if (gen != _generation) return;
      _phase = ConnectPhase.failed;
      _error = e.message;
    } on Object catch (e) {
      if (gen != _generation) return;
      _phase = ConnectPhase.failed;
      _error = 'Nieoczekiwany błąd: $e';
    }
    notifyChanged();
  }

  /// Po powrocie aplikacji z tła: jeśli łącze lokalne leży albo jesteśmy w chmurze,
  /// spróbuj znów wybrać najlepszą drogę.
  Future<void> refreshRoute() async {
    if (_phase == ConnectPhase.connecting) return;
    final c = _connection;
    if (c == null || c.kind == ConnectionKind.cloud || c.status != LinkStatus.online) {
      await connect();
    }
  }

  /// Nowy stan z urządzenia - podklasy czyszczą tu wartości „w trakcie wysyłania”.
  @protected
  void onState(S state) {}

  void _attach(DeviceConnection<S, C> conn) {
    _connection = conn;
    _subs
      ..add(
        conn.states.listen((s) {
          onState(s);
          notifyChanged();
        }),
      )
      ..add(
        conn.configs.listen((c) {
          _takeName(c);
          _description = null;
          _descriptionVersion++;
          notifyChanged();
        }),
      )
      ..add(conn.statuses.listen((_) => notifyChanged()));
    final c = conn.config;
    if (c != null) _takeName(c);
  }

  void _takeName(C config) {
    final name = codec.nameOf(config);
    if (name.isNotEmpty && name != _device.name) {
      _device = _device.copyWith(name: name);
      unawaited(_saveIfPaired());
    }
  }

  /// Lokalnie: poziom tokenu z `GET /api/me` (zmienia się np. po potwierdzeniu `idToken`).
  Future<void> _refreshMyAccess(LocalConnection<S, C> conn) async {
    try {
      final me = await conn.api.me(timeout: const Duration(seconds: 3));
      if (me.access == AccessLevel.none || me.access == _device.access) return;
      _device = _device.copyWith(access: me.access);
      unawaited(_saveIfPaired());
      notifyChanged();
    } on Object {
      // Starsze firmware bez /api/me - zostaje zapamiętany poziom.
    }
  }

  /// Nową nazwę zapisujemy tylko dla sparowanych; urządzenie znane z chmury nie trafia na listę lokalną.
  Future<void> _saveIfPaired() async {
    if (await manager.store.token(_device.id) != null) await manager.store.saveDevice(_device);
  }

  /// Wysyła dowolny Set. Nie rzuca - błąd łącza wraca jako `ok:false` z `errors['_']`.
  Future<SetResult> sendJson(Json values) async {
    final conn = _connection;
    if (conn == null) {
      return const SetResult(ok: false, errors: {'_': 'Brak połączenia z urządzeniem.'});
    }
    try {
      var r = await conn.sendSet(values);
      if (r.error != null && r.errors.isEmpty) {
        // Błąd całego polecenia (np. `busy`) - pokazujemy go jak błąd ogólny `_`.
        r = SetResult(
          ok: false,
          errors: {'_': describeApiError(r.error)},
          stateJson: r.stateJson,
          configJson: r.configJson,
        );
      }
      _lastSendError = r.errors.isEmpty ? null : describeErrors(r.errors);
      notifyChanged();
      return r;
    } on ThermostatException catch (e) {
      _lastSendError = e.message;
      notifyChanged();
      return SetResult(ok: false, errors: {'_': e.message});
    }
  }

  /// Połączenie lokalne albo null (chmurę, OTA i WiFi zmienia się tylko w sieci domowej).
  LocalConnection<S, C>? get _local =>
      _connection is LocalConnection<S, C> ? _connection as LocalConnection<S, C> : null;

  bool get isLocal => _local != null;

  bool get canManageCloud => isLocal;

  /// Klient HTTP urządzenia przy połączeniu lokalnym (OTA, /api/info); null przez chmurę.
  LocalApi? get localApi => _local?.api;

  LocalConnection<S, C> _requireLocal() {
    final local = _local;
    if (local == null) throw const ThermostatException('Połącz się z urządzeniem w sieci domowej.');
    return local;
  }

  /// `POST /api/cloud`: urządzenie zakłada własne konto, [bind] przypisuje je do domu [homeId] (pkt 8.2).
  Future<String> linkCloud({
    required String apiKey,
    required String dbUrl,
    required String homeId,
    required Future<void> Function(String deviceUid) bind,
    void Function(CloudLinkStatus status)? onStatus,
  }) => _requireLocal().linkCloud(apiKey: apiKey, dbUrl: dbUrl, homeId: homeId, bind: bind, onStatus: onStatus);

  /// `GET /api/clients` / `DELETE` - telefony sparowane z urządzeniem (poziom `config`).
  Future<List<PhoneClient>> phones() => _requireLocal().api.clients();

  Future<void> removePhone(String id) => _requireLocal().api.deleteClient(id);

  Future<void> setPhoneAccess(String id, AccessLevel access) => _requireLocal().api.setClientAccess(id, access);

  Future<({String id, String token, AccessLevel access})> createToken(String name, AccessLevel access) =>
      _requireLocal().api.createClient(name, access);

  /// `GET /api/cloud`; null, gdy połączenie nie jest lokalne.
  Future<CloudLinkStatus?> cloudStatus() async => _local?.cloudStatus();

  Future<void> unlinkCloud() => _requireLocal().unlinkCloud();

  /// `POST /api/wifi/reset` (pkt 9.3): urządzenie zapomina sieć i przechodzi w tryb konfiguracji Bluetooth.
  Future<void> wifiReset() async {
    await _requireLocal().api.wifiReset();
    await _dropConnection();
    _phase = ConnectPhase.failed;
    _error = 'Urządzenie czeka na konfigurację WiFi przez Bluetooth.';
    notifyChanged();
  }

  Future<void> _dropConnection() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final c = _connection;
    _connection = null;
    await c?.close();
  }

  @protected
  void notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_dropConnection());
    super.dispose();
  }
}
