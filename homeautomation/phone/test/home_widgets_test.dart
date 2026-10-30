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
    manager = _Manager({'parter': node, 'lampa': other, 'termostat-ab12cd': thermo, 'hub1': hubConn}, store);
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
    await tester.tap(find.byKey(const Key('widget-item--noc')));
    await tester.pump();
    expect(find.text('Pozycje (2 z 6)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('widget-save')));
    await tester.pump();
    expect(saved, const [HomeWidgetItem.output('parter', 'on1'), HomeWidgetItem.scene('noc')]);
    hub.dispose();
  });
}
