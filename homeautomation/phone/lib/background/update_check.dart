// Sprawdzanie aktualizacji firmware w tle (pkt 3e) - raz dziennie, tylko domy, których jestem właścicielem.
// Powiadomienie tylko o wersjach, o których jeszcze nie mówiliśmy.

import '../data/cloud_store.dart';
import '../models/device_type.dart';
import '../models/firmware.dart';

/// Urządzenie z dostępną wersją; [key] = `id@wersja` (pamięć powiadomień).
typedef AvailableUpdate = ({String name, String key});

/// Urządzenia domów właściciela [uid] z nowszą wersją: termostat / hub / urządzenia z chmurą wg `info`
/// (`fw`, `fwId`), węzły huba wg `devices/{hubId}/updates`.
Future<List<AvailableUpdate>> collectUpdates(CloudStore store, String uid, FirmwareManifest m) async {
  final out = <AvailableUpdate>[];
  final homes = toJsonObject(await store.read('users/$uid/homes').catchError((_) => null))?.keys ?? const [];
  for (final h in homes) {
    if (await store.read('homes/$h/ownerUid').catchError((_) => null) != uid) continue;
    final index = toJsonObject(await store.read('homes/$h/deviceIndex').catchError((_) => null)) ?? const {};
    final ids = {...index.keys, ...await store.childKeys('homes/$h/devices').catchError((_) => const <String>[])};
    String nameOf(String id) => (index[id] is Map ? (index[id] as Map)['name'] : null) as String? ?? id;
    for (final id in ids) {
      final info = toJsonObject(await store.read('homes/$h/devices/$id/info').catchError((_) => null));
      if (info == null || info['via'] is String) continue;
      final c = checkUpdate(m, fw: info['fw'] as String?, fwId: info['fwId'] as String?);
      if (c.canUpdate) out.add((name: nameOf(id), key: '$id@${c.release!.version}'));
      if (DeviceType.fromWire(info['type']) == DeviceType.hub) {
        final u = toJsonObject(await store.read('homes/$h/devices/$id/updates').catchError((_) => null));
        if (u == null) continue;
        for (final d in HubUpdates.fromJson(u).devices) {
          if (d.hasUpdate && !d.state.busy) out.add((name: nameOf(d.id), key: '${d.id}@${d.next}'));
        }
      }
    }
  }
  return out;
}

/// Treść powiadomienia albo null, gdy nie ma nic nowego względem [seen].
({String title, String body})? updateNotice(List<AvailableUpdate> available, Set<String> seen) {
  if (!available.any((a) => !seen.contains(a.key))) return null;
  final names = available.map((a) => a.name).toSet().toList();
  return (
    title: available.length == 1 ? 'Dostępna aktualizacja' : 'Dostępne aktualizacje (${available.length})',
    body:
        '${names.take(3).join(', ')}${names.length > 3 ? ' i inne' : ''} - zatwierdź w aplikacji: Urządzenia → Aktualizacje.',
  );
}
