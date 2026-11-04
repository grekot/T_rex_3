// Harmonogram wyjścia: automatyka huba z jednym wyzwalaczem czasu i jedną akcją `set` jednego wyjścia
// (model, opis dni) i sekcja na ekranie urządzenia (lista, dodanie, wyłączenie wpisu, usunięcie).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/data/automation_store.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/output_schedule.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/ui/output_schedule_section.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
}

class _Conn implements DeviceConnection<Json, Json> {
  @override
  String get deviceId => 'parter';
  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get routeDescription => '192.168.1.30';
  @override
  Json get state => const {'channels': 4, 'on1': false};
  @override
  Json get config => const {'name': 'Parter'};
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<Json> get states => const Stream.empty();
  @override
  Stream<Json> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => null;
  @override
  Future<SetResult> sendSet(Json values) async => const SetResult(ok: true);
  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager() : super(store: MemoryDeviceStore(), discovery: _NoDiscovery());

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => _Conn() as DeviceConnection<S, C>;
}

/// Automatyki huba w pamięci.
class _Automations extends HubAutomations {
  _Automations(DeviceController<Object?, Object?> hub) : super(hub: hub);

  final items = <String, Automation>{};

  @override
  Future<AutomationsInfo> load() async => AutomationsInfo(items: items.values.toList());

  @override
  Future<void> save(Automation a) async => items[a.id] = a;

  @override
  Future<void> remove(String id) async => items.remove(id);
}

Automation _rule(String id, Json when, Json then, {List<Json> conditions = const []}) =>
    Automation(id: id, name: id, when: [when], then: [then], conditions: conditions);

void main() {
  test('wpis z automatyki: godzina, dni, kanał i akcja; inne automatyki pomijane', () {
    final a = _rule(
      'r1',
      {
        'time': '06:30',
        'days': [1, 2, 3, 4, 5],
      },
      {
        'device': 'parter',
        'set': {'on2': true},
      },
    );
    final s = OutputSchedule.from(a)!;
    expect((s.time, s.point, s.on, daysLabel(s.days)), ('06:30', 'on2', true, 'Pn–Pt'));
    expect(OutputSchedule.from(s.toAutomation())!.minute, 390, reason: 'tam i z powrotem');
    expect(s.toAutomation().toJson()['when'], [
      {
        'time': '06:30',
        'days': [1, 2, 3, 4, 5],
      },
    ]);
    expect(
      OutputSchedule.from(
        _rule(
          'r2',
          {'time': '07:00'},
          {
            'device': 'parter',
            'set': {'on': false},
          },
        ),
      )!.days.length,
      7,
    );
    expect(
      OutputSchedule.from(
        _rule(
          'r3',
          {'sun': 'sunset'},
          {
            'device': 'parter',
            'set': {'on': true},
          },
        ),
      ),
      isNull,
    );
    expect(
      OutputSchedule.from(
        _rule(
          'r4',
          {'time': '07:00'},
          {
            'device': 'parter',
            'set': {'level': 40},
          },
        ),
      ),
      isNull,
    );
    expect(
      OutputSchedule.from(
        _rule(
          'r5',
          {'time': '07:00'},
          {
            'device': 'parter',
            'set': {'on': true},
          },
          conditions: [
            {
              'days': [1],
            },
          ],
        ),
      ),
      isNull,
      reason: 'z warunkiem - zwykła automatyka',
    );
    expect(
      (daysLabel([1, 2, 3, 4, 5, 6, 7]), daysLabel([6, 7]), daysLabel([1, 3, 5])),
      ('codziennie', 'weekend', 'Pn, Śr, Pt'),
    );
  });

  testWidgets('sekcja: lista wpisów urządzenia, nowy wpis na kanał 2 w weekend, wyłączenie i usunięcie', (
    tester,
  ) async {
    final hubC = DeviceController<Json, Json>(
      device: const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub),
      manager: _Manager(),
      codec: rawCodec,
    );
    final c = DeviceController<Json, Json>(
      device: const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff, access: AccessLevel.config),
      manager: _Manager(),
      codec: rawCodec,
    );
    await c.connect();
    final store = _Automations(hubC);
    store.items['r1'] = _rule(
      'r1',
      {
        'time': '06:30',
        'days': [1, 2, 3, 4, 5],
      },
      {
        'device': 'parter',
        'set': {'on1': true},
      },
    );
    store.items['inne'] = _rule(
      'inne',
      {'time': '08:00'},
      {
        'device': 'lampa',
        'set': {'on': true},
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OutputScheduleSection(controller: c, automations: store, channels: 4),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('06:30 · włącz Kanał 1'), findsOneWidget);
    expect(find.text('Pn–Pt'), findsOneWidget);
    expect(find.byKey(const Key('schedule-inne')), findsNothing, reason: 'inne urządzenie');

    await tester.tap(find.byKey(const Key('scheduleAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scheduleChannel-on2')));
    await tester.tap(find.text('Wyłącz'));
    await tester.tap(find.text('Weekend'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scheduleSave')));
    await tester.pumpAndSettle();
    final added = store.items.values.firstWhere((a) => a.id != 'r1' && a.id != 'inne');
    expect(added.toJson()['when'], [
      {
        'time': '07:00',
        'days': [6, 7],
      },
    ]);
    expect(added.toJson()['then'], [
      {
        'device': 'parter',
        'set': {'on2': false},
      },
    ]);
    expect(added.name, 'Harmonogram: Parter - wyłącz Kanał 2 07:00');
    expect(find.text('07:00 · wyłącz Kanał 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheduleEnabled-r1')));
    await tester.pumpAndSettle();
    expect(store.items['r1']!.enabled, isFalse);

    await tester.tap(find.byKey(const Key('schedule-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scheduleDelete')));
    await tester.pumpAndSettle();
    expect(store.items.containsKey('r1'), isFalse);
    expect(find.text('06:30 · włącz Kanał 1'), findsNothing);
  });

  testWidgets('bez huba: wyjaśnienie zamiast listy', (tester) async {
    final c = DeviceController<Json, Json>(
      device: const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff),
      manager: _Manager(),
      codec: rawCodec,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OutputScheduleSection(controller: c, automations: null)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheduleNoHub')), findsOneWidget);
  });
}
