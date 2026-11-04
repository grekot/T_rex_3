// „Wyłącz za…”: odliczanie w hubie (pkt 11) - timery z State huba, polecenia lokalnie (`/api/timers`) i przez
// chmurę (`timerAdd` / `timerCancel`), sekcja „Odliczanie” na ekranie wyjścia (lista, anulowanie, nowe).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/hub_api.dart';
import 'package:homeautomation/data/hub_timers.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/hub_timer.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/ui/output_timer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
}

/// Połączenie przez chmurę: stały stan, zapamiętane Set i odpowiedź [reply].
class _Conn implements DeviceConnection<Json, Json> {
  _Conn(this.deviceId, this.state);

  @override
  final String deviceId;
  @override
  final Json state;
  final sent = <Json>[];
  SetResult reply = const SetResult(ok: true);

  @override
  ConnectionKind get kind => ConnectionKind.cloud;
  @override
  String get routeDescription => 'chmura';
  @override
  Json get config => const {};
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
  Future<SetResult> sendSet(Json values) async {
    sent.add(values);
    return reply;
  }

  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager(this.conn) : super(store: MemoryDeviceStore(), discovery: _NoDiscovery());

  final _Conn conn;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conn as DeviceConnection<S, C>;
}

Future<(DeviceController<Json, Json>, _Conn)> _controller(PairedDevice d, Json state) async {
  final conn = _Conn(d.id, state);
  final c = DeviceController<Json, Json>(device: d, manager: _Manager(conn), codec: rawCodec);
  await c.connect();
  return (c, conn);
}

void main() {
  final now = DateTime.now();
  final at = now.millisecondsSinceEpoch ~/ 1000 + 1500;

  test('timery z State huba: brak pola = hub bez timerów, kolejność, wyjście, czas do końca', () {
    expect(hubTimers({'id': 'hub1'}), isNull);
    final list = hubTimers({
      'timers': [
        {
          'id': 't2',
          'device': 'parter',
          'set': {'level': 30},
          'at': at + 600,
        },
        {
          'id': 't1',
          'device': 'parter',
          'set': {'on2': false},
          'at': at,
        },
        {'id': 'zły'},
        {
          'id': 't0',
          'device': 'parter',
          'set': {'on': false},
          'at': null,
        },
      ],
    })!;
    expect([for (final t in list) t.id], ['t1', 't2', 't0'], reason: 'bez znanego czasu na końcu');
    expect(list.last.leftAt(now), isNull);
    expect(timerShort(list.last, now), 'wył. po odliczeniu');
    expect(list.first.output, (point: 'on2', on: false));
    expect(list[1].output, isNull);
    expect(list.first.leftAt(DateTime.fromMillisecondsSinceEpoch(at * 1000 - 60000)), 60);
    expect(list.first.leftAt(DateTime.fromMillisecondsSinceEpoch(at * 1000 + 5000)), 0);
    expect(timerShort(list.first, DateTime.fromMillisecondsSinceEpoch(at * 1000 - 25 * 60000)), 'wył. za 25 min');
    expect(describeTimerError('limit'), contains('20'));
  });

  test('przez chmurę: timerAdd / timerCancel, błąd pola huba', () async {
    final (hub, conn) = await _controller(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub), const {
      'timers': [],
    });
    final timers = HubTimers(hub, clock: () => DateTime(2026, 11, 4, 21, 0));
    expect(await timers.add('parter', {'on': false}, const Duration(minutes: 30)), DateTime(2026, 11, 4, 21, 30));
    expect(conn.sent.last, {
      'timerAdd': {
        'device': 'parter',
        'set': {'on': false},
        'in': 1800,
      },
    });
    await timers.cancel('t3');
    expect(conn.sent.last, {'timerCancel': 't3'});
    conn.reply = const SetResult(ok: false, errors: {'timerAdd': 'limit'});
    await expectLater(
      timers.add('parter', {'on': false}, const Duration(minutes: 5)),
      throwsA(isA<HubTimerException>().having((e) => e.code, 'code', 'limit')),
    );
  });

  test('lokalnie: POST /api/timers z `in`, odpowiedź `id` i `at`, błąd `set`', () async {
    final requests = <http.Request>[];
    final api = HubApi(
      LocalApi(
        const LocalEndpoint('192.168.1.20', 80),
        token: 'tok',
        client: MockClient((r) async {
          requests.add(r);
          if (r.method == 'DELETE') return http.Response('{"ok":false,"error":"not_found"}', 404);
          final body = jsonDecode(r.body) as Map;
          if ((body['set'] as Map).containsKey('target')) return http.Response('{"ok":false,"error":"set"}', 400);
          if (body['in'] == 60) return http.Response('{"ok":true,"id":"t4","at":null}', 200);
          return http.Response('{"ok":true,"id":"t3","at":1793990000}', 200);
        }),
      ),
    );
    final r = await api.addTimer('parter', {'on2': false}, 900);
    expect(r.id, 't3');
    expect(r.at, DateTime.fromMillisecondsSinceEpoch(1793990000 * 1000));
    expect(requests.single.url.path, '/api/timers');
    expect(jsonDecode(requests.single.body), {
      'device': 'parter',
      'set': {'on2': false},
      'in': 900,
    });
    expect((await api.addTimer('parter', {'on': true}, 60)).at, isNull, reason: 'hub bez znanego czasu');
    await expectLater(
      api.addTimer('parter', {'target': 21}, 900),
      throwsA(isA<HubTimerException>().having((e) => e.code, 'code', 'set')),
    );
    await expectLater(
      api.cancelTimer('t9'),
      throwsA(isA<HubTimerException>().having((e) => e.code, 'code', 'not_found')),
    );
  });

  testWidgets('sekcja: aktywne odliczanie z „Anuluj” i nowe „wyłącz za 15 min” na kanał 1', (tester) async {
    final (hub, conn) = await _controller(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub), {
      'timers': [
        {
          'id': 't1',
          'device': 'parter',
          'set': {'on2': false},
          'at': at,
        },
        {
          'id': 'inne',
          'device': 'lampa',
          'set': {'on': false},
          'at': at,
        },
      ],
    });
    final (c, _) = await _controller(
      const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff, access: AccessLevel.control),
      const {'channels': 4, 'on1': true, 'on2': true},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OutputTimerSection(controller: c, timers: HubTimers(hub), channels: 4),
          ),
        ),
      ),
    );
    expect(find.textContaining('Kanał 2 wyłączy się za 2'), findsOneWidget);
    expect(find.byKey(const Key('timer-inne')), findsNothing, reason: 'inne urządzenie');

    await tester.tap(find.byKey(const Key('timerCancel-t1')));
    await tester.pump();
    expect(conn.sent.last, {'timerCancel': 't1'});

    await tester.tap(find.byKey(const Key('timerAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timerChannel-on1')));
    await tester.pump();
    expect(find.text('Wyłącz za 30 min'), findsOneWidget, reason: 'kanał włączony - domyślnie wyłącz');
    await tester.tap(find.byKey(const Key('timerIn-15')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('timerStart')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'timerAdd': {
        'device': 'parter',
        'set': {'on1': false},
        'in': 900,
      },
    });
    expect(find.textContaining('Kanał 1 wyłączy się o'), findsOneWidget);
  });

  testWidgets('hub bez timerów - sekcji nie ma', (tester) async {
    final (hub, _) = await _controller(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub), const {
      'id': 'hub1',
    });
    final (c, _) = await _controller(const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff), const {
      'on': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutputTimerSection(controller: c, timers: HubTimers(hub)),
        ),
      ),
    );
    expect(find.byKey(const Key('timerAdd')), findsNothing);
  });
}
