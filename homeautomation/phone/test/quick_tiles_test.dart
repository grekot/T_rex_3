// Kafelki szybkich ustawień Androida „Dom 1-4”: ustawienie pozycji (widżet o id -1…-4), wyczyszczenie, kratka
// i dotknięcie kafelka w usłudze widżetów.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/home_widget_store.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/home_widgets/quick_tiles_screen.dart';
import 'package:homeautomation/home_widgets/widget_runtime.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home_widget.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/set_values.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
}

class _Conn implements DeviceConnection<LightState, LightConfig> {
  Json _state = {'id': 'lampa', 'on': false};
  final sent = <Json>[];
  final _states = StreamController<LightState>.broadcast();

  @override
  String get deviceId => 'lampa';
  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get routeDescription => '192.168.1.30';
  @override
  LightState get state => lightCodec.state(_state);
  @override
  LightConfig get config => lightCodec.config(const {'name': 'Lampa'});
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<LightState> get states => _states.stream;
  @override
  Stream<LightConfig> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => null;
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

class _Manager extends ConnectionManager {
  _Manager(this.conn, DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  final _Conn conn;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conn as DeviceConnection<S, C>;
}

/// Ustawienia widżetów w pamięci.
class _Store extends HomeWidgetStore {
  final configs = <int, HomeWidgetConfig>{};

  @override
  Future<List<HomeWidgetConfig>> load() async => configs.values.toList();

  @override
  Future<void> save(HomeWidgetConfig config) async => configs[config.id] = config;

  @override
  Future<void> remove(int id) async => configs.remove(id);
}

void main() {
  late MemoryDeviceStore store;
  late _Conn conn;
  late _Manager manager;

  setUp(() async {
    store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'lampa', name: 'Lampa', type: DeviceType.onOff));
    conn = _Conn();
    manager = _Manager(conn, store);
  });

  testWidgets('ekran: kafelek „Dom 2” ustawiony na lampę (widżet -2), potem wyczyszczony', (tester) async {
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess())..start();
    final widgets = _Store();
    var notified = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: QuickTilesScreen(
          hub: hub,
          store: widgets,
          onChanged: () async {
            notified++;
            return {2};
          },
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Nie ustawiono'), findsNWidgets(4));

    await tester.tap(find.byKey(const Key('quickTile-2')));
    await tester.pumpAndSettle();
    expect(find.text('Kafelek „Dom 2”'), findsOneWidget);
    await tester.tap(find.byKey(const Key('widget-item-lampa-on')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('widget-save')));
    await tester.pumpAndSettle();
    expect(widgets.configs[-2]!.items, const [HomeWidgetItem.output('lampa', 'on')]);
    expect(notified, 1);
    expect(find.textContaining('Lampa · przełącza · w pasku'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quickTileClear-2')));
    await tester.pumpAndSettle();
    expect(widgets.configs, isEmpty);
    expect(find.text('Nie ustawiono · w pasku'), findsOneWidget, reason: 'kafelek dalej w pasku, bez pozycji');
    hub.dispose();
  });

  test('usługa widżetów: kratka kafelka -1 i dotknięcie przełącza wyjście', () async {
    final renders = <Map<String, dynamic>>[];
    final runtime = WidgetRuntime(
      hubFactory: (config, wanted) => DeviceHub(store: store, manager: manager, cloud: NoCloudAccess(), wanted: wanted),
      render: (json) => renders.add(jsonDecode(json) as Map<String, dynamic>),
      debounce: Duration.zero,
      readyTimeout: const Duration(seconds: 1),
    );
    runtime.update([
      const HomeWidgetConfig(id: -1, homeId: HomeWidgetConfig.localHome, items: [HomeWidgetItem.output('lampa', 'on')]),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(((renders.last['-1'] as List).single as Map)['subtitle'], 'Wyłączone');
    await runtime.tap(-1, 0);
    expect(conn.sent.last, {'on': true});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(((renders.last['-1'] as List).single as Map)['active'], true);
    runtime.dispose();
  });
}
