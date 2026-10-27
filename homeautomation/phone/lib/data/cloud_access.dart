import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/device_type.dart';
import '../models/json_utils.dart';
import 'cloud_connection.dart';
import 'cloud_store.dart';

/// Urządzenie widoczne na koncie w chmurze (`home/{uid}/devices/{deviceId}`).
class CloudDeviceSummary {
  const CloudDeviceSummary({required this.id, this.name, this.fw, this.type = DeviceType.thermostat, this.via});

  final String id;
  final DeviceType type;
  final String? name;
  final String? fw;

  /// Hub, przez który urządzenie jest w chmurze (pkt 11).
  final String? via;
}

/// Dostęp do chmury dla bieżącego użytkownika. Gdy Firebase nie jest skonfigurowany
/// albo nikt nie jest zalogowany, [unavailableReason] mówi dlaczego, a reszta nie działa.
abstract class CloudAccess {
  /// null = chmura dostępna.
  String? get unavailableReason;

  bool get available => unavailableReason == null;

  String? get uid;
  String? get email;

  /// Wyświetlana nazwa konta (do `members`).
  String? get displayName => null;

  /// Token logowania Firebase (do parowania kodem, pkt 2).
  Future<String?> idToken() async => null;

  /// `apiKey` i `dbUrl` dla `POST /api/cloud` (z firebase_options.dart).
  String get apiKey;
  String get dbUrl;

  CloudStore get store;

  /// Bieżący dom (pkt 12); null = jeszcze nie wybrany / bez konta.
  String? homeId;

  /// Właściciel bieżącego domu (ustawia [HomeSession]); wiązanie kont urządzeń i `deviceIndex` pisze tylko on.
  String? homeOwnerUid;

  bool get isHomeOwner => uid != null && uid == homeOwnerUid;

  /// Urządzenia bieżącego domu z `homes/{h}/deviceIndex` (pkt 12) + `info` tych, do których mam dostęp.
  /// Właściciel widzi też `homes/{h}/devices` i uzupełnia nimi indeks.
  Future<List<CloudDeviceSummary>> devices() async {
    final u = uid, h = homeId;
    if (u == null || h == null) return const [];
    final index = await readDeviceIndex(store, h);
    final ids = {...index.keys};
    if (isHomeOwner) ids.addAll(await store.childKeys('homes/$h/devices').catchError((_) => const <String>[]));
    final list = await Future.wait(
      ids.map((id) async {
        final indexed = index[id];
        CloudDeviceSummary? fromInfo;
        try {
          final info = toJsonObject(await store.read('${cloudDevicePath(h, id)}/info'));
          if (info != null) {
            fromInfo = CloudDeviceSummary(
              id: id,
              type: DeviceType.fromWire(asStringOrNull(info['type'], 'info.type')),
              name: asStringOrNull(info['name'], 'info.name'),
              fw: asStringOrNull(info['fw'], 'info.fw'),
              via: asStringOrNull(info['via'], 'info.via'),
            );
          }
        } on Object {
          // bez dostępu do tego urządzenia - zostaje wpis z indeksu
        }
        if (isHomeOwner &&
            fromInfo != null &&
            (indexed?.type != fromInfo.type ||
                indexed?.name != fromInfo.name ||
                (fromInfo.via != null && indexed?.via != fromInfo.via))) {
          await writeDeviceIndex(store, h, id, fromInfo.type, fromInfo.name ?? id, via: fromInfo.via).catchError((_) {});
        }
        return fromInfo ?? indexed;
      }),
    );
    return [for (final d in list) ?d];
  }

  CloudConnection<S, C> connection<S, C>(String deviceId, DeviceCodec<S, C> codec) =>
      CloudConnection<S, C>(store: store, homeId: homeId!, by: uid!, deviceId: deviceId, codec: codec);
}

/// `homes/{h}/deviceIndex` - lista urządzeń domu dla wszystkich domowników (pkt 12).
Future<Map<String, CloudDeviceSummary>> readDeviceIndex(CloudStore store, String homeId) async {
  final j = toJsonObject(await store.read('homes/$homeId/deviceIndex').catchError((_) => null)) ?? const {};
  return {
    for (final e in j.entries)
      if (e.value is Map)
        e.key: CloudDeviceSummary(
          id: e.key,
          type: DeviceType.fromWire((e.value as Map)['type']),
          name: (e.value as Map)['name'] as String?,
          via: (e.value as Map)['via'] as String?,
        ),
  };
}

/// Wpis w `deviceIndex` `{"type","name","via"?}` (pisze właściciel: przy dodaniu urządzenia, zmianie nazwy,
/// przypisaniu do huba). Reguły biorą stąd typ huba i przynależność do niego, nie z `devices/{id}/info`.
/// `update`, więc nie kasuje `via` zapisanego wcześniej.
Future<void> writeDeviceIndex(
  CloudStore store,
  String homeId,
  String deviceId,
  DeviceType type,
  String name, {
  String? via,
}) => store.update('homes/$homeId/deviceIndex/$deviceId', {'type': type.wire, 'name': name, 'via': ?via});

/// Przypisanie anonimowego konta urządzenia do domu (pkt 8.2): `homes/{h}/deviceAccounts/{deviceUid} = deviceId`.
Future<void> bindDeviceAccount(CloudStore store, String homeId, String deviceUid, String? deviceId) =>
    store.write('homes/$homeId/deviceAccounts/$deviceUid', deviceId);

/// Identyfikatory urządzeń domu (powiadomienia w tle): z `deviceIndex`, a u właściciela także `devices`.
Future<List<String>> homeDeviceIds(CloudStore store, String homeId, String uid) async {
  final ids = {...(await readDeviceIndex(store, homeId)).keys};
  ids.addAll(await store.childKeys('homes/$homeId/devices').catchError((_) => const <String>[]));
  return ids.toList();
}

/// Aplikacja zbudowana bez google-services.json - działa tylko w sieci lokalnej.
class NoCloudAccess extends CloudAccess {
  @override
  String get unavailableReason => 'Aplikacja nie ma konfiguracji Firebase - działa tylko w sieci domowej.';

  @override
  String? get uid => null;
  @override
  String? get email => null;
  @override
  String get apiKey => '';
  @override
  String get dbUrl => '';
  @override
  CloudStore get store => throw StateError('Brak chmury');
}

/// Firebase: konto z FirebaseAuth, dane z Realtime Database.
class FirebaseCloudAccess extends CloudAccess {
  FirebaseCloudAccess(this.options);

  final FirebaseOptions options;
  late final CloudStore _store = FirebaseCloudStore(
    FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: options.databaseURL),
  );

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  String? get unavailableReason => _user == null ? 'Zaloguj się, aby sterować termostatem spoza domu.' : null;

  @override
  String? get uid => _user?.uid;
  @override
  String? get email => _user?.email;
  @override
  String? get displayName => _user?.displayName;
  @override
  Future<String?> idToken() async => _user?.getIdToken();
  @override
  String get apiKey => options.apiKey;
  @override
  String get dbUrl => options.databaseURL ?? '';
  @override
  CloudStore get store => _store;
}
