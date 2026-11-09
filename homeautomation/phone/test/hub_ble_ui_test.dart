// „Dodaj czujnik Bluetooth” (API.md pkt 11 „Czujniki Bluetooth”): szukanie przez btnode, podgląd wartości, dodanie
// z kluczem dla szyfrowanych, brak węzła. Bez gniazd - [HubApi] w pamięci.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/errors.dart';
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
import 'package:homeautomation/ui/hub_ble_screen.dart';

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

/// Hub w pamięci: szukanie trwa jedno odpytanie, potem lista znalezionych.
class _MemHubApi extends HubApi {
  _MemHubApi({this.nodes = 1, this.paired = const []}) : super(LocalApi(LocalEndpoint('127.0.0.1', 1)));

  final int nodes;
  final List<BlePaired> paired;

  /// Kod błędu kolejnego `addDevice` (np. `paired` = parowanie wygasło).
  String? addError;
  final added = <Json>[];
  var scans = 0, stops = 0, polls = 0;

  static const found = [
    BleFound(mac: 'a4:c1:38:12:34:56', rssi: -62, via: 'bt-a1b2c3', values: {'temp': 21.6, 'hum': 45.4, 'battery': 87}),
    BleFound(
      mac: 'f8:44:77:aa:bb:cc',
      encrypted: true,
      trigger: true,
      rssi: -85,
      values: {'battery': 100},
      buttons: ['btn1'],
    ),
  ];

  @override
  Future<int> bleScan({int seconds = 120}) async {
    scans++;
    return nodes;
  }

  @override
  Future<void> bleStop() async => stops++;

  @override
  Future<BleSeen> bleSeen() async {
    polls++;
    return BleSeen(
      scanning: polls < 2,
      remaining: polls < 2 ? 100 : 0,
      nodes: const [BleNode(id: 'bt-a1b2c3', online: true)],
      paired: polls < 2 ? const [] : paired,
      found: polls < 2 ? const [] : found,
    );
  }

  @override
  Future<List<HubChild>> devices() async => [
    HubChild.fromJson({'id': 'ble-a4c138123456', 'type': 'sensor', 'adapter': 'ble', 'host': '', 'name': 'Salon'}),
  ];

  @override
  Future<String> addDevice(Json device) async {
    if (addError case final e?) {
      addError = null;
      throw ThermostatException(e == 'paired' ? 'Parowanie wygasło - podłącz czujnik ponownie.' : e);
    }
    added.add(device);
    return 'ble-${(device['deviceId'] as String).replaceAll(':', '')}';
  }
}

Future<void> _pump(WidgetTester tester, HubApi api) async {
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
        home: HubBleScreen(api: api, canLink: false, hubId: 'hub-51e96c', interval: const Duration(milliseconds: 10)),
      ),
    ),
  );
}

void main() {
  testWidgets('czujniki Bluetooth: podgląd wartości, dodanie zwykłego i szyfrowanego (klucz ze schowka)', (
    tester,
  ) async {
    const key = '00112233445566778899AABBCCDDEEFF';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': ' $key '};
      return null;
    });
    final api = _MemHubApi();
    await _pump(tester, api);
    await tester.pump();
    expect(find.textContaining('Szukam przez 1 węzeł Bluetooth'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('Znalezione, jeszcze niedodane: 2'), findsOneWidget);
    expect(find.textContaining('21,6 °C · 45,4 % · bateria 87 %'), findsOneWidget);
    expect(find.textContaining('szyfrowany - potrzebny klucz'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bleFound-a4:c1:38:12:34:56')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bleKey')), findsNothing, reason: 'nieszyfrowany - bez klucza');
    await tester.enterText(find.byKey(const Key('bleName')), 'Salon');
    await tester.pump();
    await tester.tap(find.byKey(const Key('bleAddOk')));
    await tester.pumpAndSettle();
    expect(api.added.single, {'adapter': 'ble', 'deviceId': 'a4:c1:38:12:34:56', 'name': 'Salon'});
    expect(find.text('Dodano Salon.'), findsOneWidget);
    expect(find.byKey(const Key('bleFound-a4:c1:38:12:34:56')), findsNothing, reason: 'dodany znika z listy');

    await tester.tap(find.byKey(const Key('bleFound-f8:44:77:aa:bb:cc')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bleName')), 'Przycisk');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('bleAddOk'))).onPressed, isNull, reason: 'bez klucza');
    await tester.enterText(find.byKey(const Key('bleKey')), 'abc');
    await tester.pump();
    expect(find.text('Klucz ma 32 znaki 0-9 a-f'), findsOneWidget);
    await tester.tap(find.byKey(const Key('blePaste')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bleAddOk')));
    await tester.pumpAndSettle();
    expect(api.added.last, {
      'adapter': 'ble',
      'deviceId': 'f8:44:77:aa:bb:cc',
      'name': 'Przycisk',
      'localKey': key.toLowerCase(),
    });

    // Wyjście z ekranu po zakończonym szukaniu nie wysyła już „stop”.
    await tester.tap(find.byKey(const Key('bleAgain')));
    await tester.pumpAndSettle();
    expect(api.scans, 2);
  });

  testWidgets(
    'czujnik btsensor sparowany: na górze, dodanie bez klucza, wygasłe parowanie, zatwierdzenie nowego klucza',
    (tester) async {
      final api = _MemHubApi(
        paired: const [
          BlePaired(mac: 'f8:44:77:aa:bb:cc'),
          BlePaired(mac: 'a4:c1:38:12:34:56', id: 'ble-a4c138123456'),
        ],
      );
      await _pump(tester, api);
      await tester.pump();
      expect(find.byKey(const Key('blePairHint')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blePairHint')), findsNothing, reason: 'tylko w czasie szukania');
      expect(find.text('Sparowany czujnik · f8:44:77:aa:bb:cc'), findsOneWidget);
      expect(find.byKey(const Key('bleFound-f8:44:77:aa:bb:cc')), findsNothing, reason: 'nie dubluje sparowanego');
      expect(find.textContaining('bateria 100 %'), findsOneWidget, reason: 'podgląd wartości z found');

      await tester.tap(find.byKey(const Key('blePaired-f8:44:77:aa:bb:cc')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bleKey')), findsNothing, reason: 'klucz zna hub');
      await tester.enterText(find.byKey(const Key('bleName')), 'Okno');
      await tester.pump();
      api.addError = 'paired';
      await tester.tap(find.byKey(const Key('bleAddOk')));
      await tester.pumpAndSettle();
      expect(find.text('Parowanie wygasło - podłącz czujnik ponownie.'), findsOneWidget);
      expect(api.added, isEmpty);

      await tester.tap(find.byKey(const Key('blePaired-f8:44:77:aa:bb:cc')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bleName')), 'Okno');
      await tester.pump();
      await tester.tap(find.byKey(const Key('bleAddOk')));
      await tester.pumpAndSettle();
      expect(api.added.single, {'adapter': 'ble', 'deviceId': 'f8:44:77:aa:bb:cc', 'name': 'Okno', 'paired': true});
      expect(find.byKey(const Key('blePaired-f8:44:77:aa:bb:cc')), findsNothing);

      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bleConfirmKey-a4:c1:38:12:34:56')));
      await tester.pumpAndSettle();
      expect(api.added.last, {'adapter': 'ble', 'deviceId': 'a4:c1:38:12:34:56', 'paired': true, 'name': 'Salon'});
      expect(find.text('Zatwierdzono nowy klucz: Salon.'), findsOneWidget);
    },
  );

  testWidgets('czujniki Bluetooth: bez węzła btnode online - komunikat, bez odpytywania', (tester) async {
    final api = _MemHubApi(nodes: 0);
    await _pump(tester, api);
    await tester.pumpAndSettle();
    expect(find.textContaining('Hub nie ma działającego węzła Bluetooth'), findsOneWidget);
    expect(api.polls, 0);
  });

  test('opisy wartości czujnika: liczby z jednostką, stany po polsku', () {
    expect(
      [
        bleValueText('temp', 21.6),
        bleValueText('hum', 45),
        bleValueText('battery', 87.4),
        bleValueText('voltage', 2.95),
        bleValueText('window', true),
        bleValueText('motion', false),
        bleValueText('temp2', 4.0),
        bleValueText('co2', 812),
      ],
      ['21,6 °C', '45 %', 'bateria 87 %', '2,95 V', 'okno otwarte', 'spokój', '4,0 °C', '812 ppm CO₂'],
    );
  });
}
