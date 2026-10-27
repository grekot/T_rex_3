import '../controllers/device_controller.dart';
import '../models/hub.dart';
import 'cloud_store.dart';
import 'errors.dart';
import 'hub_api.dart';

/// Automatyki huba (pkt 11, ARCHITEKTURA pkt 4.5). W domu - wprost w hubie (`/api/automations`, z diagnostyką
/// i „uruchom teraz”; hub sam przenosi zmiany do chmury); poza domem - `homes/{h}/automations/{id}` z `updatedAt`
/// = teraz i Set `{"reload":true}` do huba (pobiera od razu). Pisze tylko właściciel / `config` na hubie.
class HubAutomations {
  HubAutomations({required this.hub, this.store, this.homeId, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Kontroler huba (lokalnie albo przez chmurę).
  final DeviceController<Object?, Object?> hub;
  final CloudStore? store;
  final String? homeId;
  final DateTime Function() _clock;

  HubApi? get _local => hub.localApi == null ? null : HubApi(hub.localApi!);

  /// W domu: edycja bez internetu, diagnostyka i dziennik z huba.
  bool get isLocal => _local != null;

  bool get _cloud => store != null && homeId != null;

  Future<AutomationsInfo> load() async {
    final local = _local;
    if (local != null) return local.automations();
    if (!_cloud) throw const ThermostatException('Połącz się z hubem w sieci domowej.');
    final j = toJsonObject(await store!.read('homes/$homeId/automations')) ?? const {};
    return AutomationsInfo(
      items: [
        for (final e in j.entries)
          if (e.value is Map) Automation.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
      ]..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  /// Rzuca [HubInvalidException] z listą problemów, gdy hub odrzuci regułę.
  Future<void> save(Automation a) async {
    final now = _clock().millisecondsSinceEpoch;
    final local = _local;
    if (local != null) {
      await local.putAutomation(a, updatedAt: now);
      return;
    }
    if (!_cloud) throw const ThermostatException('Połącz się z hubem w sieci domowej.');
    await store!.write('homes/$homeId/automations/${a.id}', a.toJson(updatedAt: now));
    await hub.sendJson({'reload': true});
  }

  Future<void> remove(String id) async {
    final local = _local;
    if (local != null) {
      await local.deleteAutomation(id);
      return;
    }
    if (!_cloud) throw const ThermostatException('Połącz się z hubem w sieci domowej.');
    await store!.write('homes/$homeId/automations/$id', null);
    await hub.sendJson({'reload': true});
  }

  /// „Uruchom teraz” - akcje bez wyzwalaczy i warunków (tylko w domu).
  Future<void> run(String id) async {
    final local = _local;
    if (local == null) throw const ThermostatException('„Uruchom teraz” działa w sieci domowej.');
    await local.runAutomation(id);
  }

  /// Dziennik: w domu z huba, poza domem `homes/{h}/automationLog` (najnowsze pierwsze).
  Future<List<HubLogEntry>> log() async {
    final local = _local;
    if (local != null) return local.automationLog();
    if (!_cloud) return const [];
    final j = toJsonObject(await store!.read('homes/$homeId/automationLog')) ?? const {};
    return [
      for (final e in j.entries)
        if (e.value is Map) HubLogEntry.fromJson((e.value as Map).cast<String, dynamic>()),
    ]..sort((a, b) => b.ts.compareTo(a.ts));
  }
}
