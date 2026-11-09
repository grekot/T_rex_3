// Hub (kontrakt pkt 11): API huba na atrapie (urządzenia, wykrywanie, automatyki, sceny, czas),
// automatyki w domu i przez chmurę, „Przypisz do huba”, powiadomienia. Prawdziwe gniazda - bez testWidgets.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/data/automation_store.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/hub_api.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/notifications.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/scene.dart';
import 'package:homeautomation/models/set_values.dart';

import '../tool/fake/fake_thermostat_server.dart';
import 'support/memory_cloud_store.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

/// Hub widziany przez chmurę: zapisuje wysłane Set.
class _CloudHubConn implements DeviceConnection<Json, Json> {
  final sent = <Json>[];

  @override
  String get deviceId => 'hub-51e96c';
  @override
  ConnectionKind get kind => ConnectionKind.cloud;
  @override
  String get routeDescription => 'Firebase';
  @override
  Json get state => {'id': 'hub-51e96c', 'cloud': true};
  @override
  Json get config => {'name': 'Hub'};
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<Json> get states => const Stream.empty();
  @override
  Stream<Json> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => null;
  @override
  Future<SetResult> sendSet(Json values) async {
    sent.add(values);
    return const SetResult(ok: true);
  }

  @override
  Future<void> close() async {}
}

class _StubManager extends ConnectionManager {
  _StubManager(this.conn) : super(store: MemoryDeviceStore(), discovery: _NoDiscovery());

  final DeviceConnection<Json, Json> conn;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conn as DeviceConnection<S, C>;
}

void main() {
  late FakeHub fake;
  late LocalEndpoint endpoint;
  late HubApi api;

  setUp(() async {
    fake = FakeHub()..discoverPolls = 2;
    await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
    endpoint = LocalEndpoint('127.0.0.1', fake.port);
    api = HubApi(LocalApi(endpoint, token: fake.token));
  });

  tearDown(() => fake.stop());

  test('urządzenia: wykrywanie (odpytywanie aż scanning:false), dodanie, sterowanie, 202 pending, usunięcie', () async {
    expect(await api.devices(), isEmpty);
    var d = await api.discover();
    var polls = 1;
    while (d.scanning) {
      d = await api.discover();
      polls++;
    }
    expect(polls, 3);
    expect(d.found.map((f) => (f.adapter, f.host)), [
      (HubAdapter.shelly, '192.168.1.50'),
      (HubAdapter.tasmota, '192.168.1.51'),
      (HubAdapter.ewelink, '192.168.1.52'),
      (HubAdapter.ewelink, '192.168.1.53'),
    ]);
    expect((d.found[2].deviceId, d.found[2].model), ('1000a1b2c3', 'strip'));

    final id = await api.addDevice({
      'adapter': 'shelly',
      'host': '192.168.1.50',
      'id': 'shelly-b12345',
      'name': 'Taras',
    });
    expect(id, 'shelly-b12345');
    await api.addDevice({'adapter': 'tasmota', 'host': '192.168.1.98', 'name': 'Wolny'});
    final list = await api.devices();
    expect(list.map((c) => (c.id, c.label, c.online, c.linked, c.mirror)).toList(), [
      ('shelly-b12345', 'Taras', true, false, true),
      ('tasmota-a80162', 'Wolny', true, false, true),
    ]);

    var r = await api.setDevice('shelly-b12345', {'on': true});
    expect((r.ok, r.pending), (true, false));
    expect((await api.devices()).first.state['on'], isTrue);
    r = await api.setDevice('tasmota-a80162', {'on': true});
    expect(r.pending, isTrue, reason: 'urządzenie nie odpowiedziało w 3 s');

    await expectLater(
      api.addDevice({'adapter': 'tuya', 'host': '192.168.1.60'}),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('Tuya'))),
    );
    await expectLater(
      api.addDevice({'adapter': 'ownNode', 'host': '192.168.1.61', 'id': 'sw-1', 'token': 'zly'}),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('token'))),
    );

    await api.deleteDevice('shelly-b12345');
    expect((await api.devices()).map((c) => c.id), ['tasmota-a80162']);
  });

  test('eWeLink LAN: kanały i moduł, wymagany klucz, zły klucz → error key, poprawienie klucza', () async {
    const key = '0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9';
    fake.ewelinkKeys['1000a1b2c3'] = key;
    for (final c in [0, 1]) {
      await api.addDevice({
        'adapter': 'ewelink',
        'host': '192.168.1.52',
        'deviceId': '1000a1b2c3',
        'localKey': key,
        'channel': c,
        'name': 'Biurko ${c + 1}',
        'type': 'switch',
      });
    }
    final id = await api.addDevice({
      'adapter': 'ewelink',
      'host': '192.168.1.53',
      'deviceId': '1000d4e5f6',
      'localKey': key,
      'name': 'Gniazdko',
    });
    expect(id, 'ewelink-1000d4e5f6');
    // Cały moduł jako jedno urządzenie z kanałami (pkt 10.1)
    final module = await api.addDevice({
      'adapter': 'ewelink',
      'host': '192.168.1.55',
      'deviceId': '1000c0ffee',
      'localKey': key,
      'channels': 4,
      'name': 'Światło 1',
    });
    expect(module, 'ewelink-1000c0ffee');
    var list = await api.devices();
    expect(list.map((c) => (c.id, c.adapter, c.channel, c.channels, c.deviceId, c.error)).toList(), [
      ('ewelink-1000a1b2c3-1', HubAdapter.ewelink, 0, null, '1000a1b2c3', null),
      ('ewelink-1000a1b2c3-2', HubAdapter.ewelink, 1, null, '1000a1b2c3', null),
      ('ewelink-1000d4e5f6', HubAdapter.ewelink, null, null, '1000d4e5f6', null),
      ('ewelink-1000c0ffee', HubAdapter.ewelink, null, 4, '1000c0ffee', null),
    ]);
    expect(list.last.state, {'on': false, 'channels': 4, 'on1': false, 'on2': false, 'on3': false, 'on4': false});

    await expectLater(
      api.addDevice({'adapter': 'ewelink', 'host': '192.168.1.54', 'deviceId': '1000ffffff', 'localKey': 'abc'}),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('Zły klucz urządzenia'))),
    );
    await expectLater(
      api.addDevice({'adapter': 'ewelink', 'host': '192.168.1.54', 'localKey': key}),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('identyfikatora'))),
    );

    // Zły klucz: hub nie odszyfruje ogłoszeń - error "key"; ten sam id z dobrym kluczem naprawia.
    await api.addDevice({
      'adapter': 'ewelink',
      'host': '192.168.1.52',
      'id': 'ewelink-1000a1b2c3-1',
      'deviceId': '1000a1b2c3',
      'localKey': 'ffffffff-ffff-ffff-ffff-ffffffffffff',
      'channel': 0,
    });
    list = await api.devices();
    expect((list.first.error, list.first.online), ('key', false));
    await api.addDevice({
      'adapter': 'ewelink',
      'host': '192.168.1.52',
      'id': 'ewelink-1000a1b2c3-1',
      'deviceId': '1000a1b2c3',
      'localKey': key.toUpperCase(),
      'channel': 0,
    });
    list = await api.devices();
    expect((list.first.error, list.first.online, list.length), (null, true, 4));
    expect(
      HubChild.fromJson({'id': 'ewelink-10009abcde-3', 'adapter': 'ewelink', 'host': '1.2.3.4'}).deviceId,
      '10009abcde',
    );
  });

  test('eWeLink moduł: Config z huba - kanały tylko z nazwą', () {
    final c = LightConfig.fromJson({
      'name': 'Światło 1',
      'channels': 2,
      'ch1': {'name': 'Sypialnia'},
      'ch2': {'name': 'Kanał 2'},
    });
    expect(c.channels.map((x) => (x.name, x.nameOnly)), [('Sypialnia', true), ('Kanał 2', true)]);
    expect(c.toJson()['ch1'], {'name': 'Sypialnia'});
    expect(
      LightConfig.fromJson({
        'channels': 2,
        'ch1': {'name': 'A', 'defaultOn': 'off'},
      }).channels.first.nameOnly,
      isFalse,
    );
  });

  test(
    'czujniki Bluetooth: szukanie przez btnode, podgląd, dodanie, szyfrowany z kluczem, zły klucz, brak węzła',
    () async {
      expect(await api.bleScan(), 1, reason: 'jeden węzeł btnode online');
      var seen = await api.bleSeen();
      expect((seen.scanning, seen.nodes.single.id, seen.nodes.single.scanAll), (true, 'bt-a1b2c3', true));
      while (seen.scanning) {
        seen = await api.bleSeen();
      }
      expect(seen.found.map((f) => (f.mac, f.encrypted, f.trigger)).toList(), [
        ('a4:c1:38:12:34:56', false, false),
        ('f8:44:77:aa:bb:cc', true, true),
      ]);
      expect((seen.found.first.values['temp'], seen.found.first.hubId), (21.6, 'ble-a4c138123456'));
      expect(seen.found.last.buttons, ['btn1']);

      final id = await api.addDevice({'adapter': 'ble', 'deviceId': 'a4:c1:38:12:34:56', 'name': 'Salon'});
      expect(id, 'ble-a4c138123456');
      await expectLater(
        api.addDevice({'adapter': 'ble', 'deviceId': 'f8:44:77:aa:bb:cc', 'name': 'Przycisk'}),
        throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('32 znaki'))),
        reason: 'szyfrowany bez klucza',
      );
      await expectLater(
        api.addDevice({'adapter': 'ble', 'deviceId': 'zly', 'name': 'X'}),
        throwsA(isA<ThermostatException>()),
      );
      await api.addDevice({
        'adapter': 'ble',
        'deviceId': 'f8:44:77:aa:bb:cc',
        'name': 'Przycisk',
        'localKey': 'ffffffffffffffffffffffffffffffff',
      });
      var list = await api.devices();
      final sensor = list.firstWhere((c) => c.id == 'ble-a4c138123456');
      expect(
        (sensor.adapter, sensor.type, sensor.host, sensor.deviceId, sensor.state['temp']),
        (HubAdapter.ble, 'sensor', '', 'a4:c1:38:12:34:56', 21.6),
      );
      expect(list.firstWhere((c) => c.id == 'ble-f84477aabbcc').error, 'key');
      await api.addDevice({
        'adapter': 'ble',
        'id': 'ble-f84477aabbcc',
        'deviceId': 'f8:44:77:aa:bb:cc',
        'name': 'Przycisk',
        'localKey': '00112233445566778899AABBCCDDEEFF',
      });
      list = await api.devices();
      expect(list.firstWhere((c) => c.id == 'ble-f84477aabbcc').error, isNull);
      expect((await api.bleSeen()).found, isEmpty, reason: 'dodane znikają z listy');

      await api.bleStop();
      expect((await api.bleSeen()).scanning, isFalse);
      fake.bleNodes = [
        {'id': 'bt-a1b2c3', 'online': false},
      ];
      expect(await api.bleScan(seconds: 30), 0, reason: 'brak węzła btnode online');
    },
  );

  test(
    'czujnik btsensor sparowany (pkt 15.6): paired w seen, dodanie bez klucza, nowy klucz, wygasłe parowanie',
    () async {
      // Starszy hub: brak `paired` = pusta lista.
      expect(BleSeen.fromJson({'scanning': false}).paired, isEmpty);
      fake.blePaired.add('f8:44:77:aa:bb:cc');
      var seen = await api.bleSeen();
      expect(seen.paired.map((p) => (p.mac, p.id)).toList(), [('f8:44:77:aa:bb:cc', null)]);
      await api.addDevice({'adapter': 'ble', 'deviceId': 'f8:44:77:aa:bb:cc', 'paired': true, 'name': 'Okno'});
      expect((await api.devices()).firstWhere((c) => c.id == 'ble-f84477aabbcc').error, isNull);
      expect((await api.bleSeen()).paired, isEmpty);
      await expectLater(
        api.addDevice({'adapter': 'ble', 'deviceId': 'f8:44:77:aa:bb:cc', 'paired': true, 'name': 'Okno'}),
        throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('Parowanie wygasło'))),
      );
      fake.blePaired.add('f8:44:77:aa:bb:cc');
      seen = await api.bleSeen();
      expect(seen.paired.single.id, 'ble-f84477aabbcc', reason: 'już dodany - nowy klucz');
    },
  );

  test(
    'zegarek przez Bluetooth (pkt 15.1): rejestracja, nowy klucz przy ponownej, lista punktów, odłączenie',
    () async {
      var r = await api.registerRemote(watchId: '8716545', name: 'T-Rex 3');
      expect((r.id, r.slot, r.cfgVer, RegExp(r'^[0-9a-f]{64}$').hasMatch(r.key)), ('zegarek-8716545', 1, 1, true));
      final firstKey = r.key;
      r = await api.registerRemote(watchId: '8716545', name: 'T-Rex 3');
      expect((r.slot, r.key == firstKey), (1, false), reason: 'ten sam slot, nowy klucz');
      await api.putRemote('zegarek-8716545', {
        'kind': 'watch',
        'cfgVer': 2,
        'points': [
          {'device': 'termostat-ab12cd', 'point': 'temp'},
        ],
      });
      expect(
        (fake.remotes['zegarek-8716545']!['cfgVer'], (fake.remotes['zegarek-8716545']!['points'] as List).length),
        (2, 1),
      );
      await api.deleteRemote('zegarek-8716545');
      expect(fake.remotes, isEmpty);
      await expectLater(api.deleteRemote('zegarek-8716545'), throwsA(isA<ThermostatException>()));
    },
  );

  test('automatyki i sceny w hubie: zapis z updatedAt, błędna reguła, diagnostyka, uruchom, dziennik, czas', () async {
    final a = Automation(
      id: 'taras-o-zmroku',
      name: 'Taras o zmroku',
      when: const [
        {'sun': 'sunset', 'offset': -15},
      ],
      then: const [
        {'notify': 'Zmrok', 'level': 'info'},
      ],
    );
    final at = await api.putAutomation(a, updatedAt: 1793000000000);
    expect(at, 1793000000000);
    expect(fake.automations['taras-o-zmroku']!['updatedAt'], 1793000000000);

    fake.rejectId = 'zla-regula';
    await expectLater(
      api.putAutomation(const Automation(id: 'zla-regula', name: 'Zła', when: [{}])),
      throwsA(isA<HubInvalidException>().having((e) => e.problems, 'problems', ['zla-regula: when'])),
    );

    var info = await api.automations();
    expect((info.items.single.name, info.sunrise, info.timeKnown), ('Taras o zmroku', null, true));
    fake.location = {'lat': 49.9, 'lon': 20.6};
    info = await api.automations();
    expect(info.sunrise, '06:41');

    await api.runAutomation('taras-o-zmroku');
    expect((await api.automationLog()).single.id, 'taras-o-zmroku');

    await api.putScene(const Scene(id: 'wyjscie', name: 'Wychodzę', actions: [SceneAction.notify('Pa!')]));
    expect(fake.scenes['wyjscie']!['actions'], [
      {'notify': 'Pa!', 'level': 'info'},
    ]);
    await api.runScene('wyjscie');
    expect((await api.sceneLog()).single.kind, 'scene');

    fake.timeKnown = false;
    await api.setTime(DateTime(2026, 10, 27, 20));
    expect((fake.timeKnown, fake.timeSource), (true, 'manual'));
    await api.deleteAutomation('taras-o-zmroku');
    expect(fake.automations, isEmpty);
  });

  test('HubAutomations: w domu przez API huba, poza domem chmura + updatedAt + reload', () async {
    // W domu: kontroler połączony lokalnie z atrapą huba.
    final store = MemoryDeviceStore();
    final device = PairedDevice(
      id: fake.id,
      name: 'Hub',
      type: DeviceType.hub,
      lastEndpoint: endpoint,
      access: AccessLevel.config,
    );
    await store.saveDevice(device);
    await store.saveToken(fake.id, fake.token);
    final local = DeviceController(
      device: device,
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      codec: rawCodec,
    );
    await local.connect();
    final inHome = HubAutomations(hub: local);
    expect(inHome.isLocal, isTrue);
    await inHome.save(
      const Automation(
        id: 'rano',
        name: 'Rano',
        when: [
          {'time': '06:30'},
        ],
        then: [
          {'log': 'x'},
        ],
      ),
    );
    expect(fake.automations['rano']!['updatedAt'], isA<int>());
    expect((await inHome.load()).items.single.id, 'rano');
    await inHome.run('rano');
    expect((await inHome.log()).single.id, 'rano');
    local.dispose();

    // Poza domem: chmura + Set {"reload": true}.
    final cloud = MemoryCloudStore();
    final conn = _CloudHubConn();
    final remote = DeviceController(
      device: const PairedDevice(id: 'hub-51e96c', name: 'Hub', type: DeviceType.hub),
      manager: _StubManager(conn),
      codec: rawCodec,
    );
    await remote.connect();
    final away = HubAutomations(hub: remote, store: cloud, homeId: 'h1', clock: () => DateTime(2026, 10, 27, 21));
    expect(away.isLocal, isFalse);
    await away.save(
      const Automation(
        id: 'wieczor',
        name: 'Wieczór',
        when: [
          {'sun': 'sunset'},
        ],
        then: [
          {'log': 'x'},
        ],
      ),
    );
    expect(cloud.get('homes/h1/automations/wieczor/updatedAt'), DateTime(2026, 10, 27, 21).millisecondsSinceEpoch);
    expect(conn.sent.single, {'reload': true});
    expect((await away.load()).items.single.name, 'Wieczór');
    await expectLater(away.run('wieczor'), throwsA(isA<ThermostatException>()));
    await away.remove('wieczor');
    expect(cloud.get('homes/h1/automations/wieczor'), isNull);
    remote.dispose();
  });

  test('przypisanie węzła do huba: token od węzła (POST /api/clients) → hub ownNode', () async {
    final node = FakeLight(id: 'swiatlo-0c4f21', channels: 4)..cloudCapable = false;
    await node.start(port: 0, address: InternetAddress.loopbackIPv4);
    addTearDown(node.stop);
    final nodeApi = LocalApi(LocalEndpoint('127.0.0.1', node.port), token: node.token);
    final t = await nodeApi.createClient('hub', AccessLevel.config);
    await api.addDevice({
      'adapter': 'ownNode',
      'id': 'swiatlo-0c4f21',
      'host': '192.168.1.61',
      'token': t.token,
      'type': 'switch',
      'name': 'Parter',
    });
    expect(fake.children['swiatlo-0c4f21']!['mirror'], isTrue);
    expect(node.phones.map((p) => (p.name, p.access)).last, ('hub', 'config'));
  });

  test('powiadomienia z huba: najnowsze pierwsze, nowe od ostatnio pokazanego', () {
    final all = parseNotifications({
      '1793000000000-01': {'ts': 1793000000000, 'text': 'Drzwi', 'level': 'warning', 'source': 'automation'},
      '1793000100000-01': {'ts': 1793000100000, 'text': 'Zmrok', 'level': 'info'},
    });
    expect(all.map((n) => n.text), ['Zmrok', 'Drzwi']);
    expect(newNotifications(all, 1793000000000, 1793000200000).map((n) => n.text), ['Zmrok']);
    expect(newNotifications(all, null, 1793000200000).length, 2, reason: 'pierwsze sprawdzenie: ostatnia godzina');
  });

  test('id automatyki: [a-z0-9-], 3-40 znaków, bez polskich liter', () {
    final id = hubDocId('Taras o zmroku – światło');
    expect(RegExp(r'^[a-z0-9-]{3,40}$').hasMatch(id), isTrue, reason: id);
    expect(id, startsWith('taras-o-zmroku-swiatlo-'));
  });
}
