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
import 'package:homeautomation/models/automation_templates.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/json_utils.dart';
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
        child: TermostatApp(
          home: AutomationsScreen(hub: hub, controller: hubController, service: service),
        ),
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
        child: TermostatApp(
          home: AutomationsScreen(hub: hub, controller: hubController, service: service),
        ),
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

  testWidgets('tryb restart zostaje po włączniku i edycji; opisy down / up / change; przerwa z ułamkiem', (
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
    service.items['ruch'] = Automation.fromJson('ruch', {
      'name': 'Ruch',
      'mode': 'restart',
      'when': [
        {'device': 'wej-1', 'input': 'in1', 'press': 'down'},
        {'device': 'wej-1', 'input': 'in1', 'press': 'up'},
        {'device': 'wej-1', 'input': 'in1', 'press': 'change'},
      ],
      'then': [
        {'delay': 0.5},
      ],
    });
    await tester.pumpWidget(
      Services(
        store: store,
        discovery: _NoDiscovery(),
        manager: manager,
        pairing: PairingService(store: store),
        cloud: NoCloudAccess(),
        provisioning: _NoBle(),
        rooms: _MemRooms(),
        child: TermostatApp(
          home: AutomationsScreen(hub: hub, controller: hubController, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((service.items['ruch']!.enabled, service.items['ruch']!.mode), (false, 'restart'));

    await tester.tap(find.byKey(const Key('automation-ruch')));
    await tester.pumpAndSettle();
    for (final press in ['wciśnięcie / zwarcie', 'puszczenie / rozwarcie', 'zmiana stanu']) {
      expect(find.textContaining('$press: wej-1'), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('automationRestart')),
      200,
      scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('czekaj 0.5 s'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('automationRestart'))).value, isTrue);

    await tester.tap(find.byKey(const Key('automationSave')));
    await tester.pumpAndSettle();
    expect(service.items['ruch']!.toJson()['mode'], 'restart');
    expect(service.items['ruch']!.toJson()['then'], [
      {'delay': 0.5},
    ]);

    await tester.tap(find.byKey(const Key('automation-ruch')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('automationRestart')),
      200,
      scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('automationRestart')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('automationSave')));
    await tester.pumpAndSettle();
    expect(service.items['ruch']!.toJson().containsKey('mode'), isFalse, reason: 'single to domyślny tryb');
    hub.dispose();
  });

  test('szablony: reguły jak w tabeli trybów wejść', () {
    List<Json> rules(AutomationTemplate t, {String output = 'on2'}) => [
      for (final a in buildTemplate(
        t,
        inputDevice: 'wej',
        input: 'in1',
        inputName: 'Wejście 1',
        outputDevice: 'wyj',
        output: output,
        outputName: 'Taras',
        seconds: 0.5,
      ))
        a.toJson()..remove('name'),
    ];
    Json trigger(String press) => {'device': 'wej', 'input': 'in1', 'press': press};
    Json set(Json s) => {'device': 'wyj', 'set': s};
    Json rule(String press, List<Json> then, {String? mode}) => {
      'enabled': true,
      'when': [trigger(press)],
      'if': <Json>[],
      'then': then,
      'mode': ?mode,
    };

    expect(rules(AutomationTemplate.button), [
      rule('down', [
        set({'toggle2': true}),
      ]),
    ]);
    expect(rules(AutomationTemplate.staircase, output: 'on').single['then'], [
      set({'toggle': true}),
    ]);
    expect(rules(AutomationTemplate.staircase).single['when'], [trigger('change')]);
    expect(rules(AutomationTemplate.follow), [
      rule('down', [
        set({'on2': true}),
      ]),
      rule('up', [
        set({'on2': false}),
      ]),
    ]);
    expect(rules(AutomationTemplate.timer), [
      rule('down', [
        set({'on2': true}),
        {'delay': 0.5},
        set({'on2': false}),
      ], mode: 'restart'),
    ]);

    final two = buildTemplate(
      AutomationTemplate.follow,
      inputDevice: 'wej',
      input: 'in1',
      inputName: 'Bardzo długa nazwa wejścia modułu w piwnicy',
      outputDevice: 'wyj',
      output: 'on1',
      outputName: 'Taras',
    );
    expect(two[0].id, isNot(two[1].id));
    expect(two.every((a) => a.name.length <= 40), isTrue);
  });

  testWidgets('szablon „na czas”: wejście, wyjście, czas, zapis', (tester) async {
    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'wej', name: 'Wejścia', type: DeviceType.onOff));
    await store.saveDevice(const PairedDevice(id: 'wyj', name: 'Wyjścia', type: DeviceType.onOff));
    final manager = ConnectionManager(store: store, discovery: _NoDiscovery());
    final hub = DeviceHub(store: store, manager: manager, cloud: NoCloudAccess());
    await tester.runAsync(hub.load);
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
        child: TermostatApp(
          home: AutomationsScreen(hub: hub, controller: hubController, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(String key) async {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
    }

    await tap('automationTemplates');
    await tap('template-timer');
    await tap('auto-device-wej');
    await tap('auto-point-in3');
    expect(find.text('Wyjście'), findsOneWidget);
    await tap('auto-device-wyj');
    await tap('auto-point-on');
    await tester.enterText(find.byType(TextField).last, '90');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    final a = service.items.values.single;
    expect(a.mode, 'restart');
    expect(a.when.single, {'device': 'wej', 'input': 'in3', 'press': 'down'});
    expect(a.then[1], {'delay': 90});
    hub.dispose();
  });

  test('przerwa z ułamkiem: wpis, zapis sceny bez zmian, wykonanie bez huba', () async {
    expect(
      [
        for (final t in ['60', '0.5', '0,5', '0', '-1', 'x', '', null]) parseDelay(t),
      ],
      [60, 0.5, 0.5, null, null, null, null, null],
    );
    final j = {
      'name': 'Impuls',
      'actions': [
        {'delay': 0.05},
        {'delay': 2},
      ],
    };
    final scene = Scene.fromJson('s1', j);
    expect(scene.toJson(), j);
    final store = MemoryDeviceStore();
    final hub = DeviceHub(
      store: store,
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      cloud: NoCloudAccess(),
    );
    final problems = await hub.runScene(scene, maxDelay: const Duration(seconds: 1));
    expect(problems, ['Opóźnienie 2 s wykona tylko hub - dalsze kroki pominięte.']);
    hub.dispose();
  });

  test('przycisk czujnika Bluetooth jako wyzwalacz: potrójne naciśnięcie w opisie', () {
    final store = MemoryDeviceStore();
    final hub = DeviceHub(
      store: store,
      manager: ConnectionManager(store: store, discovery: _NoDiscovery()),
      cloud: NoCloudAccess(),
    );
    expect(
      describeTrigger(hub, {'device': 'ble-f84477aabbcc', 'input': 'btn1', 'press': 'triple'}),
      startsWith('potrójne naciśnięcie: ble-f84477aabbcc'),
    );
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
