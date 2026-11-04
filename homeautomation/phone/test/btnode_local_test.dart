// Bramka Bluetooth na atrapie (tool/fake): typ po parowaniu i po połączeniu ze starym wpisem.
// Prawdziwe gniazda - dlatego zwykłe test(), bez testWidgets.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/hub_api.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';

import '../tool/fake/fake_thermostat_server.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => Stream.value(const []);
}

void main() {
  group('atrapa bramki (prawdziwe gniazda)', () {
    late FakeBtNode fake;
    late LocalEndpoint endpoint;

    setUp(() async {
      fake = FakeBtNode();
      await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
      endpoint = LocalEndpoint('127.0.0.1', fake.port);
    });

    tearDown(() => fake.stop());

    test('bramka zapisana jako typ nieznany: typ z /api/info po połączeniu, zapisany w telefonie', () async {
      final store = MemoryDeviceStore();
      final saved = PairedDevice.fromJson({
        'id': fake.id,
        'name': 'Bramka',
        'type': '',
        'access': 'config',
        'host': '127.0.0.1',
        'port': fake.port,
      });
      expect(saved.type, DeviceType.unknown);
      await store.saveDevice(saved);
      await store.saveToken(fake.id, fake.token);
      final c = DeviceController<Json, Json>(
        device: saved,
        manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
        codec: rawCodec,
      );
      await c.connect();
      for (var i = 0; i < 50 && c.device.type != DeviceType.btnode; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((c.phase, c.error, c.kind), (ConnectPhase.connected, null, ConnectionKind.local));
      expect(c.device.type, DeviceType.btnode);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await store.devices()).single.type, DeviceType.btnode);
      expect(c.stateJson?['bleConns'], 0);
      c.dispose();
    });

    test('parowanie bramki: typ btnode w telefonie', () async {
      final store = MemoryDeviceStore();
      final pairing = PairingService(store: store, clientName: () async => 'Test');
      final info = await pairing.probe(endpoint);
      expect(info.type, DeviceType.btnode);
      await pairing.start(endpoint);
      final d = await pairing.confirm(endpoint, info, fake.pairCode!);
      expect(d.type, DeviceType.btnode);
      expect((await store.devices()).single.type, DeviceType.btnode);
    });
  });

  test('czujnik dodany do huba bez wpisu w chmurze: na liście domu z via = hub (z GET /api/devices)', () async {
    final hubFake = FakeHub();
    await hubFake.start(port: 0, address: InternetAddress.loopbackIPv4);
    addTearDown(hubFake.stop);
    final endpoint = LocalEndpoint('127.0.0.1', hubFake.port);
    // Jak skryptem: prosto do huba, bez deviceIndex.
    await HubApi(
      LocalApi(endpoint, token: hubFake.token),
    ).addDevice({'adapter': 'ble', 'deviceId': 'a4:c1:38:12:34:56', 'name': 'Czujnik BT'});
    final store = MemoryDeviceStore();
    await store.saveDevice(PairedDevice(id: hubFake.id, name: 'Hub', type: DeviceType.hub, lastEndpoint: endpoint));
    await store.saveToken(hubFake.id, hubFake.token);
    final hub = DeviceHub(
      store: store,
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      cloud: NoCloudAccess(),
    );
    addTearDown(hub.dispose);
    await hub.load();
    for (var i = 0; i < 100 && hub.device('ble-a4c138123456') == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final d = hub.device('ble-a4c138123456');
    expect((d?.via, d?.type, d?.name), (hubFake.id, DeviceType.sensor, 'Czujnik BT'));
  });
}
