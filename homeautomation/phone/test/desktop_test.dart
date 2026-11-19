// Wersja na komputer (Windows): bez konfiguracji nowych urządzeń (Bluetooth, SoftAP, kod QR aparatem), mysz -
// przeciąganie przewija, prawy przycisk = przytrzymanie. Platformę zmienia `debugDefaultTargetPlatformOverride`.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/platform.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/add_device_screen.dart';
import 'package:homeautomation/ui/dashboard_tiles.dart';
import 'package:homeautomation/ui/main_screen.dart';
import 'package:homeautomation/ui/wide_layout.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
}

class _MemRooms extends RoomStore {
  @override
  Stream<List<Room>> watch() => Stream.value(const []);
  @override
  Future<void> save(Room room) async {}
  @override
  Future<void> remove(String roomId) async {}
}

class _NoBle extends ProvisioningBackend {
  @override
  bool get supported => false;
  @override
  Stream<List<ProvCandidate>> scan() => const Stream.empty();
  @override
  Future<ProvTransport> connect(ProvCandidate candidate) => throw UnimplementedError();
}

Widget _services(Widget child, {LocalDashboardStore? dashboards}) {
  final store = MemoryDeviceStore();
  return Services(
    store: store,
    discovery: _NoDiscovery(),
    manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
    pairing: PairingService(store: store),
    cloud: NoCloudAccess(),
    provisioning: _NoBle(),
    rooms: _MemRooms(),
    dashboards: dashboards,
    child: dashboards == null ? MaterialApp(home: child) : TermostatApp(home: child),
  );
}

DashWidget _w(String id, String section, int w, int h) =>
    DashWidget(id: id, view: WidgetView.value, label: id, extra: {'section': section}).resized(w, h);

/// Pulpit z trzema sekcjami (wysokości 4, 2 i 1 wiersz siatki 4).
Future<LocalDashboardStore> _dashboard() async {
  final store = LocalDashboardStore(cache: MemoryTextCache());
  await store.save(
    'local',
    Dashboard(
      id: 'd0',
      name: 'Dom',
      scope: DashboardScope.private,
      order: 0,
      grid: 4,
      sections: const [
        DashSection(id: 's1', title: 'Salon'),
        DashSection(id: 's2', title: 'Kuchnia'),
        DashSection(id: 's3', title: 'Ogród'),
      ],
      widgets: [_w('a', 's1', 4, 2), _w('b', 's1', 4, 2), _w('c', 's2', 2, 2), _w('d', 's3', 4, 1)],
    ),
  );
  for (final (i, name) in [(1, 'Gabinet'), (2, 'Garaż')]) {
    await store.save('local', Dashboard(id: 'd$i', name: name, scope: DashboardScope.private, order: i, grid: 4));
  }
  return store;
}

double _page(WidgetTester tester) => tester.widget<PageView>(find.byKey(const Key('dashboardPages'))).controller!.page!;

Future<void> _pumpDashboard(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_services(const MainScreen(), dashboards: await _dashboard()));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('szerokie okno: liczba kolumn sekcji i rozkład do najniższej kolumny', () {
    expect(
      [
        for (final w in [390.0, 899.0, 900.0, 1280.0, 1920.0, 2560.0]) dashSectionColumns(w),
      ],
      [1, 1, 2, 2, 4, 4],
    );
    expect(spreadSections([5, 3, 1, 2], 2), [
      [0],
      [1, 2, 3],
    ]);
    expect(spreadSections([1, 1, 1], 3), [
      [0],
      [1],
      [2],
    ]);
    expect(dashSectionHeight([_w('a', 's', 4, 2), _w('b', 's', 2, 1), _w('c', 's', 2, 1)], 4), 4);
  });

  testWidgets('pulpit: w szerokim oknie sekcje w kolumnach, na telefonie jedna pod drugą', (tester) async {
    await _pumpDashboard(tester, const Size(1280, 800));
    expect(find.byKey(const Key('dashColumns')), findsOneWidget);
    // Salon (najwyższy) w lewej kolumnie, Kuchnia i Ogród w prawej.
    final salon = tester.getTopLeft(find.text('Salon'));
    final kuchnia = tester.getTopLeft(find.text('Kuchnia'));
    final ogrod = tester.getTopLeft(find.text('Ogród'));
    expect(kuchnia.dx, greaterThan(salon.dx + 400));
    expect((kuchnia.dy, ogrod.dx), (salon.dy, kuchnia.dx));
    expect(ogrod.dy, greaterThan(kuchnia.dy));

    await _pumpDashboard(tester, const Size(390, 844));
    expect(find.byKey(const Key('dashColumns')), findsNothing);
    expect(tester.getTopLeft(find.text('Kuchnia')).dx, tester.getTopLeft(find.text('Salon')).dx);
  });

  testWidgets('klawiatura: Ctrl+3 / Ctrl+Tab / Ctrl+Shift+Tab - pulpity, Esc - wstecz', (tester) async {
    await _pumpDashboard(tester, const Size(1280, 800));
    expect(_page(tester), 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_page(tester), 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_page(tester), 0, reason: 'za ostatnim - pierwszy');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_page(tester), 2, reason: 'przed pierwszym - ostatni');

    // Esc zamyka otwarty ekran.
    Navigator.of(
      tester.element(find.byKey(const Key('dashboardPages'))),
    ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Ekran testowy'))));
    await tester.pumpAndSettle();
    expect(find.text('Ekran testowy'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Ekran testowy'), findsNothing);
    expect(find.byKey(const Key('dashboardPages')), findsOneWidget);
  });

  test('możliwości platformy: Windows - komputer, bez konfiguracji nowych urządzeń', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect((isDesktop, canSetUpDevices, hasPhoneLocation, fromThisDevice), (true, false, false, 'Z komputera'));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect((isDesktop, canSetUpDevices, hasPhoneLocation, fromThisDevice), (false, true, true, 'Z telefonu'));
  });

  testWidgets('Dodaj urządzenie na komputerze: tylko kod z ekranu, reszta - w telefonie', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(_services(const AddDeviceScreen(scannerCamera: false)));
    expect(find.byKey(const Key('addPhoneOnly')), findsOneWidget);
    expect(find.byKey(const Key('addCode')), findsOneWidget);
    for (final k in ['addQr', 'addBle', 'addSoftAp']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
    expect(find.textContaining('Każdy komputer dostaje własny token'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Dodaj urządzenie na telefonie: bez zmian', (tester) async {
    await tester.pumpWidget(_services(const AddDeviceScreen(scannerCamera: false)));
    expect(find.byKey(const Key('addPhoneOnly')), findsNothing);
    for (final k in ['addQr', 'addBle', 'addSoftAp', 'addCode']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
  });

  testWidgets('mysz: przeciąganie przewija, prawy przycisk na kafelku = przytrzymanie', (tester) async {
    var held = 0;
    await tester.pumpWidget(
      TermostatApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 120,
              child: TileShell(
                key: const Key('tile'),
                icon: Icons.lightbulb,
                title: 'Lampa',
                onLongPress: () => held++,
              ),
            ),
          ),
        ),
      ),
    );
    final ctx = tester.element(find.byKey(const Key('tile')));
    expect(ScrollConfiguration.of(ctx).dragDevices, contains(PointerDeviceKind.mouse));
    await tester.tap(find.text('Lampa'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(held, 1);
  });
}
