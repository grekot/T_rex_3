// Dwa źródła pogody w hubie (pkt 11, hub 0.3.43+): model porównania, ekran „Porównanie prognoz” (telefon i szerokie
// okno komputera).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/hub_api.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:homeautomation/models/hub_weather.dart';
import 'package:homeautomation/models/weather_compare.dart';
import 'package:homeautomation/ui/weather_compare_screen.dart';

import 'support/weather_compare_data.dart';

final _now = DateTime(2026, 11, 19, 14, 30);

Future<void> _pump(
  WidgetTester tester,
  Future<WeatherCompare> Function() load, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: WeatherCompareScreen(load: load, now: () => _now),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('porównanie: oba źródła, MET bez porywów i szansy opadu, różnica temperatur, opad 24 h', () {
    final c = WeatherCompare.fromJson(compareJson(_now, source: 'metno', active: 'openmeteo'))!;
    expect((c.source, c.active), ('metno', 'openmeteo'));
    final om = c.sources['openmeteo']!, met = c.sources['metno']!;
    expect((om.hourly.length, om.daily.length, met.hourly.length), (24, 7, 24));
    expect((om.current!.gust, met.current!.gust, met.hourly.first.pp, met.daily.first.pp), (30.0, null, null, null));
    expect(om.hourly.first.ts, DateTime(2026, 11, 19, 14));
    expect((om.daily.first.date, om.daily.first.tMin, om.daily.first.tMax), (DateTime(2026, 11, 19), -2.0, 6.0));
    expect(met.next, isNotNull);
    expect(om.rain24h, 1.2);
    final d = compareHourlyTemp(om, met)!;
    expect((d.mean, d.max), (1.0, 1.0));

    final only = WeatherCompare.fromJson(compareJson(_now, met: false))!;
    expect(only.sources.keys, ['openmeteo']);
    expect(WeatherCompare.fromJson('x'), isNull);
  });

  test('GET /api/weather/compare: dane, 404 weather_off, starszy hub bez porównania', () async {
    HubApi hub(int status, Object body) {
      final client = MockClient((r) async {
        expect((r.method, r.url.path), ('GET', '/api/weather/compare'));
        return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
      });
      return HubApi(LocalApi(const LocalEndpoint('192.168.68.125'), token: 't', client: client));
    }

    final c = await hub(200, compareJson(_now, active: 'metno')).weatherCompare();
    expect((c.active, c.sources.length), ('metno', 2));
    await expectLater(hub(404, {'error': 'weather_off'}).weatherCompare(), throwsA(isA<WeatherOffException>()));
    await expectLater(
      hub(404, {'error': 'not_found'}).weatherCompare(),
      throwsA(isA<ThermostatException>().having((e) => e is WeatherOffException, 'weather_off', isFalse)),
    );
  });

  test('źródło w State i prognozie; nazwy źródeł', () {
    expect(HubWeatherNow.fromJson({'source': 'metno', 'temp': 1})!.source, 'metno');
    expect(HubWeatherNow.fromJson({'temp': 1})!.source, isNull, reason: 'hub przed 0.3.43');
    expect(HubForecast.fromJson({'source': 'metno'})!.source, 'metno');
    expect(
      [weatherSourceName('openmeteo'), weatherSourceName('metno'), weatherSourceName(null)],
      ['Open-Meteo', 'MET Norway (yr.no)', 'Open-Meteo'],
    );
  });

  testWidgets('ekran porównania: teraz, różnica, wykres, 24 h i 7 dni; zapas - ostrzeżenie', (tester) async {
    await _pump(tester, () async => WeatherCompare.fromJson(compareJson(_now, source: 'metno', active: 'openmeteo'))!);
    expect(find.text('Zegary i kafelki: Open-Meteo'), findsOneWidget);
    expect(find.byKey(const Key('compareFallback')), findsOneWidget);
    expect(find.text('4,0 °C'), findsOneWidget);
    expect(find.text('5,0 °C'), findsWidgets);
    expect(find.byKey(const Key('compareNow-metno')), findsOneWidget);
    expect(find.textContaining('średnio 1,0 °C'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('compareChart')), 300);
    await tester.scrollUntilVisible(find.byKey(const Key('compareHours')), 300);
    expect(find.byKey(const Key('compareColumns')), findsNothing, reason: 'telefon - jedna kolumna');
    await tester.scrollUntilVisible(find.byKey(const Key('compareDays')), 300);
    expect(find.text('cz 19.11'), findsOneWidget);
  });

  testWidgets('szerokie okno (komputer): 24 h i 7 dni w dwóch kolumnach', (tester) async {
    await _pump(tester, () async => WeatherCompare.fromJson(compareJson(_now))!, size: const Size(1280, 900));
    expect(find.byKey(const Key('compareColumns')), findsOneWidget);
    expect(find.byKey(const Key('compareFallback')), findsNothing);
    final hours = tester.getTopLeft(find.byKey(const Key('compareHours')));
    final days = tester.getTopLeft(find.byKey(const Key('compareDays')));
    expect(days.dx, greaterThan(hours.dx + 400));
  });

  testWidgets('pogoda wyłączona: komunikat; odświeżenie pobiera ponownie', (tester) async {
    var calls = 0;
    await _pump(tester, () async {
      calls++;
      throw const WeatherOffException();
    });
    expect(find.byKey(const Key('compareError')), findsOneWidget);
    expect(find.text('Hub nie ma pogody - włącz ją i ustaw położenie domu.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('compareReload')));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
