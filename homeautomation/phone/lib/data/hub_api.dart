import '../models/firmware.dart';
import '../models/hub.dart';
import '../models/json_utils.dart';
import '../models/scene.dart';
import 'errors.dart';
import 'local_api.dart';

/// Hub odrzucił automatykę albo scenę (`400 invalid` + `problems`).
class HubInvalidException extends ThermostatException {
  HubInvalidException(this.problems) : super('Hub odrzucił regułę: ${problems.join('; ')}');

  final List<String> problems;
}

/// Hub nie przyjął zatwierdzenia aktualizacji: błąd per węzeł (`unknown`, `busy`, `not_ready`).
class HubApplyException extends ThermostatException {
  HubApplyException(this.errors)
    : super(errors.entries.map((e) => '${e.key}: ${describeApplyError(e.value)}').join('\n'));

  final Map<String, String> errors;
}

String describeApplyError(String code) => switch (code) {
  'unknown' => 'hub nie zna tego węzła',
  'busy' => 'węzeł już się aktualizuje',
  'not_ready' => 'hub nie pobrał jeszcze pliku',
  'forbidden' => 'zatwierdza tylko właściciel domu',
  final c => c,
};

/// Wynik polecenia do urządzenia podrzędnego: `pending` = urządzenie nie odpowiedziało w 3 s (hub dokończy).
typedef HubSetResult = ({bool ok, bool pending, Map<String, String> errors});

/// Lokalne API huba (kontrakt pkt 11) - w sieci domowej, tokenem telefonu.
class HubApi {
  HubApi(this.api);

  final LocalApi api;

  static String _error(Object? code) => switch (code) {
    'unsupported' => 'Hub jeszcze tego nie obsługuje (Tuya - w kolejnej wersji).',
    'too_many_devices' => 'Hub ma już 30 urządzeń.',
    'host' => 'Zły adres urządzenia (potrzebny adres IPv4).',
    'token' => 'Zły token węzła.',
    'id' => 'Zły identyfikator urządzenia.',
    'adapter' => 'Nieznany rodzaj urządzenia.',
    'type' => 'Nieznany typ urządzenia.',
    'not_found' => 'Hub nie zna tego wpisu.',
    'limit' => 'Hub ma już 50 wpisów.',
    'range' => 'Wartość poza zakresem.',
    _ => describeApiError(code as String?),
  };

  Json _ok(Object? v) {
    if (v is! Map) throw const ThermostatException('Hub zwrócił nieoczekiwaną odpowiedź.');
    final j = v.cast<String, dynamic>();
    if (j['ok'] == false) {
      if (j['error'] == 'invalid') {
        throw HubInvalidException([for (final p in (j['problems'] is List ? j['problems'] as List : const [])) '$p']);
      }
      throw ThermostatException(_error(j['error']));
    }
    return j;
  }

  // ---- urządzenia podrzędne

  Future<List<HubChild>> devices() async {
    final v = await api.request('GET', '/api/devices');
    if (v is Map) _ok(v);
    return [
      for (final e in (v is List ? v : const []))
        if (e is Map) HubChild.fromJson(e.cast<String, dynamic>()),
    ];
  }

  Future<HubDiscovery> discover() async => HubDiscovery.fromJson(_ok(await api.request('GET', '/api/discover')));

  /// Dodanie albo zmiana (to samo `id`) - zwraca `id` nadane przez hub.
  Future<String> addDevice(Json device) async =>
      asString(_ok(await api.request('POST', '/api/devices', body: device))['id'], 'id');

  Future<void> deleteDevice(String id) async => _ok(await api.request('DELETE', '/api/devices', query: {'id': id}));

  Future<HubSetResult> setDevice(String id, Json values) async {
    final j = await api.request('POST', '/api/devices/$id/set', body: values, timeout: const Duration(seconds: 8));
    if (j is! Map) throw const ThermostatException('Hub zwrócił nieoczekiwaną odpowiedź.');
    if (j['ok'] == false && j['errors'] == null) throw ThermostatException(_error(j['error']));
    final errors = <String, String>{
      for (final e in ((j['errors'] is Map ? j['errors'] as Map : const {})).entries) '${e.key}': '${e.value}',
    };
    return (ok: j['ok'] == true, pending: j['pending'] == true, errors: errors);
  }

  // ---- automatyki i sceny

  Future<AutomationsInfo> automations() async =>
      AutomationsInfo.fromJson(_ok(await api.request('GET', '/api/automations')));

  Future<int?> putAutomation(Automation a, {int? updatedAt}) async {
    final j = _ok(await api.request('PUT', '/api/automations/${a.id}', body: a.toJson(updatedAt: updatedAt)));
    return j['updatedAt'] is num ? (j['updatedAt'] as num).toInt() : null;
  }

  Future<void> deleteAutomation(String id) async => _ok(await api.request('DELETE', '/api/automations/$id'));

  Future<void> runAutomation(String id) async => _ok(await api.request('POST', '/api/automations/$id/run'));

  Future<List<HubLogEntry>> automationLog() => _log('/api/automations/log');

  Future<List<HubLogEntry>> sceneLog() => _log('/api/scenes/log');

  Future<List<HubLogEntry>> _log(String path) async {
    final v = await api.request('GET', path);
    final list = v is List ? v : (v is Map && v['items'] is List ? v['items'] as List : const []);
    return [
      for (final e in list)
        if (e is Map) HubLogEntry.fromJson(e.cast<String, dynamic>()),
    ];
  }

  Future<void> putScene(Scene s, {int? updatedAt}) async =>
      _ok(await api.request('PUT', '/api/scenes/${s.id}', body: {...s.toJson(), 'updatedAt': ?updatedAt}));

  Future<void> deleteScene(String id) async => _ok(await api.request('DELETE', '/api/scenes/$id'));

  Future<void> runScene(String id) async => _ok(await api.request('POST', '/api/scenes/$id/run'));

  // ---- aktualizacje węzłów (pkt 3e)

  Future<HubUpdates> updates() async => HubUpdates.fromJson(_ok(await api.request('GET', '/api/updates')));

  /// Zatwierdzenie: hub aktualizuje po kolei (pierwszy węzeł, 10 min obserwacji, reszta). `409` z błędami po id
  /// (`unknown|busy|not_ready`) - nic nie trafia do kolejki.
  Future<void> applyUpdates(List<String> ids) async {
    final j = await api.request('POST', '/api/updates/apply', body: {'devices': ids});
    if (j is Map && j['ok'] == false && j['errors'] is Map) {
      throw HubApplyException({for (final e in (j['errors'] as Map).entries) '${e.key}': '${e.value}'});
    }
    _ok(j);
  }

  /// Hub pobiera manifest od razu (zamiast co 6 h).
  Future<void> checkUpdates() async => _ok(await api.request('POST', '/api/updates/check'));

  /// `POST /api/time` - czas z telefonu, gdy hub go nie zna (bez internetu i RTC).
  Future<void> setTime(DateTime now) async =>
      _ok(await api.request('POST', '/api/time', body: {'ts': now.millisecondsSinceEpoch ~/ 1000}));
}
