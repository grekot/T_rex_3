import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/app.dart';
import 'package:homeautomation/controllers/thermostat_controller.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/models/thermostat_config.dart';
import 'package:homeautomation/models/thermostat_state.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/firmware_screen.dart';
import 'package:homeautomation/ui/thermostat_screen.dart';

import 'models_test.dart' show configJson, stateJson;
import 'support/memory_cloud_store.dart';

/// Połączenie w pamięci: zapisuje wysłane Set i odsyła stan jak termostat.
class FakeConnection implements ThermostatConnection {
  FakeConnection(this._state, this._config);

  ThermostatState _state;
  final ThermostatConfig _config;
  final sent = <Map<String, dynamic>>[];
  final _states = StreamController<ThermostatState>.broadcast();

  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get deviceId => _state.id;
  @override
  String get routeDescription => '192.168.1.20';
  @override
  ThermostatState get state => _state;
  @override
  ThermostatConfig get config => _config;
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<ThermostatState> get states => _states.stream;
  @override
  Stream<ThermostatConfig> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();

  @override
  Future<void> open() async {}

  @override
  Future<Map<String, dynamic>?> describeJson() async => null;

  @override
  Future<SetResult> sendSet(Map<String, dynamic> values) async {
    sent.add(values);
    final j = _state.toJson()
      ..addAll({
        for (final k in const ['target', 'mode', 'power'])
          if (values.containsKey(k)) k: values[k],
      });
    _state = ThermostatState.fromJson(j);
    _states.add(_state);
    return const SetResult(ok: true);
  }

  void push(Map<String, dynamic> changes) {
    _state = ThermostatState.fromJson(_state.toJson()..addAll(changes));
    _states.add(_state);
  }

  @override
  Future<void> close() async {}
}

class StubManager extends ConnectionManager {
  StubManager(this.connection) : super(store: MemoryDeviceStore(), discovery: _NoDiscovery());

  final FakeConnection connection;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => connection as DeviceConnection<S, C>;
}

class _NoBle extends ProvisioningBackend {
  @override
  bool get supported => false;
  @override
  Stream<List<ProvCandidate>> scan() => const Stream.empty();
  @override
  Future<ProvTransport> connect(ProvCandidate candidate) => throw UnimplementedError();
}

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => Stream.value(const []);
}

void main() {
  late FakeConnection conn;
  late ThermostatController controller;

  setUp(() {
    conn = FakeConnection(
      ThermostatState.fromJson(jsonDecode(stateJson) as Map<String, dynamic>),
      ThermostatConfig.fromJson(jsonDecode(configJson) as Map<String, dynamic>),
    );
    controller = ThermostatController(
      device: const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'),
      manager: StubManager(conn),
      targetDebounce: const Duration(milliseconds: 300),
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(TermostatApp(home: ThermostatScreen(controller: controller)));
    await tester.pumpAndSettle();
  }

  testWidgets('pokazuje stan, drogę połączenia i AUTO „do 22:30”', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Salon'), findsOneWidget);
    expect(find.text('21,4 °C'), findsOneWidget);
    expect(find.text('Wilgotność 45 %'), findsOneWidget);
    expect(find.text('21,0 °C'), findsOneWidget);
    expect(find.text('Grzeje'), findsOneWidget);
    expect(find.text('Komfort do 22:30'), findsOneWidget);
    expect(find.textContaining('Lokalnie · 192.168.1.20'), findsOneWidget);
  });

  testWidgets('+ dwa razy wysyła jedną nastawę 22,0 °C', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('targetUp')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('targetUp')));
    await tester.pump();
    expect(find.text('22,0 °C'), findsOneWidget);
    expect(conn.sent, isEmpty, reason: 'kliknięcia są łączone');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(conn.sent, [
      {'target': 22.0},
    ]);
    expect(find.text('22,0 °C'), findsOneWidget);
  });

  testWidgets('awaria czujnika i nadpisanie', (tester) async {
    await pumpScreen(tester);
    conn.push({'sensorFault': true, 'temp': null, 'heating': false, 'override': true, 'target': 23.0});
    await tester.pumpAndSettle();
    expect(find.textContaining('Awaria czujnika'), findsOneWidget);
    expect(find.text('Nie grzeje'), findsOneWidget);
    expect(find.text('Nadpisanie ręczne do 22:30'), findsOneWidget);
    expect(find.text('23,0 °C'), findsOneWidget);
  });

  testWidgets('zmiana trybu wysyła mode', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Ręczny'));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'mode': 'manual'});
    expect(find.text('Komfort do 22:30'), findsNothing);
  });

  Future<void> openSettings(WidgetTester tester, CloudAccess cloud) async {
    final store = MemoryDeviceStore();
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: StubManager(conn),
        pairing: PairingService(store: store),
        cloud: cloud,
        provisioning: _NoBle(),
        rooms: CloudRoomStore(MemoryCloudStore(), 'test'),
        child: TermostatApp(home: ThermostatScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ustawienia'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Urządzenie w chmurze'), 200, scrollable: find.byType(Scrollable).first);
  }

  testWidgets('ustawienia bez konfiguracji Firebase: chmura niedostępna', (tester) async {
    await openSettings(tester, NoCloudAccess());
    expect(find.textContaining('nie ma konfiguracji Firebase'), findsOneWidget);
    expect(find.byKey(const Key('linkCloud')), findsNothing);
  });

  testWidgets('ustawienia przez chmurę: łączenie tylko w sieci domowej', (tester) async {
    await openSettings(tester, TestCloudAccess(MemoryCloudStore()));
    expect(find.textContaining('tylko w sieci domowej'), findsOneWidget);
    expect(find.byKey(const Key('linkCloud')), findsNothing);
  });

  testWidgets('aktualizacja firmware: zły plik blokuje wgrywanie, dobry je odblokowuje', (tester) async {
    var file = (name: 'notatki.txt', bytes: Uint8List(4096));
    await tester.pumpWidget(
      TermostatApp(
        home: FirmwareScreen(controller: controller, pickFile: () async => file),
      ),
    );
    await tester.pumpAndSettle();
    FilledButton upload() => tester.widget<FilledButton>(find.byKey(const Key('uploadFirmware')));
    expect(upload().onPressed, isNull, reason: 'bez pliku');

    await tester.tap(find.byKey(const Key('chooseFirmware')));
    await tester.pumpAndSettle();
    expect(find.textContaining('.bin'), findsWidgets);
    expect(upload().onPressed, isNull);

    file = (name: 'firmware.bin', bytes: Uint8List(300 * 1024)..[0] = 0xE9);
    await tester.tap(find.byKey(const Key('chooseFirmware')));
    await tester.pumpAndSettle();
    expect(find.text('firmware.bin'), findsOneWidget);
    expect(find.text('300 KB'), findsOneWidget);
    expect(upload().onPressed, isNotNull);
  });
}
