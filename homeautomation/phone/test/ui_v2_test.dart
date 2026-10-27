// Ekrany v2: kreator „Nowe urządzenie” przez Bluetooth (na atrapie urządzenia), zakładka „Urządzenia” i pulpity.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/app.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/dashboard_store.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/models/thermostat_config.dart';
import 'package:homeautomation/models/thermostat_state.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/ble_setup_screen.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/ui/main_screen.dart';
import 'package:homeautomation/controllers/light_controller.dart';
import 'package:homeautomation/ui/generic_device_screen.dart';

import 'models_test.dart' show configJson, stateJson;
import 'support/fake_prov_device.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => Stream.value(const []);
}

class _FakeBle extends ProvisioningBackend {
  _FakeBle(this.device);

  final FakeProvDevice device;

  @override
  bool get supported => true;

  @override
  Stream<List<ProvCandidate>> scan() => Stream.value([ProvCandidate('HA_${device.id}', -55)]);

  @override
  Future<ProvTransport> connect(ProvCandidate candidate) async => device;
}

/// Połączenie w pamięci dowolnego typu: zapisuje Set i stosuje proste pola do stanu.
class _MemConnection<S, C> implements DeviceConnection<S, C> {
  _MemConnection(this.deviceId, this.codec, this._state, this._config);

  @override
  final String deviceId;
  final dynamic codec;
  Json _state;
  final Json _config;
  final sent = <Json>[];

  /// Odpowiedź `describe` (null = urządzenie bez opisu).
  Json? describe;
  final _states = StreamController<S>.broadcast();

  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get routeDescription => '192.168.1.30';
  @override
  S get state => codec.state(_state) as S;
  @override
  C get config => codec.config(_config) as C;
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<S> get states => _states.stream;
  @override
  Stream<C> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}

  @override
  Future<Map<String, dynamic>?> describeJson() async => describe;

  @override
  Future<SetResult> sendSet(Json values) async {
    sent.add(values);
    _state = {..._state, ...values};
    _states.add(state);
    return const SetResult(ok: true);
  }

  @override
  Future<void> close() async {}
}

class _StubManager extends ConnectionManager {
  _StubManager(this.connections) : super(store: MemoryDeviceStore(), discovery: _NoDiscovery());

  final Map<String, DeviceConnection<Object?, Object?>> connections;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => connections[device.id]! as DeviceConnection<S, C>;
}

/// Pokoje w pamięci (bez SharedPreferences).
class _MemRooms extends RoomStore {
  final rooms = <String, Room>{};
  final _changes = StreamController<List<Room>>.broadcast();

  @override
  Stream<List<Room>> watch() {
    late StreamController<List<Room>> c;
    StreamSubscription<List<Room>>? sub;
    c = StreamController<List<Room>>(
      onListen: () {
        sub = _changes.stream.listen(c.add);
        c.add(rooms.values.toList());
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<void> save(Room room) async {
    rooms[room.id] = room;
    _changes.add(rooms.values.toList());
  }

  @override
  Future<void> remove(String roomId) async {
    rooms.remove(roomId);
    _changes.add(rooms.values.toList());
  }
}

Widget _app({
  required MemoryDeviceStore store,
  ConnectionManager? manager,
  ProvisioningBackend? ble,
  RoomStore? rooms,
  DashboardStore? dashboards,
  required Widget home,
}) => Services(
  store: store,
  discovery: _NoDiscovery(),
  manager: manager ?? ConnectionManager(store: store, discovery: _NoDiscovery()),
  pairing: PairingService(store: store, clientName: () async => 'Pixel 8'),
  cloud: NoCloudAccess(),
  provisioning: ble ?? _FakeBle(FakeProvDevice(pop: 'x')),
  rooms: rooms ?? _MemRooms(),
  dashboards: dashboards,
  child: TermostatApp(home: home),
);

Future<void> _pumpUntil(WidgetTester tester, Finder f, {int seconds = 30}) async {
  for (var i = 0; i < seconds * 4 && f.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(f, findsWidgets);
}

void main() {
  testWidgets('nowe urządzenie przez Bluetooth: PoP, token, sieć, połączenie', (tester) async {
    final device = FakeProvDevice(
      pop: 'ab12cd34',
      type: 'thermostat',
      token: 'tok-ble',
      networks: const [
        FakeNetwork('Dom', -45, password: 'tajne123'),
        FakeNetwork('Sasiad', -80),
      ],
      connectPolls: 1,
    );
    final store = MemoryDeviceStore();
    PairedDevice? result;
    await tester.pumpWidget(
      _app(
        store: store,
        ble: _FakeBle(device),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => result = await Navigator.of(
              context,
            ).push<PairedDevice>(MaterialPageRoute(builder: (_) => const BleSetupScreen())),
            child: const Text('start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ble-termostat-ab12cd')));
    await tester.pumpAndSettle();

    // Zły PoP → komunikat, dalej ten sam krok.
    await tester.enterText(find.byKey(const Key('pop')), 'zly-kod');
    await tester.tap(find.byKey(const Key('popNext')));
    await _pumpUntil(tester, find.byKey(const Key('bleError')));
    expect(find.textContaining('PoP'), findsWidgets);

    await tester.enterText(find.byKey(const Key('pop')), 'ab12cd34');
    await tester.tap(find.byKey(const Key('popNext')));
    await _pumpUntil(tester, find.byKey(const Key('wifi-Dom')));
    expect(await store.token('termostat-ab12cd'), 'tok-ble', reason: 'ha-pair zapisał token');
    expect(device.pairedClient, 'Pixel 8');

    await tester.tap(find.byKey(const Key('wifi-Dom')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('wifiPassword')), 'tajne123');
    await tester.tap(find.byKey(const Key('wifiJoin')));
    await _pumpUntil(tester, find.byKey(const Key('bleDone')));
    expect((device.ssid, device.passphrase), ('Dom', 'tajne123'));

    await tester.tap(find.text('Zakończ'));
    await tester.pumpAndSettle();
    expect(result!.id, 'termostat-ab12cd');
    expect(result!.type, DeviceType.thermostat);
    expect(result!.lastEndpoint?.host, '192.168.1.77', reason: 'IP ze statusu WiFi');
  });

  testWidgets('Urządzenia: kafelki termostatu i światła, przełączenie, nowy pokój i przeniesienie', (tester) async {
    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'));
    await store.saveDevice(const PairedDevice(id: 'swiatlo-1', name: 'Lampa', type: DeviceType.onOff));
    final light = _MemConnection<LightState, LightConfig>(
      'swiatlo-1',
      lightCodec,
      {'id': 'swiatlo-1', 'on': false},
      {'name': 'Lampa'},
    );
    final thermo = _MemConnection<ThermostatState, ThermostatConfig>(
      'termostat-ab12cd',
      thermostatCodec,
      jsonDecode(stateJson) as Json,
      jsonDecode(configJson) as Json,
    );
    final rooms = _MemRooms();
    await tester.pumpWidget(
      _app(
        store: store,
        manager: _StubManager({'swiatlo-1': light, 'termostat-ab12cd': thermo}),
        rooms: rooms,
        home: const MainScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urządzenia'));
    await tester.pumpAndSettle();

    expect(find.text('Bez pokoju'), findsOneWidget);
    expect(find.byKey(const Key('tile-termostat-ab12cd')), findsOneWidget);
    expect(find.text('21,4 °C'), findsOneWidget);
    expect(find.text('Lampa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('switch-swiatlo-1')));
    await tester.pumpAndSettle();
    expect(light.sent, [
      {'on': true},
    ]);

    // Nowy pokój i przeniesienie lampy.
    await tester.tap(find.byKey(const Key('addRoom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('roomName')), 'Kuchnia');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Kuchnia'), findsOneWidget);

    await tester.longPress(find.byKey(const Key('tile-swiatlo-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Przenieś do: Kuchnia'));
    await tester.pumpAndSettle();
    expect(rooms.rooms.values.single.devices, ['swiatlo-1']);
    // Termostat został bez pokoju, lampa jest w kuchni.
    expect(find.text('Bez pokoju'), findsOneWidget);
  });

  testWidgets('Pulpit: startowy z urządzeń, sterowanie, widżet w 3 krokach, scena', (tester) async {
    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'));
    await store.saveDevice(const PairedDevice(id: 'swiatlo-1', name: 'Lampa', type: DeviceType.onOff));
    final light = _MemConnection<LightState, LightConfig>(
      'swiatlo-1',
      lightCodec,
      {'id': 'swiatlo-1', 'on': false},
      {'name': 'Lampa'},
    );
    final thermo = _MemConnection<ThermostatState, ThermostatConfig>(
      'termostat-ab12cd',
      thermostatCodec,
      jsonDecode(stateJson) as Json,
      jsonDecode(configJson) as Json,
    )..describe = {
        'type': 'thermostat',
        'points': [
          {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
          {'key': 'mode', 'name': 'Tryb', 'kind': 'select', 'options': ['manual', 'auto'], 'access': 'control'},
        ],
      };
    final cache = MemoryTextCache();
    final dashboards = LocalDashboardStore(cache: cache);
    await tester.pumpWidget(
      _app(
        store: store,
        manager: _StubManager({'swiatlo-1': light, 'termostat-ab12cd': thermo}),
        dashboards: dashboards,
        home: const MainScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nie masz jeszcze pulpitu.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('starterDashboard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('21,4 °C'), findsOneWidget, reason: 'widżet termostatu');

    // Przełącznik lampy na pulpicie.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(light.sent, [
      {'on': true},
    ]);

    // Nastawa + na widżecie termostatu.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(thermo.sent.single.keys, ['target']);

    // Tryb edycji: widżet w 3 krokach (urządzenie → punkt z describe → wygląd).
    await tester.tap(find.byKey(const Key('editDashboard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addWidget')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-termostat-ab12cd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-mode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('widgetLabel')), 'Tryb salonu');
    await tester.tap(find.byKey(const Key('addWidgetDone')));
    await tester.pumpAndSettle();
    expect(find.text('Tryb salonu'), findsOneWidget);

    // Scena (homes/{h}/scenes, tu w telefonie): wyłącz lampę.
    await tester.tap(find.byKey(const Key('addWidget')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pickScene')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie ma jeszcze scen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('newScene')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sceneLabel')), 'Wychodzę');
    await tester.tap(find.byKey(const Key('sceneAddStep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step-device-swiatlo-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step-point-on')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyłącz'));
    await tester.tap(find.byKey(const Key('stepDone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sceneSave')));
    await tester.pumpAndSettle();

    final raw = jsonDecode(cache.values['local_dashboards_local']!) as List;
    final saved = Dashboard.fromJson('d', DashboardScope.private, (raw.single as Map).cast<String, dynamic>());
    expect(saved.widgets.map((w) => w.view), [
      WidgetView.thermostat,
      WidgetView.toggle,
      WidgetView.value,
      WidgetView.scene,
    ]);
    expect(saved.widgets[2].point, 'mode');
    expect(saved.widgets[3].sceneId, isNotNull, reason: 'widżet wskazuje scenę domu');

    // Koniec edycji, uruchomienie sceny.
    await tester.tap(find.byKey(const Key('editDashboard')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Uruchom'));
    await tester.tap(find.text('Uruchom'));
    await tester.pumpAndSettle();
    expect(light.sent.last, {'on': false});
    expect(find.text('Wykonano „Wychodzę”.'), findsOneWidget);
  });

  testWidgets('przełącznik 4-kanałowy: kanał z describe, ustawienia kanału i wejścia', (tester) async {
    final store = MemoryDeviceStore();
    const device = PairedDevice(id: 'swiatlo-4', name: 'Parter', type: DeviceType.onOff);
    await store.saveDevice(device);
    final conn = _MemConnection<LightState, LightConfig>(
      'swiatlo-4',
      lightCodec,
      {
        'id': 'swiatlo-4', 'channels': 4, 'inputs': 8, 'on': false,
        for (var i = 1; i <= 4; i++) 'on$i': false,
        for (var k = 1; k <= 8; k++) 'in$k': false,
      },
      {
        'name': 'Parter', 'channels': 4, 'inputs': 8,
        for (var i = 1; i <= 4; i++) 'ch$i': {'name': 'Kanał $i', 'defaultOn': 'last'},
        for (var k = 1; k <= 8; k++) 'input$k': {'name': 'Wejście $k', 'mode': 'momentary', 'out': (k - 1) % 4 + 1},
      },
    )..describe = {
        'type': 'switch',
        'channels': 4,
        'points': [
          {'key': 'on', 'name': 'Wszystkie', 'kind': 'switch', 'access': 'control'},
          for (var i = 1; i <= 4; i++) {'key': 'on$i', 'name': 'Kanał $i', 'kind': 'switch', 'access': 'control', 'channel': i},
        ],
      };
    final manager = _StubManager({'swiatlo-4': conn});
    final c = LightController(device: device, manager: manager);
    await tester.pumpWidget(_app(store: store, manager: manager, home: GenericDeviceScreen(controller: c)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('point-on2')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'on2': true});

    await tester.scrollUntilVisible(find.byKey(const Key('channel-2')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('channel-2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('channelName')), 'Kinkiet');
    await tester.pump();
    await tester.tap(find.byKey(const Key('defaultOn-off')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('channelSave')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'ch2': {'name': 'Kinkiet', 'defaultOn': 'off'},
    });

    await tester.scrollUntilVisible(find.byKey(const Key('input-5')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('input-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('input-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mode-edge')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('inputOut')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kanał 3: Kanał 3').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inputSave')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'input5': {'mode': 'edge', 'out': 3},
    });
    c.dispose();
  });
}
