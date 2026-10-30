// Edytor automatyk huba (ARCHITEKTURA pkt 4.5): wyzwalacz od słońca, akcja „Powiadomienie”, zapis; błędna reguła;
// krok warunkowy „Jeśli…” (if / then / else, 2 poziomy) w automatyce i w scenie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/app.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/automation_store.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/hub_api.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/models/scene.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/automations_screen.dart';

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

class _MemRooms extends RoomStore {
  @override
  Stream<List<Room>> watch() => Stream.value(const []);
  @override
  Future<void> save(Room room) async {}
  @override
  Future<void> remove(String roomId) async {}
}

/// Automatyki w pamięci (bez huba).
class _MemAutomations extends HubAutomations {
  _MemAutomations(DeviceController<Object?, Object?> hub) : super(hub: hub);

  final items = <String, Automation>{};
  String? reject;
  int loads = 0;

  @override
  bool get isLocal => true;

  @override
  Future<AutomationsInfo> load() async {
    loads++;
    return AutomationsInfo(items: items.values.toList(), sunrise: '06:41', sunset: '16:32');
  }

  @override
  Future<void> save(Automation a) async {
    if (a.name == reject) throw HubInvalidException(['${a.id}: when[0] sun']);
    items[a.id] = a;
  }

  @override
  Future<void> remove(String id) async => items.remove(id);
}

void main() {
  testWidgets('nowa automatyka: zachód słońca → powiadomienie; błędna reguła pokazuje problemy', (tester) async {
    final store = MemoryDeviceStore();
    final manager = ConnectionManager(store: store, discovery: _NoDiscovery());
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess());
    final hubController = DeviceController(
      device: const PairedDevice(id: 'hub-51e96c', name: 'Hub', type: DeviceType.hub),
      manager: manager,
      codec: rawCodec,
    );
    final service = _MemAutomations(hubController);
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: manager,
        pairing: PairingService(store: store),
        cloud: NoCloudAccess(),
        provisioning: _NoBle(),
        rooms: _MemRooms(),
        child: TermostatApp(home: AutomationsScreen(hub: hub, controller: hubController, service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('wschód 06:41'), findsOneWidget);

    Future<void> build(String name) async {
      await tester.tap(find.byKey(const Key('newAutomation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('automationName')), name);
      await tester.tap(find.byKey(const Key('addTrigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wschód / zachód słońca'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sunOk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addAction')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Powiadomienie'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('notifyText')), 'Zmrok - zamknij rolety');
      await tester.pump();
      await tester.tap(find.text('Alarm'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('notifyOk')));
      await tester.pumpAndSettle();
      expect(find.text('zachód słońca'), findsOneWidget);
      expect(find.text('powiadomienie (alarm): Zmrok - zamknij rolety'), findsOneWidget);
      await tester.tap(find.byKey(const Key('automationSave')));
      await tester.pumpAndSettle();
    }

    service.reject = 'Zła';
    await build('Zła');
    expect(find.byKey(const Key('automationProblem')), findsOneWidget, reason: 'zostaje w edytorze z problemem');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await build('Zmrok');
    final a = service.items.values.single;
    expect(a.toJson()['when'], [
      {'sun': 'sunset'},
    ]);
    expect(a.toJson()['then'], [
      {'notify': 'Zmrok - zamknij rolety', 'level': 'alarm'},
    ]);
    expect(RegExp(r'^zmrok-[a-z0-9]+$').hasMatch(a.id), isTrue, reason: a.id);
    await tester.pumpAndSettle();
    final texts = [for (final e in find.byType(Text).evaluate()) (e.widget as Text).data].join(' | ');
    expect(find.text('Zmrok'), findsOneWidget, reason: 'loads=${service.loads} $texts');
    hub.dispose();
  });

  testWidgets('krok „Jeśli…”: warunek, „to”, „w przeciwnym razie” z drugim blokiem (bez trzeciego), opis, zapis', (
    tester,
  ) async {
    final store = MemoryDeviceStore();
    final manager = ConnectionManager(store: store, discovery: _NoDiscovery());
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess());
    final hubController = DeviceController(
      device: const PairedDevice(id: 'hub-51e96c', name: 'Hub', type: DeviceType.hub),
      manager: manager,
      codec: rawCodec,
    );
    final service = _MemAutomations(hubController);
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: manager,
        pairing: PairingService(store: store),
        cloud: NoCloudAccess(),
        provisioning: _NoBle(),
        rooms: _MemRooms(),
        child: TermostatApp(home: AutomationsScreen(hub: hub, controller: hubController, service: service)),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> menu(Key key, String item) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    Future<void> log(String text) async {
      await tester.enterText(find.byType(TextField).last, text);
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('newAutomation')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('automationName')), 'Światło');
    await menu(const Key('addTrigger'), 'Wschód / zachód słońca');
    await tester.tap(find.byKey(const Key('sunOk')));
    await tester.pumpAndSettle();

    await menu(const Key('addAction'), 'Jeśli… (warunek)');
    expect(find.byKey(const Key('branchOk')), findsOneWidget);
    await menu(const Key('branchAddIf-1'), 'Za dnia');
    await menu(const Key('branchAddThen-1'), 'Wpis w dzienniku');
    await log('A');
    await menu(const Key('branchAddElse-1'), 'Jeśli… (warunek)');
    // Drugi poziom: bez kolejnego „Jeśli…”.
    await menu(const Key('branchAddIf-2'), 'Po zmroku');
    await tester.tap(find.byKey(const Key('branchAddThen-2')));
    await tester.pumpAndSettle();
    expect(find.text('Jeśli… (warunek)'), findsNothing, reason: 'najwyżej 2 poziomy');
    await tester.tap(find.text('Wpis w dzienniku').last);
    await tester.pumpAndSettle();
    await log('B');
    await tester.tap(find.byKey(const Key('branchOk')));
    await tester.pumpAndSettle();
    expect(find.text('Jeśli po zmroku → 1 akcja'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branchOk')));
    await tester.pumpAndSettle();
    expect(find.text('Jeśli za dnia → 1 akcja, inaczej → 1 akcja'), findsOneWidget);

    // Edycja bloku: dotknięcie otwiera go z zawartością.
    await tester.tap(find.byKey(const Key('branch-0-0')));
    await tester.pumpAndSettle();
    expect(find.text('dziennik: A'), findsOneWidget);
    await menu(const Key('branchAddThen-1'), 'Przerwa');
    await tester.enterText(find.byType(TextField).last, '5');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branchOk')));
    await tester.pumpAndSettle();
    expect(find.text('Jeśli za dnia → 2 akcje, inaczej → 1 akcja'), findsOneWidget);

    await tester.tap(find.byKey(const Key('automationSave')));
    await tester.pumpAndSettle();
    expect(service.items.values.single.toJson()['then'], [
      {
        'if': [
          {'sun': 'day'},
        ],
        'then': [
          {'log': 'A'},
          {'delay': 5},
        ],
        'else': [
          {
            'if': [
              {'sun': 'night'},
            ],
            'then': [
              {'log': 'B'},
            ],
          },
        ],
      },
    ]);
    hub.dispose();
  });

  test('scena: krok „Jeśli…” i nieznana akcja zapisywane bez zmian; bez huba pomijane z komunikatem', () async {
    final j = {
      'name': 'Taras',
      'actions': [
        {
          'if': [
            {'device': 'swiatlo-79cfe4', 'point': 'on4', 'eq': false},
          ],
          'then': [
            {
              'device': 'swiatlo-79cfe4',
              'set': {'on4': true},
            },
          ],
          'else': [
            {
              'device': 'swiatlo-79cfe4',
              'set': {'on4': false},
            },
          ],
        },
        {'przyszlaAkcja': 1},
      ],
    };
    final scene = Scene.fromJson('s1', j);
    expect((scene.actions[0].isBranch, scene.actions[1].isBranch, scene.actions[1].raw != null), (true, false, true));
    expect(scene.toJson(), j);
    final store = MemoryDeviceStore();
    final hub = DeviceHub(
      store: store,
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      cloud: NoCloudAccess(),
    );
    expect(await hub.runScene(scene), ['Krok „Jeśli…” wykonuje tylko hub - pominięty.', 'Krok huba pominięty.']);
    hub.dispose();
  });
}
