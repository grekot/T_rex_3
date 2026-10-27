// HomeAutomation v2: typy urządzeń, światło (pkt 10) na atrapie, /api/wifi/reset, pokoje.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/light_controller.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/room.dart';

import '../tool/fake/fake_thermostat_server.dart';
import 'support/memory_cloud_store.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => Stream.value(const []);
}

void main() {
  group('typy', () {
    test('DeviceType z kontraktu; brak typu = termostat (API 1)', () {
      expect(DeviceType.fromWire('switch'), DeviceType.onOff);
      expect(DeviceType.fromWire('dimmer').isLight, isTrue);
      expect(DeviceType.fromWire(null), DeviceType.thermostat);
      expect(DeviceType.fromWire('kosiarka'), DeviceType.unknown);
    });

    test('PairedDevice zapamiętuje typ; stare wpisy bez typu to termostaty', () {
      final d = PairedDevice.fromJson({'id': 'swiatlo-1', 'name': 'Lampa', 'type': 'dimmer'});
      expect(d.type, DeviceType.dimmer);
      expect(PairedDevice.fromJson(d.toJson()).type, DeviceType.dimmer);
      expect(PairedDevice.fromJson({'id': 'termostat-1', 'name': 'Salon'}).type, DeviceType.thermostat);
    });

    test('LightSet wysyła tylko ustawione pola', () {
      expect(const LightSet(on: true).toJson(), {'on': true});
      expect(const LightSet(toggle: true, level: 40).toJson(), {'level': 40, 'toggle': true});
      expect(const LightSet(defaultOn: DefaultOn.off).toJson(), {'defaultOn': 'off'});
    });
  });

  group('atrapa światła (ściemniacz)', () {
    late FakeLight fake;
    late LocalEndpoint endpoint;
    late MemoryDeviceStore store;

    setUp(() async {
      fake = FakeLight(dimmable: true);
      await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
      endpoint = LocalEndpoint('127.0.0.1', fake.port);
      store = MemoryDeviceStore();
      await store.saveToken(fake.id, fake.token);
    });

    tearDown(() => fake.stop());

    test('/api/info zgłasza typ i API 2', () async {
      final info = await LocalApi(endpoint).info();
      expect((info.type, info.api, info.apiSupported), (DeviceType.dimmer, 2, true));
    });

    test('LightController: wł./wył., jasność, błąd pola', () async {
      final c = LightController(
        device: PairedDevice(id: fake.id, name: 'x', type: DeviceType.dimmer, lastEndpoint: endpoint),
        manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
        levelDebounce: Duration.zero,
      );
      await c.connect();
      expect(c.kind, ConnectionKind.local);
      expect(c.config!.name, 'Salon - sufit');
      expect(c.device.name, 'Salon - sufit', reason: 'nazwa z Config');

      final r = await c.toggle();
      expect(r.ok, isTrue);
      expect(fake.on, isTrue);

      c.setLevel(30);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fake.level, 30);

      final bad = await c.sendJson({'level': 140});
      expect(bad.errors, {'level': 'range'});
      expect(c.lastSendError, contains('Jasność'));
      c.dispose();
    });

    test('przycisk na ścianie przychodzi na żywo', () async {
      final conn = await ConnectionManager(
        store: store,
        discovery: _NoDiscovery(),
      ).connectWith(PairedDevice(id: fake.id, name: 'x', type: DeviceType.dimmer, lastEndpoint: endpoint), lightCodec);
      final next = conn.states.firstWhere((s) => s.on);
      fake.press();
      expect((await next.timeout(const Duration(seconds: 2))).level, 80);
      await conn.close();
    });

    test('POST /api/wifi/reset: 200 ok, urządzenie zamyka połączenia', () async {
      final conn = await ConnectionManager(
        store: store,
        discovery: _NoDiscovery(),
      ).connectWith(PairedDevice(id: fake.id, name: 'x', type: DeviceType.dimmer, lastEndpoint: endpoint), lightCodec);
      final dropped = conn.statuses.firstWhere((s) => s == LinkStatus.reconnecting);
      await LocalApi(endpoint, token: fake.token).wifiReset();
      expect(fake.wifiResets, 1);
      await dropped.timeout(const Duration(seconds: 3));
      await conn.close();
    });
  });

  group('pokoje', () {
    const a = Room(id: 'a', name: 'Salon', order: 0, devices: ['t1', 's1', 'znikniety']);
    const b = Room(id: 'b', name: 'Kuchnia', order: 1, devices: ['s2']);

    test('układ: kolejność pokoi i kafelków, „Bez pokoju” na końcu, nieznane pominięte', () {
      final s = layoutRooms([b, a], ['s1', 's2', 't1', 'nowy']);
      expect(
        [for (final x in s) '${x.room?.name}: ${x.deviceIds.join(',')}'],
        ['Salon: t1,s1', 'Kuchnia: s2', 'null: nowy'],
      );
    });

    test('przeniesienie do innego pokoju i wyjęcie z pokoju', () {
      final moved = moveDevice([a, b], 's1', 'b');
      expect(
        {for (final r in moved) r.id: r.devices},
        {
          'a': ['t1', 'znikniety'],
          'b': ['s2', 's1'],
        },
      );
      expect(moveDevice([a, b], 's2', null).single.devices, isEmpty);
      expect(moveDevice([a, b], 's2', 'b'), isEmpty, reason: 'już tam jest');
    });

    test('kolejność kafelków i pokoi', () {
      expect(shiftDevice(a, 's1', -1)!.devices, ['s1', 't1', 'znikniety']);
      expect(shiftDevice(a, 't1', -1), isNull);
      final shifted = shiftRoom([a, b], 'b', -1);
      expect({for (final r in shifted) r.id: r.order}, {'b': 0, 'a': 1});
    });

    test('pokoje w chmurze: homes/{h}/rooms', () async {
      final mem = MemoryCloudStore();
      final store = CloudRoomStore(mem, 'h1');
      await store.save(a);
      expect((mem.get('homes/h1/rooms/a') as Map)['devices'], ['t1', 's1', 'znikniety']);
      final rooms = await store.watch().first;
      expect(rooms.single.name, 'Salon');
      await store.remove('a');
      expect(mem.get('homes/h1/rooms/a'), isNull);
      // Pusty pokój: RTDB nie trzyma pustej listy.
      mem.set('homes/h1/rooms/p', {'name': 'Pusty', 'order': 2});
      expect((await store.watch().first).single.devices, isEmpty);
    });
  });
}
