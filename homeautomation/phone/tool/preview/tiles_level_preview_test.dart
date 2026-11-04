// Podgląd nowych kafelków do obrazka (nie jest częścią `flutter test`): poziom (pionowy i poziomy), pionowy suwak,
// wykres słupkowy, wąskie 1×2. Ciemny motyw, czcionki Roboto i ikony Material z SDK Fluttera. Uruchomienie:
//   flutter test tool/preview/tiles_level_preview_test.dart --update-goldens
// Obrazek: tool/preview/kafelki_poziom.png.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/history.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/ui/dashboard_tiles.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => Stream.value(const []);
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
  testWidgets('podgląd nowych kafelków', (tester) async {
    await tester.runAsync(() async {
      await _font('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
      await _font('MaterialIcons', ['materialicons-regular.otf']);
    });
    tester.view.physicalSize = const Size(390 * 2.0, 700 * 2.0);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'zbiornik', name: 'Zbiornik', type: DeviceType.sensor));
    await store.saveDevice(const PairedDevice(id: 'lampa', name: 'Lampa', type: DeviceType.sensor));
    await store.saveDevice(const PairedDevice(id: 'piec', name: 'Piec', type: DeviceType.sensor));
    final manager = _Manager({
      'zbiornik': _Conn<Json, Json>(
        'zbiornik',
        rawCodec,
        {'water': 64, 'pressure': 1.8, 'online': true},
        {'name': 'Zbiornik'},
        {
          'type': 'sensor',
          'points': [
            {'key': 'water', 'name': 'Woda', 'kind': 'sensor', 'unit': '%', 'decimals': 0, 'min': 0, 'max': 100},
            {
              'key': 'pressure',
              'name': 'Ciśnienie',
              'kind': 'sensor',
              'unit': 'bar',
              'decimals': 1,
              'min': 0,
              'max': 6,
            },
          ],
        },
      ),
      'lampa': _Conn<Json, Json>('lampa', rawCodec, {'on': true, 'level': 70}, {'name': 'Lampa'}, {
        'type': 'dimmer',
        'points': [
          {'key': 'on', 'name': 'Włączona', 'kind': 'switch', 'access': 'control'},
          {
            'key': 'level',
            'name': 'Jasność',
            'kind': 'setpoint',
            'unit': '%',
            'min': 0,
            'max': 100,
            'step': 1,
            'access': 'control',
          },
        ],
      }),
      'piec': _Conn<Json, Json>('piec', rawCodec, {'heating': true, 'temp': 21.4}, {'name': 'Piec'}, {
        'type': 'sensor',
        'points': [
          {'key': 'heating', 'name': 'Grzanie', 'kind': 'status', 'history': 'heat'},
          {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1, 'history': 't'},
        ],
      }),
    }, store);
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess());
    await hub.load();
    final now = DateTime.now();
    Future<List<HistoryPoint>> history(String id, String field, {int hours = 24}) async => [
      for (var m = 24 * 60 * 7; m >= 0; m -= 15)
        (
          at: now.subtract(Duration(minutes: m)),
          value: field == 'heat' ? (((m ~/ 60) % 24) < 3 + (m ~/ 1440) ? 0.8 : 0.0) : 21 + (m % 300) / 200,
        ),
    ];
    const z = 'zbiornik';
    final widgets = [
      const DashWidget(id: 'a', view: WidgetView.level, device: z, point: 'water', label: 'Woda').resized(1, 4).patch({
        'zones': [
          [0, 20, 'red'],
          [20, 100, 'green'],
        ],
      }),
      const DashWidget(id: 'b', view: WidgetView.slider, device: 'lampa', point: 'level', label: 'Lampa').resized(1, 4),
      const DashWidget(
        id: 'c',
        view: WidgetView.chart,
        device: 'piec',
        point: 'heating',
        label: 'Grzanie',
      ).resized(2, 4).patch({
        'range': '7d',
        'series': [
          {'device': 'piec', 'point': 'heating', 'line': 'bars'},
        ],
      }),
      const DashWidget(id: 'd', view: WidgetView.level, device: z, point: 'pressure', label: 'Ciśnienie').resized(4, 1),
      const DashWidget(id: 'e', view: WidgetView.value, device: z, point: 'pressure', label: 'Ciśn.').resized(1, 2),
      const DashWidget(id: 'f', view: WidgetView.toggle, device: 'lampa', point: 'on', label: 'Lampa').resized(1, 2),
      const DashWidget(
        id: 'g',
        view: WidgetView.chart,
        device: 'piec',
        point: 'temp',
        label: 'Temperatura',
      ).resized(2, 2).patch({
        'series': [
          {'device': 'piec', 'point': 'temp', 'line': 'bars'},
        ],
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFE8590C), useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DashGrid(
                grid: 4,
                widgets: widgets,
                builder: (w) => DashTile(widget: w, hub: hub, history: history),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('kafelki_poziom.png'));
    hub.dispose();
  });
}
