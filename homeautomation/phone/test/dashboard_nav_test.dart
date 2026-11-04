// Ekran główny bez dolnego paska: zakładki pulpitów, przesuwanie palcem, panel ☰ z góry, lista wszystkich pulpitów,
// kolejność i nazwy, tryb edycji z paskiem „Gotowe”.

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
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/room.dart';
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

const _names = ['Dom', 'Salon', 'Gabinet', 'Ogród', 'Garaż', 'Piętro', 'Kotłownia', 'Energia'];

Future<LocalDashboardStore> _dashboards(int n) async {
  final store = LocalDashboardStore(cache: MemoryTextCache());
  for (var i = 0; i < n; i++) {
    await store.save('local', Dashboard(id: 'd$i', name: _names[i], scope: DashboardScope.private, order: i, grid: 4));
  }
  return store;
}

Future<void> _pump(WidgetTester tester, LocalDashboardStore dashboards) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryDeviceStore();
  await tester.pumpWidget(
    Services(
      store: store,
      discovery: _NoDiscovery(),
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      pairing: PairingService(store: store),
      cloud: NoCloudAccess(),
      provisioning: _NoBle(),
      rooms: _NoRooms(),
      dashboards: dashboards,
      child: const TermostatApp(home: MainScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Nazwa bieżącego pulpitu z panelu ☰ (panel zostaje zamknięty).
Future<String> _current(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('panel')));
  await tester.pumpAndSettle();
  final t = tester.widget<Text>(find.textContaining('Ten pulpit: ')).data!;
  await tester.tap(find.byKey(const Key('panel-close')));
  await tester.pumpAndSettle();
  return t.substring('Ten pulpit: '.length);
}

void main() {
  testWidgets('zakładki zamiast dolnego paska; zakładka i przesunięcie palcem zmieniają pulpit', (tester) async {
    await _pump(tester, await _dashboards(3));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('allDashboards')), findsNothing, reason: 'trzy zakładki się mieszczą');
    expect(await _current(tester), 'Dom');

    await tester.tap(find.byKey(const Key('dashTab-d2')));
    await tester.pumpAndSettle();
    expect(await _current(tester), 'Gabinet');

    await tester.drag(find.byKey(const Key('dashboardPages')), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(await _current(tester), 'Salon');
  });

  testWidgets('panel ☰: skróty bez konta, urządzenia jako osobny ekran, edycja z paskiem „Gotowe”', (tester) async {
    await _pump(tester, await _dashboards(2));
    await tester.tap(find.byKey(const Key('panel')));
    await tester.pumpAndSettle();
    expect(find.text('Dom w telefonie'), findsOneWidget);
    expect(find.byKey(const Key('panel-devices')), findsOneWidget);
    expect(find.byKey(const Key('panel-updates')), findsOneWidget);
    expect(find.byKey(const Key('panel-members')), findsNothing, reason: 'bez konta nie ma domowników');
    expect(find.byKey(const Key('panel-watch')), findsNothing);
    expect(find.byKey(const Key('panel-arrange')), findsOneWidget);

    await tester.tap(find.byKey(const Key('panel-devices')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('addDevice')), findsOneWidget);
    await tester.tap(find.byType(BackButton)); // pageBack szuka podpowiedzi „Back”, a tu jest „Wstecz”
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('panel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editDashboard')));
    await tester.pumpAndSettle();
    expect(find.text('EDYCJA'), findsOneWidget);
    expect(find.text('Pulpit „Dom”'), findsOneWidget);
    expect(find.byKey(const Key('addWidget')), findsOneWidget);
    expect(find.byKey(const Key('panel')), findsNothing);
    await tester.tap(find.byKey(const Key('editDone')));
    await tester.pumpAndSettle();
    expect(find.text('EDYCJA'), findsNothing);
    expect(find.byKey(const Key('panel')), findsOneWidget);
  });

  testWidgets('osiem pulpitów: strzałka „wszystkie”, wybór z listy, kolejność i pulpit na starcie', (tester) async {
    final dashboards = await _dashboards(8);
    await _pump(tester, dashboards);
    expect(find.byKey(const Key('allDashboards')), findsOneWidget, reason: 'zakładki się nie mieszczą');

    await tester.tap(find.byKey(const Key('allDashboards')));
    await tester.pumpAndSettle();
    expect(find.text('Wszystkie pulpity'), findsOneWidget);
    await tester.tap(find.byKey(const Key('allDash-d6')));
    await tester.pumpAndSettle();
    expect(await _current(tester), 'Kotłownia');
    // Zakładka wybranego pulpitu przewinięta do widoku.
    final tab = tester.getRect(find.byKey(const Key('dashTab-d6')));
    expect(tab.left >= 0 && tab.right <= 390, isTrue);

    await tester.tap(find.byKey(const Key('panel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('panel-arrange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orderDown-d0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orderDefault-d3')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    double left(String id) => tester.getTopLeft(find.byKey(Key('dashTab-$id'))).dx;
    expect(left('d1') < left('d0') && left('d0') < left('d2'), isTrue, reason: 'Salon, Dom, Gabinet');
    final prefs = await tester.runAsync(() => dashboards.prefs('local'));
    expect(prefs?.defaultDashboard, 'd3');
  });
}
