import 'dart:async';

import '../controllers/device_hub.dart';
import '../controllers/thermostat_controller.dart';
import '../models/device_type.dart';
import '../models/firmware.dart';
import '../models/json_utils.dart';
import 'cloud_store.dart';
import 'errors.dart';
import 'firmware_catalog.dart';
import 'hub_api.dart';
import 'local_api.dart';

/// Urządzenie na ekranie „Aktualizacje”, które pobiera plik samo (termostat, hub, urządzenia z chmurą).
class UpdateTarget {
  const UpdateTarget({
    required this.id,
    required this.name,
    required this.type,
    this.fw,
    this.fwId,
    this.local = false,
    this.warning,
    this.blocked,
  });

  final String id;
  final String name;
  final DeviceType type;
  final String? fw;
  final String? fwId;

  /// W sieci domowej (postęp z `GET /api/ota`); inaczej poleceniem z chmury.
  final bool local;

  /// Np. termostat właśnie grzeje - pokazywane przed zatwierdzeniem.
  final String? warning;

  /// Dlaczego nie da się aktualizować (np. z chmury tylko właściciel); null = można.
  final String? blocked;
}

enum UpdatePhase { sending, downloading, restarting, waiting, done, failed }

class UpdateProgress {
  const UpdateProgress(this.phase, {this.percent, this.message});

  final UpdatePhase phase;
  final int? percent;
  final String? message;

  bool get finished => phase == UpdatePhase.done || phase == UpdatePhase.failed;

  String get label =>
      message ??
      switch (phase) {
        UpdatePhase.sending => 'Wysyłanie polecenia…',
        UpdatePhase.downloading => 'Pobieranie${percent == null ? '' : ' $percent%'}…',
        UpdatePhase.restarting => 'Restart z nową wersją…',
        UpdatePhase.waiting => 'Urządzenie pobiera plik…',
        UpdatePhase.done => 'Zaktualizowano',
        UpdatePhase.failed => 'Nieudane',
      };
}

/// Węzły jednego huba (`GET hub/api/updates`).
class HubUpdatesView {
  const HubUpdatesView({required this.hubId, required this.hubName, required this.updates, this.names = const {}});

  final String hubId;
  final String hubName;
  final HubUpdates updates;

  /// Nazwy węzłów znane aplikacji.
  final Map<String, String> names;
}

/// Źródło danych ekranu „Aktualizacje” (w testach - atrapa).
abstract class UpdateBackend {
  Future<FirmwareManifest> manifest();

  /// Kiedy pobrano manifest (null = nie wiadomo).
  DateTime? get manifestFetchedAt;

  Future<List<UpdateTarget>> targets();

  Stream<UpdateProgress> update(UpdateTarget t, FirmwareRelease r);

  Future<List<HubUpdatesView>> hubs();

  Future<void> applyHub(String hubId, List<String> ids);

  /// Hub pobiera manifest od razu (zamiast co 6 h).
  Future<void> checkHub(String hubId);
}

/// Aktualizacje urządzeń domu: kontrolery z [DeviceHub], lokalnie albo przez chmurę (pkt 3a, 3e).
class DeviceHubUpdates implements UpdateBackend {
  DeviceHubUpdates(
    this.hub, {
    FirmwareCatalog? catalog,
    this.poll = const Duration(seconds: 1),
    this.cloudPoll = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 10),
  }) : catalog = catalog ?? FirmwareCatalog();

  final DeviceHub hub;
  final FirmwareCatalog catalog;
  final Duration poll;
  final Duration cloudPoll;
  final Duration timeout;

  CloudStore? get _store => hub.cloud.available && hub.home != null ? hub.cloud.store : null;
  String get _h => hub.home!.id;

  @override
  Future<FirmwareManifest> manifest() => catalog.load();

  @override
  DateTime? get manifestFetchedAt => catalog.fetchedAt;

  Future<Json?> _cloudInfo(String id) async {
    final store = _store;
    if (store == null) return null;
    return toJsonObject(await store.read('homes/$_h/devices/$id/info').catchError((_) => null));
  }

  @override
  Future<List<UpdateTarget>> targets() async {
    final out = <UpdateTarget>[];
    for (final d in hub.devices) {
      final c = hub.controller(d.id);
      if (c == null || !hub.accessFor(d.id).canConfig) continue;
      String? fw, fwId;
      var local = false;
      final api = c.localApi;
      if (api != null) {
        try {
          final info = await api.info(timeout: const Duration(seconds: 3));
          (fw, fwId, local) = (info.fw, info.fwId, true);
        } on Object {
          // poza zasięgiem - spróbujemy chmury
        }
      }
      if (!local) {
        final info = await _cloudInfo(d.id);
        if (info == null) continue;
        // Urządzenie za hubem - aktualizuje hub (sekcja węzłów).
        if (info['via'] is String) continue;
        fw = info['fw'] as String?;
        fwId = info['fwId'] as String?;
      }
      out.add(
        UpdateTarget(
          id: d.id,
          name: d.name,
          type: d.type,
          fw: fw,
          fwId: fwId,
          local: local,
          warning: _warning(c),
          blocked: local || hub.isOwner || hub.home == null ? null : 'Z chmury aktualizuje tylko właściciel domu',
        ),
      );
    }
    return out;
  }

  static String? _warning(DeviceController<Object?, Object?> c) {
    if (c is! ThermostatController) return null;
    final s = c.state;
    if (s == null) return null;
    if (s.sensorFault || s.protect == 'faultDuty') {
      return 'Termostat ma awarię czujnika - lepiej zaktualizować po jej usunięciu.';
    }
    if (s.heating) return 'Termostat właśnie grzeje - na czas pobierania i restartu (1-2 min) grzanie się zatrzyma.';
    return null;
  }

  @override
  Stream<UpdateProgress> update(UpdateTarget t, FirmwareRelease r) async* {
    final c = hub.controller(t.id);
    if (c == null) {
      yield const UpdateProgress(UpdatePhase.failed, message: 'Brak połączenia z urządzeniem.');
      return;
    }
    yield const UpdateProgress(UpdatePhase.sending);
    final cloud = !(t.local && c.localApi != null);
    // Stary wpis `ota` (np. z poprzedniej aktualizacji) - nowy rozpoznamy po zmianie.
    final before = cloud ? await _ota(t.id) : null;
    final res = await c.sendJson(r.setJson);
    if (res.errors.isNotEmpty) {
      yield UpdateProgress(UpdatePhase.failed, message: describeErrors(res.errors));
      return;
    }
    final api = c.localApi;
    final deadline = DateTime.now().add(timeout);
    if (!cloud && api != null) {
      yield* _local(api, r, deadline);
    } else {
      yield* _cloud(t.id, r, deadline, before);
    }
  }

  Stream<UpdateProgress> _local(LocalApi api, FirmwareRelease r, DateTime deadline) async* {
    // Pobieranie: GET /api/ota aż do done / error.
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        yield const UpdateProgress(UpdatePhase.failed, message: 'Pobieranie trwa za długo - sprawdź urządzenie.');
        return;
      }
      await Future<void>.delayed(poll);
      final OtaStatus s;
      try {
        s = await api.otaStatus(timeout: const Duration(seconds: 3));
      } on Object {
        break; // urządzenie już się restartuje
      }
      if (s.state == 'error') {
        yield UpdateProgress(UpdatePhase.failed, message: describeOtaError(s.error));
        return;
      }
      if (s.state == 'done') break;
      yield UpdateProgress(UpdatePhase.downloading, percent: s.progress);
    }
    // Restart: /api/info z nową wersją.
    yield const UpdateProgress(UpdatePhase.restarting);
    String? seen;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(poll);
      try {
        seen = (await api.info(timeout: const Duration(seconds: 3))).fw;
        if (compareVersions(seen, r.version) == 0) {
          yield UpdateProgress(
            UpdatePhase.done,
            message: 'Zaktualizowano do ${r.version} - przez 10 min okres próbny.',
          );
          return;
        }
      } on Object {
        // restart trwa
      }
    }
    yield UpdateProgress(
      UpdatePhase.failed,
      message: seen == null ? 'Urządzenie nie wróciło po restarcie.' : 'Urządzenie zostało przy wersji $seen.',
    );
  }

  Future<Json?> _ota(String id) async {
    final store = _store;
    if (store == null) return null;
    return toJsonObject(await store.read('homes/$_h/devices/$id/ota').catchError((_) => null));
  }

  /// Z chmury: `devices/{id}/ota` `{state, progress, error, version, ts}` (pkt 3a) - running / failed / done /
  /// rolledBack; urządzenia bez tego wpisu (starszy firmware) - czekanie na nowe `info.fw`.
  Stream<UpdateProgress> _cloud(String id, FirmwareRelease r, DateTime deadline, Json? before) async* {
    yield const UpdateProgress(UpdatePhase.waiting);
    final stale = before?.toString();
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(cloudPoll);
      final ota = await _ota(id);
      if (ota != null && ota.toString() != stale) {
        final version = ota['version'] as String?;
        final error = ota['error'] as String?;
        switch (ota['state']) {
          case 'running':
            yield UpdateProgress(UpdatePhase.downloading, percent: (ota['progress'] as num?)?.toInt());
            continue;
          case 'failed':
            yield UpdateProgress(UpdatePhase.failed, message: describeOtaError(error));
            return;
          case 'rolledBack':
            yield UpdateProgress(
              UpdatePhase.failed,
              message: error == 'boot'
                  ? 'Nowa wersja nie wystartowała - urządzenie wróciło do ${version ?? 'poprzedniej'}.'
                  : 'Nowa wersja się zawieszała - urządzenie wróciło do ${version ?? 'poprzedniej'}.',
            );
            return;
          case 'done':
            if (version == null || compareVersions(version, r.version) == 0) {
              yield UpdateProgress(
                UpdatePhase.done,
                message: 'Zaktualizowano do ${r.version} - przez 10 min okres próbny.',
              );
            } else {
              yield UpdateProgress(UpdatePhase.failed, message: 'Urządzenie działa na wersji $version.');
            }
            return;
        }
      }
      final fw = (await _cloudInfo(id))?['fw'];
      if (fw is String && compareVersions(fw, r.version) == 0) {
        yield UpdateProgress(UpdatePhase.done, message: 'Zaktualizowano do ${r.version} - przez 10 min okres próbny.');
        return;
      }
    }
    yield const UpdateProgress(
      UpdatePhase.failed,
      message: 'Brak potwierdzenia nowej wersji - urządzenie może jeszcze pobierać. Sprawdź później.',
    );
  }

  @override
  Future<List<HubUpdatesView>> hubs() async {
    final out = <HubUpdatesView>[];
    for (final c in hub.hubs) {
      if (!c.canConfig) continue;
      HubUpdates? u;
      final api = c.localApi;
      if (api != null) {
        try {
          u = await HubApi(api).updates();
        } on Object {
          // starszy hub bez /api/updates albo poza zasięgiem
        }
      }
      if (u == null && _store != null) {
        final j = toJsonObject(await _store!.read('homes/$_h/devices/${c.device.id}/updates').catchError((_) => null));
        if (j != null) u = HubUpdates.fromJson(j);
      }
      if (u == null) continue;
      out.add(
        HubUpdatesView(
          hubId: c.device.id,
          hubName: c.device.name,
          updates: u,
          names: {for (final d in u.devices) d.id: hub.device(d.id)?.name ?? d.id},
        ),
      );
    }
    return out;
  }

  @override
  Future<void> applyHub(String hubId, List<String> ids) async {
    final c = hub.controller(hubId);
    if (c == null) throw const ThermostatException('Brak połączenia z hubem.');
    final api = c.localApi;
    try {
      if (api != null) return await HubApi(api).applyUpdates(ids);
    } on HubApplyException catch (e) {
      throw ThermostatException(_applyMessage(e.errors));
    }
    final r = await c.sendJson({'applyUpdates': ids});
    if (r.errors.isEmpty) return;
    // Set huba: `applyUpdates: "type|value|forbidden"` albo obiekt po id (→ `applyUpdates.<id>`).
    throw ThermostatException(
      _applyMessage({
        for (final e in r.errors.entries) (e.key.startsWith('applyUpdates.') ? e.key.substring(13) : e.key): e.value,
      }),
    );
  }

  String _applyMessage(Map<String, String> errors) => errors.entries
      .map(
        (e) => e.key == 'applyUpdates' || e.key == '_'
            ? describeApplyError(e.value)
            : '${hub.device(e.key)?.name ?? e.key}: ${describeApplyError(e.value)}',
      )
      .join('\n');

  @override
  Future<void> checkHub(String hubId) async {
    final c = hub.controller(hubId);
    if (c == null) throw const ThermostatException('Brak połączenia z hubem.');
    final api = c.localApi;
    if (api != null) return HubApi(api).checkUpdates();
    final r = await c.sendJson({'checkUpdates': true});
    if (r.errors.isNotEmpty) throw ThermostatException(describeErrors(r.errors));
  }
}
