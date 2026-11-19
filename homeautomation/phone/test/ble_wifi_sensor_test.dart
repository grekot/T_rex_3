// „Dodaj czujnik WiFi (zasilanie USB)” (pkt 15.7): `HA_ble-*` z sygnałem ≥ −60 dBm, sesja bez PoP, `ha-pair` z adresem
// huba (bez tokenu), sieć i hasło, dopiero po `connected` szukanie w hubie; nowy czujnik z `paired` → nazwa i dodanie,
// już dodany → `link: "wifi"`. Hub w pamięci, urządzenie - atrapa protokołu provisioningu.

import 'package:flutter/material.dart';
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
import 'package:homeautomation/ui/ble_wifi_sensor_screen.dart';

import 'support/fake_prov_device.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
}

class _MemRooms extends RoomStore {
  @override
  Stream<List<Room>> watch() => Stream.value(const []);
  @override
  Future<void> save(Room room) async {}
  @override
  Future<void> remove(String roomId) async {}
}

/// Bluetooth telefonu: stała lista urządzeń w trybie konfiguracji, połączenie z atrapą.
class _Ble extends ProvisioningBackend {
  _Ble(this.found, this.device);

  final List<ProvCandidate> found;
  final FakeProvDevice device;
  ProvCandidate? connected;

  @override
  bool get supported => true;
  @override
  Stream<List<ProvCandidate>> scan() => Stream.value(found);
  @override
  Future<ProvTransport> connect(ProvCandidate candidate) async {
    connected = candidate;
    return device;
  }
}

/// Hub w pamięci: czujnik pojawia się po drugim odpytaniu (nowy w `paired`, dodany - `link: wifi`).
class _Hub extends HubApi {
  _Hub(this.device, {this.existing = false}) : super(LocalApi(const LocalEndpoint('192.168.68.125')));

  final FakeProvDevice device;
  final bool existing;
  final added = <Json>[];
  var scans = 0, stops = 0, polls = 0;

  /// Czy szukanie w hubie ruszyło dopiero po połączeniu czujnika z siecią.
  bool? scanAfterConnected;

  @override
  Future<int> bleScan({int seconds = 120}) async {
    scans++;
    scanAfterConnected = device.applied;
    return 1;
  }

  @override
  Future<void> bleStop() async => stops++;

  @override
  Future<BleSeen> bleSeen() async {
    polls++;
    return BleSeen(scanning: true, paired: polls < 2 ? const [] : const [BlePaired(mac: '88:56:a6:77:b8:36')]);
  }

  @override
  Future<List<HubChild>> devices() async => [
    if (existing)
      HubChild.fromJson({
        'id': 'ble-8856a677b836',
        'type': 'sensor',
        'adapter': 'ble',
        'host': '',
        'name': 'Salon czerwony',
        'state': {'link': scans > 0 && polls++ >= 1 ? 'wifi' : 'bt'},
      }),
  ];

  @override
  Future<String> addDevice(Json device) async {
    added.add(device);
    return 'ble-8856a677b836';
  }
}

FakeProvDevice _sensor() => FakeProvDevice(
  pop: '',
  networks: const [FakeNetwork('Dom', -48, password: 'tajne123')],
  connectPolls: 1,
  pairResponse: {'id': 'ble-8856a677b836', 'type': 'sensor', 'fwId': 'btsensor-s3zero', 'fw': '1.3.0', 'api': 2},
);

Future<void> _pump(WidgetTester tester, HubApi api, ProvisioningBackend ble) async {
  final store = MemoryDeviceStore();
  await tester.pumpWidget(
    Services(
      store: store,
      discovery: _NoDiscovery(),
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      pairing: PairingService(store: store),
      cloud: NoCloudAccess(),
      provisioning: ble,
      rooms: _MemRooms(),
      child: MaterialApp(
        home: BleWifiSensorScreen(
          api: api,
          hubId: 'hub-51e96c',
          hubIp: '192.168.68.125',
          canLink: false,
          interval: const Duration(milliseconds: 10),
        ),
      ),
    ),
  );
}

/// Czeka (prawdziwy czas - kryptografia sesji, odpytywanie huba), aż pojawi się [f]; wskaźnik postępu kręci się
/// cały czas, więc bez `pumpAndSettle`.
Future<void> _waitFor(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(f, findsWidgets);
}

/// Kroki wspólne: instrukcja → szukanie (jeden czujnik obok - od razu) → sieć „Dom” i hasło → połącz.
Future<void> _toWifi(WidgetTester tester) async {
  expect(find.byKey(const Key('bleWifiBattery')), findsOneWidget, reason: 'ostrzeżenie o baterii');
  await tester.tap(find.byKey(const Key('bleWifiStart')));
  await _waitFor(tester, find.byKey(const Key('wifi-Dom')));
  await tester.tap(find.byKey(const Key('wifi-Dom')));
  await tester.pump();
  await tester.enterText(find.byKey(const Key('wifiPassword')), 'tajne123');
  await tester.tap(find.byKey(const Key('bleWifiJoin')));
}

void main() {
  test('ha-pair czujnika: adres huba w żądaniu, odpowiedź bez tokenu', () async {
    final dev = _sensor();
    final prov = Provisioner(dev, '');
    await prov.start();
    final r = await prov.haPairSensor('Pixel 8', hubId: 'hub-51e96c', hubIp: '192.168.68.125');
    expect((r.id, r.mac, r.type, r.fw), ('ble-8856a677b836', '8856a677b836', 'sensor', '1.3.0'));
    expect(dev.pairedHub, {'id': 'hub-51e96c', 'ip': '192.168.68.125'});
    expect(dev.pairedClient, 'Pixel 8');
  });

  testWidgets('nowy czujnik: sesja bez PoP, sieć, szukanie w hubie dopiero po połączeniu, nazwa i dodanie', (
    tester,
  ) async {
    final dev = _sensor();
    final hub = _Hub(dev);
    await _pump(tester, hub, _Ble(const [ProvCandidate('HA_ble-8856a677b836', -45)], dev));
    await _toWifi(tester);
    await _waitFor(tester, find.byKey(const Key('bleWifiName')));
    expect((dev.ssid, dev.passphrase), ('Dom', 'tajne123'));
    expect(dev.pairedHub, {'id': 'hub-51e96c', 'ip': '192.168.68.125'});
    expect(hub.scanAfterConnected, isTrue, reason: 'okno parowania w hubie dopiero po connected');
    expect(find.byKey(const Key('bleWifiName')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('bleWifiName')), 'Salon czerwony');
    await tester.pump();
    await tester.tap(find.byKey(const Key('bleWifiAdd')));
    await tester.pumpAndSettle();
    expect(hub.added.single, {
      'adapter': 'ble',
      'deviceId': '88:56:a6:77:b8:36',
      'paired': true,
      'name': 'Salon czerwony',
    });
    expect(hub.stops, 1);
    expect(find.textContaining('Dodano Salon czerwony'), findsOneWidget);
  });

  testWidgets('już dodany czujnik: po połączeniu czeka na link wifi, bez ponownego dodawania', (tester) async {
    final dev = _sensor();
    final hub = _Hub(dev, existing: true);
    await _pump(tester, hub, _Ble(const [ProvCandidate('HA_ble-8856a677b836', -45)], dev));
    await _toWifi(tester);
    await _waitFor(tester, find.text('Salon czerwony pracuje teraz przez WiFi.'));
    expect(hub.added, isEmpty);
  });

  testWidgets('kilka czujników albo daleko: bez automatu, daleki wyszarzony, wybór użytkownika', (tester) async {
    final dev = _sensor();
    final ble = _Ble(const [ProvCandidate('HA_ble-8856a677b836', -50), ProvCandidate('HA_ble-112233445566', -75)], dev);
    await _pump(tester, _Hub(dev), ble);
    await tester.tap(find.byKey(const Key('bleWifiStart')));
    await _waitFor(tester, find.byKey(const Key('bleWifi-ble-112233445566')));
    expect(find.text('Kilka czujników czeka na konfigurację - wybierz swój.'), findsOneWidget);
    expect(find.textContaining('Za daleko (-75 dBm)'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('bleWifi-ble-112233445566'))).enabled, isFalse);
    expect(ble.connected, isNull);
    await tester.tap(find.byKey(const Key('bleWifi-ble-8856a677b836')));
    await _waitFor(tester, find.byKey(const Key('wifi-Dom')));
    expect(ble.connected?.id, 'ble-8856a677b836');
  });
}
