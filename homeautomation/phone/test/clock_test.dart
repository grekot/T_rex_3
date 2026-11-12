// Zegar-termometr `clock` (pkt 10.2): strony z widżetami (pary, limity, miejsce w siatce 4×3, przeniesienie
// z pulpitu), atrapa `FakeClock` przez HTTP (błędy Set jak w kontrakcie), ekran urządzenia, ustawienia, edytor stron
// z opisami z `describe` i rozwinięciem `room`, przyciski zdalne jako automatyki huba z `owner`.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/automation_store.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/radio_browser.dart';
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
import 'package:homeautomation/controllers/field_errors.dart';
import 'package:homeautomation/ui/clock_alarms.dart';
import 'package:homeautomation/ui/clock_buttons.dart';
import 'package:homeautomation/ui/clock_pages.dart';
import 'package:homeautomation/ui/clock_section.dart';
import 'package:homeautomation/ui/automations_screen.dart';
import 'package:homeautomation/ui/clock_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  /// Config z urządzenia po Secie częściowym (np. `alarms` z `null`): pełny obraz jak przysłałby zegar.
  void push(Json cfg) {
    configJson = cfg;
    _configs.add(config);
  }

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
Future<(DeviceHub, Map<String, _Conn>, FakeClock)> _home({FakeClock? clock}) async {
  final fake = clock ?? FakeClock();
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

/// Przewija listę strony, aż [finder] się zbuduje i będzie widoczny (ListView buduje tylko okolice ekranu).
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

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
    await tester.pumpWidget(_app(ClockThemePage(controller: c, loadIndex: () async => [])));
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

  testWidgets('paczki motywów: instalacja z indeksu, wybór motywu z paczki, usunięcie, bez indeksu', (tester) async {
    const url = 'https://ha-firmware.web.app/themes/pokoj-ani-1.0.0.dctp';
    final fake = FakeClock();
    fake.packFiles[url] = {
      'id': 'pokoj-ani',
      'version': '1.0.0',
      'name': 'Pokój Ani',
      'size': 60000,
      'themes': [
        {'id': 'kotki', 'name': 'Kotki'},
        {'id': 'jednorozce', 'name': 'Jednorożce'},
      ],
    };
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    final index = [
      ClockPack.fromJson({
        'id': 'pokoj-ani',
        'name': 'Pokój Ani',
        'version': '1.0.0',
        'url': url,
        'sha256': 'ab' * 32,
        'size': 60000,
        'author': 'Tata',
        'themes': [
          {'id': 'kotki', 'name': 'Kotki'},
        ],
      })!,
    ];
    await tester.pumpWidget(_app(ClockThemePage(controller: c, loadIndex: () async => index)));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Ten zegar nie ma jeszcze paczek.'));
    expect(find.text('Ten zegar nie ma jeszcze paczek.'), findsOneWidget);
    expect(find.textContaining('wolne miejsce: 5,5 MB'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('clockPackInstall-pokoj-ani')));
    await tester.tap(find.byKey(const Key('clockPackInstall-pokoj-ani')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'themePack': {
        'install': {'url': url, 'sha256': 'ab' * 32},
      },
    });
    expect(fake.themePacks!.single['id'], 'pokoj-ani');

    // State po instalacji (zmienne pola przychodzą z kolejnym odczytem stanu)
    hub.dispose();
    final (hub2, conns2, _) = await _home(clock: fake);
    final c2 = hub2.controller('zegar-ab12cd')!;
    await tester.runAsync(c2.connect);
    await tester.pumpWidget(const SizedBox()); // nowa strona, nie stan poprzedniej
    await tester.pumpWidget(_app(ClockThemePage(controller: c2, loadIndex: () async => index)));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Paczka pokoj-ani zainstalowana'));
    expect(find.text('Paczka pokoj-ani zainstalowana'), findsOneWidget);
    expect(find.byKey(const Key('clockPackOffer-pokoj-ani')), findsNothing);
    await _scrollTo(tester, find.byKey(const Key('clockTheme-pokoj-ani/jednorozce')));
    await tester.tap(find.byKey(const Key('clockTheme-pokoj-ani/jednorozce')));
    await tester.pumpAndSettle();
    expect(conns2['zegar-ab12cd']!.sent.last, {
      'theme': {'name': 'pokoj-ani/jednorozce'},
    });
    expect(
      clockThemeLabel('pokoj-ani/jednorozce', ClockPack.listFrom(fake.stateJson()['themePacks'])),
      'Jednorożce (Pokój Ani)',
    );
    await _scrollTo(tester, find.byKey(const Key('clockPackRemove-pokoj-ani')));
    await tester.tap(find.byKey(const Key('clockPackRemove-pokoj-ani')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockPackRemoveOk')));
    await tester.pumpAndSettle();
    expect(fake.themePacks, isEmpty);
    hub2.dispose();

    // Bez indeksu (jeszcze nie opublikowany) i zegar bez paczek
    final (hub3, _, _) = await _home(clock: FakeClock());
    final c3 = hub3.controller('zegar-ab12cd')!;
    await tester.runAsync(c3.connect);
    await tester.pumpWidget(const SizedBox()); // nowa strona, nie stan poprzedniej
    await tester.pumpWidget(_app(ClockThemePage(controller: c3, loadIndex: () async => throw Exception('HTTP 404'))));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.textContaining('Katalog paczek jest niedostępny'));
    expect(find.textContaining('Katalog paczek jest niedostępny'), findsOneWidget);
    hub3.dispose();
    final (hub4, _, _) = await _home(clock: FakeClock(withThemePacks: false));
    final c4 = hub4.controller('zegar-ab12cd')!;
    await tester.runAsync(c4.connect);
    await tester.pumpWidget(const SizedBox()); // nowa strona, nie stan poprzedniej
    await tester.pumpWidget(_app(ClockThemePage(controller: c4, loadIndex: () async => index)));
    await tester.pumpAndSettle();
    expect(find.text('Paczki motywów'), findsNothing);
    hub4.dispose();
  });

  test('paczki motywów: Set theme bez packs, wersje, nazwa motywu z paczki', () {
    expect(clockVersionNewer('1.2.0', '1.1.9'), true);
    expect(clockVersionNewer('1.0', '1.0.0'), false);
    expect(clockThemeLabel('dark', const []), 'Ciemny');
    expect(clockThemeLabel('brak/kotki', const []), 'brak/kotki');
    expect(clockBytesText(60000), '59 KB');
  });

  testWidgets('radio: stacje, włączenie, stacja, głośność, wyciszenie, zaawansowane; bez radia ukryte', (tester) async {
    final fake = FakeClock();
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    Map radio() => conn.sent.last['radio'] as Map;
    await tester.pumpWidget(_app(ClockRadioPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dodaj stację'), findsWidgets);
    expect(find.byKey(const Key('clockRadioOn')), findsNothing);

    await tester.tap(find.byKey(const Key('clockStationAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clockStationName')), 'Radio 357');
    await tester.enterText(find.byKey(const Key('clockStationUrl')), 'stream.radio357.pl');
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    expect(find.text('Adres zaczyna się od https:// albo http://'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('clockStationUrl')), 'https://stream.radio357.pl');
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    expect(radio()['stations'], [
      {'name': 'Radio 357', 'url': 'https://stream.radio357.pl'},
    ]);
    await tester.tap(find.byKey(const Key('clockStationAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clockStationName')), 'Nowy Świat');
    await tester.enterText(find.byKey(const Key('clockStationUrl')), 'https://stream.nowyswiat.online/mp3');
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    expect((fake.radio!['stations'] as List).length, 2);

    // Sterowanie: State z punktami radia (zegar ma już stacje)
    hub.dispose();
    final (hub2, conns2, _) = await _home(clock: fake);
    final conn2 = conns2['zegar-ab12cd']!;
    final c2 = hub2.controller('zegar-ab12cd')!;
    await tester.runAsync(c2.connect);
    await tester.pumpWidget(const SizedBox()); // nowa strona, nie stan poprzedniej
    await tester.pumpWidget(_app(ClockRadioPage(controller: c2)));
    await tester.pumpAndSettle();
    expect(find.text('Wyłączone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockRadioOn')));
    await tester.pumpAndSettle();
    expect(conn2.sent.last, {'radioOn': true});
    expect((fake.radioOn, fake.radioStation), (true, 'Radio 357'));
    await tester.tap(find.byKey(const Key('clockStationPlay-1')));
    await tester.pumpAndSettle();
    expect(conn2.sent.last, {'radioStation': 'Nowy Świat'});
    await tester.drag(find.byKey(const Key('clockRadioVol')), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(conn2.sent.last, {'radioVol': 100});
    expect(fake.applySet({'radioVol': 101}), {'radioVol': 'range'});
    expect(fake.applySet({'radioStation': 'Trójka'}), {'radioStation': 'value'});
    expect(fake.applySet({'radioStation': 'next'}), isEmpty);
    expect(fake.radioStation, 'Radio 357');

    await _scrollTo(tester, find.byKey(const Key('clockRadioResume')));
    await tester.tap(find.byKey(const Key('clockRadioResume')));
    await tester.pumpAndSettle();
    expect((conn2.sent.last['radio'] as Map)['resume'], true);
    await _scrollTo(tester, find.byKey(const Key('clockRadioAdvanced')));
    await tester.tap(find.byKey(const Key('clockRadioAdvanced')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('clockRadioMaxW')));
    await tester.drag(find.byKey(const Key('clockRadioMaxW')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect((conn2.sent.last['radio'] as Map)['maxW'], 0.1);
    expect(
      fake.applySet({
        'radio': {'maxW': 2.0},
      }),
      {'radio.maxW': 'range'},
    );
    expect(
      fake.applySet({
        'radio': {'stations': []},
      }),
      isEmpty,
    );
    expect(fake.applySet({'radioOn': true}), {'radioOn': 'no_stations'});
    hub2.dispose();

    final (hub3, _, _) = await _home(clock: FakeClock(withRadio: false));
    final c3 = hub3.controller('zegar-ab12cd')!;
    await tester.runAsync(c3.connect);
    await tester.pumpWidget(const SizedBox()); // nowa strona, nie stan poprzedniej
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: ClockSection(controller: c3, hub: hub3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockRadio')), findsNothing);
    expect(find.byKey(const Key('clockNews')), findsOneWidget);
    hub3.dispose();
  });

  testWidgets('ekran radia: logo ze „Znajdź logo”, błędny adres logo, czas ekranu, ekran na liście', (tester) async {
    final fake = FakeClock();
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    Map radio() => conn.sent.last['radio'] as Map;
    final asked = <String>[];
    final client = MockClient((req) async {
      asked.add(req.url.toString());
      if (req.url.path == '/json/stations/byurl') {
        return http.Response(
          jsonEncode([
            {'favicon': 'https://radio357.pl/logo.png', 'homepage': ''},
          ]),
          200,
        );
      }
      if (req.url.path == '/json/stations/search') {
        return http.Response(
          jsonEncode([
            {'favicon': 'https://radio357.pl/inne.png'},
          ]),
          200,
        );
      }
      if (req.url.path == '/logo.png') return http.Response.bytes(_png1, 200, headers: {'content-type': 'image/png'});
      if (req.url.path == '/inne.png') return http.Response.bytes(_png2, 200, headers: {'content-type': 'image/png'});
      return http.Response('<html>404</html>', 404, headers: {'content-type': 'text/html'});
    });
    await tester.pumpWidget(
      _app(
        ClockRadioPage(
          controller: c,
          browser: RadioBrowser(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockStationAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clockStationName')), 'Radio 357');
    await tester.enterText(find.byKey(const Key('clockStationUrl')), 'https://stream.radio357.pl');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockStationFindLogo')));
    await tester.pumpAndSettle();
    expect(asked.first, contains('/json/stations/byurl?url=https%3A%2F%2Fstream.radio357.pl'));
    expect(find.byKey(const Key('clockLogoPick-1')), findsOneWidget); // dwa działające, martwe pominięte
    await tester.tap(find.text('PNG 1×1 · 1 KB · radio357.pl').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    expect(radio()['stations'], [
      {'name': 'Radio 357', 'url': 'https://stream.radio357.pl', 'logo': 'https://radio357.pl/logo.png'},
    ]);

    // Zły adres logo blokuje zapis; SVG - ostrzeżenie (zegar pokaże inicjały)
    await tester.tap(find.byKey(const Key('clockStationAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clockStationName')), 'Nowy Świat');
    await tester.enterText(find.byKey(const Key('clockStationUrl')), 'https://stream.nowyswiat.online/mp3');
    await tester.enterText(find.byKey(const Key('clockStationLogo')), 'ftp://nowyswiat.online/logo.png');
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    expect(find.text('Adres zaczyna się od https:// albo http://'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('clockStationLogo')), 'https://nowyswiat.online/logo.svg');
    await tester.pumpAndSettle();
    expect(find.textContaining('tylko PNG i JPG'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('clockStationLogo')), '');
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    expect((radio()['stations'] as List)[1], {'name': 'Nowy Świat', 'url': 'https://stream.nowyswiat.online/mp3'});

    // Czas ekranu radia (Config radio.showS)
    await _scrollTo(tester, find.byKey(const Key('clockRadioShowS')));
    await tester.drag(find.byKey(const Key('clockRadioShowS')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(radio()['showS'], 0);
    expect(
      fake.applySet({
        'radio': {'showS': 121},
      }),
      {'radio.showS': 'range'},
    );
    expect(
      fake.applySet({
        'radio': {
          'stations': [
            {'name': 'A', 'url': 'https://a.pl/stream', 'logo': 'a.png'},
          ],
        },
      }),
      {'radio.stations': 'value'},
    );
    hub.dispose();

    // Model: ekran „radio” tylko przy firmware z showS, stacja bez logo bez pola logo
    expect(
      clockHasRadioScreen({
        'radio': {'stations': [], 'showS': 10},
      }),
      true,
    );
    expect(
      clockHasRadioScreen({
        'radio': {'stations': []},
      }),
      false,
    );
    expect(clockStationJson((name: 'A', url: 'https://a.pl/s', logo: '')), {'name': 'A', 'url': 'https://a.pl/s'});
    expect(
      clockStationsFrom({
        'stations': [
          {'name': 'A', 'url': 'https://a.pl/s', 'logo': 'https://a.pl/l.jpg'},
        ],
      }).single.logo,
      'https://a.pl/l.jpg',
    );
    expect(clockLogoWarning('https://a.pl/favicon.ico'), isNotNull);
    expect(clockLogoWarning('https://a.pl/logo.JPG'), isNull);
    expect(clockScreens['radio'], 'Radio');
  });

  testWidgets('po ręcznej zmianie ekranu: do środkowego przycisku / 5 min, błąd atrapy, ukryte bez holdS', (
    tester,
  ) async {
    final fake = FakeClock();
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    await tester.pumpWidget(_app(ClockScreensPage(controller: c)));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('clockHold')));
    expect(find.text('Do środkowego przycisku'), findsOneWidget);
    expect(find.textContaining('do środkowego przycisku (w rogu ikona pauzy)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockHold')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 min').last);
    await tester.pumpAndSettle();
    expect((conn.sent.last['screens'] as Map)['holdS'], 300);
    expect(fake.screens['holdS'], 300);
    expect(
      fake.applySet({
        'screens': {'holdS': 30},
      }),
      {'screens.holdS': 'range'},
    );
    hub.dispose();

    final old = FakeClock()..screens.remove('holdS');
    final (hub2, _, _) = await _home(clock: old);
    final c2 = hub2.controller('zegar-ab12cd')!;
    await tester.runAsync(c2.connect);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(ClockScreensPage(controller: c2)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockHold')), findsNothing);
    hub2.dispose();
  });

  testWidgets('budzik: karta dzwonienia (drzemka, wyłącz), wyłącznik czasowy radia, kafel ustawień', (tester) async {
    final fake = FakeClock()
      ..radio!['stations'] = [
        {'name': 'Jazz', 'url': 'http://a/jazz'},
      ]
      ..radioOn = true
      ..radioStation = 'Jazz'
      ..alarms![0]['on'] = true
      ..ring(0);
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
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
    expect(find.text('Dzwoni budzik 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockAlarmSnooze')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'alarmSnooze': true});
    expect(fake.snoozeUntil, greaterThan(0));
    expect(fake.alarmRinging, isNull);
    await tester.tap(find.byKey(const Key('clockAlarmStop')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'alarmStop': true});
    expect(fake.snoozeUntil, 0);
    // Wyłącznik czasowy: przy grającym radiu
    await tester.tap(find.byKey(const Key('clockSleep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockSleep-30')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'sleepTimer': 30});
    expect(fake.sleepUntil, greaterThan(0));
    expect(fake.applySet({'sleepTimer': 200}), {'sleepTimer': 'range'});
    expect(find.byKey(const Key('clockAlarms')), findsOneWidget);
    expect(find.text('Budzik 1: 6:30 · pn–pt\nBudzik 2: wył.'), findsOneWidget);
    hub.dispose();

    // Zegar sprzed 0.8.0: bez budzika i wyłącznika
    final old = FakeClock(withAlarms: false)
      ..radio!['stations'] = [
        {'name': 'Jazz', 'url': 'http://a/jazz'},
      ]
      ..radioOn = true;
    final (hub2, _, _) = await _home(clock: old);
    final c2 = hub2.controller('zegar-ab12cd')!;
    await tester.runAsync(c2.connect);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: ClockSection(controller: c2, hub: hub2),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockAlarms')), findsNothing);
    expect(find.byKey(const Key('clockSleep')), findsNothing);
    expect(find.byKey(const Key('clockAlarmCard')), findsNothing);
    hub2.dispose();
  });

  testWidgets('budzik: ekran budzików - włączenie, dni, skrót, dźwięk ze stacji, drzemka, błędy', (tester) async {
    final fake = FakeClock()
      ..radio!['stations'] = [
        {'name': 'Jazz', 'url': 'http://a/jazz'},
      ];
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    await tester.pumpWidget(_app(ClockAlarmsPage(controller: c)));
    await tester.pumpAndSettle();
    // Po każdym Secie zegar przysyła pełny Config (Set budzika jest częściowy)
    Future<void> sync() async {
      conn.push(fake.configJson());
      await tester.pumpAndSettle();
    }

    expect(find.text('Żaden budzik nie jest włączony'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockAlarmOn-0')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'alarms': [
        {'on': true},
        null,
      ],
    });
    expect(fake.alarms![0]['on'], isTrue);
    await sync();
    await tester.tap(find.byKey(const Key('clockAlarmDay-0-3'))); // środa odznaczona
    await tester.pumpAndSettle();
    expect(fake.alarms![0]['days'], [1, 2, 4, 5]);
    await sync();
    await tester.tap(find.byKey(const Key('clockAlarmPreset-0-Weekend')));
    await tester.pumpAndSettle();
    expect(fake.alarms![0]['days'], [6, 7]);
    await sync();
    await tester.tap(find.byKey(const Key('clockAlarmSource-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jazz').last);
    await tester.pumpAndSettle();
    expect(fake.alarms![0]['source'], 'radio');
    expect(fake.alarms![0]['station'], 'Jazz');
    await sync();
    await _scrollTo(tester, find.byKey(const Key('clockAlarmSnooze-0')));
    await tester.tap(find.byKey(const Key('clockAlarmSnooze-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 min').last);
    await tester.pumpAndSettle();
    expect(fake.alarms![0]['snoozeMin'], 15);
    expect(
      fake.applySet({
        'alarms': [
          {'time': '25:00', 'vol': 3},
        ],
      }),
      {'alarms.0.time': 'value', 'alarms.0.vol': 'range'},
    );
    expect(fake.applySet({'alarmSnooze': true}), {'alarmSnooze': 'state'});
    expect(describeErrors({'alarms.0.time': 'value'}), startsWith('Budzik 1 - godzina: '));
    expect(clockAlarmDays([1, 2, 3, 4, 5]), 'pn–pt');
    expect(clockAlarmDays([1, 3]), 'pn, śr');
    expect(clockAlarmDays([]), 'jednorazowo');
    hub.dispose();
  });

  testWidgets('korekcja głośnika: wybór w ustawieniach radia, opis, błąd atrapy, ukryta bez pola eq', (tester) async {
    final fake = FakeClock();
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    await tester.pumpWidget(_app(ClockRadioPage(controller: c)));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('clockRadioEq')));
    expect(find.text(clockRadioEqHints['music']!), findsOneWidget);
    await tester.tap(find.text('Mowa'));
    await tester.pumpAndSettle();
    expect((conn.sent.last['radio'] as Map)['eq'], 'voice');
    expect(fake.radio!['eq'], 'voice');
    expect(find.text(clockRadioEqHints['voice']!), findsOneWidget);
    expect(
      fake.applySet({
        'radio': {'eq': 'bass'},
      }),
      {'radio.eq': 'value'},
    );
    hub.dispose();

    // Starszy firmware (bez radio.eq): wybór ukryty
    final old = FakeClock()..radio!.remove('eq');
    final (hub2, _, _) = await _home(clock: old);
    final c2 = hub2.controller('zegar-ab12cd')!;
    await tester.runAsync(c2.connect);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(ClockRadioPage(controller: c2)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockRadioEq')), findsNothing);
    hub2.dispose();
  });

  testWidgets('Szukaj stacji: filtr MP3, wypełnienie nazwy (limit), strumienia i logo ze strony stacji', (
    tester,
  ) async {
    final fake = FakeClock();
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    final client = MockClient((req) async {
      final p = req.url.path;
      if (p == '/json/stations/search' && req.url.queryParameters['limit'] == '30') {
        expect(req.url.queryParameters['name'], 'Nowy Świat');
        expect(req.headers['User-Agent'], radioBrowserUserAgent);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {'name': 'Radio Nowy Świat AAC', 'url_resolved': 'https://n.pl/aac', 'codec': 'AAC', 'bitrate': 64},
              {
                'name': 'Radio Nowy Świat - Muzyka i Rozmowy',
                'url': 'https://n.pl/stary',
                'url_resolved': 'https://n.pl/mp3',
                'codec': 'MP3',
                'bitrate': 128,
                'countrycode': 'PL',
                'homepage': 'https://nowyswiat.online/',
                'favicon': 'https://nowyswiat.online/stare.png',
              },
            ]),
          ),
          200,
        );
      }
      if (p.startsWith('/json/')) return http.Response('[]', 200);
      if (req.url.host == 'nowyswiat.online' && p == '/') {
        return http.Response('<head><link rel="apple-touch-icon" href="/img/apple.png"></head>', 200);
      }
      if (p == '/img/apple.png') return http.Response.bytes(_png1, 200, headers: {'content-type': 'image/png'});
      return http.Response('nie ma', 404, headers: {'content-type': 'text/html'});
    });
    await tester.pumpWidget(
      _app(
        ClockRadioPage(
          controller: c,
          browser: RadioBrowser(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockStationAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockStationSearch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clockStationQuery')), 'Nowy Świat');
    await tester.tap(find.byKey(const Key('clockStationQueryGo')));
    await tester.pumpAndSettle();
    expect(find.text('Radio Nowy Świat AAC'), findsNothing); // domyślnie tylko MP3
    expect(find.text('Ukryte inne formaty: 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockStationMp3Only')));
    await tester.pumpAndSettle();
    expect(find.textContaining('zegar nie zagra (AAC)'), findsOneWidget);
    await tester.tap(find.text('Radio Nowy Świat - Muzyka i Rozmowy'));
    await tester.pumpAndSettle();
    final name = tester.widget<TextField>(find.byKey(const Key('clockStationName'))).controller!.text;
    expect(utf8.encode(name).length <= 24, true);
    expect(name, startsWith('Radio Nowy Świat'));
    expect(tester.widget<TextField>(find.byKey(const Key('clockStationUrl'))).controller!.text, 'https://n.pl/mp3');
    expect(
      tester.widget<TextField>(find.byKey(const Key('clockStationLogo'))).controller!.text,
      'https://nowyswiat.online/img/apple.png', // martwy favicon z katalogu pominięty, ikona ze strony stacji
    );
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    final st = ((conn.sent.last['radio'] as Map)['stations'] as List).single as Map;
    expect((st['url'], st['logo']), ('https://n.pl/mp3', 'https://nowyswiat.online/img/apple.png'));

    // Ręcznie wpisany martwy adres logo: komunikat i „Zapisz mimo to”
    await tester.tap(find.byKey(const Key('clockStation-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('clockStationLogo')),
      'https://www.rmf.fm/inc/img/favicon/apple-icon-114x114.png?2',
    );
    await tester.tap(find.byKey(const Key('clockStationSave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Logo nie działa: HTTP 404'), findsOneWidget);
    expect(find.text('Zapisz mimo to'), findsOneWidget);
    hub.dispose();
  });

  test('radio-browser: martwy favicon, kandydaci ze strony, formaty, rozmiar, zapasowy serwer, MP3', () async {
    final big = Uint8List.fromList([..._png1, ...List.filled(70 * 1024, 0)]);
    final prog = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xC2, 0, 11, 8, 0, 64, 0, 64, 3, 1, 0, 0, 0, 0]);
    final hosts = <String>[];
    final client = MockClient((req) async {
      final u = req.url;
      if (u.host.endsWith('radio-browser.info')) {
        hosts.add(u.host);
        if (u.host == 'all.api.radio-browser.info') return http.Response('', 503); // zapasowy serwer
        if (u.path == '/json/stations/byurl') {
          return http.Response(
            jsonEncode([
              {
                'name': 'RMF FM',
                'url': 'http://195.150.20.242:8000/rmf_fm',
                'codec': 'MP3',
                'favicon': 'https://www.rmf.fm/inc/img/favicon/apple-icon-114x114.png?2',
                'homepage': 'https://www.rmf.fm/',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      }
      switch (u.path) {
        case '/':
          return http.Response(
            '<html><head><link rel="icon" type="image/svg+xml" href="/i.svg">'
            "<link href='/duze.png' rel='apple-touch-icon' sizes='180x180'>"
            '<link rel="shortcut icon" href="https://cdn.rmf.fm/prog.jpg">'
            '<meta property="og:image" content="/og.jpg&amp;v=2"></head></html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        case '/duze.png':
          return http.Response.bytes(_png2, 200, headers: {'content-type': 'image/png'});
        case '/i.svg':
          return http.Response('<svg/>', 200, headers: {'content-type': 'image/svg+xml'});
        case '/prog.jpg':
          return http.Response.bytes(prog, 200, headers: {'content-type': 'image/jpeg'});
        case '/og.jpg':
          return http.Response.bytes(big, 200, headers: {'content-type': 'image/jpeg'});
        case '/apple-touch-icon.png':
          return http.Response.bytes(_png1, 200, headers: {'content-type': 'image/png'});
        case '/favicon.ico':
          return http.Response.bytes([0, 0, 1, 0], 200, headers: {'content-type': 'image/x-icon'});
      }
      return http.Response('<html>404</html>', 404, headers: {'content-type': 'text/html'});
    });
    final rb = RadioBrowser(client: client);
    final logos = await rb.findLogos(name: 'RMF FM', streamUrl: 'http://195.150.20.242:8000/rmf_fm');
    expect(hosts.first, 'all.api.radio-browser.info');
    expect(hosts, contains('de1.api.radio-browser.info'));
    expect([for (final l in logos) Uri.parse(l.url).path], unorderedEquals(['/duze.png', '/apple-touch-icon.png']));
    expect(pageIconLinks('<link rel="apple-touch-icon" href="/a.png"><meta property="og:image" content="/b.jpg">'), [
      '/a.png',
      '/b.jpg',
    ]);
    expect((await rb.check('https://www.rmf.fm/inc/img/favicon/apple-icon-114x114.png?2')).error, 'HTTP 404');
    expect((await rb.check('https://www.rmf.fm/i.svg')).error, contains('SVG'));
    expect((await rb.check('https://www.rmf.fm/favicon.ico')).error, contains('X-ICON'));
    expect((await rb.check('https://cdn.rmf.fm/prog.jpg')).error, contains('progresywny'));
    expect((await rb.check('https://www.rmf.fm/og.jpg&v=2')).logo, isNull);
    expect((await rb.check('https://www.rmf.fm/og.jpg')).error, contains('za duży'));
    final nothing = RadioBrowser(client: MockClient((_) async => http.Response('', 503)));
    expect(await nothing.findLogos(name: 'X', streamUrl: 'https://x.pl/s'), isEmpty);
    expect(await nothing.search('X'), isEmpty);

    final s = RbStation.fromJson({'name': 'A', 'url': 'http://a/x', 'url_resolved': 'http://a/y', 'codec': 'mp3'});
    expect((s.url, s.mp3), ('http://a/y', true));
    expect(RbStation.fromJson({'name': 'B', 'url': 'http://b', 'codec': 'AAC+'}).mp3, false);
    expect(clockTrimName('Radio Nowy Świat - Muzyka i Rozmowy').length <= 24, true);
    expect(utf8.encode(clockTrimName('ŚŚŚŚŚŚŚŚŚŚŚŚŚŚŚ')).length, 24);
  });

  testWidgets('dymki: wiadomość na zegar z ikoną i odpowiedzią, spotkanie; zegar bez dymków bez przycisków', (
    tester,
  ) async {
    final fake = FakeClock();
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    Widget section(DeviceController<Object?, Object?> c, DeviceHub hub) => _app(
      Scaffold(
        body: SingleChildScrollView(
          child: ClockSection(controller: c, hub: hub),
        ),
      ),
    );
    await tester.pumpWidget(section(c, hub));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockBubbles')), findsOneWidget);
    expect(find.text('3 dziennie, 09:00-20:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clockBubble')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bubbleSend')));
    await tester.pumpAndSettle();
    expect(find.text('Wpisz treść'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('bubbleText')), 'Obiad gotowy!');
    await tester.tap(find.byKey(const Key('bubbleIcon-food')));
    await tester.tap(find.text('Idę!'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bubbleSend')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'bubble': {'text': 'Obiad gotowy!', 'icon': 'food', 'reply': 'Idę!'},
    });
    expect(fake.bubbleShown.single['text'], 'Obiad gotowy!');
    expect(
      fake.applySet({
        'bubble': {'text': 'x', 'id': 'fun'},
      }),
      {'bubble.id': 'value'},
    );
    expect(
      fake.applySet({
        'bubble': {'text': ''},
      }),
      {'bubble.text': 'length'},
    );

    await tester.tap(find.byKey(const Key('clockMeeting')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting-30')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'meeting': 30});
    expect(fake.meetingUntil, isNotNull);
    hub.dispose();

    final (hub2, _, _) = await _home(clock: FakeClock(withBubbles: false));
    final c2 = hub2.controller('zegar-ab12cd')!;
    await tester.runAsync(c2.connect);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(section(c2, hub2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockBubble')), findsNothing);
    expect(find.byKey(const Key('clockMeeting')), findsNothing);
    expect(find.byKey(const Key('clockFun')), findsNothing);
    hub2.dispose();
  });

  testWidgets('dymki i ciekawostki: limit, kategorie, dni, paczka treści z indeksu', (tester) async {
    const url = 'https://ha-firmware.web.app/content/zagadki-dla-dzieci-1.0.0.dccp';
    final fake = FakeClock();
    fake.packFiles[url] = {
      'id': 'zagadki-dla-dzieci',
      'version': '1.0.0',
      'name': 'Zagadki dla dzieci',
      'size': 30000,
      'categories': [
        {'id': 'zagadki', 'name': 'Zagadki', 'count': 80},
      ],
    };
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    await tester.pumpWidget(_app(ClockBubblesPage(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockBubbleMax')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'bubbles': {'vol': 30, 'maxPerDay': 10},
    });

    final index = [
      ClockPack.fromJson({
        'id': 'zagadki-dla-dzieci',
        'name': 'Zagadki dla dzieci',
        'version': '1.0.0',
        'url': url,
        'sha256': 'cd' * 32,
        'size': 30000,
        'categories': [
          {'id': 'zagadki', 'name': 'Zagadki', 'count': 80},
        ],
      })!,
    ];
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(ClockFunPage(controller: c, loadIndex: () async => index)));
    await tester.pumpAndSettle();
    Map fun() => conn.sent.last['fun'] as Map;
    await tester.tap(find.byKey(const Key('clockFunDay-7')));
    await tester.pumpAndSettle();
    expect(fun()['days'], [1, 2, 3, 4, 5, 6]);
    await tester.tap(find.byKey(const Key('clockFunCat-cytaty')));
    await tester.pumpAndSettle();
    expect(fun()['categories'], ['swieta', 'zagadki']);
    await tester.tap(find.byKey(const Key('clockFunCat-cytaty')));
    await tester.pumpAndSettle();
    expect(fun()['categories'], isEmpty, reason: 'wszystkie = []');
    expect(
      fake.applySet({
        'fun': {'window': '20:00-09:00'},
      }),
      {'fun.window': 'format'},
    );

    await _scrollTo(tester, find.byKey(const Key('clockPack-wbudowane')));
    expect(find.byKey(const Key('clockPackRemove-wbudowane')), findsNothing, reason: 'wbudowane nieusuwalne');
    await _scrollTo(tester, find.byKey(const Key('clockPackInstall-zagadki-dla-dzieci')));
    await tester.tap(find.byKey(const Key('clockPackInstall-zagadki-dla-dzieci')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'contentPack': {
        'install': {'url': url, 'sha256': 'cd' * 32},
      },
    });
    expect(fake.contentPacks!.map((p) => p['id']), ['wbudowane', 'zagadki-dla-dzieci']);
    hub.dispose();
  });

  testWidgets('dymki w automatyce: akcja „Dymek na zegarze” i wyzwalacz „Odpowiedź z dymka” z podpowiedzią id', (
    tester,
  ) async {
    final (hub, _, _) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    final store = _MemAutomations(hub.controller('hub1')!);
    await tester.pumpWidget(_app(AutomationEditorScreen(hub: hub, service: store)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addAction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addAction')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dymek na zegarze').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bubbleText')), 'Obiad gotowy!');
    await tester.enterText(find.byKey(const Key('bubbleId')), 'obiad');
    await tester.enterText(find.byKey(const Key('bubbleReply')), 'Idę!');
    await tester.tap(find.byKey(const Key('bubbleSend')));
    await tester.pumpAndSettle();
    expect(find.text('Biurko: dymek „Obiad gotowy!” (odpowiedź „Idę!”)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addTrigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stan urządzenia').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-device-zegar-ab12cd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-point-bubbleReply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bubbleReplyId-obiad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bubbleReplyOk')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('automationName')), 'Obiad');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('automationSave')));
    await tester.pumpAndSettle();
    final a = store.items.values.single;
    expect(a.when.single, {'device': 'zegar-ab12cd', 'point': 'bubbleReply', 'eq': 'obiad'});
    expect(a.then.single, {
      'device': 'zegar-ab12cd',
      'set': {
        'bubble': {'text': 'Obiad gotowy!', 'reply': 'Idę!', 'id': 'obiad'},
      },
    });
    expect(clockBubbleIds([...a.then], 'zegar-ab12cd'), {'obiad'});
    hub.dispose();
  });

  test('radio: dwuklik / przytrzymanie przycisku zegara z radiem koliduje', () {
    final cfg = FakeClock().configJson();
    expect(clockPressCollides(cfg, {'device': 'z', 'input': 'in2', 'press': 'double'}), true);
    expect(clockPressCollides(cfg, {'device': 'z', 'input': 'in1', 'press': 'long'}), true);
    expect(clockPressCollides(cfg, {'device': 'z', 'input': 'in1', 'press': 'short'}), false);
    expect(clockPressCollides(cfg, {'device': 'z', 'input': 'btn1', 'press': 'double'}), false);
    expect(clockPressCollides(FakeClock(withRadio: false).configJson(), {'input': 'in2', 'press': 'double'}), false);
  });

  testWidgets('wiadomości: propozycja, IMGW alarmowy, własny adres z błędem, słowo, przeskok, stan i przeczytane', (
    tester,
  ) async {
    final (hub, conns, fake) = await _home();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
    final conn = conns['zegar-ab12cd']!;
    Map news() => conn.sent.last['news'] as Map;
    await tester.pumpWidget(_app(ClockNewsPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Bez kanałów zegar nic nie pobiera.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clockFeedAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockFeedSuggest-RMF24')));
    await tester.pumpAndSettle();
    expect(news()['feeds'], [
      {'name': 'RMF24', 'url': 'https://www.rmf24.pl/feed', 'alert': false},
    ]);
    expect(news()['keywords'], ['pilne', 'alarm', 'ostrzeżenie', 'ewakuacja']);

    await tester.tap(find.byKey(const Key('clockFeedAdd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockFeedSuggest-RMF24')), findsNothing);
    await tester.tap(find.byKey(const Key('clockFeedImgw')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clockFeedTeryt')), '1201');
    await tester.pumpAndSettle();
    expect(find.text('powiat bocheński'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockFeedSave')));
    await tester.pumpAndSettle();
    expect((news()['feeds'] as List).last, {'name': 'IMGW', 'imgw': '1201', 'alert': true});
    expect(find.text('Ostrzeżenia IMGW · bocheński (1201)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clockFeedAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockFeedOwn')));
    await tester.pumpAndSettle();
    final sent = conn.sent.length;
    await tester.enterText(find.byKey(const Key('clockFeedName')), 'Mój');
    await tester.enterText(find.byKey(const Key('clockFeedUrl')), 'ftp://x.pl/rss');
    await tester.tap(find.byKey(const Key('clockFeedSave')));
    await tester.pumpAndSettle();
    expect(find.text('Adres zaczyna się od https:// albo http://'), findsOneWidget);
    expect(conn.sent.length, sent);
    await tester.enterText(find.byKey(const Key('clockFeedUrl')), 'https://example.com/rss');
    await tester.tap(find.byKey(const Key('clockFeedSave')));
    await tester.pumpAndSettle();
    expect((news()['feeds'] as List).length, 3);

    await tester.tap(find.byKey(const Key('clockFeedAlert-0')));
    await tester.pumpAndSettle();
    expect(((news()['feeds'] as List)[0] as Map)['alert'], true);
    await tester.tap(find.byKey(const Key('clockFeedRemove-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockFeedRemoveOk')));
    await tester.pumpAndSettle();
    expect((news()['feeds'] as List).length, 2);
    expect(fake.news!['feeds'], news()['feeds']);

    await tester.ensureVisible(find.byKey(const Key('clockKeywordAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockKeywordAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clockKeywordField')), 'burz');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(news()['keywords'], ['pilne', 'alarm', 'ostrzeżenie', 'ewakuacja', 'burz']);
    await tester.tap(
      find.descendant(of: find.byKey(const Key('clockKeyword-alarm')), matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();
    expect(news()['keywords'], ['pilne', 'ostrzeżenie', 'ewakuacja', 'burz']);

    await tester.ensureVisible(find.byKey(const Key('clockNewsJump')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockNewsJump')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tylko pasek').last);
    await tester.pumpAndSettle();
    expect(news()['jumpS'], 0);
    expect(
      fake.applySet({
        'news': {'jumpS': 5},
      }),
      {'news.jumpS': 'range'},
    );
    hub.dispose();
  });

  testWidgets('wiadomości: stan z zegara, błąd kanału, przeczytane; podsumowanie w ustawieniach', (tester) async {
    final fake = FakeClock()
      ..applySet({
        'news': {
          'feeds': [
            {'name': 'Onet', 'url': 'https://wiadomosci.onet.pl/.feed'},
            {'name': 'IMGW', 'imgw': '1201', 'alert': true},
          ],
        },
      })
      ..newsUnread = 2;
    final (hub, conns, _) = await _home(clock: fake);
    final conn = conns['zegar-ab12cd']!;
    conn.stateJson = {
      ...fake.stateJson(),
      'news': {
        'items': 9,
        'age': 120,
        'errors': [
          {'name': 'Onet', 'error': 'HTTP 404'},
        ],
        'alert': {'title': 'Burze z gradem', 'source': 'IMGW', 'ts': 1794329340, 'alert': true},
      },
    };
    conn.configJson = fake.configJson();
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
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
    expect(find.text('2 kanały, alarmowe: 1'), findsOneWidget);
    await tester.pumpWidget(_app(ClockNewsPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('9 wiadomości'), findsOneWidget);
    expect(find.text('pobrane 2 min temu'), findsOneWidget);
    expect(find.text('HTTP 404'), findsOneWidget);
    expect(find.text('Burze z gradem'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockNewsRead')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'newsRead': true});
    expect(fake.newsUnread, 0);
    hub.dispose();
  });

  testWidgets('wiadomości: zegar bez news - wpis wyszarzony, bez ekranu news', (tester) async {
    final (hub, _, _) = await _home(clock: FakeClock(withNews: false));
    final c = hub.controller('zegar-ab12cd')!;
    await tester.runAsync(c.connect);
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
    expect(find.text('Wymaga nowszego firmware zegara'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('clockNews'))).enabled, false);
    await tester.pumpWidget(_app(ClockScreensPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockScreen-news')), findsNothing);
    expect(find.byKey(const Key('clockScreen-air')), findsOneWidget);
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
    expect(find.byKey(const Key('clockButtonRadioWarning')), findsNothing);
    // Dwuklik przycisku samego zegara z radiem: zegar przełączy też stację
    await tester.tap(find.byKey(const Key('clockButtonDevice-zegar-ab12cd')));
    await tester.pumpAndSettle();
    expect(find.text(clockRadioPressWarning), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockButtonDevice-parter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockButtonRadioWarning')), findsNothing);
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

/// Prawidłowy PNG 1×1 (podgląd w testach) i ten sam obraz z dopiskiem za IEND (inny plik, ten sam nagłówek).
final _png1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
final _png2 = Uint8List.fromList([..._png1, 1, 2, 3]);
