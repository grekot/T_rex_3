// Zdjęcia na zegarach (lib/data/photo_sync.dart): logika różnic, potem przebiegi po HTTP z atrapą mostu aplikacji
// „Zdjęcia” i atrapą zegara (prawdziwe gniazda - zwykłe test(), bez testWidgets).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/photo_sync.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/ui/clock_photos.dart';

import '../tool/fake/fake_photo_bridge.dart';
import '../tool/fake/fake_thermostat_server.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => Stream.value(const []);
}

BridgePhoto _b(String id, int day, {String caption = '', bool memory = false}) =>
    BridgePhoto(id: id, taken: DateTime(2026, 11, day, 12).millisecondsSinceEpoch, caption: caption, memory: memory);

ClockPhoto _c(BridgePhoto p, {String? caption}) =>
    ClockPhoto(id: p.id, taken: p.takenS, caption: caption ?? p.caption, memory: p.memory);

void main() {
  group('różnice puli i zegara', () {
    test('brakujące najnowsze najpierw (najwyżej 6), spoza puli do usunięcia, reszta czeka', () {
      final pool = [for (var d = 1; d <= 9; d++) _b('p$d', d)];
      final plan = planPhotoSync(
        pool: pool,
        clock: ClockPhotos(
          photos: [
            _c(pool[0]),
            const ClockPhoto(id: 'stare'),
          ],
        ),
      );
      expect(plan.delete, ['stare']);
      expect([for (final p in plan.upload) p.id], ['p9', 'p8', 'p7', 'p6', 'p5', 'p4']);
      expect(plan.waiting, 2);
    });

    test('bez różnic - pusto; zmieniony podpis, wspomnienie albo data - jeszcze raz', () {
      final pool = [_b('a', 1, caption: 'Jezioro'), _b('b', 2), _b('c', 3, memory: true)];
      expect(
        planPhotoSync(
          pool: pool,
          clock: ClockPhotos(photos: [for (final p in pool) _c(p)]),
        ).isEmpty,
        isTrue,
      );

      final changed = [_b('a', 1, caption: 'Jezioro o świcie'), _b('b', 2, memory: true), _b('c', 4, memory: true)];
      final plan = planPhotoSync(
        pool: changed,
        clock: ClockPhotos(photos: [for (final p in pool) _c(p)]),
      );
      expect(plan.delete, isEmpty);
      expect([for (final p in plan.upload) p.id], ['c', 'b', 'a']);
    });

    test('zegar oddaje podpis inaczej (np. przycięty): po jednym wysłaniu już nie w kółko', () {
      final p = _b('a', 1, caption: 'Bardzo długi podpis od AI');
      final clock = ClockPhotos(photos: [_c(p, caption: 'Bardzo długi')]);
      expect(planPhotoSync(pool: [p], clock: clock).upload, hasLength(1));
      expect(planPhotoSync(pool: [p], clock: clock, sent: {'a': p.signature}).isEmpty, isTrue);
    });

    test('wspomnienie: rok z końca podpisu obcięty (zegar dopisuje sam), porównanie na obciętym', () {
      final m = _b('m', 1, caption: 'Nad jeziorem · 2019', memory: true);
      expect(m.clockCaption, 'Nad jeziorem');
      expect(_b('x', 1, caption: 'Nad jeziorem · 2019').clockCaption, 'Nad jeziorem · 2019'); // nie wspomnienie
      expect(_b('y', 1, caption: 'Rok 2019', memory: true).clockCaption, 'Rok 2019');
      // Zegar ma podpis już obcięty - bez różnic.
      final clock = ClockPhotos(
        photos: [ClockPhoto(id: 'm', taken: m.takenS, caption: 'Nad jeziorem', memory: true)],
      );
      expect(planPhotoSync(pool: [m], clock: clock).isEmpty, isTrue);
    });

    test('odrzucone przez zegar pomijane, dopóki się nie zmienią', () {
      final p = _b('a', 1);
      expect(planPhotoSync(pool: [p], clock: const ClockPhotos(), rejected: {'a': p.signature}).isEmpty, isTrue);
      final p2 = _b('a', 1, caption: 'nowy');
      expect(planPhotoSync(pool: [p2], clock: const ClockPhotos(), rejected: {'a': p.signature}).upload, [p2]);
    });

    test('max zegara: na zegarze tylko najnowsze z puli - najpierw usuwanie najstarszych', () {
      final pool = [for (var d = 1; d <= 5; d++) _b('p$d', d)];
      final plan = planPhotoSync(
        pool: pool,
        clock: ClockPhotos(max: 3, photos: [_c(pool[0]), _c(pool[1]), _c(pool[4])]),
      );
      expect(plan.delete, ['p1', 'p2']);
      expect([for (final p in plan.upload) p.id], ['p4', 'p3']);
    });

    test('złe i powtórzone id z manifestu pominięte', () {
      final plan = planPhotoSync(
        pool: [_b('ok_1-A', 1), _b('zły/id', 2), _b('a' * 41, 3), _b('ok_1-A', 4)],
        clock: const ClockPhotos(),
      );
      expect([for (final p in plan.upload) p.id], ['ok_1-A']);
    });

    test('manifest mostu: taken w ms → s, memory, bez podpisu', () {
      final list = BridgePhoto.manifest({
        'version': 1,
        'photos': [
          {'id': 'a', 'size': 10, 'taken': 1731600000123, 'memory': true},
          {'id': 'b', 'size': 10, 'taken': 1731600001000, 'caption': 'Poranek'},
          'zły wpis',
        ],
      })!;
      expect(
        [for (final p in list) (p.id, p.takenS, p.memory, p.caption)],
        [('a', 1731600000, true, ''), ('b', 1731600001, false, 'Poranek')],
      );
      expect(BridgePhoto.manifest({'version': 1}), isNull);
    });
  });

  group('opis stanu', () {
    final now = DateTime(2026, 11, 15, 18);
    test('brak mostu - podpowiedź; liczba i godzina; problemy', () {
      expect(
        photoSyncText(bridge: (at: 1, ok: false), now: now),
        'Zainstaluj aplikację Zdjęcia i włącz jej usługę w tle',
      );
      final at = DateTime(2026, 11, 15, 14, 5).millisecondsSinceEpoch;
      final ok = PhotoSyncStatus(at: at, result: PhotoSyncResult.ok, okAt: at, count: 5);
      expect(photoSyncText(bridge: (at: at, ok: true), status: ok, now: now), '5 zdjęć na zegarze · ostatnio 14:05');
      expect(photoSyncText(status: ok, onClock: 2, now: now), '2 zdjęcia na zegarze · ostatnio 14:05');
      expect(
        photoSyncText(status: ok, onClock: 1, now: DateTime(2026, 11, 16, 9)),
        startsWith('1 zdjęcie na zegarze · ostatnio wczoraj 14:05'),
      );
      expect(
        photoSyncText(
          status: ok.copyWith(result: PhotoSyncResult.full),
          now: now,
        ),
        '5 zdjęć na zegarze · ostatnio 14:05\nZegar nie ma miejsca na więcej zdjęć',
      );
      expect(photoSyncText(now: now), 'Jeszcze nie synchronizowano');
    });
  });

  group('przebieg po HTTP (atrapa mostu i zegara)', () {
    late FakeClock clock;
    late FakePhotoBridge bridge;
    late MemoryDeviceStore store;
    late MemoryPhotoSyncLog log;

    PhotoSync sync({Uri? bridgeUri}) =>
        PhotoSync(store: store, log: log, bridge: bridgeUri ?? bridge.uri, busyDelay: const Duration(milliseconds: 5));

    Future<void> saveClock({AccessLevel access = AccessLevel.control, int? port}) async {
      await store.saveDevice(
        PairedDevice(
          id: clock.id,
          name: 'Biurko',
          type: DeviceType.clock,
          access: access,
          lastEndpoint: LocalEndpoint('127.0.0.1', port ?? clock.port),
        ),
      );
      await store.saveToken(clock.id, clock.token);
    }

    setUp(() async {
      clock = FakeClock();
      clock.screens['list'] = ['main', 'photo'];
      await clock.start(port: 0, address: InternetAddress.loopbackIPv4);
      bridge = FakePhotoBridge();
      await bridge.start();
      store = MemoryDeviceStore();
      log = MemoryPhotoSyncLog();
      await saveClock();
    });

    tearDown(() async {
      await clock.stop();
      await bridge.stop();
    });

    test('po 6 najnowszych na przebieg, potem reszta, potem nic (bez pobierania z mostu)', () async {
      for (var d = 1; d <= 8; d++) {
        bridge.add('p$d', DateTime(2026, 11, d, 10), caption: d == 8 ? 'Poranek nad jeziorem & mgła' : null);
      }
      bridge.add('mem', DateTime(2019, 8, 3), caption: 'Nad jeziorem · 2019', memory: true);

      final r1 = await sync().run();
      expect(r1.bridge, isTrue);
      expect(r1.sent, 6);
      expect(clock.photoLog, ['GET', 'PUT p8', 'PUT p7', 'PUT p6', 'PUT p5', 'PUT p4', 'PUT p3']);
      expect(bridge.requests.where((r) => r.startsWith('jpg')).first, 'jpg p8 320x240');
      // Podpis %20 (nie +), taken w sekundach, memory 0/1.
      final taken = DateTime(2026, 11, 8, 10).millisecondsSinceEpoch ~/ 1000;
      expect(clock.photoQueries.first, 'caption=Poranek%20nad%20jeziorem%20%26%20mg%C5%82a&taken=$taken&memory=0');
      expect(clock.photos['p8']!['caption'], 'Poranek nad jeziorem & mgła');
      expect(log.clocks[clock.id]!.result, PhotoSyncResult.ok);
      expect(log.clocks[clock.id]!.count, 6);
      expect(log.clocks[clock.id]!.photoOn, isTrue);

      clock.photoLog.clear();
      final r2 = await sync().run();
      expect(r2.sent, 3);
      expect(clock.photoLog, ['GET', 'PUT p2', 'PUT p1', 'PUT mem']);
      expect(clock.photos['mem']!['memory'], isTrue);
      expect(clock.photoQueries.last, startsWith('caption=Nad%20jeziorem&'));
      expect(clock.photoQueries.last, endsWith('memory=1'));
      expect(clock.photos['mem']!['caption'], 'Nad jeziorem');

      clock.photoLog.clear();
      bridge.requests.clear();
      final r3 = await sync().run();
      expect((r3.sent, r3.deleted), (0, 0));
      expect(clock.photoLog, ['GET']);
      expect(bridge.requests, ['manifest']);
      expect(log.clocks[clock.id]!.count, 9);
    });

    test('nowy podpis - wysłane jeszcze raz; zdjęcie zniknęło z puli - usunięte z zegara', () async {
      bridge
        ..add('a', DateTime(2026, 11, 1))
        ..add('b', DateTime(2026, 11, 2));
      await sync().run();
      bridge.photos
        ..removeWhere((p) => p['id'] == 'a')
        ..first['caption'] = 'Spacer';
      clock.photoLog.clear();
      final r = await sync().run();
      expect(clock.photoLog, ['GET', 'DELETE a', 'PUT b']);
      expect((r.sent, r.deleted), (1, 1));
      expect(clock.photos.keys, ['b']);
      expect(clock.photos['b']!['caption'], 'Spacer');
    });

    test('503 busy: ponowienie co chwilę; po 10 próbach - stan „zajęty”', () async {
      bridge.add('a', DateTime(2026, 11, 1));
      clock.photoBusy = 3;
      await sync().run();
      expect(clock.photoLog, ['GET', 'PUT a busy', 'PUT a busy', 'PUT a busy', 'PUT a']);
      expect(clock.photos.keys, ['a']);

      bridge.add('b', DateTime(2026, 11, 2));
      clock
        ..photoBusy = 50
        ..photoLog.clear();
      await sync().run();
      expect(clock.photoLog.where((l) => l == 'PUT b busy'), hasLength(10));
      expect(log.clocks[clock.id]!.result, PhotoSyncResult.busy);
    });

    test('507 full: koniec przebiegu, stan „brak miejsca”', () async {
      for (var d = 1; d <= 4; d++) {
        bridge.add('p$d', DateTime(2026, 11, d));
      }
      clock.photoFullAt = 2;
      final r = await sync().run();
      expect(r.sent, 2);
      expect(clock.photoLog, ['GET', 'PUT p4', 'PUT p3', 'PUT p2']);
      expect(log.clocks[clock.id]!.result, PhotoSyncResult.full);
      expect(photoSyncText(status: log.clocks[clock.id]), contains('nie ma miejsca'));
    });

    test('za duży i progresywny JPEG: odrzucone i nie ponawiane co przebieg', () async {
      bridge
        ..add('duzy', DateTime(2026, 11, 1))
        ..add('prog', DateTime(2026, 11, 2))
        ..add('ok', DateTime(2026, 11, 3));
      bridge.override['duzy'] = fakeJpeg(320, 240, size: 100000);
      bridge.override['prog'] = fakeJpeg(320, 240, sof: 0xC2);
      await sync().run();
      expect(clock.photoLog, ['GET', 'PUT ok', 'PUT prog']); // za duży nawet nie poszedł
      expect(log.clocks[clock.id]!.rejected.keys, unorderedEquals(['duzy', 'prog']));

      clock.photoLog.clear();
      bridge.requests.clear();
      await sync().run();
      expect(clock.photoLog, ['GET']);
      expect(bridge.requests, ['manifest']);
    });

    test('brak mostu: zegar nietknięty, podpowiedź o aplikacji Zdjęcia', () async {
      final closed = FakePhotoBridge();
      await closed.start();
      final uri = closed.uri;
      await closed.stop();
      final r = await sync(bridgeUri: uri).run();
      expect(r.bridge, isFalse);
      expect(clock.photoLog, isEmpty);
      expect(log.lastBridge!.ok, isFalse);
      expect(photoSyncText(bridge: log.lastBridge), contains('Zainstaluj aplikację Zdjęcia'));
    });

    test('bez ekranu photo w pokazie, bez tokenu control, inny sprzęt pod adresem - zdjęć nie ruszamy', () async {
      bridge.add('a', DateTime(2026, 11, 1));
      clock.screens['list'] = ['main'];
      await sync().run();
      expect(clock.photoLog, isEmpty);
      expect(log.clocks[clock.id]!.result, PhotoSyncResult.off);
      expect(await photoSyncWanted(store, log), isFalse);

      clock.screens['list'] = ['main', 'photo'];
      await saveClock(access: AccessLevel.view);
      log.clocks.clear();
      final r = await sync().run();
      expect(r.clocks, isEmpty);
      expect(clock.photoLog, isEmpty);
      expect(await photoSyncWanted(store, log), isFalse);

      final other = FakeClock(id: 'zegar-innny');
      await other.start(port: 0, address: InternetAddress.loopbackIPv4);
      await saveClock(port: other.port);
      await sync().run();
      expect(log.clocks[clock.id]!.result, PhotoSyncResult.unreachable);
      expect(other.photoLog, isEmpty);
      await other.stop();
      expect(await photoSyncWanted(store, log), isTrue);
    });

    test('ekran zegara: przebieg tylko dla niego, przez bieżące połączenie lokalne; stan do kafelka', () async {
      bridge.add('a', DateTime(2026, 11, 1));
      final c = DeviceController<Json, Json>(
        device: (await store.devices()).single,
        manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
        codec: rawCodec,
      );
      ClockPhotoSync.logFactory = () => log;
      ClockPhotoSync.syncFactory = (c, log) =>
          PhotoSync(store: c.manager.store, log: log, bridge: bridge.uri, busyDelay: Duration.zero);
      addTearDown(() {
        ClockPhotoSync.logFactory = PrefsPhotoSyncLog.new;
        ClockPhotoSync.syncFactory = (c, log) => PhotoSync(store: c.manager.store, log: log);
      });
      await c.connect();
      final ui = ClockPhotoSync(c);
      expect(ui.canRun, isTrue);
      expect(ui.photoOn, isTrue);
      await ui.run();
      expect(clock.photos.keys, ['a']);
      expect(ui.status!.count, 1);
      for (var i = 0; i < 50 && c.stateJson?['photos'] != 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ui.text, startsWith('1 zdjęcie na zegarze · ostatnio '));

      // Zaraz potem z minInterval - pominięty (bez żądań do zegara).
      clock.photoLog.clear();
      await ui.run(minInterval: const Duration(minutes: 1));
      expect(clock.photoLog, isEmpty);
      ui.dispose();
      c.dispose();
    });
  });
}
