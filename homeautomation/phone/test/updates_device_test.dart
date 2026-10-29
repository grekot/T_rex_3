// Aktualizacje firmware (pkt 3e) na atrapach urządzeń - prawdziwe gniazda, więc bez testWidgets
// (ekran: firmware_test.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/dashboard_store.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/firmware_catalog.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/updates.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/firmware.dart';
import 'package:homeautomation/models/home.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/fake/fake_thermostat_server.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

final _sha = 'a' * 64;

Map<String, dynamic> _release(String fwId, String version, {String? minVersion}) => {
  'version': version,
  'url': 'https://ha-firmware.web.app/fw/$fwId-$version.bin',
  'sha256': _sha,
  'size': 1200000,
  'minVersion': ?minVersion,
  'notes': 'Poprawki',
};

void main() {
  late FakeThermostat thermo;
  late FakeLight light;
  late FakeHub hubFake;
  late DeviceHub hub;
  late DeviceHubUpdates updates;

  setUp(() async {
    thermo = FakeThermostat(simulate: false)
      ..otaDelay = const Duration(milliseconds: 10)
      ..otaRestart = const Duration(milliseconds: 100);
    light = FakeLight(id: 'swiatlo-1', name: 'Lampa');
    hubFake = FakeHub();
    final store = MemoryDeviceStore();
    for (final (f, type, name) in [
      (thermo as FakeDevice, DeviceType.thermostat, 'Salon'),
      (light, DeviceType.onOff, 'Lampa'),
      (hubFake, DeviceType.hub, 'Hub'),
    ]) {
      await f.start(port: 0, address: InternetAddress.loopbackIPv4);
      await store.saveDevice(
        PairedDevice(
          id: f.id,
          name: name,
          type: type,
          lastEndpoint: LocalEndpoint('127.0.0.1', f.port),
          access: AccessLevel.config,
        ),
      );
      await store.saveToken(f.id, f.token);
    }
    hub = DeviceHub(
      store: store,
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      cloud: NoCloudAccess(),
    );
    await hub.load();
    for (var i = 0; i < 100 && hub.devices.any((d) => hub.controller(d.id)?.isLocal != true); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final manifest = {
      'v': 1,
      'generated': '2026-11-02T10:00:00Z',
      'fw': {
        'thermostat-n16r8': _release('thermostat-n16r8', '2.2.0'),
        'switch4-s2mini': _release('switch4-s2mini', '3.1.0', minVersion: '3.0.0'),
        'hub-n16r8': _release('hub-n16r8', '0.2.0'),
      },
    };
    updates = DeviceHubUpdates(
      hub,
      catalog: FirmwareCatalog(
        client: MockClient((_) async => http.Response(jsonEncode(manifest), 200)),
        cache: MemoryTextCache(),
      ),
      poll: const Duration(milliseconds: 20),
      timeout: const Duration(seconds: 10),
    );
  });

  tearDown(() async {
    hub.dispose();
    await thermo.stop();
    await light.stop();
    await hubFake.stop();
  });

  test('lista: fw i fwId z /api/info, stan wobec manifestu', () async {
    final m = await updates.manifest();
    final targets = {for (final t in await updates.targets()) t.id: t};
    expect(targets.keys.toSet(), {'termostat-ab12cd', 'swiatlo-1', 'hub-51e96c'});
    expect(targets.values.every((t) => t.local && t.blocked == null), isTrue);
    UpdateStatus status(String id) => checkUpdate(m, fw: targets[id]!.fw, fwId: targets[id]!.fwId).status;
    expect(status('termostat-ab12cd'), UpdateStatus.available);
    expect(status('swiatlo-1'), UpdateStatus.needsIntermediate, reason: 'atrapa ma 2.1.0, minVersion 3.0.0');
    expect(status('hub-51e96c'), UpdateStatus.upToDate);
  });

  test('aktualizacja termostatu: Set firmwareUrl + sha256, postęp, restart z nową wersją; zła suma', () async {
    final m = await updates.manifest();
    final t = (await updates.targets()).firstWhere((t) => t.id == 'termostat-ab12cd');
    final steps = await updates.update(t, m.releases['thermostat-n16r8']!).toList();
    expect(steps.first.phase, UpdatePhase.sending);
    expect(steps.map((s) => s.phase), containsAllInOrder([UpdatePhase.downloading, UpdatePhase.restarting]));
    expect(steps.last.phase, UpdatePhase.done, reason: steps.last.label);
    expect(
      (thermo.firmwareUrls.single, thermo.fw),
      ('https://ha-firmware.web.app/fw/thermostat-n16r8-2.2.0.bin', '2.2.0'),
    );

    thermo.firmwareSha256Mismatch = true;
    final failed = await updates.update(t, m.releases['thermostat-n16r8']!).last;
    expect(failed.phase, UpdatePhase.failed);
    expect(failed.label, contains('Suma pobranego pliku'));
  });

  test(
    'węzły huba: GET /api/updates, zatwierdzenie, 409 not_ready, dwa kroki przez wersję pośrednią, sprawdź teraz',
    () async {
      hubFake.nodeUpdates.addAll([
        {
          'id': 'swiatlo-1',
          'fwId': 'switch4-s2mini',
          'current': '1.1.0',
          'available': '1.4.0',
          'next': '1.3.0',
          'ready': true,
          'state': 'idle',
        },
        {
          'id': 'swiatlo-2',
          'fwId': 'switch4-s2mini',
          'current': '1.3.0',
          'available': '1.4.0',
          'next': '1.4.0',
          'ready': false,
          'state': 'idle',
        },
      ]);
      final view = (await updates.hubs()).single;
      expect((view.hubId, view.names['swiatlo-1']), ('hub-51e96c', 'Lampa'));
      expect(view.updates.devices.map((d) => d.selectable), [true, false], reason: 'drugi - hub jeszcze pobiera plik');
      expect(view.updates.devices.first.twoSteps, isTrue);

      await expectLater(
        updates.applyHub('hub-51e96c', ['swiatlo-1', 'swiatlo-2']),
        throwsA(
          isA<ThermostatException>().having((e) => e.message, 'message', contains('hub nie pobrał jeszcze pliku')),
        ),
      );
      expect(hubFake.nodeUpdates.first['state'], 'idle', reason: '409 - nic nie trafia do kolejki');

      await updates.applyHub('hub-51e96c', ['swiatlo-1']);
      expect((await updates.hubs()).single.updates.devices.first.state, HubUpdateState.queued);
      while (hubFake.advanceUpdates()) {}
      var first = (await updates.hubs()).single.updates.devices.first;
      expect((first.state, first.current, first.next, first.selectable), (HubUpdateState.done, '1.3.0', '1.4.0', true));

      await updates.applyHub('hub-51e96c', ['swiatlo-1']);
      while (hubFake.advanceUpdates()) {}
      first = (await updates.hubs()).single.updates.devices.first;
      expect((first.current, first.hasUpdate), ('1.4.0', false));

      await updates.checkHub('hub-51e96c');
      expect(hubFake.updateChecks, 1);
    },
  );
}
