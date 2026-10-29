// Kafelki pulpitu (etap 1 przebudowy): dwie strefy dotyku, kolor wg stanu, natychmiastowa reakcja,
// wszystkie wyjścia węzła, stan wejścia z usterką, plakietki termostatu, arkusz szczegółów.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_hub.dart';
import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/models/thermostat_config.dart';
import 'package:homeautomation/models/thermostat_state.dart';
import 'package:homeautomation/data/history.dart';
import 'package:homeautomation/ui/dashboard_summary.dart';
import 'package:homeautomation/ui/dashboard_tiles.dart';
import 'package:homeautomation/ui/widget_editor.dart';
import 'package:homeautomation/models/home.dart';

import 'support/memory_cloud_store.dart';
import 'package:homeautomation/models/describe.dart';

import 'models_test.dart' show configJson, stateJson;

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

/// Połączenie w pamięci; [hold] wstrzymuje odpowiedź na Set (sprawdzenie natychmiastowej reakcji kafelka).
class _Conn<S, C> implements DeviceConnection<S, C> {
  _Conn(this.deviceId, this.codec, this._state, this._config);

  @override
  final String deviceId;
  final DeviceCodec<S, C> codec;
  Json _state;
  final Json _config;
  final sent = <Json>[];
  Json? describe;
  Completer<void>? hold;
  final _states = StreamController<S>.broadcast();

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
  Stream<S> get states => _states.stream;
  @override
  Stream<C> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => describe;

  @override
  Future<SetResult> sendSet(Json values) async {
    sent.add(values);
    await hold?.future;
    // Węzeł wielokanałowy: `on` = wszystkie kanały.
    final n = _state['channels'];
    final applied = {...values};
    if (n is int && values['on'] is bool) {
      for (var i = 1; i <= n; i++) {
        applied['on$i'] = values['on'];
      }
    }
    _state = {..._state, ...applied};
    _states.add(state);
    return const SetResult(ok: true);
  }

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

void main() {
  late _Conn<LightState, LightConfig> node;
  late _Conn<ThermostatState, ThermostatConfig> thermo;
  late DeviceHub hub;
  late _Conn<Json, Json> hubConn;

  Future<void> setUpHub(WidgetTester tester, {CloudAccess? cloud, Home? home}) async {
    final store = MemoryDeviceStore();
    await store.saveDevice(const PairedDevice(id: 'parter', name: 'Parter', type: DeviceType.onOff));
    await store.saveDevice(const PairedDevice(id: 'termostat-ab12cd', name: 'Salon'));
    await store.saveDevice(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub));
    hubConn = _Conn<Json, Json>(
      'hub1',
      rawCodec,
      {
        'id': 'hub1',
        'devices': 4,
        'online': 3,
        'automations': 2,
        'running': 0,
        'lastRun': {'id': 'zmrok', 'kind': 'automation', 'ok': true, 'at': 1793000000},
        'cloud': false,
      },
      {'name': 'Hub'},
    );
    node =
        _Conn(
            'parter',
            lightCodec,
            {
              'id': 'parter',
              'on': true,
              'channels': 4,
              'on1': true,
              'on2': false,
              'on3': true,
              'on4': false,
              'inputs': 4,
              'in1': false,
              'in2': true,
              'in3': false,
              'in4': false,
              'in3Fault': true,
            },
            {'name': 'Parter'},
          )
          ..describe = {
            'type': 'switch',
            'points': [
              for (final (i, n) in ['Schody', 'Hol', 'Taras', 'Garaż'].indexed)
                {'key': 'on${i + 1}', 'name': n, 'kind': 'switch', 'access': 'control'},
              {'key': 'in2', 'name': 'Łącznik taras', 'kind': 'status'},
              {'key': 'in3', 'name': 'Wejście 3', 'kind': 'status'},
            ],
          };
    thermo = _Conn('termostat-ab12cd', thermostatCodec, {
      ...jsonDecode(stateJson) as Json,
      'heating': true,
    }, jsonDecode(configJson) as Json);
    hub = DeviceHub(
      store: store,
      manager: _Manager({'parter': node, 'termostat-ab12cd': thermo, 'hub1': hubConn}, store),
      cloud: cloud ?? NoCloudAccess(),
      home: home,
    );
    await hub.load();
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, DashWidget w, {double width = 360}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8590C))),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: w.size.rows * dashRowHeight + (w.size.rows - 1) * dashGap,
              child: DashTile(widget: w, hub: hub),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color tileColor(WidgetTester tester) => tester
      .widget<Material>(find.descendant(of: find.byType(TileShell), matching: find.byType(Material)).first)
      .color!;

  testWidgets('jedno wyjście: ikona przełącza od razu (zanim urządzenie odpowie), kolor = stan', (tester) async {
    await setUpHub(tester);
    await show(tester, const DashWidget(id: 'w1', view: WidgetView.toggle, device: 'parter', point: 'on2'));
    expect(find.text('Hol'), findsOneWidget, reason: 'nazwa kanału z describe');
    expect(find.textContaining('Wyłączone'), findsOneWidget);
    final off = tileColor(tester);

    node.hold = Completer<void>();
    await tester.tap(find.byKey(const Key('dash-toggle-w1')));
    await tester.pump();
    expect(find.textContaining('Włączone'), findsOneWidget, reason: 'stan pokazany przed odpowiedzią');
    expect(tileColor(tester), isNot(off), reason: 'włączony kafelek w kolorze akcentu');
    node.hold!.complete();
    await tester.pumpAndSettle();
    expect(node.sent.single, {'on2': true});

    // Dotyk poza ikoną: arkusz szczegółów z pełną kontrolką i przejściem do urządzenia.
    await tester.tap(find.text('Hol'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('point-on2')), findsOneWidget);
    expect(find.byKey(const Key('tileOpenDevice')), findsOneWidget);
  });

  testWidgets('wszystkie wyjścia węzła: kanały z nazwami, „2 z 4”, ikona wyłącza wszystkie, usterka wejścia', (
    tester,
  ) async {
    await setUpHub(tester);
    await show(
      tester,
      const DashWidget(id: 'w2', view: WidgetView.toggle, size: WidgetSize.s2x1, device: 'parter', point: 'on'),
    );
    expect(find.text('2 z 4 włączone'), findsOneWidget);
    expect(find.text('Taras'), findsOneWidget);
    expect(find.text('USTERKA WEJŚCIA'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dash-ch-w2-2')));
    await tester.pumpAndSettle();
    expect(node.sent.last, {'on2': true});
    expect(find.text('3 z 4 włączone'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dash-toggle-w2')));
    await tester.pumpAndSettle();
    expect(node.sent.last, {'on': false});
    expect(find.text('0 z 4 włączone'), findsOneWidget);

    // Kafelek 1×1: same numery kanałów.
    await show(tester, const DashWidget(id: 'w3', view: WidgetView.toggle, device: 'parter', point: 'on'), width: 170);
    expect(find.text('Schody'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('stan wejścia: zwarte / rozwarte, usterka', (tester) async {
    await setUpHub(tester);
    await show(tester, const DashWidget(id: 'w4', view: WidgetView.status, device: 'parter', point: 'in2'));
    expect(find.text('Łącznik taras'), findsOneWidget);
    expect(find.textContaining('Zwarte'), findsOneWidget);
    await show(tester, const DashWidget(id: 'w5', view: WidgetView.status, device: 'parter', point: 'in3'));
    expect(find.text('USTERKA'), findsOneWidget);
    expect(find.textContaining('zablokowane'), findsOneWidget);
  });

  testWidgets('termostat: temperatura, nastawa w drugiej linii, plakietka GRZEJE, + od razu', (tester) async {
    await setUpHub(tester);
    await show(
      tester,
      const DashWidget(id: 'w6', view: WidgetView.thermostat, size: WidgetSize.s2x1, device: 'termostat-ab12cd'),
    );
    expect(find.text('21,4 °C'), findsOneWidget);
    expect(find.text('GRZEJE'), findsOneWidget);
    expect(find.textContaining('nastawa 21,0 °C'), findsOneWidget);
    thermo.hold = Completer<void>();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.textContaining('nastawa 21,5 °C'), findsOneWidget);
    thermo.hold!.complete();
    await tester.pumpAndSettle();
    expect(thermo.sent.single, {'target': 21.5});
  });

  testWidgets('każdy rodzaj w najmniejszym kafelku 1×1 (170 px) - bez przepełnień', (tester) async {
    await setUpHub(tester);
    for (final w in const [
      DashWidget(id: 'a', view: WidgetView.thermostat, device: 'termostat-ab12cd'),
      DashWidget(id: 'b', view: WidgetView.toggle, device: 'parter', point: 'on'),
      DashWidget(id: 'c', view: WidgetView.toggle, device: 'parter', point: 'on1', label: 'Bardzo długa nazwa kanału'),
      DashWidget(id: 'd', view: WidgetView.status, device: 'parter', point: 'in3'),
      DashWidget(id: 'e', view: WidgetView.value, device: 'termostat-ab12cd', point: 'temp'),
      DashWidget(id: 'f', view: WidgetView.value, device: 'termostat-ab12cd', point: 'mode'),
      DashWidget(id: 'g', view: WidgetView.slider, device: 'termostat-ab12cd', point: 'target'),
      DashWidget(id: 'h', view: WidgetView.stepper, device: 'termostat-ab12cd', point: 'target'),
      DashWidget(id: 'i', view: WidgetView.chart, device: 'termostat-ab12cd', point: 'temp'),
      DashWidget(id: 'j', view: WidgetView.thermostat, size: WidgetSize.s2x2, device: 'termostat-ab12cd'),
    ]) {
      await show(tester, w, width: w.size == WidgetSize.s1x1 ? 170 : 360);
      expect(tester.takeException(), isNull, reason: '${w.view} ${w.point}');
    }
  });

  // ---- pkt 13.1: siatka 4 i ustawienia kafelka

  final historyCalls = <(String, String, int)>[];
  Future<List<HistoryPoint>> history(String id, String field, {int hours = 24}) async {
    historyCalls.add((id, field, hours));
    final now = DateTime(2026, 10, 29, 20);
    return [
      for (var i = 0; i <= 24; i++)
        (at: now.subtract(Duration(hours: 24 - i)), value: field == 'heat' ? (i % 6 < 2 ? 1.0 : 0.0) : 20 + i % 3 / 2),
    ];
  }

  Future<void> show4(WidgetTester tester, DashWidget w) async {
    final size = dashTileSize(w, 4, 380);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8590C))),
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: size,
              child: DashTile(widget: w, hub: hub, history: history),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('13.1: kolor, druga linia, rozmiar ikony, napisy stanu, wybrane kanały', (tester) async {
    await setUpHub(tester);
    const on1 = DashWidget(id: 'a', view: WidgetView.toggle, device: 'parter', point: 'on1');
    await show4(tester, on1.resized(2, 2));
    final auto = tileColor(tester);
    await show4(tester, on1.resized(2, 2).patch({'color': 'blue'}));
    expect(tileColor(tester), isNot(auto), reason: 'inny kolor włączonego kafelka');

    await show4(tester, on1.resized(2, 2).patch({'secondary': 'none'}));
    expect(find.textContaining('Włączone'), findsNothing);
    await show4(tester, on1.resized(2, 2).patch({'secondary': 'point:in2'}));
    expect(find.textContaining('Łącznik taras'), findsOneWidget);

    await show4(tester, on1.resized(2, 2).patch({'iconSize': 'l'}));
    expect(tester.getSize(find.byKey(const Key('dash-toggle-a'))), const Size(56, 56));

    await show4(
      tester,
      const DashWidget(id: 'b', view: WidgetView.status, device: 'parter', point: 'in2').resized(2, 1).patch({
        'labels': ['Otwarte', 'Zamknięte'],
      }),
    );
    expect(find.text('Zamknięte'), findsOneWidget);

    await show4(
      tester,
      const DashWidget(id: 'c', view: WidgetView.toggle, device: 'parter', point: 'on').resized(4, 2).patch({
        'points': ['on3', 'on1'],
      }),
    );
    expect(find.text('2 z 2 włączone'), findsOneWidget);
    expect(find.text('Taras'), findsOneWidget);
    expect(find.text('Hol'), findsNothing);
    await tester.tap(find.byKey(const Key('dash-ch-c-3')));
    await tester.pumpAndSettle();
    expect(node.sent.last, {'on3': false});
    // Ikona: tylko wybrane kanały (nie `on` dla wszystkich).
    await tester.tap(find.byKey(const Key('dash-toggle-c')));
    await tester.pumpAndSettle();
    expect(node.sent.last, {'on3': true, 'on1': true}.map((k, v) => MapEntry(k, false)));
  });

  testWidgets('13.1: potwierdzenie przed akcją, dotyk ikony „nic”', (tester) async {
    await setUpHub(tester);
    const w = DashWidget(id: 'd', view: WidgetView.toggle, device: 'parter', point: 'on2');
    await show4(tester, w.resized(2, 2).patch({'confirm': true}));
    await tester.tap(find.byKey(const Key('dash-toggle-d')));
    await tester.pumpAndSettle();
    expect(node.sent, isEmpty, reason: 'najpierw pytanie');
    await tester.tap(find.byKey(const Key('tileConfirm')));
    await tester.pumpAndSettle();
    expect(node.sent.single, {'on2': true});

    await show4(tester, w.resized(2, 2).patch({'iconTap': 'none'}));
    await tester.tap(find.byKey(const Key('dash-toggle-d')));
    await tester.pumpAndSettle();
    expect(node.sent.length, 1);
  });

  testWidgets('13.1: pokrętło - przeciągnięcie po łuku, nastawa wysłana po puszczeniu', (tester) async {
    await setUpHub(tester);
    await show4(
      tester,
      const DashWidget(id: 'e', view: WidgetView.dial, device: 'termostat-ab12cd', point: 'target').resized(4, 3),
    );
    expect(find.text('21,0 °C'), findsOneWidget);
    expect(find.textContaining('teraz 21,4'), findsOneWidget);
    final box = tester.getRect(find.byKey(const Key('dial')));
    final g = await tester.startGesture(Offset(box.left + 20, box.bottom - 14));
    await g.moveTo(Offset(box.center.dx, box.top + 10));
    await g.moveTo(Offset(box.right - 30, box.top + 40));
    await tester.pump();
    expect(thermo.sent, isEmpty, reason: 'w trakcie przeciągania nic nie idzie');
    await g.up();
    await tester.pumpAndSettle();
    final v = thermo.sent.single['target'] as num;
    expect(v, greaterThan(24));
    expect(v * 2 % 1, 0, reason: 'krok 0,5');
  });

  testWidgets('13.1: wskaźnik, tryby w kafelku, wykres z seriami i przełącznikiem zakresu, pasek 4×1', (tester) async {
    await setUpHub(tester);
    await show4(
      tester,
      const DashWidget(id: 'f', view: WidgetView.gauge, device: 'termostat-ab12cd', point: 'hum').resized(2, 2).patch({
        'min': 0,
        'max': 100,
        'zones': [
          [0, 30, 'amber'],
          [30, 60, 'green'],
          [60, 100, 'blue'],
        ],
      }),
    );
    expect(find.byKey(const Key('gauge-f')), findsOneWidget);
    expect(find.text('45 %'), findsOneWidget);

    await show4(
      tester,
      const DashWidget(id: 'g', view: WidgetView.value, device: 'termostat-ab12cd', point: 'temp').resized(4, 2).patch({
        'features': [
          {'type': 'modes', 'point': 'mode'},
        ],
      }),
    );
    await tester.tap(find.byKey(const Key('feat-g-mode-manual')));
    await tester.pumpAndSettle();
    expect(thermo.sent.single, {'mode': 'manual'});

    historyCalls.clear();
    await show4(
      tester,
      const DashWidget(id: 'h', view: WidgetView.chart, device: 'termostat-ab12cd', point: 'temp').resized(4, 3).patch({
        'series': [
          {'device': 'termostat-ab12cd', 'point': 'temp', 'line': 'smooth'},
          {'device': 'termostat-ab12cd', 'point': 'target', 'line': 'step'},
          {'device': 'termostat-ab12cd', 'point': 'heating', 'line': 'band'},
        ],
        'rangeSwitch': true,
        'ref': 21,
      }),
    );
    expect(historyCalls.map((c) => (c.$2, c.$3)), [('t', 24), ('target', 24), ('heat', 24)]);
    await tester.tap(find.byKey(const Key('chartRange-7d')));
    await tester.pumpAndSettle();
    expect(historyCalls.last.$3, 168);

    await show4(
      tester,
      const DashWidget(id: 'i', view: WidgetView.slider, device: 'termostat-ab12cd', point: 'target').resized(4, 1),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget, reason: 'pasek 4×1 - suwak obok nazwy');
  });

  testWidgets('podsumowanie domu: światła, grzanie, alarmy; „Wyłącz wszystkie”', (tester) async {
    await setUpHub(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DashSummary(hub: hub)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 światła'), findsOneWidget);
    expect(find.text('Grzeje · 21,4°'), findsOneWidget);
    expect(find.text('1 alarm'), findsOneWidget, reason: 'usterka wejścia 3 węzła');
    await tester.tap(find.byKey(const Key('summaryLights')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('summaryAllOff')));
    await tester.pumpAndSettle();
    expect(node.sent.single, {'on': false});
  });

  testWidgets('13.1: grupa wyjść - „1 z 2”, ikona wyłącza wszystko, lista z przełącznikami', (tester) async {
    await setUpHub(tester);
    final g = const DashWidget(id: 'gr', view: WidgetView.group, label: 'Parter').resized(2, 2).patch({
      'members': [
        {'device': 'parter', 'point': 'on1'},
        {'device': 'parter', 'point': 'on2'},
      ],
    });
    await show4(tester, g);
    expect(find.text('1 z 2 włączone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dash-toggle-gr')));
    await tester.pumpAndSettle();
    expect(
      node.sent,
      unorderedEquals([
        {'on1': false},
        {'on2': false},
      ]),
    );
    expect(find.text('0 z 2 włączone'), findsOneWidget);
    await tester.tap(find.text('Parter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('groupMember-parter-on2')));
    await tester.pumpAndSettle();
    expect(node.sent.last, {'on2': true});
  });

  testWidgets('13.1: pogoda z termostatu i stan huba', (tester) async {
    await setUpHub(tester);
    await show4(tester, const DashWidget(id: 'we', view: WidgetView.weather, device: 'termostat-ab12cd').resized(2, 2));
    expect(find.text('4,2 °C'), findsOneWidget);
    expect(find.text('Na zewnątrz'), findsOneWidget);
    expect(
      (weatherLabel(3), weatherLabel(803), weatherLabel(4), weatherLabel(611)),
      ('Pochmurno', 'Pochmurno', 'Deszcz', 'Śnieg'),
    );

    await show4(tester, const DashWidget(id: 'hb', view: WidgetView.hub, device: 'hub1').resized(4, 2));
    expect(find.text('3 z 4 urządzeń · 2 automatyk'), findsOneWidget);
    expect(find.text('BEZ CHMURY'), findsOneWidget);
    expect(find.textContaining('Ostatnio: zmrok'), findsOneWidget);
  });

  test('gotowe kafelki: termostat, węzeł wielokanałowy, ściemniacz, hub', () {
    List<String> titles(PairedDevice d, List<DataPoint> points, [Json? state]) => [
      for (final p in tilePresets(d, points, state)) p.title,
    ];
    expect(titles(const PairedDevice(id: 't', name: 'Salon'), const []), [
      'Termostat',
      'Pokrętło nastawy',
      'Temperatura i wilgotność',
      'Wilgotność - wskaźnik',
      'Wykres 24 h',
      'Pogoda',
      'Pogoda z wykresem',
    ]);
    final node = tilePresets(
      const PairedDevice(id: 'p', name: 'Parter', type: DeviceType.onOff),
      const [
        DataPoint(key: 'on1', name: 'Schody', kind: PointKind.switchKind),
        DataPoint(key: 'in2', name: 'Łącznik', kind: PointKind.status),
      ],
      {'channels': 2},
    );
    expect(
      [for (final p in node) (p.title, p.widget.view, p.widget.point, p.widget.gridW, p.widget.gridH)],
      [
        ('Wszystkie wyjścia', WidgetView.toggle, 'on', 4, 2),
        ('Schody', WidgetView.toggle, 'on1', 2, 1),
        ('Kanał 2', WidgetView.toggle, 'on2', 2, 1),
        ('Łącznik', WidgetView.status, 'in2', 2, 1),
      ],
    );
    expect(titles(const PairedDevice(id: 'd', name: 'Lampa', type: DeviceType.dimmer), const []), [
      'Przełącznik',
      'Jasność - pasek',
      'Jasność - pokrętło',
    ]);
    expect(titles(const PairedDevice(id: 'h', name: 'Hub', type: DeviceType.hub), const []), ['Stan huba']);
  });

  testWidgets('kreator grupy: nazwa, wyjścia (kanały węzła osobno), kafelek group 2×2', (tester) async {
    await setUpHub(tester);
    DashWidget? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await Navigator.of(
                context,
              ).push<DashWidget>(MaterialPageRoute(builder: (_) => GroupPickerScreen(hub: hub))),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Parter · Schody'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('groupName')), 'Schody i hol');
    await tester.tap(find.byKey(const Key('groupPick-parter-on1')));
    await tester.tap(find.byKey(const Key('groupPick-parter-on2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('groupDone')));
    await tester.pumpAndSettle();
    expect((result!.view, result!.label, result!.gridW, result!.gridH), (WidgetView.group, 'Schody i hol', 2, 2));
    expect(result!.members.map((m) => m.point), ['on1', 'on2']);
  });

  testWidgets('hub: nazwa ostatniej automatyki z homes/{h}/automations', (tester) async {
    final cloud = MemoryCloudStore()..set('homes/h1/automations/zmrok', {'name': 'Zmrok - światła'});
    await setUpHub(
      tester,
      cloud: TestCloudAccess(cloud, uid: 'u1')..homeOwnerUid = 'u1',
      home: const Home(id: 'h1', name: 'Dom', ownerUid: 'u1'),
    );
    await show4(tester, const DashWidget(id: 'hb', view: WidgetView.hub, device: 'hub1').resized(4, 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ostatnio: Zmrok - światła'), findsOneWidget);
  });
}
