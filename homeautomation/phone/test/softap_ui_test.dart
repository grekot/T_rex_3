// Kreator „Urządzenie bez Bluetootha” (pkt 9.4): kod z naklejki → sieć HA_* → ha-pair → sieć domowa → gotowe.
// HTTP do urządzenia przez MockClient (w testach widżetów prawdziwe gniazda są wyłączone).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/app.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/provisioning/softap_transport.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/ble_setup_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_prov_device.dart';

class _RecordingJoiner implements ApJoiner {
  final joins = <(String?, String)>[];
  int releases = 0;

  @override
  bool get supported => true;

  @override
  Future<void> join({String? ssid, required String passphrase}) async => joins.add((ssid, passphrase));

  @override
  Future<void> release() async => releases++;
}

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

class _NoBle extends ProvisioningBackend {
  @override
  bool get supported => false;
  @override
  Stream<List<ProvCandidate>> scan() => const Stream.empty();
  @override
  Future<ProvTransport> connect(ProvCandidate candidate) => throw UnimplementedError();
}

class _MemRooms extends RoomStore {
  @override
  Stream<List<Room>> watch() => Stream.value(const []);
  @override
  Future<void> save(Room room) async {}
  @override
  Future<void> remove(String roomId) async {}
}

void main() {
  testWidgets('kreator „Urządzenie bez Bluetootha”: kod z naklejki → sieć → gotowe', (tester) async {
    final device = FakeProvDevice(
      pop: 'ab12cd34',
      id: 'swiatlo-0c4f21',
      type: 'switch',
      token: 'tok-softap',
      networks: const [FakeNetwork('Dom', -50, password: 'tajne123')],
      connectPolls: 1,
    );
    final cookies = <String?>[];
    final client = MockClient((req) async {
      cookies.add(req.headers['Cookie']);
      final out = await device.exchange(req.url.path.substring(1), Uint8List.fromList(req.bodyBytes));
      return http.Response.bytes(out, 200, headers: {'set-cookie': 'session=7; Path=/'});
    });
    final store = MemoryDeviceStore();
    final joiner = _RecordingJoiner();
    PairedDevice? result;
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
        pairing: PairingService(store: store, clientName: () async => 'Pixel 8'),
        cloud: NoCloudAccess(),
        provisioning: _NoBle(),
        rooms: _MemRooms(),
        softAp: SoftApProvisioning(joiner: joiner, clientFactory: () => client),
        child: TermostatApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async => result = await Navigator.of(
                context,
              ).push<PairedDevice>(MaterialPageRoute(builder: (_) => const BleSetupScreen(softAp: true))),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Urządzenie bez Bluetootha'), findsOneWidget);

    Future<void> until(Finder f) async {
      for (var i = 0; i < 120 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 250));
      }
      final texts = [for (final e in find.byType(Text).evaluate()) (e.widget as Text).data].join(' | ');
      expect(f, findsWidgets, reason: texts);
    }

    await tester.enterText(find.byKey(const Key('pop')), 'AB12CD34');
    await tester.tap(find.byKey(const Key('popNext')));
    await until(find.byKey(const Key('wifi-Dom')));
    expect(joiner.joins.single, (null, 'ab12cd34'), reason: 'PoP małymi literami = hasło sieci HA_*');
    expect(await store.token('swiatlo-0c4f21'), 'tok-softap');
    expect(cookies.skip(1).toSet(), {'session=7'});

    await tester.tap(find.byKey(const Key('wifi-Dom')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('wifiPassword')), 'tajne123');
    await tester.tap(find.byKey(const Key('wifiJoin')));
    await until(find.byKey(const Key('bleDone')));
    expect(joiner.releases, greaterThanOrEqualTo(1), reason: 'telefon wraca do sieci domowej');
    await tester.tap(find.text('Zakończ'));
    await tester.pumpAndSettle();
    expect((result!.id, result!.type, result!.lastEndpoint?.host), ('swiatlo-0c4f21', DeviceType.onOff, '192.168.1.77'));
  });
}
