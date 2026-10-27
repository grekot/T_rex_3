// Ocena alarmów z danych w chmurze: awaria czujnika i termostat offline.
// Czysty Dart - testy bez Firebase i bez powiadomień.

import '../data/cloud_access.dart';
import '../data/cloud_connection.dart';
import '../data/cloud_store.dart';
import '../models/json_utils.dart';

enum AlertKind { sensorFault, offline }

/// To, co zadanie w tle wie o termostacie.
class DeviceHealth {
  const DeviceHealth({required this.id, required this.name, required this.sensorFault, required this.lastSeenMs});

  final String id;
  final String name;
  final bool sensorFault;

  /// `lastSeen` z chmury (ms); null = termostat nigdy się nie odezwał.
  final int? lastSeenMs;
}

class Alert {
  const Alert(this.deviceId, this.kind, this.title, this.body);

  final String deviceId;
  final AlertKind kind;
  final String title;
  final String body;

  /// Stały numer powiadomienia: nowe zastępuje stare tego samego rodzaju.
  int get notificationId => alertNotificationId(deviceId, kind);
}

/// FNV-1a - stały między uruchomieniami (w przeciwieństwie do String.hashCode).
int alertNotificationId(String deviceId, AlertKind kind) {
  var h = 0x811c9dc5;
  for (final c in deviceId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return (h & 0x3fffffff) * 2 + kind.index;
}

/// Które alarmy już pokazaliśmy - powiadamiamy tylko przy przejściu w zły stan.
class AlertMemory {
  AlertMemory([Set<String>? active]) : active = active ?? {};

  /// Klucze `deviceId|kind`.
  final Set<String> active;

  static String key(String id, AlertKind k) => '$id|${k.name}';

  factory AlertMemory.fromJson(Object? j) => AlertMemory(j is List ? {for (final e in j) e.toString()} : {});

  List<String> toJson() => active.toList()..sort();
}

class AlertEvaluation {
  const AlertEvaluation(this.newAlerts, this.resolved, this.memory);

  /// Do pokazania teraz.
  final List<Alert> newAlerts;

  /// Alarmy, które minęły - ich powiadomienia można schować.
  final List<(String, AlertKind)> resolved;
  final AlertMemory memory;
}

AlertEvaluation evaluateAlerts(
  List<DeviceHealth> devices,
  AlertMemory previous,
  int nowMs, {
  Duration offlineAfter = cloudOfflineAfter,
}) {
  final active = <String>{};
  final fresh = <Alert>[];
  final resolved = <(String, AlertKind)>[];

  for (final d in devices) {
    final offline = d.lastSeenMs == null || nowMs - d.lastSeenMs! > offlineAfter.inMilliseconds;
    // Offline zasłania awarię: stary stan z chmury nie mówi nic pewnego.
    final checks = {AlertKind.offline: offline, AlertKind.sensorFault: !offline && d.sensorFault};
    for (final MapEntry(key: kind, value: bad) in checks.entries) {
      final k = AlertMemory.key(d.id, kind);
      if (bad) {
        active.add(k);
        if (!previous.active.contains(k)) fresh.add(_alert(d, kind, nowMs));
      } else if (previous.active.contains(k)) {
        resolved.add((d.id, kind));
      }
    }
  }
  // Termostat usunięty z konta - jego alarmy też znikają.
  final known = {for (final d in devices) d.id};
  for (final k in previous.active) {
    final id = k.substring(0, k.lastIndexOf('|'));
    if (!known.contains(id)) {
      resolved.add((id, AlertKind.values.byName(k.substring(k.lastIndexOf('|') + 1))));
    }
  }
  return AlertEvaluation(fresh, resolved, AlertMemory(active));
}

Alert _alert(DeviceHealth d, AlertKind kind, int nowMs) => switch (kind) {
  AlertKind.sensorFault => Alert(
    d.id,
    kind,
    'Awaria czujnika: ${d.name}',
    'Termostat nie odczytuje temperatury i wstrzymał grzanie.',
  ),
  AlertKind.offline => Alert(
    d.id,
    kind,
    'Brak kontaktu: ${d.name}',
    d.lastSeenMs == null
        ? 'Urządzenie nie łączy się z chmurą.'
        : 'Brak kontaktu od ${_ago(nowMs - d.lastSeenMs!)}. Sprawdź zasilanie i Wi-Fi.',
  ),
};

String _ago(int ms) {
  final min = ms ~/ 60000;
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  return h < 48 ? '$h h' : '${h ~/ 24} dni';
}

/// Zbiera stan urządzeń wszystkich domów konta: `info/name`, `state/sensorFault`, `lastSeen`.
Future<List<DeviceHealth>> collectHealth(CloudAccess access) async {
  final uid = access.uid;
  if (uid == null) return const [];
  final store = access.store;
  final homes = {...?toJsonObject(await store.read('users/$uid/homes'))?.keys, ?access.homeId};
  final result = <DeviceHealth>[];
  for (final h in homes) {
    final ids = await homeDeviceIds(store, h, uid);
    result.addAll(
      await Future.wait(
        ids.map((id) async {
          final base = cloudDevicePath(h, id);
          final results = await Future.wait([
            store.read('$base/info/name').catchError((_) => null),
            store.read('$base/state/sensorFault').catchError((_) => null),
            store.read('$base/lastSeen').catchError((_) => null),
          ]);
          return DeviceHealth(
            id: id,
            name: asStringOrNull(results[0], 'info.name') ?? id,
            sensorFault: results[1] == true,
            lastSeenMs: results[2] is num ? (results[2] as num).toInt() : null,
          );
        }),
      ),
    );
  }
  return result;
}
