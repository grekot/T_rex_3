// Zdjęcia na zegarach (docs/API.md pkt 10.2 „Zdjęcia”): aplikacja „Zdjęcia” na tym samym telefonie wystawia mostem HTTP
// tylko pod 127.0.0.1:8765 listę dla zegarów (`/clocks.json`: pula zegarka + co godzinę kilka zdjęć z archiwum, każde
// z czasem dodania; starsze wersje - tylko `/manifest.json` z pulą ~20 zdjęć), a HomeAutomation przenosi je do zegarów
// z ekranem `photo` w pokazie. Zegar trzyma najnowsze wg czasu dodania, więc przez dzień zdjęcia wymieniają się po kilka.
// Zdjęcia „spalone” na zegarze (obejrzane przy przeglądaniu, `seen` w `GET /api/photos`, zegar biurkowy 0.9.3+)
// ustępują miejsca kolejnym z listy - o ile są czym je zastąpić.
// Najpierw czysta logika różnic ([planPhotoSync]), potem wykonanie po HTTP ([PhotoSync]). Gdy nic się nie zmieniło,
// przebieg kończy się na trzech małych GET-ach do zegara - bez pobierania zdjęć z mostu.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_type.dart';
import '../models/json_utils.dart';
import 'device_store.dart';
import 'local_endpoint.dart';

/// Most aplikacji „Zdjęcia” (tylko pętla zwrotna telefonu).
final defaultPhotoBridge = Uri.parse('http://127.0.0.1:8765');

/// Najwyżej tyle zdjęć wysyłamy w jednym przebiegu (reszta w następnym, za ~15 min).
const photoUploadsPerRun = 6;

/// Rok na końcu podpisu wspomnienia w manifeście mostu („Nad jeziorem · 2019”).
final _memoryYear = RegExp(r'\s·\s\d{4}$');

/// Identyfikator zdjęcia, jaki przyjmuje zegar.
final _photoId = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

/// Zdjęcie z listy mostu: [taken] w ms (jak w moście), [caption] od AI ('' = bez podpisu),
/// [memory] = wspomnienie (z historii galerii albo z archiwum), [added] - kiedy weszło do listy dla zegarów (ms).
class BridgePhoto {
  const BridgePhoto({required this.id, required this.taken, this.caption = '', this.memory = false, this.added});

  final String id;
  final int taken;
  final String caption;
  final bool memory;
  final int? added;

  /// Kolejność na zegarze: najpóźniej dodane (stary most bez [added] - najnowsze zdjęcia).
  int get order => added ?? taken;

  /// Czas zrobienia w sekundach od epoki (tak zapisuje zegar).
  int get takenS => taken ~/ 1000;

  /// Podpis dla zegara: przy wspomnieniu bez końcówki „ · 2019” (most dopisuje rok dla zegarka Zepp, a zegar sam
  /// pokazuje „wspomnienie · sierpień 2019”).
  String get clockCaption => memory ? caption.replaceFirst(_memoryYear, '') : caption;

  /// Podpis do porównania z zegarem (na podpisie już obciętym): zmiana = wysłać jeszcze raz.
  String get signature => photoSignature(takenS, memory, clockCaption);

  static BridgePhoto? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return BridgePhoto(
      id: j['id'] as String,
      taken: j['taken'] is num ? (j['taken'] as num).toInt() : 0,
      caption: j['caption'] is String ? j['caption'] as String : '',
      memory: j['memory'] == true,
      added: j['added'] is num ? (j['added'] as num).toInt() : null,
    );
  }

  /// Lista z `{"version":1,"photos":[...]}`; null = to nie jest manifest mostu.
  static List<BridgePhoto>? manifest(Object? j) {
    if (j is! Map || j['photos'] is! List) return null;
    return [for (final p in j['photos'] as List) ?fromJson(p)];
  }
}

/// Zdjęcie zapisane w zegarze (`GET /api/photos`): [taken] w sekundach; [seen] - obejrzane przy przeglądaniu.
class ClockPhoto {
  const ClockPhoto({
    required this.id,
    this.size = 0,
    this.taken,
    this.caption = '',
    this.memory = false,
    this.seen = false,
  });

  final String id;
  final int size;
  final int? taken;
  final String caption;
  final bool memory;
  final bool seen;

  String get signature => photoSignature(taken ?? -1, memory, caption);

  static ClockPhoto? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return ClockPhoto(
      id: j['id'] as String,
      size: j['size'] is num ? (j['size'] as num).toInt() : 0,
      taken: j['taken'] is num ? (j['taken'] as num).toInt() : null,
      caption: j['caption'] is String ? j['caption'] as String : '',
      memory: j['memory'] == true,
      seen: j['seen'] == true,
    );
  }
}

/// Odpowiedź `GET /api/photos`: rozmiar kadru [w]×[h], [max] zdjęć (z wolnego miejsca), [maxBytes] na plik.
class ClockPhotos {
  const ClockPhotos({
    this.w = 320,
    this.h = 240,
    this.max = 20,
    this.maxBytes = 98304,
    this.busy = false,
    this.photos = const [],
  });

  final int w, h, max, maxBytes;
  final bool busy;
  final List<ClockPhoto> photos;

  factory ClockPhotos.fromJson(Json j) {
    int n(String k, int d) => j[k] is num ? (j[k] as num).toInt() : d;
    return ClockPhotos(
      w: n('w', 320),
      h: n('h', 240),
      max: n('max', 20),
      maxBytes: n('maxBytes', 98304),
      busy: j['busy'] == true,
      photos: [for (final p in (j['photos'] is List ? j['photos'] as List : const [])) ?ClockPhoto.fromJson(p)],
    );
  }
}

String photoSignature(int takenS, bool memory, String caption) => '$takenS|${memory ? 1 : 0}|$caption';

/// Co zrobić w jednym przebiegu: [delete] najpierw (miejsce), potem [upload] (najnowsze najpierw).
class PhotoPlan {
  const PhotoPlan({this.delete = const [], this.upload = const [], this.waiting = 0});

  final List<String> delete;
  final List<BridgePhoto> upload;

  /// Ile zdjęć z puli czeka na kolejne przebiegi (limit [photoUploadsPerRun]).
  final int waiting;

  bool get isEmpty => delete.isEmpty && upload.isEmpty;
}

/// Różnice puli mostu i zegara.
/// - Na zegarze ma być najwyżej `max` najpóźniej dodanych zdjęć puli ([BridgePhoto.order] malejąco); inne - do usunięcia.
/// - Brakujące i te ze zmienionym podpisem (`taken`, `memory`, `caption`) - do wysłania, najwyżej [maxUploads].
/// - [sent]: podpis wysłany ostatnio do tego zegara. Gdy zegar odda podpis inaczej (np. przycięty), nie wysyłamy
///   w kółko: zmiana liczy się tylko, gdy podpis z puli różni się też od wysłanego.
/// - [rejected]: podpisy, których zegar nie przyjął (`400`, `413`) albo most nie dał - pomijane, dopóki się nie zmienią.
/// - [burned]: „spalone” (obejrzane przy przeglądaniu na zegarze) - idą na koniec kolejki: na zegarze zostają tylko,
///   gdy w liście nie ma dość innych zdjęć.
PhotoPlan planPhotoSync({
  required List<BridgePhoto> pool,
  required ClockPhotos clock,
  Map<String, String> sent = const {},
  Map<String, String> rejected = const {},
  Set<String> burned = const {},
  int maxUploads = photoUploadsPerRun,
}) {
  final ids = <String>{};
  final valid =
      [
        for (final p in pool)
          if (_photoId.hasMatch(p.id) && ids.add(p.id)) p,
      ]..sort((a, b) {
        final ba = burned.contains(a.id), bb = burned.contains(b.id);
        if (ba != bb) return ba ? 1 : -1;
        return b.order != a.order ? b.order.compareTo(a.order) : a.id.compareTo(b.id);
      });
  final wanted = valid.take(clock.max < 0 ? 0 : clock.max).toList();
  final wantedIds = {for (final p in wanted) p.id};
  final onClock = {for (final p in clock.photos) p.id: p};

  final delete = [
    for (final p in clock.photos)
      if (!wantedIds.contains(p.id)) p.id,
  ];
  var free = clock.max - (clock.photos.length - delete.length);
  final upload = <BridgePhoto>[];
  var waiting = 0;
  for (final p in wanted) {
    final sig = p.signature;
    if (rejected[p.id] == sig) continue;
    final have = onClock[p.id];
    final needed = have == null ? free > 0 : have.signature != sig && sent[p.id] != sig;
    if (!needed) continue;
    if (upload.length >= maxUploads) {
      waiting++;
      continue;
    }
    if (have == null) free--;
    upload.add(p);
  }
  return PhotoPlan(delete: delete, upload: upload, waiting: waiting);
}

// ---------------------------------------------------------------- Stan synchronizacji (do UI)

/// Wynik ostatniej próby dla zegara.
enum PhotoSyncResult {
  ok('ok'),

  /// Ekranu `photo` nie ma w `screens.list` - zegara nie ruszamy.
  off('off'),
  unreachable('unreachable'),

  /// Zegar bez `/api/photos` (starszy firmware).
  unsupported('unsupported'),
  unauthorized('unauthorized'),

  /// `507 full` - zegar nie ma miejsca.
  full('full'),

  /// Zegar zajęty zapisem dłużej niż 10 prób.
  busy('busy'),
  error('error');

  const PhotoSyncResult(this.wire);

  final String wire;

  static PhotoSyncResult fromWire(Object? v) => values.where((r) => r.wire == v).firstOrNull ?? error;
}

/// Stan zegara po ostatniej próbie. [okAt] i [count] - ostatnia udana synchronizacja (do „ostatnio HH:MM”).
class PhotoSyncStatus {
  const PhotoSyncStatus({
    required this.at,
    required this.result,
    this.okAt,
    this.count,
    this.photoOn,
    this.detail,
    this.sent = const {},
    this.rejected = const {},
    this.burned = const {},
  });

  /// Ostatnia próba (ms od epoki).
  final int at;
  final PhotoSyncResult result;
  final int? okAt;
  final int? count;

  /// Ekran `photo` w pokazie (ostatnio widziany); null = nie wiadomo.
  final bool? photoOn;
  final String? detail;
  final Map<String, String> sent, rejected;

  /// Zdjęcia „spalone” na tym zegarze (`seen` z `GET /api/photos`) - pamiętane, dopóki są w liście mostu.
  final Set<String> burned;

  PhotoSyncStatus copyWith({
    int? at,
    PhotoSyncResult? result,
    int? okAt,
    int? count,
    bool? photoOn,
    String? detail,
    Map<String, String>? sent,
    Map<String, String>? rejected,
    Set<String>? burned,
  }) => PhotoSyncStatus(
    at: at ?? this.at,
    result: result ?? this.result,
    okAt: okAt ?? this.okAt,
    count: count ?? this.count,
    photoOn: photoOn ?? this.photoOn,
    detail: detail,
    sent: sent ?? this.sent,
    rejected: rejected ?? this.rejected,
    burned: burned ?? this.burned,
  );

  Json toJson() => {
    'at': at,
    'result': result.wire,
    'okAt': ?okAt,
    'count': ?count,
    'photoOn': ?photoOn,
    'detail': ?detail,
    if (sent.isNotEmpty) 'sent': sent,
    if (rejected.isNotEmpty) 'rejected': rejected,
    if (burned.isNotEmpty) 'burned': burned.toList(),
  };

  static PhotoSyncStatus? fromJson(Object? j) {
    if (j is! Map || j['at'] is! num) return null;
    Map<String, String> map(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if (e.value is String) '${e.key}': e.value as String,
    };
    return PhotoSyncStatus(
      at: (j['at'] as num).toInt(),
      result: PhotoSyncResult.fromWire(j['result']),
      okAt: j['okAt'] is num ? (j['okAt'] as num).toInt() : null,
      count: j['count'] is num ? (j['count'] as num).toInt() : null,
      photoOn: j['photoOn'] is bool ? j['photoOn'] as bool : null,
      detail: j['detail'] is String ? j['detail'] as String : null,
      sent: map(j['sent']),
      rejected: map(j['rejected']),
      burned: {if (j['burned'] is List) ...(j['burned'] as List).whereType<String>()},
    );
  }
}

/// Ostatnie sprawdzenie mostu: [ok] = most odpowiedział manifestem.
typedef BridgeSeen = ({int at, bool ok});

/// Zapis stanu synchronizacji (SharedPreferences; w testach w pamięci).
abstract class PhotoSyncLog {
  Future<PhotoSyncStatus?> clock(String id);
  Future<void> saveClock(String id, PhotoSyncStatus status);
  Future<BridgeSeen?> bridge();
  Future<void> saveBridge(BridgeSeen seen);

  /// Ekran `photo` w pokazie zegara (z Config widzianego w aplikacji) - bez sieci.
  Future<void> notePhotoOn(String id, bool on, {int? now}) async {
    final s = await clock(id);
    if (s?.photoOn == on) return;
    await saveClock(
      id,
      s == null
          ? PhotoSyncStatus(at: 0, result: on ? PhotoSyncResult.ok : PhotoSyncResult.off, photoOn: on)
          : s.copyWith(photoOn: on, detail: s.detail),
    );
  }
}

class PrefsPhotoSyncLog extends PhotoSyncLog {
  static const _bridgeKey = 'photo_bridge';
  static String _clockKey(String id) => 'photo_sync_$id';

  SharedPreferencesAsync? _prefs;

  /// Leniwie: w testach bez wtyczki konstruktor rzuca - wtedy po prostu nic nie pamiętamy.
  SharedPreferencesAsync get _p => _prefs ??= SharedPreferencesAsync();

  Future<Object?> _read(String key) async {
    try {
      final raw = await _p.getString(key);
      return raw == null ? null : jsonDecode(raw);
    } on Object {
      return null;
    }
  }

  Future<void> _write(String key, Object value) async {
    try {
      await _p.setString(key, jsonEncode(value));
    } on Object {
      // Brak magazynu (testy) - stan tylko do pokazania, synchronizacja działa bez niego.
    }
  }

  @override
  Future<PhotoSyncStatus?> clock(String id) async => PhotoSyncStatus.fromJson(await _read(_clockKey(id)));

  @override
  Future<void> saveClock(String id, PhotoSyncStatus status) => _write(_clockKey(id), status.toJson());

  @override
  Future<BridgeSeen?> bridge() async {
    final j = await _read(_bridgeKey);
    if (j is! Map || j['at'] is! num) return null;
    return (at: (j['at'] as num).toInt(), ok: j['ok'] == true);
  }

  @override
  Future<void> saveBridge(BridgeSeen seen) => _write(_bridgeKey, {'at': seen.at, 'ok': seen.ok});
}

class MemoryPhotoSyncLog extends PhotoSyncLog {
  final clocks = <String, PhotoSyncStatus>{};
  BridgeSeen? lastBridge;

  @override
  Future<PhotoSyncStatus?> clock(String id) async => clocks[id];

  @override
  Future<void> saveClock(String id, PhotoSyncStatus status) async => clocks[id] = status;

  @override
  Future<BridgeSeen?> bridge() async => lastBridge;

  @override
  Future<void> saveBridge(BridgeSeen seen) async => lastBridge = seen;
}

/// Zegar, do którego synchronizacja ma sens: własny token ≥ `control` (sprawdzany przy wywołaniu).
bool photoSyncCandidate(PairedDevice d) => d.type == DeviceType.clock && d.access.canControl;

/// Czy zadanie w tle jest potrzebne: jest zegar z tokenem ≥ `control`, który nie ma na pewno wyłączonego ekranu `photo`.
Future<bool> photoSyncWanted(DeviceStore store, PhotoSyncLog log) async {
  for (final d in await store.devices()) {
    if (!photoSyncCandidate(d) || await store.token(d.id) == null) continue;
    if ((await log.clock(d.id))?.photoOn != false) return true;
  }
  return false;
}

// ---------------------------------------------------------------- Wykonanie

/// Wynik przebiegu: [bridge] = most odpowiedział; stany zegarów, które sprawdzaliśmy.
class PhotoSyncReport {
  const PhotoSyncReport({this.bridge, this.clocks = const {}, this.sent = 0, this.deleted = 0});

  /// null = nie pytaliśmy (żaden zegar do sprawdzenia).
  final bool? bridge;
  final Map<String, PhotoSyncStatus> clocks;
  final int sent, deleted;
}

class _Stop implements Exception {
  const _Stop(this.result, [this.detail]);

  final PhotoSyncResult result;
  final String? detail;
}

/// Synchronizacja puli mostu z zegarami w sieci lokalnej.
class PhotoSync {
  PhotoSync({
    required this.store,
    PhotoSyncLog? log,
    http.Client Function()? clientFactory,
    Uri? bridge,
    this.busyDelay = const Duration(seconds: 1),
    this.busyTries = 10,
    this.clockTimeout = const Duration(seconds: 5),
    this.bridgeTimeout = const Duration(seconds: 3),
    this.imageTimeout = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : log = log ?? PrefsPhotoSyncLog(),
       bridge = bridge ?? defaultPhotoBridge,
       _clientFactory = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;

  final DeviceStore store;
  final PhotoSyncLog log;
  final Uri bridge;
  final Duration busyDelay;
  final int busyTries;
  final Duration clockTimeout, bridgeTimeout, imageTimeout;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;

  /// Jeden przebieg naraz w tym izolacie (start aplikacji i ekran zegara mogą wołać prawie jednocześnie).
  static Future<void> _queue = Future.value();

  /// Przebieg dla wszystkich zegarów albo tylko [deviceId] (wtedy [endpoint] - adres z bieżącego połączenia).
  /// [minInterval]: zegar sprawdzony niedawno pomijamy (wywołania z UI).
  Future<PhotoSyncReport> run({String? deviceId, LocalEndpoint? endpoint, Duration minInterval = Duration.zero}) {
    final done = Completer<PhotoSyncReport>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _run(deviceId, endpoint, minInterval));
      } on Object catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<PhotoSyncReport> _run(String? deviceId, LocalEndpoint? endpoint, Duration minInterval) async {
    final now = _now().millisecondsSinceEpoch;
    final targets = <(PairedDevice, String, LocalEndpoint, PhotoSyncStatus?)>[];
    for (final d in await store.devices()) {
      if (deviceId != null && d.id != deviceId) continue;
      if (!photoSyncCandidate(d)) continue;
      final ep = (deviceId != null ? endpoint : null) ?? d.lastEndpoint;
      if (ep == null || !isLocalNetworkHost(ep.host)) continue;
      final token = await store.token(d.id);
      if (token == null) continue;
      final prev = await log.clock(d.id);
      if (prev != null && prev.photoOn == false && minInterval > Duration.zero) continue;
      if (prev != null && now - prev.at < minInterval.inMilliseconds) continue;
      targets.add((d, token, ep, prev));
    }
    if (targets.isEmpty) return const PhotoSyncReport();

    final client = _clientFactory();
    try {
      final pool = await _manifest(client);
      await log.saveBridge((at: now, ok: pool != null));
      if (pool == null) return const PhotoSyncReport(bridge: false);

      final out = <String, PhotoSyncStatus>{};
      var sent = 0, deleted = 0;
      for (final (d, token, ep, prev) in targets) {
        final r = await _syncClock(client, d, token, ep, pool, prev);
        out[d.id] = r.status;
        sent += r.sent;
        deleted += r.deleted;
        await log.saveClock(d.id, r.status);
      }
      return PhotoSyncReport(bridge: true, clocks: out, sent: sent, deleted: deleted);
    } finally {
      client.close();
    }
  }

  /// Lista mostu dla zegarów (`/clocks.json`, a gdy aplikacja Zdjęcia jej nie zna - `/manifest.json`);
  /// null = brak mostu (aplikacja Zdjęcia nie zainstalowana albo jej usługa nie działa).
  Future<List<BridgePhoto>?> _manifest(http.Client client) async {
    try {
      var res = await client.get(bridge.replace(path: '/clocks.json')).timeout(bridgeTimeout);
      if (res.statusCode == 404) res = await client.get(bridge.replace(path: '/manifest.json')).timeout(bridgeTimeout);
      if (res.statusCode != 200) return null;
      return BridgePhoto.manifest(jsonDecode(utf8.decode(res.bodyBytes)));
    } on Object {
      return null;
    }
  }

  Future<({PhotoSyncStatus status, int sent, int deleted})> _syncClock(
    http.Client client,
    PairedDevice d,
    String token,
    LocalEndpoint ep,
    List<BridgePhoto> pool,
    PhotoSyncStatus? prev,
  ) async {
    final at = _now().millisecondsSinceEpoch;
    var status = (prev ?? PhotoSyncStatus(at: at, result: PhotoSyncResult.ok)).copyWith(at: at);
    var sent = 0, deleted = 0;
    var count = prev?.count;
    final sentSigs = {...status.sent};
    final rejected = {...status.rejected};
    final burned = {...status.burned};
    try {
      // To ten zegar? (stary adres mógł dostać inny sprzęt - tokenu nie wysyłamy w ciemno).
      final info = await _clock(client, 'GET', ep, '/api/info', timeout: const Duration(seconds: 2));
      if (info.$1 != 200 || info.$2?['id'] != d.id) throw const _Stop(PhotoSyncResult.unreachable);

      final cfg = await _clock(client, 'GET', ep, '/api/config', token: token);
      _checkAuth(cfg.$1);
      if (cfg.$1 != 200 || cfg.$2 == null) throw _Stop(PhotoSyncResult.error, 'Config: HTTP ${cfg.$1}');
      final screens = cfg.$2!['screens'];
      final on = screens is Map && screens['list'] is List && (screens['list'] as List).contains('photo');
      status = status.copyWith(photoOn: on);
      if (!on) throw const _Stop(PhotoSyncResult.off);

      final list = await _clock(client, 'GET', ep, '/api/photos', token: token);
      _checkAuth(list.$1);
      if (list.$1 == 404) throw const _Stop(PhotoSyncResult.unsupported);
      if (list.$1 != 200 || list.$2 == null || list.$2!['ok'] == false) {
        throw _Stop(PhotoSyncResult.error, '/api/photos: HTTP ${list.$1}');
      }
      final photos = ClockPhotos.fromJson(list.$2!);
      count = photos.photos.length;

      // Zapomniane: zdjęć spoza puli nie pamiętamy.
      final poolIds = {for (final p in pool) p.id};
      sentSigs.removeWhere((id, _) => !poolIds.contains(id));
      rejected.removeWhere((id, _) => !poolIds.contains(id));
      burned
        ..addAll([
          for (final p in photos.photos)
            if (p.seen) p.id,
        ])
        ..removeWhere((id) => !poolIds.contains(id));

      final plan = planPhotoSync(pool: pool, clock: photos, sent: sentSigs, rejected: rejected, burned: burned);
      final have = {for (final p in photos.photos) p.id};

      for (final id in plan.delete) {
        final r = await _busy(() => _clock(client, 'DELETE', ep, '/api/photos/$id', token: token));
        _checkAuth(r.$1);
        if (r.$1 == 503) throw const _Stop(PhotoSyncResult.busy);
        if (r.$1 != 200 && r.$1 != 404) throw _Stop(PhotoSyncResult.error, 'DELETE: HTTP ${r.$1}');
        if (have.remove(id)) deleted++;
        sentSigs.remove(id);
      }

      for (final p in plan.upload) {
        final jpeg = await _image(client, p.id, photos.w, photos.h);
        if (jpeg == null) continue; // zdjęcie zniknęło z puli między manifestem a pobraniem
        if (jpeg.isEmpty || jpeg.length > photos.maxBytes) {
          rejected[p.id] = p.signature;
          continue;
        }
        final r = await _busy(() => _put(client, ep, token, p, jpeg));
        _checkAuth(r.$1);
        switch (r.$1) {
          case 200:
            sent++;
            have.add(p.id);
            sentSigs[p.id] = p.signature;
            rejected.remove(p.id);
          case 400 || 413:
            rejected[p.id] = p.signature;
          case 507:
            throw const _Stop(PhotoSyncResult.full);
          case 503:
            throw const _Stop(PhotoSyncResult.busy);
          default:
            throw _Stop(PhotoSyncResult.error, 'PUT: HTTP ${r.$1}');
        }
      }
      count = have.length;
      return (
        status: status.copyWith(
          result: PhotoSyncResult.ok,
          okAt: at,
          count: count,
          sent: sentSigs,
          rejected: rejected,
          burned: burned,
        ),
        sent: sent,
        deleted: deleted,
      );
    } on _Stop catch (s) {
      return (
        status: status.copyWith(
          result: s.result,
          detail: s.detail,
          count: count,
          sent: sentSigs,
          rejected: rejected,
          burned: burned,
        ),
        sent: sent,
        deleted: deleted,
      );
    } on Object catch (e) {
      // _BridgeImage i nieprzewidziane (np. zła odpowiedź) - błąd tego zegara, inne zegary dalej.
      return (
        status: status.copyWith(
          result: PhotoSyncResult.error,
          detail: e is _BridgeImage ? e.message : '$e',
          count: count,
          sent: sentSigs,
          rejected: rejected,
          burned: burned,
        ),
        sent: sent,
        deleted: deleted,
      );
    }
  }

  static void _checkAuth(int code) {
    if (code == 401 || code == 403) throw const _Stop(PhotoSyncResult.unauthorized);
  }

  /// `503 busy` - zegar jeszcze zapisuje poprzednie zdjęcie: ponawiamy co [busyDelay], najwyżej [busyTries] razy.
  Future<(int, Json?)> _busy(Future<(int, Json?)> Function() f) async {
    for (var i = 1; ; i++) {
      final r = await f();
      if (r.$1 != 503 || i >= busyTries) return r;
      await Future<void>.delayed(busyDelay);
    }
  }

  Future<(int, Json?)> _clock(
    http.Client client,
    String method,
    LocalEndpoint ep,
    String path, {
    String? token,
    Duration? timeout,
  }) async {
    final req = http.Request(method, ep.http(path));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    return _send(client, req, timeout ?? clockTimeout);
  }

  /// `PUT /api/photos/<id>?caption=&taken=&memory=` - treść JPEG. Podpis kodowany `%20` (nie `+`).
  Future<(int, Json?)> _put(http.Client client, LocalEndpoint ep, String token, BridgePhoto p, Uint8List jpeg) {
    final query = 'caption=${Uri.encodeComponent(p.clockCaption)}&taken=${p.takenS}&memory=${p.memory ? 1 : 0}';
    final req = http.Request('PUT', ep.http('/api/photos/${p.id}').replace(query: query))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'image/jpeg'
      ..bodyBytes = jpeg;
    return _send(client, req, clockTimeout + const Duration(seconds: 10));
  }

  Future<(int, Json?)> _send(http.Client client, http.BaseRequest req, Duration timeout) async {
    final http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(req).timeout(timeout)).timeout(timeout);
    } on Object {
      throw const _Stop(PhotoSyncResult.unreachable);
    }
    Json? body;
    try {
      final v = jsonDecode(utf8.decode(res.bodyBytes));
      if (v is Map) body = v.cast<String, dynamic>();
    } on FormatException {
      body = null;
    }
    // Zegar zgłasza zajętość w treści - liczy się `busy`, nawet gdyby kod był inny.
    if (body?['error'] == 'busy') return (503, body);
    return (res.statusCode, body);
  }

  /// Kadr W×H z mostu; null = brak zdjęcia (404).
  Future<Uint8List?> _image(http.Client client, String id, int w, int h) async {
    final http.Response res;
    try {
      res = await client
          .get(bridge.replace(path: '/p/$id.jpg', queryParameters: {'w': '$w', 'h': '$h'}))
          .timeout(imageTimeout);
    } on Object {
      throw const _BridgeImage('Aplikacja Zdjęcia nie oddała zdjęcia.');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode == 400) return Uint8List(0); // zły rozmiar kadru - nie ponawiamy co przebieg
    if (res.statusCode != 200) throw _BridgeImage('Aplikacja Zdjęcia: HTTP ${res.statusCode}.');
    final b = res.bodyBytes;
    // Tylko JPEG (SOI FF D8) - inaczej zegar i tak odrzuci.
    return b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8 ? b : Uint8List(0);
  }
}

class _BridgeImage implements Exception {
  const _BridgeImage(this.message);

  final String message;
}

// ---------------------------------------------------------------- Opis do UI

String _photosWord(int n) {
  if (n == 1) return 'zdjęcie';
  final few = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return few ? 'zdjęcia' : 'zdjęć';
}

String _when(int ms, DateTime now) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return hm;
  if (today.difference(day).inDays == 1) return 'wczoraj $hm';
  return '${t.day}.${two(t.month)} $hm';
}

/// Stan do ustawień zegara: „5 zdjęć na zegarze · ostatnio 14:05” albo podpowiedź o aplikacji Zdjęcia.
/// [onClock] - liczba z State `photos` (dokładniejsza niż z ostatniej synchronizacji).
String photoSyncText({BridgeSeen? bridge, PhotoSyncStatus? status, int? onClock, DateTime? now}) {
  final n = now ?? DateTime.now();
  if (bridge != null && !bridge.ok) return 'Zainstaluj aplikację Zdjęcia i włącz jej usługę w tle';
  final count = onClock ?? status?.count;
  final okAt = status?.okAt;
  final head = [
    if (count != null) '$count ${_photosWord(count)} na zegarze',
    if (okAt != null) 'ostatnio ${_when(okAt, n)}',
  ].join(' · ');
  final problem = switch (status?.result) {
    PhotoSyncResult.full => 'Zegar nie ma miejsca na więcej zdjęć',
    PhotoSyncResult.unsupported => 'Zegar nie przyjmuje zdjęć - zaktualizuj jego oprogramowanie',
    PhotoSyncResult.unauthorized => 'Zegar odrzucił token - sparuj telefon ponownie',
    PhotoSyncResult.busy => 'Zegar był zajęty zapisem - kolejna próba za kilkanaście minut',
    PhotoSyncResult.error => 'Błąd synchronizacji${status?.detail == null ? '' : ' (${status!.detail})'}',
    PhotoSyncResult.unreachable when okAt == null => 'Zegar nie odpowiadał w sieci domowej',
    _ => null,
  };
  if (head.isEmpty && problem == null) {
    return bridge == null ? 'Jeszcze nie synchronizowano' : 'Zdjęcia trafią na zegar przy najbliższej synchronizacji';
  }
  return [if (head.isNotEmpty) head, ?problem].join('\n');
}
