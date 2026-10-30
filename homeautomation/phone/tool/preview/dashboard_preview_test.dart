// Podgląd pulpitu do obrazka (nie jest częścią `flutter test`): prawdziwe czcionki Roboto i ikony Material
// z SDK Fluttera, jasny i ciemny motyw. Uruchomienie:
//   flutter test tool/preview/dashboard_preview_test.dart --update-goldens
// Obrazki: tool/preview/pulpit_jasny.png, tool/preview/pulpit_ciemny.png.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/dashboard_store.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/history.dart';
import 'package:homeautomation/data/scene_store.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/describe.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/scene.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/models/thermostat_config.dart';
import 'package:homeautomation/models/thermostat_state.dart';
import 'package:homeautomation/ui/dashboard_summary.dart';
import 'package:homeautomation/ui/dashboard_tiles.dart';
import 'package:homeautomation/ui/tile_settings.dart';

import '../../test/models_test.dart' show configJson, stateJson;

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

class _Conn<S, C> implements DeviceConnection<S, C> {
  _Conn(this.deviceId, this.codec, this._state, this._config, [this.describe]);

  @override
  final String deviceId;
  final DeviceCodec<S, C> codec;
  final Json _state;
  final Json _config;
  final Json? describe;

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
  Stream<S> get states => const Stream.empty();
  @override
  Stream<C> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => describe;
  @override
  Future<SetResult> sendSet(Json values) async => const SetResult(ok: true);
  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager(this.connections, DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  final Map<String, DeviceConnection<Object?, Object?>> connections;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => connections[device.id]! as DeviceConnection<S, C>;
}

Future<void> _font(String family, List<String> files) async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File('$sdk/bin/cache/artifacts/material_fonts/$f').readAsBytesSync())),
    );
  }
  await loader.load();
}

void main() {
  testWidgets('podgląd pulpitu', (tester) async {
    await tester.runAsync(() async {
      await _font('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
      await _font('MaterialIcons', ['materialicons-regular.otf']);
    });
    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'));
    await store.saveDevice(const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff));
    await store.saveDevice(const PairedDevice(id: 'lampa', name: 'Lampa nad stołem', type: DeviceType.dimmer));
    await store.saveDevice(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub));
    final node = _Conn(
      'parter',
      lightCodec,
      {
        'id': 'parter',
        'on': true,
        'channels': 4,
        'on1': true,
        'on2': false,
        'on3': true,
        'on4': false,
        'inputs': 4,
        'in1': false,
        'in2': true,
        'in3': false,
        'in4': false,
        'in3Fault': true,
      },
      {'name': 'Parter'},
      {
        'type': 'switch',
        'points': [
          for (final (i, n) in ['Schody', 'Hol', 'Taras', 'Garaż'].indexed)
            {'key': 'on${i + 1}', 'name': n, 'kind': 'switch', 'access': 'control'},
          {'key': 'in2', 'name': 'Łącznik taras', 'kind': 'status'},
          {'key': 'in3', 'name': 'Kontaktron garaż', 'kind': 'status'},
        ],
      },
    );
    final lamp = _Conn('lampa', lightCodec, {'id': 'lampa', 'on': true, 'level': 60}, {'name': 'Lampa nad stołem'});
    final scenes = LocalSceneStore(cache: MemoryTextCache());
    await scenes.save(
      'local',
      const Scene(
        id: 'wyjscie',
        name: 'Wychodzę',
        actions: [
          SceneAction.set('parter', {'on': false}),
          SceneAction.set('lampa', {'on': false}),
        ],
      ),
    );
    final hub = DeviceHub(
      store: store,
      manager: _Manager({
        'termostat-ab12cd': _Conn<ThermostatState, ThermostatConfig>('termostat-ab12cd', thermostatCodec, {
          ...jsonDecode(stateJson) as Json,
          'heating': true,
        }, jsonDecode(configJson) as Json),
        'parter': node,
        'lampa': lamp,
        'hub1': _Conn<Json, Json>(
          'hub1',
          rawCodec,
          {
            'id': 'hub1',
            'devices': 5,
            'online': 5,
            'automations': 3,
            'running': 0,
            'lastRun': {'id': 'wyjscie', 'kind': 'scene', 'ok': true, 'at': 1793300000},
            'cloud': true,
          },
          {'name': 'Hub'},
        ),
      }, store),
      cloud: NoCloudAccess(),
      sceneStore: scenes,
    )..start();
    await hub.load();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();

    final now = DateTime(2026, 10, 29, 20);
    Future<List<HistoryPoint>> history(String id, String field, {int hours = 24}) async => [
      for (var i = 0; i <= 96; i++)
        (
          at: now.subtract(Duration(minutes: 15 * (96 - i))),
          value: 20.6 + 0.8 * (i % 24 < 12 ? i % 12 : 12 - i % 12) / 12,
        ),
    ];

    const widgets = [
      DashWidget(id: 'w1', view: WidgetView.thermostat, size: WidgetSize.s2x1, device: 'termostat-ab12cd'),
      DashWidget(id: 'w2', view: WidgetView.toggle, device: 'parter', point: 'on1', icon: 'stairs'),
      DashWidget(id: 'w3', view: WidgetView.toggle, device: 'parter', point: 'on2', icon: 'ceiling'),
      DashWidget(id: 'w4', view: WidgetView.toggle, size: WidgetSize.s2x1, device: 'parter', point: 'on'),
      DashWidget(
        id: 'w5',
        view: WidgetView.slider,
        size: WidgetSize.s2x1,
        device: 'lampa',
        point: 'level',
        label: 'Lampa nad stołem',
      ),
      DashWidget(id: 'w6', view: WidgetView.status, device: 'parter', point: 'in2', icon: 'switch'),
      DashWidget(id: 'w7', view: WidgetView.status, device: 'parter', point: 'in3', icon: 'door-sensor'),
      DashWidget(id: 'w8', view: WidgetView.value, device: 'termostat-ab12cd', point: 'hum', label: 'Wilgotność'),
      DashWidget(id: 'w9', view: WidgetView.scene, sceneId: 'wyjscie', icon: 'leave'),
      DashWidget(
        id: 'w10',
        view: WidgetView.chart,
        size: WidgetSize.s2x1,
        device: 'termostat-ab12cd',
        point: 'temp',
        label: 'Salon - 24 h',
      ),
    ];

    for (final (dark, file) in [(false, 'pulpit_jasny.png'), (true, 'pulpit_ciemny.png')]) {
      tester.view.physicalSize = const Size(412 * 2.5, 1480 * 2.5);
      tester.view.devicePixelRatio = 2.5;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Roboto',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFE8590C),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('Dom')),
            body: RepaintBoundary(
              key: const Key('shot'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DashGrid(
                  widgets: widgets,
                  builder: (w) => DashTile(widget: w, hub: hub, history: history),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await expectLater(find.byType(Scaffold), matchesGoldenFile(file));
    }
    // Tryb edycji na siatce i arkusz ustawień kafelka (jasny motyw).
    final theme = ThemeData(
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8590C)),
    );
    tester.view.physicalSize = const Size(412 * 2.5, 900 * 2.5);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(
          appBar: AppBar(title: const Text('Dom'), actions: const [Icon(Icons.check), SizedBox(width: 16)]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Widżet'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: DashGrid(
              grid: 4,
              widgets: [
                const DashWidget(
                  id: 'e1',
                  view: WidgetView.status,
                  device: 'parter',
                  point: 'in2',
                  label: 'Brama',
                ).resized(2, 2),
                const DashWidget(
                  id: 'e2',
                  view: WidgetView.toggle,
                  device: 'parter',
                  point: 'on',
                  label: 'Światła',
                ).resized(2, 2),
                // 1×1 przypięty na środku (kolumna 2), obok wolne pola.
                const DashWidget(
                  id: 'e3',
                  view: WidgetView.scene,
                  sceneId: 'wyjscie',
                  icon: 'leave',
                ).resized(1, 1).pinnedAt(1, 2),
                const DashWidget(
                  id: 'e4',
                  view: WidgetView.toggle,
                  device: 'parter',
                  point: 'on1',
                  label: 'Schody',
                ).resized(4, 2).pinnedAt(0, 3),
              ],
              emptyCell: (r, c) => EmptyCell(onDrop: (_) {}),
              builder: (w) => EditableTile(
                id: w.id,
                onTap: () {},
                onResize: () {},
                onDrop: (_) {},
                child: DashTile(widget: w, hub: hub, history: history),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('edycja_siatka.png'));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open'),
                onPressed: () => showTileSettings(
                  context,
                  widget: widgets[1].copyWith(label: 'Schody').resized(2, 1).patch({'color': 'amber', 'section': 's1'}),
                  hub: hub,
                  views: const [WidgetView.toggle, WidgetView.status],
                  defaultTitle: 'Kanał 1',
                  grid: 4,
                  sections: const [
                    DashSection(id: 's1', title: 'Parter'),
                    DashSection(id: 's2', title: 'Ogród'),
                  ],
                  points: [
                    for (final (i, n) in ['Schody', 'Hol', 'Taras', 'Garaż'].indexed)
                      DataPoint(key: 'on${i + 1}', name: n, kind: PointKind.switchKind),
                    const DataPoint(key: 'in2', name: 'Łącznik taras', kind: PointKind.status),
                  ],
                  channels: 4,
                ),
                child: const Text('Ustawienia'),
              ),
            ),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(412 * 2.5, 1500 * 2.5);
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tileMoreLook')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('edycja_arkusz.png'));

    // Siatka 4 kolumn z sekcjami i podsumowaniem (pkt 13.1), jasny i ciemny motyw.
    DashWidget g(String id, WidgetView v, String? dev, String? pt, int w, int h, [Map<String, Object?> x = const {}]) =>
        DashWidget(id: id, view: v, device: dev, point: pt).resized(w, h).patch(x);
    final salon = [
      g('s1', WidgetView.thermostat, 'termostat-ab12cd', null, 4, 2),
      g('s2', WidgetView.toggle, 'parter', 'on1', 2, 1, {'secondary': 'point:in2'}).copyWith(icon: 'stairs'),
      g('s3', WidgetView.toggle, 'parter', 'on2', 2, 1).copyWith(icon: 'ceiling'),
      g('s4', WidgetView.slider, 'lampa', 'level', 4, 1).copyWith(label: 'Lampa nad stołem'),
      g('s5', WidgetView.dial, 'termostat-ab12cd', 'target', 2, 3).copyWith(label: 'Nastawa'),
      g('s6', WidgetView.gauge, 'termostat-ab12cd', 'hum', 2, 3, {
        'min': 0,
        'max': 100,
        'zones': [
          [0, 30, 'amber'],
          [30, 60, 'green'],
          [60, 100, 'blue'],
        ],
      }).copyWith(label: 'Wilgotność'),
    ];
    final extra = [
      g('x1', WidgetView.weather, 'termostat-ab12cd', null, 2, 2),
      const DashWidget(id: 'x2', view: WidgetView.group, label: 'Światła parteru').resized(2, 2).patch({
        'members': [
          {'device': 'parter', 'point': 'on1'},
          {'device': 'parter', 'point': 'on2'},
          {'device': 'parter', 'point': 'on3'},
          {'device': 'lampa', 'point': 'on'},
        ],
      }),
      g('x3', WidgetView.hub, 'hub1', null, 4, 2),
      g('x4', WidgetView.schedule, 'termostat-ab12cd', null, 4, 2),
      const DashWidget(id: 'x5', view: WidgetView.valueList, label: 'Rozdzielnia').resized(4, 2).patch({
        'items': [
          {'device': 'termostat-ab12cd', 'point': 'temp'},
          {'device': 'termostat-ab12cd', 'point': 'hum'},
          {'device': 'termostat-ab12cd', 'point': 'outdoor.temp', 'label': 'Na zewnątrz'},
          {'device': 'parter', 'point': 'on3', 'label': 'Pompa'},
        ],
      }),
      const DashWidget(id: 'x6', view: WidgetView.valueList, label: 'Salon').resized(2, 2).patch({
        'items': [
          {'device': 'termostat-ab12cd', 'point': 'temp'},
          {'device': 'termostat-ab12cd', 'point': 'hum'},
        ],
      }),
      const DashWidget(id: 'x7', view: WidgetView.valueList, label: 'Piwnica').resized(2, 2).patch({
        'items': [
          {'device': 'parter', 'point': 'in2', 'label': 'Drzwi'},
          {'device': 'nieznane', 'point': 'temp', 'label': 'Temp.'},
        ],
      }),
    ];
    final parter = [
      g('p1', WidgetView.toggle, 'parter', 'on', 4, 2),
      g('p2', WidgetView.status, 'parter', 'in2', 2, 1, {
        'labels': ['Otwarte', 'Zamknięte'],
      }).copyWith(icon: 'door-sensor', label: 'Brama'),
      g('p3', WidgetView.toggle, 'parter', 'on3', 2, 1, {'color': 'amber'}).copyWith(icon: 'outdoor-light'),
      g('p4', WidgetView.chart, 'termostat-ab12cd', 'temp', 4, 3, {
        'series': [
          {'device': 'termostat-ab12cd', 'point': 'temp', 'line': 'smooth'},
          {'device': 'termostat-ab12cd', 'point': 'target', 'line': 'step'},
          {'device': 'termostat-ab12cd', 'point': 'heating', 'line': 'band'},
        ],
        'rangeSwitch': true,
        'ref': 21,
      }).copyWith(label: 'Salon - temperatura'),
      const DashWidget(id: 'p5', view: WidgetView.scene, sceneId: 'wyjscie', icon: 'leave').resized(2, 1),
    ];
    Future<List<HistoryPoint>> hist(String id, String field, {int hours = 24}) async => [
      for (var i = 0; i <= 48; i++)
        (
          at: now.subtract(Duration(minutes: 30 * (48 - i))),
          value: switch (field) {
            'heat' => (i % 12 < 4 ? 1.0 : 0.0),
            'target' => (i % 24 < 14 ? 21.0 : 18.0),
            _ => 19.6 + 1.4 * (i % 12 < 6 ? i % 12 : 12 - i % 12) / 6,
          },
        ),
    ];
    Widget section(String title, List<DashWidget> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 0, 6),
          child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        DashGrid(
          grid: 4,
          widgets: list,
          builder: (w) => DashTile(widget: w, hub: hub, history: hist),
        ),
      ],
    );
    for (final (dark, file) in [(false, 'siatka4_jasny.png'), (true, 'siatka4_ciemny.png')]) {
      tester.view.physicalSize = const Size(412 * 2.5, 2000 * 2.5);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Roboto',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFE8590C),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('Dom')),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                DashSummary(hub: hub),
                section('Salon', salon),
                section('Parter', parter),
                section('Dom', extra),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await expectLater(find.byType(Scaffold), matchesGoldenFile(file));
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    hub.dispose();
  });
}
