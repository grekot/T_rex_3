// Zegarek (i pilot) przez Bluetooth bez telefonu (kontrakt pkt 15.1): rejestracja w hubie, klucz dla zegarka
// w `users/{uid}/watches/{watchId}/ble`, lista punktów w `homes/{h}/remotes/{id}` wyliczana z pulpitu zegarka.

import 'json_utils.dart';
import 'watch.dart';

/// `users/{uid}/watches/{watchId}/ble` - czyta tylko właściciel zegarka (Side Service); klucz nie trafia do `homes/`.
class WatchBleLink {
  const WatchBleLink({
    required this.homeId,
    required this.hub,
    required this.id,
    required this.slot,
    required this.key,
  });

  final String homeId;

  /// Hub, w którym zegarek jest zarejestrowany.
  final String hub;

  /// Id pilota w hubie (`zegarek-<watchId>`).
  final String id;

  /// Numer w ramkach GATT (1-250).
  final int slot;

  /// 64 hex.
  final String key;

  static WatchBleLink? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    if (j['homeId'] is! String || j['hub'] is! String || j['id'] is! String) return null;
    return WatchBleLink(
      homeId: j['homeId'] as String,
      hub: j['hub'] as String,
      id: j['id'] as String,
      slot: asInt(j['slot'], 'slot'),
      key: asString(j['key'], 'key'),
    );
  }

  Json toJson() => {'homeId': homeId, 'hub': hub, 'id': id, 'slot': slot, 'key': key};
}

/// Punkt pilota: urządzenie i pole (`runScene` huba z `arg` = scena). Indeks w ramkach = pozycja na liście.
typedef RemotePoint = ({String device, String point, String? arg});

Json remotePointJson(RemotePoint p) => {'device': p.device, 'point': p.point, 'arg': ?p.arg};

/// Najwięcej punktów pilota (indeks w ramce to 1 bajt, 0-127).
const maxRemotePoints = 128;

/// Najwięcej bajtów treści lokalnego `PUT hub/api/remotes/{id}` (dłuższa lista idzie przez chmurę).
const maxRemotePutBytes = 4000;

/// Punkty kafelka termostatu na zegarku.
const thermostatRemotePoints = ['temp', 'target', 'mode', 'power', 'heating'];

/// Lista punktów z pulpitu zegarka (pkt 15.1): kafelki po kolei, termostat = [thermostatRemotePoints],
/// scena = `runScene` huba [hubId] z `arg`; bez powtórzeń, najwyżej [maxRemotePoints].
List<RemotePoint> watchRemotePoints(List<WatchPage> pages, String hubId) {
  final out = <RemotePoint>[];
  void add(RemotePoint p) {
    if (out.length < maxRemotePoints && !out.contains(p)) out.add(p);
  }

  for (final page in pages) {
    for (final t in page.tiles) {
      switch (t.view) {
        case WatchView.scene:
          if (t.sceneId != null) add((device: hubId, point: 'runScene', arg: t.sceneId));
        case WatchView.thermostat:
          if (t.device != null) {
            for (final k in thermostatRemotePoints) {
              add((device: t.device!, point: k, arg: null));
            }
          }
        case _:
          if (t.device != null && t.point != null) add((device: t.device!, point: t.point!, arg: null));
      }
    }
  }
  return out;
}

/// `homes/{h}/remotes/{id}` (i treść `PUT hub/api/remotes/{id}`).
Json remoteDoc({
  required String ownerUid,
  required String name,
  required String hub,
  required int cfgVer,
  required List<RemotePoint> points,
}) => {
  'kind': 'watch',
  'ownerUid': ownerUid,
  'name': name,
  'hub': hub,
  'cfgVer': cfgVer,
  'points': [for (final p in points) remotePointJson(p)],
};
