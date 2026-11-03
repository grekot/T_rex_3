// Bramka Bluetooth (`btnode`): typ nie zamienia się w termostat, ekran bramki z listą urządzeń z huba.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/app.dart';
import 'package:homeautomation/controllers/device_controller.dart';
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
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/remote.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/btnode_section.dart';
import 'package:homeautomation/ui/generic_device_screen.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => Stream.value(const []);
}

class _NoBle extends ProvisioningBackend {
  @override
  bool get supported => false;

  @override
  Stream<List<ProvCandidate>> scan() => const Stream.empty();

  @override
  Future<ProvTransport> connect(ProvCandidate candidate) => throw UnimplementedError();
}

class _NoRooms extends RoomStore {
  @override
  Stream<List<Room>> watch() => Stream.value(const []);

  @override
  Future<void> save(Room room) async {}

  @override
  Future<void> remove(String roomId) async {}
}

/// Bramka w pamięci: stały stan, bez `describe`.
class _Conn implements DeviceConnection<Json, Json> {
  _Conn(this._state);

  final Json _state;

  @override
  String get deviceId => 'bt-a1b2c3';
  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get routeDescription => '192.168.1.40';
  @override
  Json get state => _state;
  @override
  Json get config => const {'name': 'Bramka w salonie'};
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
  Future<SetResult> sendSet(Json values) async => const SetResult(ok: true);
  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager(this.conn) : super(store: MemoryDeviceStore(), discovery: _NoDiscovery());

  final DeviceConnection<Json, Json> conn;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conn as DeviceConnection<S, C>;
}

/// Hub w pamięci: czujniki przy dwóch bramkach, zegarek, słyszany niedodany czujnik.
class _Hub extends HubApi {
  _Hub() : super(LocalApi(LocalEndpoint('127.0.0.1', 1)));

  bool oldHub = false;

  @override
  Future<List<HubChild>> devices() async => [
    HubChild.fromJson({
      'id': 'ble-a4c138123456',
      'adapter': 'ble',
      'host': '',
      'type': 'sensor',
      'name': 'Termometr - salon',
      'online': true,
      'state': {'temp': 21.6, 'hum': 45, 'battery': 87, 'rssi': -62, 'via': 'bt-a1b2c3'},
    }),
    HubChild.fromJson({
      'id': 'ble-f84477aabbcc',
      'adapter': 'ble',
      'host': '',
      'type': 'sensor',
      'name': 'Przycisk - garaż',
      'online': false,
      'error': 'offline',
      'state': {'battery': 100, 'rssi': -88, 'via': 'bt-a1b2c3'},
    }),
    HubChild.fromJson({
      'id': 'ble-112233445566',
      'adapter': 'ble',
      'host': '',
      'name': 'Termometr - piętro',
      'online': true,
      'state': {'temp': 19, 'rssi': -70, 'via': 'bt-ffffff'},
    }),
    HubChild.fromJson({'id': 'shelly-b12345', 'adapter': 'shelly', 'host': '192.168.1.50', 'online': true}),
  ];

  @override
  Future<List<HubRemote>> remotes() async {
    if (oldHub) throw const ThermostatException('HTTP 404');
    return [
      HubRemote.fromJson({
        'id': 'zegarek-8716545',
        'kind': 'watch',
        'name': 'T-Rex 3',
        'lastUsed': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 300,
        'via': 'bt-a1b2c3',
      }),
      HubRemote.fromJson({'id': 'pilot-x', 'kind': 'pilot', 'lastUsed': 0, 'via': ''}),
    ];
  }

  @override
  Future<BleSeen> bleSeen() async => BleSeen.fromJson({
    'scanning': false,
    'nodes': [
      {'id': 'bt-a1b2c3', 'online': true, 'bleOk': true, 'received': 1520, 'lost': 3, 'age': 2},
    ],
    'found': [
      {'mac': 'aa:bb:cc:dd:ee:ff', 'kind': 'bthome', 'rssi': -70, 'via': 'bt-a1b2c3', 'age': 5},
      {'mac': 'aa:bb:cc:dd:ee:00', 'kind': 'bthome', 'rssi': -70, 'via': 'bt-ffffff', 'age': 5},
    ],
  });
}

Future<DeviceController<Json, Json>> _controller(Json state) async {
  final c = DeviceController<Json, Json>(
    device: const PairedDevice(id: 'bt-a1b2c3', name: 'Bramka w salonie', type: DeviceType.btnode),
    manager: _Manager(_Conn(state)),
    codec: rawCodec,
  );
  await c.connect();
  return c;
}

Widget _app(Widget home) {
  final store = MemoryDeviceStore();
  return Services(
    store: store,
    discovery: _NoDiscovery(),
    manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
    pairing: PairingService(store: store),
    cloud: NoCloudAccess(),
    provisioning: _NoBle(),
    rooms: _NoRooms(),
    child: TermostatApp(home: home),
  );
}

const _state = {
  'id': 'bt-a1b2c3',
  'bleOk': true,
  'bleConns': 2,
  'scanAll': false,
  'advPerMin': 240,
  'bleFw': 6,
  'bleUptime': 7200,
  'linkCrcErrors': 0,
};

void main() {
  group('typ bramki', () {
    test('btnode ma własny typ; zapisany typ nieznany nie staje się termostatem', () {
      expect(DeviceType.fromWire('btnode'), DeviceType.btnode);
      expect(DeviceType.fromWire(null), DeviceType.thermostat, reason: 'API 1 bez pola type');
      expect(DeviceType.fromWire(''), DeviceType.unknown, reason: 'tak zapisywał się typ nieznany do 1.6.0');
      const d = PairedDevice(id: 'bt-a1b2c3', name: 'Bramka', type: DeviceType.btnode);
      expect(PairedDevice.fromJson(d.toJson()).type, DeviceType.btnode);
      const u = PairedDevice(id: 'x-1', name: 'Coś', type: DeviceType.unknown);
      expect(PairedDevice.fromJson(u.toJson()).type, DeviceType.unknown);
    });

    test('lista urządzeń bramki z list huba: tylko jej czujniki i zegarki', () async {
      final hub = _Hub();
      final d = btnodeDevices('bt-a1b2c3', await hub.devices(), await hub.remotes(), await hub.bleSeen());
      expect(d.sensors.map((s) => s.id), ['ble-a4c138123456', 'ble-f84477aabbcc']);
      expect(d.remotes!.map((r) => r.id), ['zegarek-8716545']);
      expect((d.node?.received, d.node?.lost), (1520, 3));
      expect(d.found!.map((f) => f.mac), ['aa:bb:cc:dd:ee:ff']);
      expect(HubRemote.fromJson({'id': 'p', 'lastUsed': 0, 'via': ''}).lastUsed, isNull);
    });

    test('opis po polsku: liczebniki, sygnał, kafelek', () {
      expect([1, 2, 5, 12, 22, 25].map((n) => plPlural(n, 'połączenie', 'połączenia', 'połączeń')), [
        '1 połączenie',
        '2 połączenia',
        '5 połączeń',
        '12 połączeń',
        '22 połączenia',
        '25 połączeń',
      ]);
      expect([-60, -70, -80, -95].map(rssiText), [
        'bardzo dobry sygnał',
        'dobry sygnał',
        'słaby sygnał',
        'bardzo słaby sygnał',
      ]);
      expect(btnodeSummary(_state), 'Bramka Bluetooth · 2 połączenia');
      expect(btnodeSummary({..._state, 'bleConns': 0, 'scanAll': true}), 'Bramka Bluetooth · szuka czujników');
      expect(btnodeSummary({..._state, 'bleOk': false}), 'Układ Bluetooth nie odpowiada');
    });
  });

  testWidgets('ekran bramki: stan układów, czujniki, zegarki i nowe czujniki z huba', (tester) async {
    final c = await _controller(_state);
    final hub = _Hub();
    await tester.pumpWidget(_app(GenericDeviceScreenForTest(controller: c, hubApi: hub)));
    await tester.pumpAndSettle();

    expect(find.text('Układ Bluetooth działa'), findsOneWidget);
    expect(find.text('wersja 6 · działa od 2 h 0 min'), findsOneWidget);
    expect(find.text('2 połączenia'), findsOneWidget);
    expect(find.text('Hub odbiera dane z bramki'), findsOneWidget);
    expect(find.textContaining('1520 komunikatów · zgubione 3'), findsOneWidget);
    expect(find.text('Szukaj nowych czujników'), findsNothing, reason: 'scanAll przełącza hub, nie ręcznie');

    await tester.scrollUntilVisible(find.byKey(const Key('btnodeRemote-zegarek-8716545')), 200);
    expect(find.byKey(const Key('btnodeSensor-ble-a4c138123456')), findsOneWidget);
    expect(find.textContaining('21,6 °C · 45 % · bateria 87 % · bardzo dobry sygnał (-62 dBm)'), findsOneWidget);
    expect(find.textContaining('niedostępny · bateria 100 % · bardzo słaby sygnał'), findsOneWidget);
    expect(find.byKey(const Key('btnodeSensor-ble-112233445566')), findsNothing, reason: 'czujnik innej bramki');
    expect(find.text('W zasięgu: 1 nowy czujnik'), findsOneWidget);
    expect(find.text('zegarek · ostatnio 5 min temu'), findsOneWidget);
    expect(find.byKey(const Key('btnodeRemote-pilot-x')), findsNothing);
    c.dispose();
  });

  testWidgets('ekran bramki: układ Bluetooth nie odpowiada, stary hub bez listy zegarków, bez huba', (tester) async {
    final c = await _controller({..._state, 'bleOk': false, 'bleConns': 0, 'linkCrcErrors': 4});
    final hub = _Hub()..oldHub = true;
    await tester.pumpWidget(_app(GenericDeviceScreenForTest(controller: c, hubApi: hub)));
    await tester.pumpAndSettle();
    expect(find.text('Układ Bluetooth nie odpowiada'), findsOneWidget);
    expect(find.text('Brak połączeń Bluetooth'), findsOneWidget);
    expect(find.text('Błędy łącza między układami: 4'), findsOneWidget);
    expect(find.text('Zegarki i piloty'), findsNothing);
    expect(find.byKey(const Key('btnodeSensor-ble-a4c138123456')), findsOneWidget);

    await tester.pumpWidget(_app(GenericDeviceScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('btnodeNoHub')), findsOneWidget);
    c.dispose();
  });
}

/// Ekran bramki z hubem w pamięci (bez połączonego huba w `DeviceHub`).
class GenericDeviceScreenForTest extends StatelessWidget {
  const GenericDeviceScreenForTest({super.key, required this.controller, required this.hubApi});

  final DeviceController<Json, Json> controller;
  final HubApi hubApi;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      children: [BtNodeSection(controller: controller, hubApi: hubApi)],
    ),
  );
}
