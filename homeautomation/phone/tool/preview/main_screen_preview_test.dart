// Podgląd ekranu głównego do obrazków (nie jest częścią `flutter test`): zakładki pulpitów, panel ☰, edycja.
// Ciemny motyw, prawdziwe czcionki Roboto i ikony Material z SDK Fluttera. Uruchomienie:
//   flutter test tool/preview/main_screen_preview_test.dart --update-goldens
// Obrazki: tool/preview/glowny_pulpit.png, glowny_panel.png, glowny_edycja.png.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/main_screen.dart';

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
  testWidgets('podgląd ekranu głównego', (tester) async {
    await tester.runAsync(() async {
      await _font('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
      await _font('MaterialIcons', ['materialicons-regular.otf']);
    });
    tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'gabinet', name: 'Gabinet', type: DeviceType.sensor));
    await store.saveDevice(const PairedDevice(id: 'salon', name: 'Salon', type: DeviceType.sensor));
    await store.saveDevice(const PairedDevice(id: 'swiatla', name: 'Światło salon', type: DeviceType.onOff));
    Json sensorDescribe(bool pressure) => {
      'type': 'sensor',
      'points': [
        {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
        {'key': 'hum', 'name': 'Wilgotność', 'kind': 'sensor', 'unit': '%', 'decimals': 0},
        if (pressure) {'key': 'pressure', 'name': 'Ciśnienie', 'kind': 'sensor', 'unit': 'hPa', 'decimals': 1},
      ],
    };
    final manager = _Manager({
      'gabinet': _Conn<Json, Json>(
        'gabinet',
        rawCodec,
        {'temp': 22.3, 'hum': 57},
        {'name': 'Gabinet'},
        sensorDescribe(false),
      ),
      'salon': _Conn<Json, Json>(
        'salon',
        rawCodec,
        {'temp': 22.4, 'hum': 58, 'pressure': 997.8},
        {'name': 'Salon'},
        sensorDescribe(true),
      ),
      'swiatla': _Conn(
        'swiatla',
        lightCodec,
        {'id': 'swiatla', 'on': true, 'channels': 4, 'on1': false, 'on2': false, 'on3': true, 'on4': false},
        {
          'name': 'Światło salon',
          'channels': 4,
          'ch1': {'name': '12 V'},
          'ch2': {'name': 'Garaż'},
          'ch3': {'name': 'Przód'},
          'ch4': {'name': 'Tył'},
        },
      ),
    }, store);

    final dashboards = LocalDashboardStore(cache: MemoryTextCache());
    await tester.runAsync(() async {
      await dashboards.save(
        'local',
        Dashboard(
          id: 'd0',
          name: 'Dom',
          scope: DashboardScope.private,
          grid: 4,
          widgets: [
            const DashWidget(id: 'w1', view: WidgetView.valueList, size: WidgetSize.s2x2, label: 'Gabinet')
                .patch({
                  'items': [
                    {'device': 'gabinet', 'point': 'temp'},
                    {'device': 'gabinet', 'point': 'hum'},
                  ],
                })
                .resized(2, 2),
            const DashWidget(id: 'w2', view: WidgetView.valueList, size: WidgetSize.s2x2, label: 'Salon')
                .patch({
                  'items': [
                    {'device': 'salon', 'point': 'temp'},
                    {'device': 'salon', 'point': 'hum'},
                    {'device': 'salon', 'point': 'pressure'},
                  ],
                })
                .resized(2, 2),
            const DashWidget(id: 'w3', view: WidgetView.toggle, device: 'swiatla', point: 'on').resized(4, 2),
          ],
        ),
      );
      for (final (i, n) in ['Salon', 'Gabinet', 'Ogród', 'Garaż', 'Kotłownia'].indexed) {
        await dashboards.save(
          'local',
          Dashboard(id: 'd${i + 1}', name: n, scope: DashboardScope.private, order: i + 1, grid: 4),
        );
      }
    });

    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: manager,
        pairing: PairingService(store: store),
        cloud: NoCloudAccess(),
        provisioning: _NoBle(),
        rooms: _NoRooms(),
        dashboards: dashboards,
        child: const TermostatApp(home: MainScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MainScreen), matchesGoldenFile('glowny_pulpit.png'));

    await tester.tap(find.byKey(const Key('panel')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('glowny_panel.png'));
    await tester.tap(find.byKey(const Key('editDashboard')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('glowny_edycja.png'));
    await tester.tap(find.byKey(const Key('editDone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('allDashboards')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('glowny_wszystkie.png'));
  });
}
