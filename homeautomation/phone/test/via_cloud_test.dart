// Urządzenie za hubem (`via`): sekcja „Chmura” pokazuje lustro huba (`deviceIndex/{id}/via`) i „Do chmury”,
// czujnik Bluetooth bez „Zmień sieć WiFi” i innych opcji węzła.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/app.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/generic_device_screen.dart';

import 'support/memory_cloud_store.dart';

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

/// Czujnik przez hub (połączenie huba w pamięci).
class _Conn implements DeviceConnection<Json, Json> {
  @override
  String get deviceId => 'ble-b8f862d84911';
  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get routeDescription => 'przez hub';
  @override
  Json get state => const {'temp': 22.4, 'hum': 58, 'online': true};
  @override
  Json get config => const {'name': 'Czujnik BT'};
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
  _Manager(DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => _Conn() as DeviceConnection<S, C>;
}

Future<void> _pump(WidgetTester tester, MemoryCloudStore cloud, {String uid = 'u1'}) async {
  final store = MemoryDeviceStore();
  await store.saveDevice(const PairedDevice(id: 'hub-51e96c', name: 'Hub w garażu', type: DeviceType.hub));
  final manager = _Manager(store);
  final access = TestCloudAccess(cloud, uid: uid)..homeOwnerUid = 'u1';
  final c = DeviceController<Json, Json>(
    device: const PairedDevice(
      id: 'ble-b8f862d84911',
      name: 'Czujnik BT',
      type: DeviceType.sensor,
      access: AccessLevel.config,
      via: 'hub-51e96c',
    ),
    manager: manager,
    codec: rawCodec,
  );
  await c.connect();
  await tester.pumpWidget(
    Services(
      store: store,
      discovery: _NoDiscovery(),
      manager: manager,
      pairing: PairingService(store: store),
      cloud: access,
      provisioning: _NoBle(),
      rooms: _NoRooms(),
      child: TermostatApp(home: GenericDeviceScreen(controller: c)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(const Key('viaCloud')), 200);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('czujnik za hubem bez wpisu w chmurze: „Tylko w domu”, „Do chmury” zapisuje deviceIndex z via', (
    tester,
  ) async {
    final cloud = MemoryCloudStore();
    await _pump(tester, cloud);
    expect(find.text('Tylko w domu'), findsOneWidget);
    expect(find.text('Urządzenie w chmurze'), findsNothing, reason: 'to nie urządzenie z własnym kontem');
    expect(find.byKey(const Key('changeWifi')), findsNothing, reason: 'czujnik Bluetooth nie ma WiFi');
    expect(find.byKey(const Key('phones')), findsNothing);

    await tester.tap(find.byKey(const Key('linkViaHub')));
    await tester.pumpAndSettle();
    expect(cloud.get('homes/h1/deviceIndex/ble-b8f862d84911'), {
      'type': 'sensor',
      'name': 'Czujnik BT',
      'via': 'hub-51e96c',
    });
    expect(find.text('W chmurze przez Hub w garażu'), findsOneWidget);
    expect(find.byKey(const Key('linkViaHub')), findsNothing);
  });

  testWidgets('domownik widzi stan, ale „Do chmury” robi właściciel', (tester) async {
    final cloud = MemoryCloudStore();
    await _pump(tester, cloud, uid: 'u2');
    expect(find.text('Łączy właściciel domu'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('linkViaHub'))).enabled, isFalse);
  });

  testWidgets('czujnik już w chmurze przez hub', (tester) async {
    final cloud = MemoryCloudStore()
      ..set('homes/h1/deviceIndex/ble-b8f862d84911', {'type': 'sensor', 'name': 'Czujnik BT', 'via': 'hub-51e96c'});
    await _pump(tester, cloud);
    expect(find.text('W chmurze przez Hub w garażu'), findsOneWidget);
    expect(find.byKey(const Key('linkViaHub')), findsNothing);
  });
}
