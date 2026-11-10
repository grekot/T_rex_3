// Zegar-termometr `clock` (pkt 10.2): strony z widżetami (pary, limity, miejsce w siatce 4×3, przeniesienie
// z pulpitu), atrapa `FakeClock` przez HTTP (błędy Set jak w kontrakcie), ekran urządzenia, ustawienia, edytor stron
// z opisami z `describe` i rozwinięciem `room`, przyciski zdalne jako automatyki huba z `owner`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/automation_store.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/clock.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/describe.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/ui/clock_buttons.dart';
import 'package:homeautomation/ui/clock_pages.dart';
import 'package:homeautomation/ui/clock_section.dart';
import 'package:homeautomation/ui/clock_settings.dart';

import '../tool/fake/fake_thermostat_server.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
}

/// Połączenie w pamięci: stan i Config (przez kodek typu), Set jak w urządzeniu (Config scalany), opis punktów.
class _Conn<S, C> implements DeviceConnection<S, C> {
  _Conn(this.deviceId, this.codec, this.stateJson, this.configJson, {this.describe, this.apply});

  @override
  final String deviceId;
  final DeviceCodec<S, C> codec;
  Json stateJson;
  Json configJson;
  final Json? describe;

  @override
  S get state => codec.state(stateJson);
  @override
  C get config => codec.config(configJson);

  /// Set jak w urządzeniu (atrapa) - błędy pól.
  final Map<String, String> Function(Json values)? apply;
  final sent = <Json>[];
  final _configs = StreamController<C>.broadcast();

  @override
  ConnectionKind get kind => ConnectionKind.cloud;
  @override
  String get routeDescription => 'chmura';
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<S> get states => const Stream.empty();
  @override
  Stream<C> get configs => _configs.stream;
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => describe;
  @override
  Future<SetResult> sendSet(Json values) async {
    sent.add(values);
    final errors = apply?.call(values) ?? const {};
    if (errors.isEmpty) {
      configJson = {...configJson, ...values};
      _configs.add(config);
    }
    return SetResult(ok: errors.isEmpty, errors: errors);
  }

  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager(this.conns, DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  final Map<String, _Conn<Object?, Object?>> conns;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conns[device.id]! as DeviceConnection<S, C>;
}

class _MemAutomations extends HubAutomations {
  _MemAutomations(DeviceController<Object?, Object?> hub) : super(hub: hub);

  final items = <String, Automation>{};

  @override
  Future<AutomationsInfo> load() async => AutomationsInfo(items: items.values.toList());
  @override
  Future<void> save(Automation a) async => items[a.id] = a;
  @override
  Future<void> remove(String id) async => items.remove(id);
}

/// Dom: hub, zegar i węzeł (przez hub), termostat (poza hubem).
Future<(DeviceHub, Map<String, _Conn>, FakeClock)> _home() async {
  final fake = FakeClock();
  final store = MemoryDeviceStore();
  await store.saveDevice(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub));
  await store.saveDevice(const PairedDevice(id: 'zegar-ab12cd', name: 'Biurko', type: DeviceType.clock, via: 'hub1'));
  await store.saveDevice(const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff, via: 'hub1'));
  await store.saveDevice(const PairedDevice(id: 'sasiad-1', name: 'Sąsiad', type: DeviceType.sensor));
  await store.saveDevice(
    const PairedDevice(id: 'ble-b8f862d84911', name: 'Ogród', type: DeviceType.sensor, via: 'hub1'),
  );
  final conns = <String, _Conn<Object?, Object?>>{
    'hub1': _Conn<Json, Json>('hub1', rawCodec, {'id': 'hub1', 'online': 3, 'devices': 4}, {'name': 'Hub'}),
    'zegar-ab12cd': _Conn<Json, Json>(
      'zegar-ab12cd',
      rawCodec,
      fake.stateJson(),
      fake.configJson(),
      describe: fake.describeJson(),
      apply: fake.applySet,
    ),
    'parter': _Conn<LightState, LightConfig>(
      'parter',
      lightCodec,
      {'id': 'parter', 'on': true, 'temp': 31.4, 'in3': true},
      {'name': 'Parter'},
      describe: {
        'type': 'switch',
        'points': [
          {'key': 'on', 'name': 'Światło', 'kind': 'switch', 'access': 'control'},
          {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1, 'history': 't'},
          {'key': 'in3', 'name': 'Brama', 'kind': 'status'},
        ],
      },
    ),
    'sasiad-1': _Conn<Json, Json>('sasiad-1', rawCodec, {'temp': 12.0}, {'name': 'Sąsiad'}),
    'ble-b8f862d84911': _Conn<Json, Json>(
      'ble-b8f862d84911',
      rawCodec,
      {'temp': 4.2, 'hum': 88},
      {'name': 'Ogród'},
      describe: {
        'type': 'sensor',
        'points': [
          {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
          {'key': 'hum', 'name': 'Wilgotność', 'kind': 'sensor', 'unit': '%'},
          {'key': 'batt', 'name': 'Bateria', 'kind': 'sensor', 'unit': '%'},
        ],
      },
    ),
  };
  final hub = DeviceHub(store: store, manager: _Manager(conns, store), cloud: NoCloudAccess());
  await hub.load();
  return (hub, conns, fake);
}

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  setUpAll(() => ClockTransitionPreview.animate = false);

  test('strony: pary bez powtórzeń, limity, poza siatką, wolne miejsce, JSON tylko z polami zegara', () {
    final page = ClockPage(
      id: 'p1',
      title: 'Dom',
      widgets: [
        const DashWidget(id: 'w1', view: WidgetView.value, device: 'a', point: 'temp').patch({'x': 0, 'y': 0, 'w': 2}),
        const DashWidget(id: 'w2', view: WidgetView.thermostat, device: 't').patch({
          'points': ['temp', 'target'],
          'x': 2,
          'y': 0,
          'w': 2,
          'h': 2,
        }),
        const DashWidget(id: 'w3', view: WidgetView.valueList).patch({
          'items': [
            {'device': 'a', 'point': 'temp'},
            {'device': 'b', 'point': 'hum'},
          ],
          'x': 0,
          'y': 2,
          'w': 4,
        }),
      ],
    );
    expect(clockPairs([page]), {('a', 'temp'), ('t', 'temp'), ('t', 'target'), ('b', 'hum')});
    expect(clockPagesProblems([page]), isEmpty);
    expect(clockFreeSpot(page.widgets, 2, 1), (0, 1));
    expect(clockFreeSpot(page.widgets, 3, 1), isNull);
    expect(clockWidgetJson(page.widgets.first).containsKey('size'), isFalse);

    final wide = page.copyWith(
      widgets: [
        page.widgets.first.patch({'x': 3, 'w': 2}),
      ],
    );
    expect(clockPagesProblems([wide]).single, contains('poza siatką'));
    final many = [for (var i = 0; i < 5; i++) ClockPage(id: 'p$i', title: 'S$i')];
    expect(clockPagesProblems(many), contains('Najwyżej 4 strony.'));
    final pairs = ClockPage(
      id: 'p1',
      title: 'Dużo',
      widgets: [
        for (var i = 0; i < 3; i++)
          DashWidget(id: 'w$i', view: WidgetView.valueList).patch({
            'items': [
              for (var k = 0; k < 9; k++) {'device': 'd$i', 'point': 'p$k'},
            ],
            'x': 0,
            'y': i,
            'w': 4,
          }),
      ],
    );
    expect(clockPagesProblems([pairs]).single, contains('27'));
  });

  test('z pulpitu: sterowanie jako stan, sceny pominięte, 4×4 → 4×3, nowa strona, gdy brak miejsca', () {
    final r = clockPagesFromDashboard(
      [
        const DashWidget(id: 'a', view: WidgetView.thermostat, device: 't').resized(4, 2),
        const DashWidget(id: 'b', view: WidgetView.toggle, device: 'l', point: 'on1', label: 'Pompa').resized(2, 1),
        const DashWidget(id: 'c', view: WidgetView.scene, sceneId: 's', label: 'Kino').resized(2, 1),
        const DashWidget(id: 'd', view: WidgetView.slider, device: 'l', point: 'level').resized(2, 1),
        const DashWidget(id: 'e', view: WidgetView.chart, device: 'l', point: 'temp').resized(4, 4),
      ],
      title: 'Dom',
      newId: () => 'p${DateTime.now().microsecondsSinceEpoch}',
    );
    expect(r.skipped, ['Kino']);
    expect(r.pages, hasLength(2));
    expect(
      [for (final w in r.pages.first.widgets) (w.view, w.x, w.y, clockW(w), clockH(w))],
      [(WidgetView.thermostat, 0, 0, 4, 2), (WidgetView.status, 0, 2, 2, 1), (WidgetView.value, 2, 2, 2, 1)],
    );
    expect((r.pages.last.title, clockH(r.pages.last.widgets.single)), ('Dom 2', 3));
  });

  testWidgets('ekran urządzenia: pokój, rozgrzewanie, pogoda, „Pokaż ekran”, wejścia do ustawień', (tester) async {
    final (hub, conns, fake) = await _home();
    fake.warmup = true;
    conns['zegar-ab12cd']!.stateJson = fake.stateJson();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    expect(clockSummary(fake.stateJson()), 'rozgrzewanie · 46 % · na zewnątrz 9,1 °C');
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: ClockSection(controller: c, hub: hub),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockWarn')), findsOneWidget);
    expect(find.text('Małe zachmurzenie'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockShowScreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockShow-hours')));
    await tester.pumpAndSettle();
    expect(conns['zegar-ab12cd']!.sent.last, {'showScreen': 'hours'});
    expect(find.byKey(const Key('clockPages')), findsOneWidget);
    hub.dispose();
  });

  testWidgets('ekrany: włączenie kalendarza, ×3 na głównym, przejście; noc bez czujnika światła; czujnik', (
    tester,
  ) async {
    final (hub, conns, _) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    final conn = conns['zegar-ab12cd']!;
    await tester.pumpWidget(_app(ClockScreensPage(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockScreenOn-calendar')));
    await tester.pumpAndSettle();
    expect((conn.sent.last['screens'] as Map)['list'], ['main', 'hours', 'days', 'chart', 'calendar']);
    await tester.scrollUntilVisible(
      find.byKey(const Key('clockMainFactor')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('×3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('×3'));
    await tester.pumpAndSettle();
    expect((conn.sent.last['screens'] as Map)['mainFactor'], 3);
    await tester.scrollUntilVisible(
      find.byKey(const Key('clockTransition-cover')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('clockTransition-cover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockTransition-cover')));
    await tester.pumpAndSettle();
    expect((conn.sent.last['screens'] as Map)['transition'], 'cover');

    await tester.pumpWidget(_app(ClockDisplayPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.textContaining('czujnika światła (BH1750)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockRotation')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'display': {'brightness': 80, 'auto': true, 'rotation': 180},
    });

    await tester.pumpWidget(_app(ClockSensorPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.textContaining('surowa 23,2 °C'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockComp')));
    await tester.pumpAndSettle();
    expect((conn.sent.last['sensor'] as Map)['comp'], false);
    // Przełącznik pokazuje nową wartość od razu, bez ponownego wejścia na stronę.
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('clockComp'))).value, false);

    await tester.pumpWidget(_app(ClockTimePage(controller: c)));
    await tester.pumpAndSettle();
    final was = tester.widget<SwitchListTile>(find.byKey(const Key('clockSeconds'))).value;
    await tester.tap(find.byKey(const Key('clockSeconds')));
    await tester.pumpAndSettle();
    expect((conn.sent.last['clock'] as Map)['seconds'], !was);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('clockSeconds'))).value, !was);
    hub.dispose();
  });

  test('czujnik na zewnątrz: punkty temp / hum z describe, domyślne i zastępcze', () {
    const t = DataPoint(key: 'temp', name: 'T', kind: PointKind.sensor, unit: '°C');
    const t2 = DataPoint(key: 'probe', name: 'Sonda', kind: PointKind.sensor, unit: '°C');
    const h = DataPoint(key: 'hum', name: 'W', kind: PointKind.sensor, unit: '%');
    const set = DataPoint(key: 'target', name: 'Nastawa', kind: PointKind.setpoint, unit: '°C');
    expect(clockOutdoorFor('a', const [t2, t, h]), {'device': 'a', 'temp': 'temp', 'hum': 'hum'});
    expect(clockOutdoorFor('a', const [set, t2]), {'device': 'a', 'temp': 'probe', 'hum': ''});
    expect(clockOutdoorTempPoints(const [set, t, h]), [t]);
  });

  testWidgets('pogoda: czujnik na zewnątrz - lista z huba, zapis, wilgotność, błąd pola, powrót do pogody', (
    tester,
  ) async {
    final (hub, conns, fake) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(() async {
      for (final id in conns.keys) {
        await hub.controller(id)!.connect();
      }
    });
    final conn = conns['zegar-ab12cd']!;
    await tester.pumpWidget(_app(ClockWeatherPage(controller: c, hub: hub)));
    await tester.pumpAndSettle();
    expect(find.text('Open-Meteo (internet)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clockOutdoor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockOutdoor-ble-b8f862d84911')), findsOneWidget);
    expect(find.byKey(const Key('clockOutdoor-parter')), findsOneWidget, reason: 'węzeł z temperaturą');
    expect(find.byKey(const Key('clockOutdoor-sasiad-1')), findsNothing, reason: 'poza hubem zegara');
    expect(find.byKey(const Key('clockOutdoor-zegar-ab12cd')), findsNothing, reason: 'nie sam zegar');
    await tester.tap(find.byKey(const Key('clockOutdoor-ble-b8f862d84911')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'outdoor': {'device': 'ble-b8f862d84911', 'temp': 'temp', 'hum': 'hum'},
    });
    expect(find.text('Ogród'), findsOneWidget);
    expect(find.textContaining('Brak odczytu z ostatnich 30 min'), findsOneWidget);

    // Hub przysłał odczyty - ekran pokazuje temperaturę z czujnika.
    fake.applySet({
      'ext': [
        {'device': 'ble-b8f862d84911', 'point': 'temp', 'v': 4.2},
        {'device': 'ble-b8f862d84911', 'point': 'hum', 'v': 88},
      ],
    });
    conn.stateJson = fake.stateJson();
    await tester.pumpWidget(_app(ClockWeatherPage(controller: c, hub: hub)));
    await tester.pumpAndSettle();
    expect(find.text('Teraz 4,2 °C, wilg. 88 %'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clockOutdoorHum')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bez wilgotności').last);
    await tester.pumpAndSettle();
    expect((conn.sent.last['outdoor'] as Map)['hum'], '');

    // Błąd pola przy polu (zły id urządzenia w Config).
    conn.configJson = {
      ...conn.configJson,
      'outdoor': {'device': 'zły id', 'temp': 'temp', 'hum': ''},
    };
    conn._configs.add(conn.config);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockOutdoorHum')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bez wilgotności').last);
    await tester.pumpAndSettle();
    expect(find.text('niedozwolona wartość'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clockOutdoor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockOutdoor-none')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'outdoor': null});
    expect(fake.outdoor, isNull);
    expect(find.text('Open-Meteo (internet)'), findsOneWidget);
    hub.dispose();
  });

  testWidgets('motyw: wybór z miniatur, pora roku, animacje', (tester) async {
    final (hub, conns, _) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    final conn = conns['zegar-ab12cd']!;
    await tester.pumpWidget(_app(ClockThemePage(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockSeasonal')));
    await tester.pumpAndSettle();
    expect((conn.sent.last['theme'] as Map)['seasonal'], true);
    await tester.tap(find.byKey(const Key('clockAnimations')));
    await tester.pumpAndSettle();
    expect((conn.sent.last['theme'] as Map)['animations'], false);
    expect(find.text('Boże Narodzenie (wieczór)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('clockTheme-dark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockTheme-dark')));
    await tester.pumpAndSettle();
    expect((conn.sent.last['theme'] as Map)['name'], 'dark');
    for (final k in ['advent', 'nicholas', 'thaw', 'holidays', 'indianSummer', 'gloom']) {
      await tester.ensureVisible(find.byKey(Key('clockTheme-$k')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('clockTheme-$k')));
      await tester.pumpAndSettle();
      expect((conn.sent.last['theme'] as Map)['name'], k);
    }
    expect(find.text('Babie lato'), findsOneWidget);
    hub.dispose();
  });

  testWidgets('edytor strony: przeniesienie widżetu w siatce, ikony stanu wł. / wył.', (tester) async {
    final (hub, _, _) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    ClockPage? result;
    final page = ClockPage(
      id: 'p1',
      title: 'Dom',
      widgets: [
        const DashWidget(
          id: 'a',
          view: WidgetView.status,
          device: 'parter',
          point: 'on',
          label: 'Pompa',
        ).patch({'x': 0, 'y': 0}),
        const DashWidget(
          id: 'b',
          view: WidgetView.value,
          device: 'parter',
          point: 'temp',
          label: 'Warsztat',
        ).patch({'x': 1, 'y': 0}),
      ],
    );
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context).push<ClockPage>(
              MaterialPageRoute(
                builder: (_) => ClockPageEditor(page: page, hub: hub, known: const {'parter'}, clock: c),
              ),
            ),
            child: const Text('otwórz'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pompa'));
    await tester.pumpAndSettle();
    // Pole zajęte przez drugi widżet jest nieaktywne, wolne przenosi
    await tester.tap(find.byKey(const Key('clockWidgetPos-1-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockWidgetPos-3-2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('clockWidget-iconOn')));
    await tester.tap(find.byKey(const Key('clockWidget-iconOn')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('icon-door-open')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('icon-door-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon-door-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('icon-door-open')), findsNothing, reason: 'wybór ikony zamknięty');
    expect(find.text('Drzwi otwarte'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('clockWidgetOk')));
    await tester.tap(find.byKey(const Key('clockWidgetOk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockWidgetOk')), findsNothing, reason: 'arkusz widżetu zamknięty');
    await tester.tap(find.byKey(const Key('clockPageDone')));
    await tester.pumpAndSettle();
    final a = result!.widgets.firstWhere((w) => w.id == 'a');
    expect((a.x, a.y), (3, 2));
    expect(a.extra['iconOn'], 'door-open');
    expect(a.extra.containsKey('iconOff'), isFalse);
    hub.dispose();
  });

  testWidgets('strony: z pulpitu, opisy z describe przy zapisie, rozwinięty pokój, strona w pokazie; obcy wyszarzony', (
    tester,
  ) async {
    final (hub, conns, _) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(() async {
      for (final id in conns.keys) {
        await hub.controller(id)!.connect();
      }
    });
    final dash = Dashboard(
      id: 'd1',
      name: 'Parter',
      scope: DashboardScope.private,
      widgets: [
        const DashWidget(id: 'a', view: WidgetView.value, device: 'parter', point: 'temp').resized(2, 1),
        const DashWidget(id: 'b', view: WidgetView.toggle, device: 'parter', point: 'on').resized(2, 1),
        const DashWidget(id: 'd', view: WidgetView.value, device: 'sasiad-1', point: 'temp').resized(2, 1),
        const DashWidget(id: 'c', view: WidgetView.room).patch({'room': 'r1'}).resized(4, 1),
      ],
    );
    await tester.pumpWidget(
      _app(
        ClockPagesScreen(
          controller: c,
          hub: hub,
          dashboards: [dash],
          rooms: const [
            Room(id: 'r1', name: 'Warsztat', order: 0, devices: ['parter']),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockFromDashboard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockFromDash-d1')));
    await tester.pumpAndSettle();
    expect(find.text('niedostępne'), findsOneWidget, reason: 'czujnik poza hubem zegara');
    await tester.tap(find.byKey(const Key('clockPagesSave')));
    await tester.pumpAndSettle();

    final sent = conns['zegar-ab12cd']!.sent.last;
    expect((sent['screens'] as Map)['list'], ['main', 'hours', 'days', 'chart', 'page:p1']);
    final widgets = ((sent['pages'] as List).single as Map)['widgets'] as List;
    final byId = <Object?, Map>{for (final w in widgets.cast<Map>()) w['id']: w};
    expect(byId['a'], containsPair('unit', '°C'));
    expect(byId['a'], containsPair('label', 'Parter'));
    expect(byId['b'], containsPair('view', 'status'));
    expect(byId['b'], containsPair('labels', ['wył.', 'wł.']));
    expect(byId['c']!['items'], [
      {'device': 'parter', 'point': 'temp', 'unit': '°C', 'decimals': 1},
    ]);
    expect(byId['c']!['members'], [
      {'device': 'parter', 'point': 'on'},
    ]);
    expect(byId['c']!['label'], 'Warsztat');
    expect(byId['a']!.containsKey('size'), isFalse);
    hub.dispose();
  });

  testWidgets('przyciski zdalne: wejście węzła, podwójnie → kalendarz, automatyka z owner', (tester) async {
    final (hub, conns, _) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(() async {
      await c.connect();
      await hub.controller('parter')!.connect();
    });
    final store = _MemAutomations(hub.controller('hub1')!);
    await tester.pumpWidget(_app(ClockButtonsScreen(controller: c, hub: hub, automations: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockButtonAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockButtonDevice-parter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('podwójnie'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockButtonInput-in3')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('clockButtonAction-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockButtonAction-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockButtonSave')));
    await tester.pumpAndSettle();
    final a = store.items.values.single;
    expect(a.owner, 'zegar-ab12cd');
    expect(a.when.single, {'device': 'parter', 'input': 'in3', 'press': 'double'});
    expect(a.then.single, {
      'device': 'zegar-ab12cd',
      'set': {'showScreen': 'home'},
    });
    expect(a.toJson()['owner'], 'zegar-ab12cd');
    expect(find.textContaining('Parter · in3 · podwójnie'), findsOneWidget);
    hub.dispose();
  });
}
