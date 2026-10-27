// Chmura (pkt 8 kontraktu) na Realtime Database w pamięci: stan na żywo, polecenia
// przez commands/lastCommand, offline wg lastSeen, wybór drogi lokalnie → chmura.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/cloud_connection.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/set_values.dart';

import 'models_test.dart' show configJson, stateJson;
import 'support/memory_cloud_store.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => Stream.value(const []);
}

const uid = 'uid-1';
const id = 'termostat-ab12cd';
const home = 'h1';
const base = 'homes/$home/devices/$id';
const commands = 'commands/$home/$id';

void main() {
  late MemoryCloudStore store;
  late DateTime now;

  /// Termostat w chmurze: wpisuje stan/konfigurację i odpowiada na polecenia jak firmware.
  void putDevice({bool respond = true, Map<String, String> errors = const {}}) {
    // RTDB nie przechowuje null - pola null po prostu znikają.
    final state = (jsonDecode(stateJson) as Map<String, dynamic>)..removeWhere((_, v) => v == null);
    store
      ..set('$base/info', {'name': 'Salon', 'fw': '2.0.0', 'api': 1})
      ..set('$base/state', state)
      ..set('$base/config', jsonDecode(configJson))
      ..set('$base/lastSeen', store.now);
    store.onPush = (path, key, value) {
      if (!respond || path != commands) return;
      final values = (value as Map)['values'] as Map;
      Future.microtask(() {
        if (values['target'] is num) store.set('$base/state/target', values['target']);
        store
          ..set('$base/lastCommand', {'key': key, 'ok': errors.isEmpty, 'errors': errors, 'ts': store.now})
          ..set('$commands/$key', null);
      });
    };
  }

  ThermostatConnection connect() => CloudConnection(
    codec: thermostatCodec,
    store: store,
    homeId: home,
    by: uid,
    deviceId: id,
    commandTimeout: const Duration(milliseconds: 300),
    clock: () => now,
  );

  setUp(() {
    store = MemoryCloudStore();
    now = DateTime.fromMillisecondsSinceEpoch(store.now);
  });

  test('stan i konfiguracja z chmury, bez pól null', () async {
    putDevice();
    store.set('$base/state/press', null);
    final c = connect();
    await c.open();
    expect(c.kind, ConnectionKind.cloud);
    expect(c.state!.temp, 21.4);
    expect(c.state!.press, isNull);
    expect(c.config!.name, 'Salon');
    expect(c.status, LinkStatus.online);

    final next = c.states.firstWhere((s) => s.sensorFault);
    store.set('$base/state/sensorFault', true);
    expect((await next).sensorFault, isTrue);
    await c.close();
  });

  test('polecenie: push do commands, wynik z lastCommand o tym samym kluczu', () async {
    putDevice();
    final c = connect();
    await c.open();
    final r = await c.set(const SetValues(target: 22.5));
    expect(r.ok, isTrue);
    expect(c.state!.target, 22.5);
    expect(store.get(commands), anyOf(isNull, isEmpty), reason: 'termostat usuwa wykonane polecenie');
    await c.close();
  });

  test('polecenie z błędem pola', () async {
    putDevice(errors: {'schedule.weekday': 'format'});
    final c = connect();
    await c.open();
    final r = await c.set(const SetValues(schedule: SchedulePatch(weekday: 'zle')));
    expect(r.ok, isFalse);
    expect(r.errors, {'schedule.weekday': 'format'});
    await c.close();
  });

  test('push zawiera values i znacznik czasu serwera', () async {
    putDevice(respond: false);
    final c = connect();
    await c.open();
    final r = await c.set(const SetValues(mode: null, power: false));
    expect(r.error, 'timeout');
    final pending = store.get(commands) as Map;
    final cmd = pending.values.single as Map;
    expect(cmd['values'], {'power': false});
    expect(cmd['ts'], store.now);
    await c.close();
  });

  test('offline, gdy lastSeen starsze niż 3 min', () async {
    putDevice();
    now = now.add(const Duration(minutes: 4));
    final c = connect();
    await c.open();
    expect(c.status, LinkStatus.offline);
    final back = c.statuses.firstWhere((s) => s == LinkStatus.online);
    store.set('$base/lastSeen', now.millisecondsSinceEpoch);
    await back;
    await c.close();
  });

  test('termostat bez danych w chmurze → NoRouteException z podpowiedzią', () async {
    final c = connect();
    await expectLater(
      c.open(),
      throwsA(isA<NoRouteException>().having((e) => e.message, 'message', contains('Chmura'))),
    );
  });

  group('wybór drogi', () {
    test('termostat tylko z konta (bez tokenu) → od razu chmura', () async {
      putDevice();
      final manager = ConnectionManager(
        store: MemoryDeviceStore(),
        discovery: _NoDiscovery(),
        cloud: TestCloudAccess(store),
      );
      final steps = <String>[];
      final c = await manager.connect(
        const PairedDevice(id: id, name: 'Salon'),
        onStep: steps.add,
      );
      expect(c.kind, ConnectionKind.cloud);
      expect(steps, ['Łączenie przez chmurę…']);
      await c.close();
    });

    test('sparowany, ale poza domem → lokalnie nie odpowiada, potem chmura', () async {
      putDevice();
      final local = MemoryDeviceStore();
      await local.saveToken(id, 'token');
      final manager = ConnectionManager(
        store: local,
        discovery: _NoDiscovery(),
        cloud: TestCloudAccess(store),
        probeTimeout: const Duration(milliseconds: 200),
        discoveryTimeout: const Duration(milliseconds: 100),
      );
      final c = await manager.connect(
        const PairedDevice(id: id, name: 'Salon', lastEndpoint: LocalEndpoint('127.0.0.1', 1)),
      );
      expect(c.kind, ConnectionKind.cloud);
      await c.close();
    });

    test('bez logowania i bez tokenu → trzeba sparować', () async {
      final manager = ConnectionManager(
        store: MemoryDeviceStore(),
        discovery: _NoDiscovery(),
        cloud: TestCloudAccess(store, uid: null),
      );
      await expectLater(
        manager.connect(const PairedDevice(id: id, name: 'Salon')),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  test('lista urządzeń domu (właściciel): klucze homes/{h}/devices + info z typem', () async {
    putDevice();
    store.set('homes/$home/devices/swiatlo-000001/info', {'name': 'Sypialnia', 'type': 'switch'});
    store.set('homes/inny-dom/devices/termostat-999999/info', {'name': 'Cudzy'});
    final list = await (TestCloudAccess(store)..homeOwnerUid = 'uid-1').devices();
    expect(
      {for (final d in list) d.id: (d.name, d.type.wire)},
      {id: ('Salon', 'thermostat'), 'swiatlo-000001': ('Sypialnia', 'switch')},
    );
  });
}
