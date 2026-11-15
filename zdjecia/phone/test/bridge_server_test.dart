import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zdjecia/background/auto_service.dart';
import 'package:zdjecia/bridge/bridge_server.dart';
import 'package:zdjecia/bridge/photo_prep.dart';
import 'package:zdjecia/bridge/published_source.dart';
import 'package:zdjecia/select/crop.dart';
import 'package:zdjecia/select/store.dart';

/// Zdjęcie źródłowe 1600×1200: niebieskie, prawa ćwiartka pomarańczowa
Uint8List sourcePhoto() {
  final src = img.Image(width: 1600, height: 1200);
  img.fill(src, color: img.ColorRgb8(0, 0, 255));
  img.fillRect(src, x1: 1200, y1: 0, x2: 1599, y2: 1199, color: img.ColorRgb8(200, 120, 40));
  return Uint8List.fromList(img.encodeJpg(src, quality: 92));
}

/// Czy JPEG jest progresywny (marker SOF2 w nagłówku przed danymi obrazu)
bool progressive(List<int> jpg) {
  var i = 2;
  while (i + 3 < jpg.length && jpg[i] == 0xFF) {
    final m = jpg[i + 1];
    if (m == 0xC2) return true;
    if (m == 0xDA) return false;
    i += 2 + (jpg[i + 2] << 8 | jpg[i + 3]);
  }
  return false;
}

void main() {
  late BridgeServer server;
  late HttpClient client;
  late List<BridgePhoto> photos;

  setUp(() async {
    photos = [
      BridgePhoto(id: 'a_1', png: Uint8List.fromList([1, 2, 3, 4]), taken: DateTime.utc(2026, 10, 19, 8), caption: 'Las'),
      BridgePhoto(
        id: 'm_2',
        png: Uint8List.fromList([5]),
        taken: DateTime.utc(2019, 8, 3),
        memory: true,
        jpeg: (w, h) async => utf8.encode('jpg ${w}x$h'),
      ),
    ];
    // Źródło czytane przy każdym zapytaniu - zmiana puli jest od razu widoczna
    server = BridgeServer(source: () async => photos, port: 0);
    await server.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.dispose();
  });

  Future<(int, List<int>, String?)> get(String path) async {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}$path'));
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    return (res.statusCode, bytes, res.headers.contentType?.mimeType);
  }

  test('lista zdjęć z podpisem i znacznikiem wspomnienia', () async {
    final (status, body, type) = await get('/manifest.json');
    expect(status, 200);
    expect(type, 'application/json');
    expect(jsonDecode(utf8.decode(body)), {
      'version': 1,
      'photos': [
        {'id': 'a_1', 'size': 4, 'taken': DateTime.utc(2026, 10, 19, 8).millisecondsSinceEpoch, 'caption': 'Las', 'memory': false},
        {'id': 'm_2', 'size': 1, 'taken': DateTime.utc(2019, 8, 3).millisecondsSinceEpoch, 'memory': true},
      ],
    });
  });

  test('JPEG dla zegara: rozmiar z zapytania, złe wymiary = 400, nieznane zdjęcie = 404', () async {
    final (status, body, type) = await get('/p/m_2.jpg?w=320&h=240');
    expect(status, 200);
    expect(type, 'image/jpeg');
    expect(utf8.decode(body), 'jpg 320x240');
    expect((await get('/p/m_2.jpg?w=64&h=800')).$1, 200);
    for (final q in ['', '?w=320', '?w=63&h=240', '?w=320&h=801', '?w=abc&h=240', '?w=320.5&h=240']) {
      expect((await get('/p/m_2.jpg$q')).$1, 400, reason: q);
    }
    expect((await get('/p/inne.jpg?w=320&h=240')).$1, 404);
    // zdjęcie bez JPEG-a (most go nie robi) też 404
    expect((await get('/p/a_1.jpg?w=320&h=240')).$1, 404);
    expect(jpegSide('800'), 800);
    expect(jpegSide('801'), isNull);
  });

  test('plik PNG, nieznane adresy i nowa pula bez restartu', () async {
    final (status, body, type) = await get('/p/a_1.png');
    expect(status, 200);
    expect(type, 'image/png');
    expect(body, [1, 2, 3, 4]);
    expect((await get('/p/inne.png')).$1, 404);
    expect((await get('/')).$1, 404);
    photos = [BridgePhoto(id: 'b_2', png: Uint8List.fromList([9]), taken: DateTime.utc(2026))];
    expect((await get('/p/a_1.png')).$1, 404);
    expect((await get('/p/b_2.png')).$2, [9]);
  });

  test('każde zapytanie trafia do dziennika (także przez usługę w tle)', () async {
    final logged = server.requests.first;
    await get('/manifest.json');
    final r = await logged;
    expect((r.path, r.status), ('/manifest.json', 200));
    expect(r.bytes, greaterThan(0));
    final back = BridgeRequest.fromJson(r.toJson());
    // przez kanał usługi czas idzie w milisekundach
    expect((back.path, back.bytes, back.took.inMilliseconds), (r.path, r.bytes, r.took.inMilliseconds));
  });

  test('opublikowana pula z plików (tak jak w usłudze w tle)', () async {
    final dir = await Directory.systemTemp.createTemp('zdjecia_pub');
    try {
      final store = SelectStore(dir);
      final png = File('${dir.path}/x.png')..writeAsBytesSync([7, 7]);
      await store.publish([
        PublishedPhoto(id: 'x_1', path: png.path, size: 2, taken: DateTime.utc(2026, 10, 1), caption: 'Morze'),
        PublishedPhoto(id: 'brak', path: '${dir.path}/nie-ma.png', size: 1, taken: DateTime.utc(2026)),
      ]);
      final list = await publishedPhotos(store);
      expect(list.map((p) => p.id), ['x_1']);
      expect(await list.single.read(), [7, 7]);
      expect(manifestOf(list)['photos'], [
        {'id': 'x_1', 'size': 2, 'taken': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch, 'caption': 'Morze', 'memory': false},
      ]);
      expect(list.single.jpeg, isNull); // bez wytwórcy JPEG-ów
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('JPEG z opublikowanej puli (usługa w tle): kadr z published.json, pamięć podręczna, sprzątanie', () async {
    final dir = await Directory.systemTemp.createTemp('zdjecia_jpg');
    // Galeria w teście: zapisuje, o które zdjęcia pytano; [gone] = zdjęcie usunięte z galerii
    final loads = <String>[];
    var gone = false;
    final store = SelectStore(dir);
    final maker = JpegMaker(store, loadSource: (assetId) async {
      if (gone) return null;
      loads.add(assetId);
      return sourcePhoto();
    });
    final pub = BridgeServer(source: () => publishedPhotos(store, jpeg: maker), port: 0);
    try {
      final png = File('${dir.path}/x.png')..writeAsBytesSync([7, 7]);
      await store.publish([
        PublishedPhoto(
          id: 'x_1',
          photoId: 'x',
          path: png.path,
          size: 2,
          taken: DateTime.utc(2019, 8, 3),
          memory: true,
          assetId: '42',
          // fragment od AI w prawej ćwiartce zdjęcia
          frame: const CropFrame(aspect: 4 / 3, focus: [0.78, 0.3, 0.2, 0.4]),
        ),
        // pula sprzed 0.10.0: bez danych kadru i bez analizy - JPEG-a nie da się zrobić
        PublishedPhoto(id: 'old_1', path: png.path, size: 2, taken: DateTime.utc(2026)),
      ]);
      final back = (await store.loadPublished()).first;
      expect((back.memory, back.assetId), (true, '42'));
      expect(back.frame?.focus, [0.78, 0.3, 0.2, 0.4]);

      await pub.start();
      Future<(int, List<int>, String?)> fetch(String path) async {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:${pub.boundPort}$path'));
        final res = await req.close();
        final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
        return (res.statusCode, bytes, res.headers.contentType?.mimeType);
      }

      final manifest = jsonDecode(utf8.decode((await fetch('/manifest.json')).$2)) as Map;
      expect([for (final p in manifest['photos'] as List) p['memory']], [true, false]);

      final (status, body, type) = await fetch('/p/x_1.jpg?w=320&h=240');
      expect(status, 200);
      expect(type, 'image/jpeg');
      expect(body.length, lessThanOrEqualTo(maxJpegBytes));
      expect(progressive(body), isFalse);
      final out = img.decodeJpg(Uint8List.fromList(body))!;
      expect((out.width, out.height), (320, 240));
      expect(out.getPixel(160, 120).r, greaterThan(150)); // środek kadru w pomarańczowej części
      expect(loads, ['42']);

      // drugie pobranie z pamięci podręcznej (bez sięgania do galerii), inny rozmiar = nowy plik
      expect((await fetch('/p/x_1.jpg?w=320&h=240')).$2, body);
      expect(loads, ['42']);
      final square = await fetch('/p/x_1.jpg?w=260&h=260');
      expect(img.decodeJpg(Uint8List.fromList(square.$2))!.width, 260);
      expect(loads, ['42', '42']);
      expect(store.jpegFile('x_1', 320, 240).existsSync(), isTrue);

      expect((await fetch('/p/old_1.jpg?w=320&h=240')).$1, 404);
      // zdjęcia nie ma już w galerii
      gone = true;
      expect((await fetch('/p/x_1.jpg?w=400&h=300')).$1, 404);

      // po nowej puli zostają tylko JPEG-i zdjęć z puli i z bieżącej wersji obróbki
      final stale = File('${store.jpegDir.path}/x_1_320x240_s1r0.jpg')..writeAsBytesSync([1]);
      await store.pruneJpegs({'x_1'});
      expect(store.jpegFile('x_1', 320, 240).existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);
      await store.pruneJpegs({'y_2'});
      expect(store.jpegFile('x_1', 260, 260).existsSync(), isFalse);
    } finally {
      await pub.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('blokada: tylko jedno odświeżanie naraz, porzucona blokada wygasa', () async {
    final dir = await Directory.systemTemp.createTemp('zdjecia_lock');
    try {
      final a = SelectStore(dir), b = SelectStore(dir);
      final now = DateTime(2026, 10, 20, 9);
      expect(await a.tryLock(now: now), isTrue);
      expect(await b.tryLock(now: now.add(const Duration(minutes: 5))), isFalse);
      expect(await b.tryLock(now: now.add(staleLock + const Duration(minutes: 1))), isTrue);
      await b.unlock();
      expect(await a.tryLock(now: now), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('automatyczne odświeżanie: co 12 h, po błędzie po godzinie', () async {
    final now = DateTime(2026, 10, 20, 12);
    expect(autoRefreshDue(const AutoState(), now), isTrue);
    expect(autoRefreshDue(AutoState(lastRun: now.subtract(const Duration(hours: 11))), now), isFalse);
    expect(autoRefreshDue(AutoState(lastRun: now.subtract(const Duration(hours: 12))), now), isTrue);
    expect(autoRefreshDue(AutoState(lastRun: now.subtract(const Duration(minutes: 70)), ok: false), now), isTrue);

    final dir = await Directory.systemTemp.createTemp('zdjecia_auto');
    try {
      final store = SelectStore(dir);
      await store.saveAuto(AutoState(lastRun: now, poolSize: 20, newPhotos: 3));
      final back = await store.loadAuto();
      expect((back.lastRun, back.poolSize, back.newPhotos, back.ok), (now, 20, 3, true));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('tekst powiadomienia usługi', () {
    final t = DateTime(2026, 10, 20, 8, 15);
    expect(autoNotificationText(const AutoState()), 'Udostępniam pulę zegarkowi');
    expect(autoNotificationText(AutoState(lastRun: t, poolSize: 20, newPhotos: 2)), 'Pula: 20 zdjęć, nowe: 2 · odświeżono 20.10 08:15');
    expect(autoNotificationText(AutoState(lastRun: t, ok: false)), contains('nieudane'));
  });
}
