// Aktualizacje z chmury (pkt 3a / 3e): postęp z `homes/{h}/devices/{id}/ota`, dwa kroki przez wersję pośrednią,
// powrót do poprzedniej wersji, lustro `updates` huba (mapa, `next`) i Set `applyUpdates` / `checkUpdates`.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/dashboard_store.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/firmware_catalog.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/data/updates.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/firmware.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_cloud_store.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

/// Hub w chmurze: Set z `firmwareUrl` uruchamia [onFirmware], inne Set - [onSet].
class _CloudHub implements DeviceConnection<Json, Json> {
  final sent = <Json>[];
  void Function(Json values)? onFirmware;
  SetResult Function(Json values) onSet = (_) => const SetResult(ok: true);

  @override
  String get deviceId => 'hub1';
  @override
  ConnectionKind get kind => ConnectionKind.cloud;
  @override
  String get routeDescription => 'Firebase';
  @override
  Json get state => {'id': 'hub1', 'cloud': true};
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
    if (values.containsKey('firmwareUrl')) {
      onFirmware?.call(values);
      return const SetResult(ok: true);
    }
    return onSet(values);
  }

  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager(this.conn, DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  final _CloudHub conn;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conn as DeviceConnection<S, C>;
}

final _sha = 'c' * 64;

void main() {
  late MemoryCloudStore cloud;
  late _CloudHub conn;
  late DeviceHub hub;
  late DeviceHubUpdates updates;

  setUp(() async {
    cloud = MemoryCloudStore();
    cloud.set('homes/h1/ownerUid', 'u1');
    cloud.set('homes/h1/devices/hub1/info', {'type': 'hub', 'fw': '1.0.0', 'fwId': 'hub-n16r8'});
    // Stary wpis z poprzedniej aktualizacji - nie może dać „done”.
    cloud.set('homes/h1/devices/hub1/ota', {'state': 'done', 'version': '1.0.0', 'ts': 1});
    conn = _CloudHub();
    final store = MemoryDeviceStore();
    await store.saveDevice(
      const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub, access: AccessLevel.config),
    );
    hub = DeviceHub(
      store: store,
      manager: _Manager(conn, store),
      cloud: TestCloudAccess(cloud, uid: 'u1')..homeOwnerUid = 'u1',
      home: const Home(id: 'h1', name: 'Dom', ownerUid: 'u1'),
    );
    await hub.load();
    for (var i = 0; i < 50 && hub.controller('hub1')?.state == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final manifest = {
      'v': 1,
      'fw': {
        'hub-n16r8': {
          'version': '1.4.0',
          'url': 'https://ha-firmware.web.app/fw/hub-n16r8-1.4.0.bin',
          'sha256': _sha,
          'minVersion': '1.2.0',
          'intermediate': {
            'version': '1.3.0',
            'url': 'https://ha-firmware.web.app/fw/hub-n16r8-1.3.0.bin',
            'sha256': _sha,
            'size': 1,
          },
        },
      },
    };
    updates = DeviceHubUpdates(
      hub,
      catalog: FirmwareCatalog(
        client: MockClient((_) async => http.Response(jsonEncode(manifest), 200)),
        cache: MemoryTextCache(),
      ),
      cloudPoll: const Duration(milliseconds: 10),
      timeout: const Duration(seconds: 5),
    );
  });

  tearDown(() => hub.dispose());

  /// Urządzenie po Set pisze kolejne stany `ota` (PUT całego obiektu).
  void script(List<Json> steps) => conn.onFirmware = (_) async {
    for (final s in steps) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      cloud.set('homes/h1/devices/hub1/ota', s);
    }
  };

  test('z chmury w dwóch krokach: najpierw wersja pośrednia, postęp z ota, potem wydanie', () async {
    final m = await updates.manifest();
    var t = (await updates.targets()).single;
    expect((t.local, t.blocked, t.fw), (false, null, '1.0.0'));
    var check = checkUpdate(m, fw: t.fw, fwId: t.fwId);
    expect((check.status, check.twoSteps, check.step!.version), (UpdateStatus.available, true, '1.3.0'));

    script([
      {'state': 'running', 'progress': 0, 'version': '1.3.0', 'ts': 2},
      {'state': 'running', 'progress': 50, 'version': '1.3.0', 'ts': 3},
      {'state': 'done', 'version': '1.3.0', 'ts': 4},
    ]);
    final steps = await updates.update(t, check.step!).toList();
    expect(conn.sent.last, {
      'firmwareUrl': 'https://ha-firmware.web.app/fw/hub-n16r8-1.3.0.bin',
      'firmwareSha256': _sha,
    });
    expect(steps.map((s) => s.percent).whereType<int>(), containsAllInOrder([0, 50]));
    expect(steps.last.phase, UpdatePhase.done, reason: steps.last.label);

    cloud.set('homes/h1/devices/hub1/info/fw', '1.3.0');
    t = (await updates.targets()).single;
    check = checkUpdate(m, fw: t.fw, fwId: t.fwId);
    expect((check.twoSteps, check.step!.version), (false, '1.4.0'));
  });

  test('z chmury: błąd sumy i powrót do poprzedniej wersji (także po wcześniejszym done)', () async {
    final m = await updates.manifest();
    final t = (await updates.targets()).single;
    final r = m.releases['hub-n16r8']!;

    script([
      {'state': 'running', 'progress': 0, 'version': '1.4.0', 'ts': 2},
      {'state': 'failed', 'error': 'sha256', 'version': '1.4.0', 'ts': 3},
    ]);
    final failed = await updates.update(t, r).last;
    expect(failed.phase, UpdatePhase.failed);
    expect(failed.label, contains('Suma pobranego pliku'));

    script([
      {'state': 'rolledBack', 'error': 'boot', 'version': '1.0.0', 'ts': 5},
    ]);
    final back = await updates.update(t, r).last;
    expect(back.phase, UpdatePhase.failed);
    expect(back.label, contains('nie wystartowała'));
  });

  test('lustro updates huba (mapa, next), Set applyUpdates z błędem po id, checkUpdates', () async {
    cloud.set('homes/h1/devices/hub1/updates', {
      'checked': 1793000000,
      'devices': {
        'sw1': {'id': 'sw1', 'current': '1.1.0', 'available': '1.4.0', 'next': '1.3.0', 'ready': true, 'state': 'idle'},
        'sw2': {'id': 'sw2', 'current': '1.4.0', 'available': '1.4.0', 'state': 'done'},
      },
    });
    final view = (await updates.hubs()).single;
    final byId = {for (final d in view.updates.devices) d.id: d};
    expect((byId['sw1']!.selectable, byId['sw1']!.twoSteps, byId['sw2']!.hasUpdate), (true, true, false));

    await updates.applyHub('hub1', ['sw1']);
    expect(conn.sent.last, {
      'applyUpdates': ['sw1'],
    });

    conn.onSet = (v) => SetResult(
      ok: false,
      errors: asErrors({
        'applyUpdates': {'sw1': 'not_ready'},
      }),
    );
    await expectLater(
      updates.applyHub('hub1', ['sw1']),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', 'sw1: hub nie pobrał jeszcze pliku')),
    );

    conn.onSet = (_) => const SetResult(ok: true);
    await updates.checkHub('hub1');
    expect(conn.sent.last, {'checkUpdates': true});
  });
}
