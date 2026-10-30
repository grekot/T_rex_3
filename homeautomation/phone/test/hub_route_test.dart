// Urządzenia podrzędne w sieci domowej przez hub (kontrakt pkt 1 i 11), chmura jako zapas.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/hub_child_connection.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => Stream.value(const []);
}

/// Atrapa huba: `hub-1` z jednym Shelly.
class _Hub {
  bool on = false;
  bool online = true;
  bool hasConfigRoute = true;
  bool reachable = true;
  final requests = <String>[];

  Json get _state => {'id': 'shelly-1', 'on': on, 'online': online, 'cloud': false, 'ts': 1};

  late final client = MockClient((r) async {
    if (!reachable) throw http.ClientException('brak');
    requests.add('${r.method} ${r.url.path}');
    http.Response json(Object v, [int code = 200]) =>
        http.Response(jsonEncode(v), code, headers: {'content-type': 'application/json'});
    return switch ('${r.method} ${r.url.path}') {
      'GET /api/info' => json({'id': 'hub-1', 'type': 'hub', 'api': 2, 'fw': '1'}),
      'GET /api/devices' => json([
        {
          'id': 'shelly-1',
          'type': 'switch',
          'adapter': 'shelly',
          'host': '192.168.1.9',
          'name': 'Lampa',
          'mirror': true,
          'linked': false,
          'online': online,
          'state': {'on': on},
        },
        {
          'id': 'tylko-automatyki',
          'type': 'switch',
          'adapter': 'shelly',
          'host': '192.168.1.8',
          'mirror': false,
          'linked': false,
          'online': true,
        },
      ]),
      'GET /api/devices/shelly-1/state' => json(_state),
      'GET /api/devices/shelly-1/config' when hasConfigRoute => json({'name': 'Lampa'}),
      'POST /api/devices/shelly-1/set' => () {
        on = (jsonDecode(r.body) as Map)['on'] == true;
        return json({'ok': true, 'state': _state});
      }(),
      _ => json({'ok': false, 'error': 'not_found'}, 404),
    };
  });
}

void main() {
  late _Hub fake;
  late MemoryDeviceStore store;
  late ConnectionManager manager;
  const child = PairedDevice(id: 'shelly-1', name: 'x', type: DeviceType.onOff, via: 'hub-1');

  setUp(() async {
    fake = _Hub();
    store = MemoryDeviceStore();
    await store.saveDevice(
      const PairedDevice(
        id: 'hub-1',
        name: 'Hub',
        type: DeviceType.hub,
        access: AccessLevel.control,
        lastEndpoint: LocalEndpoint('192.168.1.5'),
      ),
    );
    await store.saveToken('hub-1', 'token-huba');
    manager = ConnectionManager(
      store: store,
      discovery: _NoDiscovery(),
      discoveryTimeout: const Duration(milliseconds: 50),
      hubPollInterval: const Duration(milliseconds: 20),
      httpClientFactory: () => fake.client,
    );
  });

  test('urządzenie bez własnego tokenu idzie lokalnie przez hub, polecenie też', () async {
    final conn = await manager.connectWith(child, lightCodec);
    expect(conn, isA<HubChildConnection<LightState, LightConfig>>());
    expect(conn.kind, ConnectionKind.local);
    expect(conn.routeDescription, 'przez hub 192.168.1.5');
    expect(conn.config!.name, 'Lampa');

    final r = await conn.sendSet({'on': true});
    expect(r.ok, isTrue);
    expect(fake.on, isTrue);
    expect(conn.state!.on, isTrue);
    await conn.close();
  });

  test('zmiana na ścianie dochodzi ze wspólnego odpytywania, offline z pola online', () async {
    final conn = await manager.connectWith(child, lightCodec);
    final next = conn.states.firstWhere((s) => s.on);
    fake.on = true;
    await next.timeout(const Duration(seconds: 2));

    final gone = conn.statuses.firstWhere((s) => s == LinkStatus.offline);
    fake.online = false;
    await gone.timeout(const Duration(seconds: 2));
    await conn.close();
  });

  test('dwa połączenia jednego huba dzielą odpytywanie, po zamknięciu ustaje', () async {
    final a = await manager.connectWith(child, lightCodec);
    final b = await manager.connectWith(child, lightCodec);
    expect((a as HubChildConnection).link, same((b as HubChildConnection).link));
    await a.close();
    await b.close();
    fake.requests.clear();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fake.requests, isEmpty);
  });

  test('hub ze starszym firmware albo poza zasięgiem: bez drogi lokalnej', () async {
    fake.hasConfigRoute = false;
    await expectLater(manager.connectWith(child, lightCodec), throwsA(anything));
    fake
      ..hasConfigRoute = true
      ..reachable = false;
    await expectLater(manager.connectWith(child, lightCodec), throwsA(anything));
  });

  test('bez tokenu huba: nie próbuje huba', () async {
    await store.removeDevice('hub-1');
    await expectLater(manager.connectWith(child, lightCodec), throwsA(anything));
    expect(fake.requests, isEmpty);
  });

  test('DeviceHub pokazuje urządzenia huba bez konta; bez mirror pominięte', () async {
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess());
    await hub.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect([for (final d in hub.devices) d.id], ['hub-1', 'shelly-1']);
    final d = hub.device('shelly-1')!;
    expect((d.via, d.access, d.name), ('hub-1', AccessLevel.control, 'Lampa'));
    hub.dispose();
  });
}
