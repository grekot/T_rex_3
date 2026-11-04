// Pogoda w hubie (pkt 11): model bieżącej pogody i prognozy, ustawienia na ekranie huba (włączenie, miejsce,
// położenie z telefonu), kafelek pogody huba z prognozą, punkty `weather.*` w edytorze automatyk.

import 'dart:async';

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
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/room_store.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/hub.dart';
import 'package:homeautomation/models/hub_weather.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/room.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/provisioning/ble_transport.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/services.dart';
import 'package:homeautomation/ui/automations_screen.dart';
import 'package:homeautomation/ui/dashboard_tiles.dart';
import 'package:homeautomation/ui/hub_screen.dart';
import 'package:homeautomation/ui/widget_editor.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
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

class _MemAutomations extends HubAutomations {
  _MemAutomations(DeviceController<Object?, Object?> hub) : super(hub: hub);

  final items = <String, Automation>{};

  @override
  bool get isLocal => true;
  @override
  Future<AutomationsInfo> load() async => AutomationsInfo(items: items.values.toList());
  @override
  Future<void> save(Automation a) async => items[a.id] = a;
  @override
  Future<void> remove(String id) async => items.remove(id);
}

/// Hub przez chmurę: stan i Config z testu, zapamiętane Set (Config zmienia się jak w hubie).
class _HubConn implements DeviceConnection<Json, Json> {
  _HubConn(this.state, this.config);

  @override
  Json state;
  @override
  Json config;
  final sent = <Json>[];
  Json? describe;
  final _configs = StreamController<Json>.broadcast();

  @override
  String get deviceId => 'hub1';
  @override
  ConnectionKind get kind => ConnectionKind.cloud;
  @override
  String get routeDescription => 'chmura';
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<Json> get states => const Stream.empty();
  @override
  Stream<Json> get configs => _configs.stream;
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => describe;
  @override
  Future<SetResult> sendSet(Json values) async {
    sent.add(values);
    config = {...config, ...values};
    _configs.add(config);
    return const SetResult(ok: true);
  }

  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager(this.conn, DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  final _HubConn conn;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conn as DeviceConnection<S, C>;
}

const _weather = {
  'temp': 4.2,
  'feels': 1.5,
  'hum': 81,
  'wind': 14,
  'gust': 30,
  'icon': 3,
  'day': true,
  'mm': 0.0,
  'rain3h': 1.2,
  'tMin24h': -2.0,
  'place': 'Kraków',
  'age': 420,
};

/// Prognoza od [now]: 48 h co godzinę i 7 dni.
Json _forecast(DateTime now) {
  final start = DateTime(now.year, now.month, now.day, now.hour);
  return {
    'place': 'Kraków',
    'at': now.millisecondsSinceEpoch ~/ 1000,
    'current': _weather,
    'hourly': [
      for (var i = 0; i < 48; i++)
        {
          'ts': start.add(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
          't': 4 + i % 5,
          'icon': i.isEven ? 3 : 4,
          'pp': i * 2,
          'mm': 0.1,
        },
    ],
    'daily': [
      for (var i = 0; i < 7; i++)
        {
          'date': start.add(Duration(days: i)).toIso8601String().substring(0, 10),
          'tMax': 6 + i,
          'tMin': -2 + i,
          'icon': 2,
          'pp': 40,
          'mm': 1.0,
        },
    ],
  };
}

Future<(DeviceHub, _HubConn, MemoryDeviceStore)> _hub(Json state, Json config) async {
  final store = MemoryDeviceStore();
  await store.saveDevice(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub));
  final conn = _HubConn(state, config);
  final hub = DeviceHub(store: store, manager: _Manager(conn, store), cloud: NoCloudAccess());
  return (hub, conn, store);
}

Widget _app(MemoryDeviceStore store, DeviceHub hub, Widget home) => Services(
  store: store,
  discovery: _NoDiscovery(),
  manager: hub.manager,
  pairing: PairingService(store: store),
  cloud: NoCloudAccess(),
  provisioning: _NoBle(),
  rooms: _MemRooms(),
  child: TermostatApp(home: home),
);

void main() {
  test('pogoda ze State huba i prognoza: pola, godziny od teraz, dni od dziś, brak pola = hub bez pogody', () {
    final now = DateTime(2026, 11, 4, 20, 30);
    final w = HubWeatherNow.fromJson(_weather)!;
    expect((w.temp, w.hum, w.icon, w.day, w.rain3h, w.tMin24h, w.place), (4.2, 81, 3, true, 1.2, -2.0, 'Kraków'));
    expect(HubWeatherNow.fromJson(null), isNull);
    expect(hubHasWeather({'id': 'hub1'}), isFalse);
    expect(hubHasWeather({'weather': null}), isTrue, reason: 'pole jest - pogoda wyłączona');

    final f = HubForecast.fromJson(_forecast(now))!;
    expect(f.hourly, hasLength(48));
    expect(f.hoursFrom(now.add(const Duration(hours: 2))).first.ts, DateTime(2026, 11, 4, 22));
    expect(f.daysFrom(now.add(const Duration(days: 1))).first.date, DateTime(2026, 11, 5));
    expect(f.daily.first.tMax, 6);
  });

  testWidgets('ekran huba: pogoda w liście, włączenie z miejscem, bez położenia - okno położenia z GPS telefonu', (
    tester,
  ) async {
    final (hub, conn, store) = await _hub({'id': 'hub1', 'weather': null}, {'name': 'Hub', 'location': null});
    await tester.runAsync(hub.load);
    await tester.pumpWidget(
      _app(
        store,
        hub,
        HubScreen(controller: hub.controller('hub1')!, hub: hub, locate: () async => (lat: 50.06143, lon: 19.93658)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('hubWeather')));
    await tester.pumpAndSettle();
    expect(find.text('Wyłączona - hub może pobierać pogodę i prognozę dla domu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hubWeather')));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('weatherEnabled'))).value, isTrue);
    await tester.enterText(find.byKey(const Key('weatherPlace')), 'Zakopane - Gubałówka, Słoneczna 12');
    await tester.pump();
    expect(find.text('Za długa (najwyżej 32 bajty)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('weatherPlace')), 'Kraków');
    await tester.pump();
    await tester.tap(find.byKey(const Key('weatherOk')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'weather': {'enabled': true, 'place': 'Kraków'},
    });

    // Bez położenia domu od razu okno położenia - z telefonu.
    await tester.tap(find.byKey(const Key('locationGps')));
    await tester.pumpAndSettle();
    expect(find.text('50.061'), findsOneWidget);
    await tester.tap(find.byKey(const Key('locationOk')));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {
      'location': {'lat': 50.061, 'lon': 19.937},
    });
    hub.dispose();
  });

  testWidgets('położenie z telefonu: brak zgody - komunikat w oknie, pola bez zmian', (tester) async {
    final (hub, _, store) = await _hub({'id': 'hub1'}, {'name': 'Hub', 'location': null});
    await tester.runAsync(hub.load);
    await tester.pumpWidget(
      _app(
        store,
        hub,
        HubScreen(
          controller: hub.controller('hub1')!,
          hub: hub,
          locate: () async => throw const ThermostatException('Brak zgody na lokalizację'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hubWeather')), findsNothing, reason: 'hub bez pogody');
    await tester.tap(find.byKey(const Key('hubLocation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locationGps')));
    await tester.pumpAndSettle();
    expect(find.text('Brak zgody na lokalizację'), findsOneWidget);
    hub.dispose();
  });

  testWidgets('kafelek pogody huba: miejsce w tytule, temperatura, opis; prognoza - godziny i dni, wąsko - wiersze', (
    tester,
  ) async {
    final (hub, _, _) = await _hub({'id': 'hub1', 'weather': _weather}, {'name': 'Hub'});
    await tester.runAsync(hub.load);
    final presets = tilePresets(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub), const [], {
      'weather': null,
    });
    expect([for (final p in presets) p.title], containsAll(['Pogoda', 'Pogoda z prognozą']));
    expect(
      tilePresets(const PairedDevice(id: 'hub1', name: 'Hub', type: DeviceType.hub), const [], {'id': 'hub1'}),
      hasLength(1),
      reason: 'hub bez pogody - tylko stan huba',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 170,
              height: 170,
              child: DashTile(
                widget: const DashWidget(id: 'w1', view: WidgetView.weather, device: 'hub1').resized(2, 2),
                hub: hub,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kraków'), findsOneWidget);
    expect(find.text('4,2 °C'), findsOneWidget);
    expect(find.textContaining('Pochmurno · odczuwalna 1,5 °C'), findsOneWidget);

    final now = DateTime(2026, 11, 4, 20, 30);
    final f = HubForecast.fromJson(_forecast(now))!;
    Future<void> view(double w, double h) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: HubForecastView(forecast: f, now: now),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await view(340, 170);
    expect(find.text('20:00'), findsOneWidget, reason: 'godziny co 3 h od bieżącej');
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('Dziś'), findsOneWidget);
    expect(find.text('Cz'), findsOneWidget, reason: '5 listopada 2026 - czwartek');
    expect(find.text('6° -2°'), findsOneWidget);

    await view(340, 64);
    expect(find.text('20:00'), findsNothing, reason: 'nisko - same dni');
    expect(find.text('Dziś'), findsOneWidget);

    await view(150, 80);
    expect(find.text('6° / -2°'), findsOneWidget, reason: 'wąsko - dni w wierszach');
    expect(find.text('Cz'), findsOneWidget);
    expect(find.text('Pt'), findsOneWidget);
    expect(find.text('Sb'), findsNothing, reason: 'tyle wierszy, ile się mieści');
    hub.dispose();
  });

  testWidgets('automatyka: wyzwalacz „najniższa temperatura w 24 h < 0” z punktów pogody huba', (tester) async {
    final (hub, conn, store) = await _hub({'id': 'hub1', 'weather': _weather}, {'name': 'Hub'});
    conn.describe = {
      'type': 'hub',
      'points': [
        {'key': 'runScene', 'name': 'Scena', 'kind': 'action', 'access': 'control'},
        {'key': 'weather.temp', 'name': 'Pogoda: temperatura', 'kind': 'sensor', 'unit': '°C'},
        {'key': 'weather.tMin24h', 'name': 'Najniższa temperatura w 24 h', 'kind': 'sensor', 'unit': '°C'},
      ],
    };
    await tester.runAsync(hub.load);
    final service = _MemAutomations(hub.controller('hub1')!);
    await tester.pumpWidget(
      _app(store, hub, AutomationsScreen(hub: hub, controller: hub.controller('hub1')!, service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newAutomation')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('automationName')), 'Mróz');
    await tester.tap(find.byKey(const Key('addTrigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stan urządzenia').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-device-hub1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auto-point-runScene')), findsNothing, reason: 'z huba tylko pogoda');
    await tester.tap(find.byKey(const Key('auto-point-weather.tMin24h')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('<').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stateValue')), '0');
    await tester.pump();
    await tester.tap(find.byKey(const Key('stateOk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hub: Najniższa temperatura w 24 h < 0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('addAction')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wpis w dzienniku').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Jutro mróz');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('automationSave')));
    await tester.pumpAndSettle();
    expect(service.items.values.single.when.single, {'device': 'hub1', 'point': 'weather.tMin24h', 'lt': 0});
    hub.dispose();
  });

  testWidgets('słońce, księżyc i powietrze: wiersze nad prognozą, gdy zostaje miejsce; bez prognozy - same wiersze', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 4, 20, 30);
    final astro = HubAstro.fromJson({
      'sunrise': '06:41',
      'sunset': '16:12',
      'day': '9:31',
      'dayDelta': -3,
      'moonPhase': 0.38,
      'moonIllum': 86,
      'moonName': 'przybywający garb',
      'fullMoon': '2026-11-07',
    });
    final air = HubAir.fromJson({
      'aqi': 38,
      'aqiLevel': 'umiarkowana',
      'pm25': 12.4,
      'uv': 2.1,
      'pollen': {'alder': 0, 'grass': 4, 'birch': 1},
      'pollenLevel': 'niskie',
    });
    expect(air!.topPollen, 'trawy');
    final f = HubForecast.fromJson(_forecast(now))!;
    Future<void> view(double w, double h, {HubForecast? forecast}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: HubForecastView(forecast: forecast, astro: astro, air: air, now: now),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await view(340, 120, forecast: f);
    expect(find.text('06:41–16:12'), findsOneWidget);
    expect(find.text('86% · pełnia za 3 d'), findsOneWidget);
    expect(find.text('AQI 38 umiarkowana · UV 2 · pyłki niskie (trawy)'), findsOneWidget);
    expect(find.text('Dziś'), findsOneWidget, reason: 'pod wierszami pasek dni');

    await view(340, 70, forecast: f);
    expect(find.byKey(const Key('astroLine')), findsNothing, reason: 'za mało miejsca - pierwszeństwo ma prognoza');
    expect(find.text('Dziś'), findsOneWidget);

    await view(150, 50);
    expect(find.byKey(const Key('astroLine')), findsOneWidget, reason: 'bez prognozy - wiersze');
    expect(find.byKey(const Key('airLine')), findsOneWidget);
  });

  testWidgets('automatyka bez opisu huba: zapasowe punkty pogody, księżyca i powietrza wg State', (tester) async {
    final (hub, _, store) = await _hub(
      {
        'id': 'hub1',
        'astro': {'moonIllum': 86},
        'air': {'aqi': 38},
      },
      {'name': 'Hub'},
    );
    await tester.runAsync(hub.load);
    final service = _MemAutomations(hub.controller('hub1')!);
    await tester.pumpWidget(
      _app(store, hub, AutomationsScreen(hub: hub, controller: hub.controller('hub1')!, service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newAutomation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addTrigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stan urządzenia').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-device-hub1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auto-point-weather.temp')), findsNothing, reason: 'State bez weather');
    expect(find.byKey(const Key('auto-point-astro.fullMoonToday')), findsOneWidget);
    expect(find.byKey(const Key('auto-point-air.aqi')), findsOneWidget);
    expect(find.text('Jakość powietrza (AQI)'), findsOneWidget);
    hub.dispose();
  });

  testWidgets('ekran huba: godzina przypomnień z kalendarza (calendarNotifyAt)', (tester) async {
    final (hub, conn, store) = await _hub({'id': 'hub1'}, {'name': 'Hub', 'calendarNotifyAt': '19:00'});
    await tester.runAsync(hub.load);
    await tester.pumpWidget(_app(store, hub, HubScreen(controller: hub.controller('hub1')!, hub: hub)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('hubCalendarNotifyAt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dzień wcześniej o 19:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hubCalendarNotifyAt')));
    await tester.pumpAndSettle();
    // Zegar: tryb wpisywania i 18:30.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '18');
    await tester.enterText(fields.at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'calendarNotifyAt': '18:30'});
    hub.dispose();
  });
}
