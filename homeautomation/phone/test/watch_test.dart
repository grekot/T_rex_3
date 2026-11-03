// Pulpit zegarka (pkt 13a): układ zgodny z aplikacją zegarka, zapis w users/{uid}/watchDashboards, ekran „Zegarek”.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/app.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/hub_api.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/remote.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/data/watch_store.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/watch.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/watch_screen.dart';

import 'support/memory_cloud_store.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

class _NoBle extends ProvisioningBackend {
  @override
  bool get supported => false;
  @override
  Stream<List<ProvCandidate>> scan() => const Stream.empty();
  @override
  Future<ProvTransport> connect(ProvCandidate candidate) => throw UnimplementedError();
}

WatchTile _t(String id, WatchTileSize s) => WatchTile(id: id, view: WatchView.value, size: s);

// Wynik `layoutPages` z homeautomation/watch/utils/layout.js dla tych samych stron (node, 2026-10-27).
const _expected = {
  (480, 480, WatchShape.round): [
    ['h:Dom', 65, 92, 350, 40], ['t1', 40, 132, 400, 186], ['t2', 40, 328, 195, 88], ['t3', 245, 328, 195, 88],
    ['t4', 40, 426, 400, 88], ['h:Światła', 40, 524, 400, 40], ['t5', 143, 564, 195, 88], ['t6', 40, 662, 400, 88],
    ['t7', 40, 760, 195, 88], ['t8', 245, 760, 195, 88], ['t9', 160, 858, 160, 88],
  ],
  (390, 450, WatchShape.square): [
    ['h:Dom', 14, 92, 362, 40], ['t1', 14, 132, 362, 186], ['t2', 14, 328, 176, 88], ['t3', 200, 328, 176, 88],
    ['t4', 14, 426, 362, 88], ['h:Światła', 14, 524, 362, 40], ['t5', 107, 564, 176, 88], ['t6', 14, 662, 362, 88],
    ['t7', 14, 760, 176, 88], ['t8', 200, 760, 176, 88], ['t9', 107, 858, 176, 88],
  ],
  (466, 466, WatchShape.round): [
    ['h:Dom', 62, 92, 343, 40], ['t1', 37, 132, 392, 186], ['t2', 33, 328, 195, 88], ['t3', 238, 328, 195, 88],
    ['t4', 33, 426, 400, 88], ['h:Światła', 33, 524, 400, 40], ['t5', 136, 564, 195, 88], ['t6', 33, 662, 400, 88],
    ['t7', 33, 760, 195, 88], ['t8', 238, 760, 195, 88], ['t9', 155, 858, 156, 88],
  ],
};

/// Hub w pamięci: rejestracja zegarka, lista punktów, odłączenie; hub nie zna żadnego urządzenia.
class _MemHubApi extends HubApi {
  _MemHubApi() : super(LocalApi(LocalEndpoint('127.0.0.1', 1)));

  final puts = <Json>[];
  final deleted = <String>[];

  @override
  Future<({String id, int slot, String key, int cfgVer})> registerRemote({
    required String watchId,
    required String name,
    String kind = 'watch',
  }) async => (id: 'zegarek-$watchId', slot: 3, key: 'ab' * 32, cfgVer: 1);

  @override
  Future<void> putRemote(String id, Json doc) async => puts.add(doc);

  @override
  Future<void> deleteRemote(String id) async => deleted.add(id);

  @override
  Future<List<HubChild>> devices() async => const [];
}

void main() {
  test('układ kafelków taki jak na zegarku (layout.js)', () {
    const h = WatchTileSize.half, f = WatchTileSize.full, b = WatchTileSize.big;
    final pages = [
      WatchPage(title: 'Dom', tiles: [_t('t1', b), _t('t2', h), _t('t3', h), _t('t4', f)]),
      const WatchPage(title: 'Pusta'),
      WatchPage(title: 'Światła', tiles: [_t('t5', h), _t('t6', f), _t('t7', h), _t('t8', h), _t('t9', h)]),
    ];
    for (final e in _expected.entries) {
      final (w, hh, shape) = e.key;
      final r = layoutWatchPages(pages, w, hh, shape);
      expect(r.height, 1026);
      expect([
        for (final x in r.blocks) [x.header == null ? x.tile!.id : 'h:${x.header}', x.x, x.y, x.w, x.h],
      ], e.value, reason: '$w×$hh ${shape.wire}');
    }
  });

  test('JSON pulpitu zegarka (pkt 13a) i magazyn', () async {
    final store = MemoryCloudStore();
    store.set('users/u1/watches/8716545', {
      'name': 'Amazfit T-Rex 3',
      'deviceSource': 8716545,
      'width': 480,
      'height': 480,
      'shape': 'round',
      'app': '1.2.0',
      'lastSeen': 5,
    });
    final ws = WatchStore(store, 'u1');
    final watch = (await ws.watches().first).single;
    expect((watch.id, watch.name, watch.resolution), ('8716545', 'Amazfit T-Rex 3', '480×480, okrągły'));

    const dash = WatchDashboard(
      pages: [
        WatchPage(
          title: 'Dom',
          tiles: [
            WatchTile(id: 't1', device: 'termostat-ab12cd', view: WatchView.thermostat, size: WatchTileSize.big),
            WatchTile(id: 't4', sceneId: 'wyjscie', view: WatchView.scene, size: WatchTileSize.full, label: 'Wychodzę'),
          ],
        ),
      ],
    );
    await ws.save('h1', watch, dash);
    expect(store.get('users/u1/watchDashboards/h1/8716545'), {
      'watch': {'width': 480, 'height': 480, 'shape': 'round'},
      'pages': [
        {
          'title': 'Dom',
          'tiles': [
            {'id': 't1', 'device': 'termostat-ab12cd', 'view': 'thermostat', 'size': 'big'},
            {'id': 't4', 'sceneId': 'wyjscie', 'view': 'scene', 'size': 'full', 'label': 'Wychodzę'},
          ],
        },
      ],
      'updatedAt': store.now,
    });
    expect((await ws.load('h1', '8716545'))!.pages.single.tiles.last.sceneId, 'wyjscie');
    await ws.remove('h1', '8716545');
    expect(await ws.load('h1', '8716545'), isNull);
  });

  testWidgets('ekran „Zegarek”: bez zgłoszonego zegarka model z listy, kafelek, podgląd, zapis', (tester) async {
    final cloud = MemoryCloudStore();
    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'));
    final manager = ConnectionManager(store: store, discovery: _NoDiscovery());
    final hub = DeviceHub(store: store, manager: manager, cloud: TestCloudAccess(cloud, uid: 'u1'));
    await hub.load();
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: manager,
        pairing: PairingService(store: store),
        cloud: TestCloudAccess(cloud, uid: 'u1'),
        provisioning: _NoBle(),
        rooms: CloudRoomStore(cloud, 'h1'),
        child: TermostatApp(home: WatchScreen(hub: hub, store: WatchStore(cloud, 'u1'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Żaden zegarek się jeszcze nie zgłosił'), findsOneWidget);
    expect(find.text('480×480, okrągły'), findsOneWidget);
    expect(find.byKey(const Key('watchPreview')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('watchAddTile-0')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('watchAddTile-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-termostat-ab12cd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-thermostat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('view-chart')), findsNothing, reason: 'zegarek nie ma wykresów');
    await tester.tap(find.byKey(const Key('addWidgetDone')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('watchSave')));
    await tester.pumpAndSettle();
    final saved = cloud.get('users/u1/watchDashboards/local/model:t-rex-3') as Map;
    final tile = ((saved['pages'] as List).single as Map)['tiles'] as List;
    expect(tile.single, containsPair('view', 'thermostat'));
    expect(tile.single, containsPair('size', 'big'));
    expect(saved['watch'], {'width': 480, 'height': 480, 'shape': 'round'});
    hub.dispose();
  });

  test('punkty pilota z pulpitu zegarka: termostat = 5 punktów, scena = runScene huba, bez powtórzeń', () {
    const pages = [
      WatchPage(
        title: 'Dom',
        tiles: [
          WatchTile(id: 't1', device: 'termostat-ab12cd', view: WatchView.thermostat, size: WatchTileSize.big),
          WatchTile(id: 't2', device: 'swiatlo-79cfe4', point: 'on2', view: WatchView.toggle),
          WatchTile(id: 't3', device: 'termostat-ab12cd', point: 'temp', view: WatchView.value),
        ],
      ),
      WatchPage(
        title: 'Sceny',
        tiles: [WatchTile(id: 't4', sceneId: 'wyjscie', view: WatchView.scene)],
      ),
    ];
    expect([for (final p in watchRemotePoints(pages, 'hub-51e96c')) remotePointJson(p)], [
      for (final k in ['temp', 'target', 'mode', 'power', 'heating']) {'device': 'termostat-ab12cd', 'point': k},
      {'device': 'swiatlo-79cfe4', 'point': 'on2'},
      {'device': 'hub-51e96c', 'point': 'runScene', 'arg': 'wyjscie'},
    ]);
  });

  testWidgets('zegarek: połączenie z hubem przez Bluetooth, punkty w remotes z cfgVer, ostrzeżenie, odłączenie', (
    tester,
  ) async {
    final cloud = MemoryCloudStore();
    cloud.set('users/u1/watches/8716545', {'name': 'T-Rex 3', 'width': 480, 'height': 480, 'shape': 'round'});
    cloud.set('users/u1/watchDashboards/local/8716545', {
      'pages': [
        {
          'title': 'Dom',
          'tiles': [
            {'id': 't1', 'device': 'termostat-ab12cd', 'view': 'thermostat', 'size': 'big'},
            {'id': 't2', 'sceneId': 'wyjscie', 'view': 'scene', 'size': 'full'},
          ],
        },
      ],
    });
    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'));
    await store.saveDevice(const PairedDevice(id: 'hub-51e96c', name: 'Hub', type: DeviceType.hub));
    final manager = ConnectionManager(store: store, discovery: _NoDiscovery());
    final hub = DeviceHub(store: store, manager: manager, cloud: TestCloudAccess(cloud, uid: 'u1'));
    await hub.load();
    final api = _MemHubApi();
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: manager,
        pairing: PairingService(store: store),
        cloud: TestCloudAccess(cloud, uid: 'u1'),
        provisioning: _NoBle(),
        rooms: CloudRoomStore(cloud, 'h1'),
        child: TermostatApp(
          home: WatchScreen(hub: hub, store: WatchStore(cloud, 'u1'), hubApi: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('watchBleMissing')), findsOneWidget, reason: 'termostat poza hubem');
    expect(find.textContaining('Hub nie zna: Salon'), findsOneWidget);

    await tester.tap(find.byKey(const Key('watchBle')));
    await tester.pumpAndSettle();
    final ble = cloud.get('users/u1/watches/8716545/ble') as Map;
    expect((ble['homeId'], ble['hub'], ble['id'], ble['slot'], ble['key']), (
      'local',
      'hub-51e96c',
      'zegarek-8716545',
      3,
      'ab' * 32,
    ));
    var doc = cloud.get('homes/local/remotes/zegarek-8716545') as Map;
    expect((doc['kind'], doc['ownerUid'], doc['hub'], doc['cfgVer'], (doc['points'] as List).length), (
      'watch',
      'u1',
      'hub-51e96c',
      1,
      6,
    ));
    expect((doc['points'] as List).last, {'device': 'hub-51e96c', 'point': 'runScene', 'arg': 'wyjscie'});
    expect(api.puts.single['cfgVer'], 1);
    expect(api.puts.single.keys, unorderedEquals(['name', 'cfgVer', 'points']), reason: 'hub pomija resztę, limit 4 kB');
    expect(find.byKey(const Key('watchBleLinked')), findsOneWidget);

    // Zapis pulpitu: cfgVer + 1 w chmurze i w hubie.
    // Przewijanie listy wprost (przeciąganie na środku trafiałoby w przewijany podgląd zegarka).
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    list.jumpTo(list.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('watchAddPage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('watchSave')));
    await tester.pumpAndSettle();
    doc = cloud.get('homes/local/remotes/zegarek-8716545') as Map;
    expect((doc['cfgVer'], api.puts.length, api.puts.last['cfgVer']), (2, 2, 2));

    list.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('watchBleUnlink')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('watchBleUnlinkOk')));
    await tester.pumpAndSettle();
    expect(api.deleted, ['zegarek-8716545']);
    expect(cloud.get('homes/local/remotes/zegarek-8716545'), isNull);
    expect(cloud.get('users/u1/watches/8716545/ble'), isNull);
    expect(find.byKey(const Key('watchBle')), findsOneWidget);
    hub.dispose();
  });

  test('wbudowana lista modeli ma T-Rex 3 i oba kształty', () {
    expect(builtInWatches.first.name, 'Amazfit T-Rex 3');
    expect(builtInWatches.map((w) => w.shape).toSet(), {WatchShape.round, WatchShape.square});
    expect(DeviceType.thermostat.wire, 'thermostat');
  });
}
