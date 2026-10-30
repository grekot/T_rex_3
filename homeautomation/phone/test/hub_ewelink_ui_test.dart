// Dodawanie Sonoffa z eWeLink przez hub (API.md pkt 11 „eWeLink LAN”): klucz urządzenia (walidacja, wklejanie),
// listwa jako osobne kanały. Bez gniazd - [HubApi] w pamięci.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/hub_api.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/hub_screen.dart';

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

/// Hub w pamięci: jedno wykrycie i zapis żądań `POST /api/devices`.
class _MemHubApi extends HubApi {
  _MemHubApi(this.found) : super(LocalApi(LocalEndpoint('127.0.0.1', 1)));

  final List<HubFound> found;
  final added = <Json>[];

  @override
  Future<HubDiscovery> discover() async => HubDiscovery(scanning: false, age: 0, found: found);

  @override
  Future<String> addDevice(Json device) async {
    added.add(device);
    final ch = device['channel'];
    return ch is int ? 'ewelink-${device['deviceId']}-${ch + 1}' : 'ewelink-${device['deviceId']}';
  }
}

void main() {
  testWidgets('Sonoff (eWeLink): listwa - klucz z walidacją i wklejaniem, wybór kanałów → osobne urządzenia', (
    tester,
  ) async {
    const key = '0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': ' $key '};
      return null;
    });
    final api = _MemHubApi(const [
      HubFound(adapter: HubAdapter.ewelink, host: '192.168.1.52', deviceId: '1000a1b2c3', model: 'strip'),
      HubFound(adapter: HubAdapter.ewelink, host: '192.168.1.53', deviceId: '1000d4e5f6', model: 'plug'),
    ]);
    final store = MemoryDeviceStore();
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
        pairing: PairingService(store: store),
        cloud: NoCloudAccess(),
        provisioning: _NoBle(),
        rooms: _MemRooms(),
        child: MaterialApp(
          home: HubDiscoverScreen(api: api, canLink: false, hubId: 'hub-51e96c'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sonoff (listwa)'), findsOneWidget);
    expect(find.text('Sonoff'), findsOneWidget);

    await tester.tap(find.byKey(const Key('found-192.168.1.52')));
    await tester.pumpAndSettle();
    expect(find.text('Dodaj listwę Sonoff'), findsOneWidget);
    expect(find.textContaining('tools/ewelink_klucze.py'), findsOneWidget);
    FilledButton ok() => tester.widget<FilledButton>(find.byKey(const Key('addOk')));
    expect(ok().onPressed, isNull, reason: 'bez klucza');

    await tester.enterText(find.byKey(const Key('addName')), 'Biurko');
    await tester.enterText(find.byKey(const Key('ewelinkKey')), '1234');
    await tester.pump();
    expect(find.text('Klucz ma 36 znaków: 8-4-4-4-12'), findsOneWidget);
    expect(ok().onPressed, isNull);

    await tester.tap(find.byKey(const Key('ewelinkPaste')));
    await tester.pumpAndSettle();
    expect(find.text('Klucz ma 36 znaków: 8-4-4-4-12'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('ewelinkChannel-4')));
    await tester.tap(find.byKey(const Key('ewelinkChannel-4')));
    await tester.pump();
    expect(find.text('Dodaj (3)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('addOk')));
    await tester.pumpAndSettle();
    expect(api.added, [
      for (final c in [0, 1, 2])
        {
          'adapter': 'ewelink',
          'host': '192.168.1.52',
          'deviceId': '1000a1b2c3',
          'localKey': key.toLowerCase(),
          'type': 'switch',
          'channel': c,
          'name': 'Biurko ${c + 1}',
        },
    ]);
    expect(find.text('Dodano Biurko 1, Biurko 2, Biurko 3.'), findsOneWidget);

    // Gniazdko (plug): jedno urządzenie, bez kanałów.
    await tester.tap(find.byKey(const Key('found-192.168.1.53')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ewelinkChannel-1')), findsNothing);
    await tester.tap(find.byKey(const Key('ewelinkPaste')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addOk')));
    await tester.pumpAndSettle();
    expect(api.added.last, {
      'adapter': 'ewelink',
      'host': '192.168.1.53',
      'deviceId': '1000d4e5f6',
      'localKey': key.toLowerCase(),
      'type': 'switch',
      'name': 'Sonoff',
    });
  });
}
