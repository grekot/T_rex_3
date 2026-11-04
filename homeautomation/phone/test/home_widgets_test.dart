// Widżety na ekranie Androida: zapis konfiguracji, kratki ze stanu, dotknięcia, ograniczenie połączeń, pauza.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/scene_store.dart';
import 'package:homeautomation/data/dashboard_store.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/home_widgets/widget_cells.dart';
import 'package:homeautomation/home_widgets/widget_config.dart';
import 'package:homeautomation/home_widgets/widget_look.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/home_widgets/widget_runtime.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home_widget.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/scene.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/models/thermostat_config.dart';
import 'package:homeautomation/models/thermostat_state.dart';

import 'models_test.dart' show configJson, stateJson;

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

class _Conn<S, C> implements DeviceConnection<S, C> {
  _Conn(this.deviceId, this.codec, this._state, this._config);

  @override
  final String deviceId;
  final DeviceCodec<S, C> codec;
  Json _state;
  final Json _config;
  final sent = <Json>[];
  Json? describe;
  Map<String, String> errors = const {};
  bool closed = false;
  final _states = StreamController<S>.broadcast();

  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get routeDescription => '192.168.1.30';
  @override
  S get state => codec.state(_state);
  @override
  C get config => codec.config(_config);
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
  Future<Json?> describeJson() async => describe;

  void push(Json j) {
    _state = {..._state, ...j};
    _states.add(state);
  }

  @override
  Future<SetResult> sendSet(Json values) async {
    sent.add(values);
    if (errors.isNotEmpty) return SetResult(ok: false, errors: errors);
    final n = _state['channels'];
    final applied = {...values};
    if (n is int && values['on'] is bool) {
      for (var i = 1; i <= n; i++) {
        applied['on$i'] = values['on'];
      }
    }
    push(applied);
    return const SetResult(ok: true);
  }

  @override
  Future<void> close() async => closed = true;
}

class _Manager extends ConnectionManager {
  _Manager(this.connections, DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  final Map<String, DeviceConnection<Object?, Object?>> connections;
  final connected = <String>[];

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async {
    connected.add(device.id);
    return connections[device.id]! as DeviceConnection<S, C>;
  }
}

void main() {
  late _Conn<LightState, LightConfig> node;
  late _Conn<ThermostatState, ThermostatConfig> thermo;
  late _Conn<LightState, LightConfig> other;
  late _Conn<Json, Json> hubConn;
  late _Conn<Json, Json> salon;
  late _Manager manager;
  late MemoryDeviceStore store;
  late LocalSceneStore scenes;
  late List<Map<String, dynamic>> renders;
  late WidgetRuntime runtime;

  WidgetRuntime makeRuntime() => WidgetRuntime(
    hubFactory: (config, wanted) => DeviceHub(
      store: store,
      manager: manager,
      cloud: NoCloudAccess(),
      sceneStore: scenes,
      wanted: wanted,
    ),
    render: (json) => renders.add(jsonDecode(json) as Map<String, dynamic>),
    debounce: Duration.zero,
    readyTimeout: const Duration(seconds: 1),
    messageTime: const Duration(milliseconds: 40),
  );

  setUp(() async {
    store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff));
    await store.saveDevice(const PairedDevice(id: 'lampa', name: 'Lampa', type: DeviceType.onOff));
    await store.saveDevice(const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'));
    await store.saveDevice(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub));
    await store.saveDevice(const PairedDevice(id: 'ble-b8f862d84911', name: 'Salon BT', type: DeviceType.sensor));
    await store.saveDevice(const PairedDevice(id: 'gabinet', name: 'Gabinet', type: DeviceType.sensor));
    node =
        _Conn(
            'parter',
            lightCodec,
            {'id': 'parter', 'on': true, 'channels': 2, 'on1': true, 'on2': false},
            {'name': 'Parter'},
          )
          ..describe = {
            'type': 'switch',
            'points': [
              {'key': 'on1', 'name': 'Schody', 'kind': 'switch', 'access': 'control'},
              {'key': 'on2', 'name': 'Brama', 'kind': 'action', 'access': 'control'},
            ],
          };
    other = _Conn('lampa', lightCodec, {'id': 'lampa', 'on': false}, {'name': 'Lampa'});
    thermo = _Conn(
      'termostat-ab12cd',
      thermostatCodec,
      (jsonDecode(stateJson) as Map).cast<String, dynamic>(),
      (jsonDecode(configJson) as Map).cast<String, dynamic>(),
    );
    hubConn = _Conn<Json, Json>('hub1', rawCodec, {'id': 'hub1'}, {'name': 'Hub'});
    salon =
        _Conn<Json, Json>('ble-b8f862d84911', rawCodec, {
            'temp': 22.4,
            'hum': 58,
            'battery': 87,
            'pressure': 997.8,
            'rssi': -60,
            'online': true,
          }, {'name': 'Salon BT'})
          ..describe = {
            'type': 'sensor',
            'points': [
              {'key': 'battery', 'name': 'Bateria', 'kind': 'sensor', 'unit': '%', 'decimals': 0},
              {'key': 'rssi', 'name': 'Sygnał', 'kind': 'sensor', 'unit': 'dBm', 'decimals': 0},
              {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
              {'key': 'hum', 'name': 'Wilgotność', 'kind': 'sensor', 'unit': '%', 'decimals': 0},
              {'key': 'pressure', 'name': 'Ciśnienie', 'kind': 'sensor', 'unit': 'hPa', 'decimals': 1},
            ],
          };
    final gabinet = _Conn<Json, Json>('gabinet', rawCodec, {'temp': 21.0, 'hum': 45}, {'name': 'Gabinet'});
    manager = _Manager({
      'parter': node,
      'lampa': other,
      'termostat-ab12cd': thermo,
      'hub1': hubConn,
      'ble-b8f862d84911': salon,
      'gabinet': gabinet,
    }, store);
    scenes = LocalSceneStore(cache: MemoryTextCache());
    renders = [];
    runtime = makeRuntime();
  });

  tearDown(() => runtime.dispose());

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

  Map<String, dynamic> cell(int id, [int index = 0]) => (renders.last['$id'] as List)[index] as Map<String, dynamic>;

  HomeWidgetConfig config(int id, List<HomeWidgetItem> items) =>
      HomeWidgetConfig(id: id, homeId: HomeWidgetConfig.localHome, items: items);

  test('konfiguracja przechodzi przez JSON, nieznana pozycja jest pomijana', () {
    final c = HomeWidgetConfig(
      id: 7,
      homeId: 'dom',
      homeName: 'Dom',
      ownerUid: 'u1',
      items: const [
        HomeWidgetItem.output('parter', 'on2'),
        HomeWidgetItem.thermostat('t'),
        HomeWidgetItem.scene('wyjscie'),
      ],
    );
    final json = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
    (json['items'] as List).add({'kind': 'nowy'});
    final back = HomeWidgetConfig.fromJson(json);
    expect(back.items, c.items);
    expect(back.ownerUid, 'u1');
  });

  test('kratki: kanał, wszystkie wyjścia, termostat', () async {
    runtime.update([
      config(1, const [
        HomeWidgetItem.output('parter', 'on'),
        HomeWidgetItem.output('parter', 'on1'),
        HomeWidgetItem.thermostat('termostat-ab12cd'),
      ]),
    ]);
    await settle();
    expect(cell(1)['subtitle'], '1 z 2 włączone');
    expect(cell(1)['active'], true);
    expect(cell(1, 1)['subtitle'], 'Włączone');
    final t = cell(1, 2);
    expect(t['title'], 'Salon');
    expect(t['value'], endsWith('°'));
    expect(t['open'], 'termostat-ab12cd');
  });

  test('czujnik: 3 wartości z describe (bez sygnału, bateria na końcu), bez describe - znane pola, niedostępny', () async {
    runtime.update([
      config(1, const [HomeWidgetItem.sensor('ble-b8f862d84911'), HomeWidgetItem.sensor('gabinet')]),
    ]);
    await settle();
    await settle();
    final s = cell(1);
    expect((s['title'], s['value'], s['subtitle'], s['icon'], s['open'], s['dimmed']), (
      'Salon BT',
      '22,4 °C',
      '58 % · 997,8 hPa',
      'sensor',
      'ble-b8f862d84911',
      false,
    ));
    expect((cell(1, 1)['value'], cell(1, 1)['subtitle']), ('21,0 °C', '45 %'));
    salon.push({'temp': 22.6, 'online': false});
    await settle();
    expect((cell(1)['value'], cell(1)['subtitle'], cell(1)['dimmed']), ('22,6 °C', 'Niedostępny · ostatni odczyt', true));
    await runtime.tap(1, 0);
    expect(salon.sent, isEmpty, reason: 'dotknięcie otwiera aplikację (Android)');
    final back = HomeWidgetConfig.fromJson(
      jsonDecode(jsonEncode(config(2, const [HomeWidgetItem.sensor('gabinet')]).toJson())) as Map<String, dynamic>,
    );
    expect(back.items, const [HomeWidgetItem.sensor('gabinet')]);
  });

  test('stan na żywo trafia na widżet bez dotykania', () async {
    runtime.update([
      config(1, const [HomeWidgetItem.output('parter', 'on2')]),
    ]);
    await settle();
    expect(cell(1)['active'], false);
    node.push({'on2': true});
    await settle();
    expect(cell(1)['active'], true);
  });

  test('tylko urządzenia z widżetów są łączone, a scena dokłada huba i swoje urządzenia', () async {
    await scenes.save('local', const Scene(id: 'noc', name: 'Noc', actions: [SceneAction.set('lampa', {'on': false})]));
    runtime.update([
      config(1, const [HomeWidgetItem.output('parter', 'on1')]),
    ]);
    await settle();
    expect(manager.connected, ['parter']);
    runtime.update([
      config(1, const [HomeWidgetItem.output('parter', 'on1')]),
      config(2, const [HomeWidgetItem.scene('noc')]),
    ]);
    await settle();
    expect(manager.connected.toSet(), {'parter', 'hub1', 'lampa'});
    expect(manager.connected, isNot(contains('termostat-ab12cd')));
  });

  test('dotknięcie przełącza kanał, wszystkie wyjścia i wysyła impuls', () async {
    runtime.update([
      config(1, const [
        HomeWidgetItem.output('parter', 'on1'),
        HomeWidgetItem.output('parter', 'on'),
        HomeWidgetItem.output('parter', 'on2'),
      ]),
    ]);
    await settle();
    await runtime.tap(1, 0);
    expect(node.sent.last, {'on1': false});
    await runtime.tap(1, 1);
    expect(node.sent.last, {'on': true});
    await runtime.tap(1, 2);
    expect(node.sent.last, {'on2': true});
  });

  test('błąd urządzenia widać na chwilę, potem wraca stan', () async {
    runtime.update([
      config(1, const [HomeWidgetItem.output('parter', 'on1')]),
    ]);
    await settle();
    node.errors = {'on1': 'forbidden'};
    await runtime.tap(1, 0);
    await settle();
    expect(cell(1)['subtitle'], isNot('Włączone'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(cell(1)['subtitle'], 'Włączone');
  });

  test('scena idzie przez huba', () async {
    await scenes.save('local', const Scene(id: 'noc', name: 'Noc', actions: [SceneAction.set('lampa', {'on': false})]));
    runtime.update([
      config(1, const [HomeWidgetItem.scene('noc')]),
    ]);
    await settle();
    expect(cell(1)['title'], 'Noc');
    await runtime.tap(1, 0);
    expect(hubConn.sent.last, {'runScene': 'noc'});
    await settle();
    expect(cell(1)['subtitle'], 'Uruchomiona');
  });

  test('zgaszony ekran zamyka połączenia, dotknięcie i zapalenie otwierają je znowu', () async {
    runtime.update([
      config(1, const [HomeWidgetItem.output('parter', 'on1')]),
    ]);
    await settle();
    runtime.pause();
    await settle();
    expect(node.closed, true);
    expect(cell(1)['subtitle'], 'Włączone'); // ostatni obraz zostaje
    expect(runtime.hub('local'), isNull);
    runtime.resume();
    await settle();
    expect(runtime.hub('local'), isNotNull);
    expect(manager.connected.where((d) => d == 'parter').length, 2);
  });

  test('po wylogowaniu komunikat zamiast stanu i bez połączeń', () async {
    runtime.update([
      config(1, const [HomeWidgetItem.output('parter', 'on1')]),
    ]);
    await settle();
    runtime.showMessage('Zaloguj się w aplikacji');
    await settle();
    expect(cell(1)['subtitle'], 'Zaloguj się w aplikacji');
    expect(runtime.hub('local'), isNull);
    await runtime.tap(1, 0);
    expect(node.sent, isEmpty);
  });

  test('outputToggle: węzeł z włączonym kanałem wyłącza wszystko', () {
    expect(outputToggle('on', {'channels': 2, 'on1': false, 'on2': true}), {'on': false});
    expect(outputToggle('on', {'channels': 2, 'on1': false, 'on2': false}), {'on': true});
    expect(outputToggle('on', {'on': true}), {'on': false});
  });

  testWidgets('ekran konfiguracji: kilka pozycji z kanałami i sceną', (tester) async {
    await tester.runAsync(() async {
      await scenes.save('local', const Scene(id: 'noc', name: 'Noc'));
    });
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess(), sceneStore: scenes)..start();
    List<HomeWidgetItem>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeWidgetConfigScreen(hub: hub, multi: true, onSave: (items) async => saved = items),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('widget-item-parter-on1')));
    await tester.tap(find.byKey(const Key('widget-item-parter-on1')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('widget-item--noc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('widget-item--noc')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('widget-item-ble-b8f862d84911-')));
    await tester.pumpAndSettle();
    expect(find.text('Czujnik · 22,4 °C · 58 % · 998 hPa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('widget-item-ble-b8f862d84911-')));
    await tester.pump();
    expect(find.text('Pozycje (3 z 6)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('widget-save')));
    await tester.pump();
    expect(saved, const [
      HomeWidgetItem.output('parter', 'on1'),
      HomeWidgetItem.scene('noc'),
      HomeWidgetItem.sensor('ble-b8f862d84911'),
    ]);
    hub.dispose();
  });

  // ---- wygląd pozycji (podpis, ikona, kolor, główna wartość)

  test('wygląd pozycji przechodzi przez JSON; równość pozycji bez wyglądu', () {
    const look = WidgetItemLook(label: 'Salon', icon: 'temperature', color: 'blue', main: 'temp', more: ['hum']);
    final c = HomeWidgetConfig(
      id: 3,
      homeId: 'local',
      items: const [
        HomeWidgetItem.sensor('ble-b8f862d84911', look: look),
        HomeWidgetItem.output('parter', 'on1', look: WidgetItemLook(tap: 'open')),
        HomeWidgetItem.thermostat('t', look: WidgetItemLook(more: [])),
      ],
    );
    final back = HomeWidgetConfig.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
    expect([for (final i in back.items) i.look], [look, const WidgetItemLook(tap: 'open'), const WidgetItemLook(more: [])]);
    expect(back.items.first, const HomeWidgetItem.sensor('ble-b8f862d84911'), reason: 'ten sam czujnik');
    expect(c.toJson()['items'], isNot(contains(containsPair('look', anything))), reason: 'pola płasko w pozycji');
  });

  test('kratki z wyglądem: główna wartość i pod nią, podpis, kolor, ikona, termostat i dotknięcie wyjścia', () async {
    runtime.update([
      config(1, const [
        HomeWidgetItem.sensor(
          'ble-b8f862d84911',
          look: WidgetItemLook(label: 'Salon', main: 'hum', more: ['pressure'], color: 'blue', icon: 'humidity'),
        ),
        HomeWidgetItem.sensor('ble-b8f862d84911', look: WidgetItemLook(more: [])),
        HomeWidgetItem.thermostat('termostat-ab12cd', look: WidgetItemLook(more: ['hum'])),
        HomeWidgetItem.output('parter', 'on1', look: WidgetItemLook(tap: 'open', label: 'Schody')),
      ]),
    ]);
    await settle();
    await settle();
    final s = cell(1);
    expect((s['title'], s['value'], s['subtitle'], s['color'], s['iconKey']), (
      'Salon',
      '58 %',
      '997,8 hPa',
      'blue',
      'humidity',
    ));
    expect((cell(1, 1)['value'], cell(1, 1)['subtitle']), ('22,4 °C', ''), reason: 'domyślnie temperatura, pod nią nic');
    expect(cell(1, 2)['subtitle'], startsWith('Wilgotność '));
    expect((cell(1, 3)['title'], cell(1, 3)['open']), ('Schody', 'parter'));
    await runtime.tap(1, 3);
    expect(node.sent, isEmpty, reason: 'dotknięcie otwiera aplikację zamiast przełączać');
  });

  test('ikona z katalogu jako PNG: rysowana raz na klucz, potem w kratce', () async {
    final drawn = <String>[];
    runtime.dispose();
    runtime = WidgetRuntime(
      hubFactory: (config, wanted) =>
          DeviceHub(store: store, manager: manager, cloud: NoCloudAccess(), sceneStore: scenes, wanted: wanted),
      render: (json) => renders.add(jsonDecode(json) as Map<String, dynamic>),
      debounce: Duration.zero,
      iconPng: (key) async {
        drawn.add(key);
        return 'PNG-$key';
      },
    );
    runtime.update([
      config(1, const [
        HomeWidgetItem.output('parter', 'on1', look: WidgetItemLook(icon: 'fan')),
        HomeWidgetItem.output('parter', 'on2', look: WidgetItemLook(icon: 'fan')),
        HomeWidgetItem.output('lampa', 'on'),
      ]),
    ]);
    await settle();
    await settle();
    expect(drawn, ['fan']);
    expect((cell(1)['iconPng'], cell(1, 1)['iconPng'], cell(1, 2)['iconPng']), ('PNG-fan', 'PNG-fan', null));
  });

  test('kafelek pulpitu jako pozycja: wartość czujnika, kilka wartości, wyjście, termostat, scena; grupa - nie', () async {
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess(), sceneStore: scenes)..start();
    await hub.load();
    final value = const DashWidget(
      id: 'w1',
      view: WidgetView.value,
      device: 'ble-b8f862d84911',
      point: 'temp',
      label: 'Salon',
      icon: 'temperature',
    ).patch({'color': 'green', 'secondary': 'point:hum'});
    expect(itemFromTile(value, hub)?.look, const WidgetItemLook(
      label: 'Salon',
      icon: 'temperature',
      color: 'green',
      main: 'temp',
      more: ['hum'],
    ));
    final values = const DashWidget(id: 'w2', view: WidgetView.valueList).patch({
      'items': [
        {'device': 'gabinet', 'point': 'temp'},
        {'device': 'gabinet', 'point': 'hum'},
        {'device': 'parter', 'point': 'on1'},
      ],
    });
    final fromValues = itemFromTile(values, hub);
    expect((fromValues?.kind, fromValues?.device, fromValues?.look.main), (HomeWidgetKind.sensor, 'gabinet', 'temp'));
    expect(fromValues?.look.more, ['hum'], reason: 'tylko wartości z tego samego urządzenia');
    expect(
      itemFromTile(const DashWidget(id: 'w3', view: WidgetView.toggle, device: 'parter', point: 'on2'), hub),
      const HomeWidgetItem.output('parter', 'on2'),
    );
    expect(
      itemFromTile(const DashWidget(id: 'w4', view: WidgetView.thermostat, device: 'termostat-ab12cd'), hub),
      const HomeWidgetItem.thermostat('termostat-ab12cd'),
    );
    expect(itemFromTile(const DashWidget(id: 'w5', view: WidgetView.scene, sceneId: 'noc'), hub), const HomeWidgetItem.scene('noc'));
    expect(itemFromTile(const DashWidget(id: 'w6', view: WidgetView.group), hub), isNull);
    hub.dispose();
  });

  testWidgets('ekran konfiguracji: „Wygląd” czujnika (podpis, główna wartość, kolor) i pozycja z kafelka pulpitu', (
    tester,
  ) async {
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess(), sceneStore: scenes)..start();
    List<HomeWidgetItem>? saved;
    final dash = Dashboard(
      id: 'd1',
      name: 'Dom',
      scope: DashboardScope.private,
      grid: 4,
      widgets: [
        const DashWidget(id: 'k1', view: WidgetView.toggle, device: 'parter', point: 'on2', label: 'Brama')
            .resized(2, 1)
            .patch({'color': 'red'}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeWidgetConfigScreen(hub: hub, multi: true, dashboards: [dash], onSave: (items) async => saved = items),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    const sensorKey = 'ble-b8f862d84911-';
    await tester.ensureVisible(find.byKey(const Key('widget-item-$sensorKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('widget-item-$sensorKey')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('widget-look-$sensorKey')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('look-preview')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('look-label')), 'Salon');
    await tester.ensureVisible(find.byKey(const Key('look-color-blue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look-color-blue')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('look-main-hum')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look-main-hum')));
    await tester.pump();
    await tester.drag(find.byType(ListView).last, const Offset(0, 600));
    await tester.pump();
    expect(find.descendant(of: find.byKey(const Key('look-preview')), matching: find.text('58 %')), findsOneWidget);
    await tester.tap(find.byKey(const Key('look-done')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('widget-tile-k1')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('widget-tile-k1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('widget-save')));
    await tester.pump();
    expect(saved!.map((i) => i.look), [
      const WidgetItemLook(label: 'Salon', main: 'hum', color: 'blue'),
      const WidgetItemLook(label: 'Brama', color: 'red'),
    ]);
    expect(saved!.last, const HomeWidgetItem.output('parter', 'on2'));
    hub.dispose();
  });
}
