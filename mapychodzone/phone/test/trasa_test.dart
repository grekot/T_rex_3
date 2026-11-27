import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapychodzone/trasa/brouter.dart';
import 'package:mapychodzone/trasa/trasa.dart';

void main() {
  group('sumaPrzewyzszen', () {
    test('liczy podejścia i zejścia', () {
      expect(sumaPrzewyzszen([100, 150, 120, 200]), (130.0, 30.0));
    });

    test('pomija szum poniżej progu', () {
      expect(sumaPrzewyzszen([100, 102, 99, 103, 100, 104]), (0.0, 0.0));
    });

    test('powolny wzrost małymi krokami też się liczy', () {
      expect(sumaPrzewyzszen([100, 103, 106, 109, 112]).$1, 12.0);
    });

    test('za mało punktów', () {
      expect(sumaPrzewyzszen([500]), (0.0, 0.0));
    });
  });

  group('czasPrzejscia (DIN 33466)', () {
    test('płasko: 4 km/h', () {
      expect(czasPrzejscia(dlugoscM: 8000, podejsciaM: 0, zejsciaM: 0), const Duration(hours: 2));
    });

    test('poziomo dłużej: większy + połowa mniejszego', () {
      // 12 km = 3 h, 600 m w górę = 2 h → 3 + 1 = 4 h
      expect(czasPrzejscia(dlugoscM: 12000, podejsciaM: 600, zejsciaM: 0), const Duration(hours: 4));
    });

    test('pionowo dłużej', () {
      // 4 km = 1 h, 900 m w górę = 3 h, 500 m w dół = 1 h → 4 + 0,5 = 4,5 h
      expect(czasPrzejscia(dlugoscM: 4000, podejsciaM: 900, zejsciaM: 500), const Duration(minutes: 270));
    });
  });

  test('odlegloscM: stopień szerokości to ok. 111 km', () {
    expect(odlegloscM(49, 20, 50, 20), closeTo(111195, 50));
  });

  test('trasa z BRoutera: Koninki → Turbacz', () {
    final t = Trasa.zGeojsonBRoutera(File('test/dane/brouter_koninki_turbacz.geojson').readAsStringSync());
    // BRouter podaje track-length 9506 m i plain-ascend 465 m (Turbacz 1310 m)
    expect(t.dlugosc, closeTo(9506, 30));
    expect(t.najwyzej, closeTo(1310, 5));
    expect(t.podejscia, greaterThan(465));
    expect(t.podejscia, lessThan(800));
    expect(t.punkty.first.odStartu, 0);
    // trasa przez Tobołów ma po drodze zejście (ok. 260 m), więc DIN daje ok. 4 h
    expect(t.zejscia, inInclusiveRange(200, 320));
    expect(t.czas, czasPrzejscia(dlugoscM: t.dlugosc, podejsciaM: t.podejscia, zejsciaM: t.zejscia));
    expect(t.czas.inMinutes, inInclusiveRange(200, 280));
    final geo = t.geojson['features'] as List;
    expect(((geo.first as Map)['geometry'] as Map)['type'], 'LineString');
  });

  test('opisy liczb', () {
    expect(opisDlugosci(850), '850 m');
    expect(opisDlugosci(9506), '9,51 km');
    expect(opisDlugosci(12440), '12,4 km');
    expect(opisCzasu(const Duration(minutes: 45)), '45 min');
    expect(opisCzasu(const Duration(minutes: 185)), '3 h 05 min');
  });

  test('błędy BRoutera po polsku', () {
    expect(opisBleduBRoutera('position not mapped in existing datafile'), contains('poza pobranymi'));
    expect(opisBleduBRoutera('datafile E25_N45.rd5 not found'), contains('poza pobranymi'));
  });
}
