import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zdjecia/background/auto_service.dart';
import 'package:zdjecia/bridge/bridge_server.dart';
import 'package:zdjecia/bridge/published_source.dart';
import 'package:zdjecia/select/store.dart';

void main() {
  late BridgeServer server;
  late HttpClient client;
  late List<BridgePhoto> photos;

  setUp(() async {
    photos = [
      BridgePhoto(id: 'a_1', png: Uint8List.fromList([1, 2, 3, 4]), taken: DateTime.utc(2026, 10, 19, 8), caption: 'Las'),
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

  test('lista zdjęć z podpisem', () async {
    final (status, body, type) = await get('/manifest.json');
    expect(status, 200);
    expect(type, 'application/json');
    expect(jsonDecode(utf8.decode(body)), {
      'version': 1,
      'photos': [
        {'id': 'a_1', 'size': 4, 'taken': DateTime.utc(2026, 10, 19, 8).millisecondsSinceEpoch, 'caption': 'Las'},
      ],
    });
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
        {'id': 'x_1', 'size': 2, 'taken': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch, 'caption': 'Morze'},
      ]);
    } finally {
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
