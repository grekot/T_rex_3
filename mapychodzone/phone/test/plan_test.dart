import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapychodzone/mapa/punkty_nazwane.dart';
import 'package:mapychodzone/trasa/plan.dart';
import 'package:mapychodzone/trasa/trasa.dart';

/// Prosta trasa na wschód wzdłuż równoleżnika 49,5°: punkty co 0,001° długości (ok. 72 m),
/// wysokość rośnie do połowy i maleje.
Trasa trasaProsta(int n) {
  final punkty = <PunktTrasy>[];
  double suma = 0;
  for (var i = 0; i < n; i++) {
    final lon = 20.0 + i * 0.001;
    if (i > 0) suma += odlegloscM(49.5, punkty.last.lon, 49.5, lon);
    final h = 500.0 + (i < n / 2 ? i * 10 : (n - i) * 10);
    punkty.add(PunktTrasy(lon, 49.5, h, suma));
  }
  return Trasa(punkty);
}

void main() {
  group('PlanTrasy', () {
    test('start, cel, a kolejny punkt przedłuża trasę (stary cel = przystanek)', () {
      var plan = const PlanTrasy().dodajNaKoncu(20.0, 49.5);
      expect(plan.punkty.single.rodzaj, RodzajPunktu.start);
      plan = plan.dodajNaKoncu(20.1, 49.5);
      expect(plan.punkty.map((p) => p.rodzaj), [RodzajPunktu.start, RodzajPunktu.cel]);
      plan = plan.dodajNaKoncu(20.2, 49.5);
      expect(plan.punkty.map((p) => p.rodzaj), [RodzajPunktu.start, RodzajPunktu.przystanek, RodzajPunktu.cel]);
      expect(plan.numerPrzystanku(1), 1);
      expect(plan.indeksyCelow, [1, 2]);
    });

    test('punkt „przez” nie jest celem i nie ma numeru', () {
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5)
          .dodajNaKoncu(20.2, 49.5)
          .wstaw(20.1, 49.51, RodzajPunktu.przez);
      expect(plan.punkty.map((p) => p.rodzaj), [RodzajPunktu.start, RodzajPunktu.przez, RodzajPunktu.cel]);
      expect(plan.indeksyCelow, [2]);
      expect(plan.numerPrzystanku(1), isNull);
    });

    test('wstawianie bez trasy: tam, gdzie najmniejszy objazd', () {
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5)
          .dodajNaKoncu(20.1, 49.5)
          .dodajNaKoncu(20.2, 49.5)
          .wstaw(20.15, 49.501, RodzajPunktu.przystanek);
      expect(plan.punkty.map((p) => p.lon), [20.0, 20.1, 20.15, 20.2]);
    });

    test('wstawianie po trasie: decyduje najbliższy kawałek policzonej trasy', () {
      final trasa = trasaProsta(201); // 20,0 … 20,2
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5)
          .dodajNaKoncu(20.1, 49.5)
          .dodajNaKoncu(20.2, 49.5)
          .wstaw(20.05, 49.5005, RodzajPunktu.przez, trasa: trasa);
      expect(plan.punkty.map((p) => p.lon), [20.0, 20.05, 20.1, 20.2]);
    });

    test('usunięcie startu: następny punkt zostaje startem', () {
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5)
          .dodajNaKoncu(20.1, 49.5)
          .dodajNaKoncu(20.2, 49.5)
          .usun(0);
      expect(plan.punkty.map((p) => p.rodzaj), [RodzajPunktu.start, RodzajPunktu.cel]);
    });

    test('zmiana rodzaju tylko dla punktów pośrednich', () {
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5)
          .dodajNaKoncu(20.1, 49.5)
          .dodajNaKoncu(20.2, 49.5);
      expect(plan.zmienRodzaj(1, RodzajPunktu.przez).punkty[1].rodzaj, RodzajPunktu.przez);
      expect(plan.zmienRodzaj(0, RodzajPunktu.przez).punkty[0].rodzaj, RodzajPunktu.start);
      expect(plan.zmienRodzaj(2, RodzajPunktu.przez).punkty[2].rodzaj, RodzajPunktu.cel);
    });

    test('tryby trasy przekazują BRouterowi siłę trzymania się szlaków', () {
      expect(TrybTrasy.szlakami.parametryBRoutera, {'hiking_routes_preference': '5.0'});
      // najkrócej: bez kary za trudność ścieżki (inaczej omijał krótkie podejście T3 na Modyń)
      expect(TrybTrasy.najkrocej.parametryBRoutera, {'hiking_routes_preference': '0.0', 'SAC_K1': '0', 'SAC_K2': '0'});
    });

    test('unikanie stromych dokłada koszt podejść ponad 15 %, bez kary za zejścia', () {
      expect(parametryTrasy(TrybTrasy.szlakami), {'hiking_routes_preference': '5.0'});
      final p = parametryTrasy(TrybTrasy.szlakiISkroty, unikajStromych: true);
      expect(p['hiking_routes_preference'], '1.0');
      expect(p['consider_elevation'], '1');
      expect(p['uphillcutoffvalue'], '15');
      expect(p['downhillcostvalue'], '0');
    });

    test('przesunięcie punktu: rodzaj zostaje, nazwa z nowego miejsca', () {
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5, nazwa: 'Koninki')
          .dodajNaKoncu(20.2, 49.5)
          .wstaw(20.1, 49.51, RodzajPunktu.przystanek, nazwa: 'Schronisko');
      final po = plan.przesun(1, 20.12, 49.52);
      expect(po.punkty.map((p) => p.rodzaj), [RodzajPunktu.start, RodzajPunktu.przystanek, RodzajPunktu.cel]);
      expect(po.punkty[1].lon, 20.12);
      expect(po.punkty[1].nazwa, isNull);
      expect(po.punkty[0].nazwa, 'Koninki');
      expect(plan.przesun(0, 20.01, 49.5, nazwa: 'Start').punkty.first.rodzaj, RodzajPunktu.start);
      expect(identical(plan.przesun(5, 0, 0), plan), isTrue);
    });
  });

  group('odcinki', () {
    test('przystanek dzieli trasę, punkt „przez” nie', () {
      final trasa = trasaProsta(201);
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5)
          .dodajNaKoncu(20.2, 49.5)
          .wstaw(20.05, 49.5, RodzajPunktu.przez, trasa: trasa)
          .wstaw(20.12, 49.5, RodzajPunktu.przystanek, trasa: trasa);
      expect(plan.punkty.map((p) => p.rodzaj),
          [RodzajPunktu.start, RodzajPunktu.przez, RodzajPunktu.przystanek, RodzajPunktu.cel]);
      final o = odcinki(trasa, plan);
      expect(o.length, 2);
      expect(o[0].odIndeksu, 0);
      expect(o[0].doIndeksu, 2);
      expect(o[1].doIndeksu, 3);
      expect(o[0].dlugosc + o[1].dlugosc, closeTo(trasa.dlugosc, 1));
      expect(o[0].dlugosc, closeTo(trasa.punkty[120].odStartu, 80));
      // do połowy trasy (indeks 100) w górę, potem w dół
      expect(o[0].podejscia, greaterThan(900));
      expect(o[1].podejscia, 0);
    });

    test('trasa tam i z powrotem: przystanek bierze pierwsze przejście', () {
      final tam = trasaProsta(101).punkty;
      final punkty = [...tam];
      for (final p in tam.reversed.skip(1)) {
        punkty.add(PunktTrasy(p.lon, p.lat, p.wysokosc, punkty.last.odStartu + odlegloscM(49.5, punkty.last.lon, 49.5, p.lon)));
      }
      final trasa = Trasa(punkty);
      final plan = PlanTrasy([
        const PunktPlanu(20.0, 49.5, RodzajPunktu.start),
        const PunktPlanu(20.1, 49.5, RodzajPunktu.przystanek),
        const PunktPlanu(20.0, 49.5, RodzajPunktu.cel),
      ]);
      expect(indeksyNaTrasie(trasa, plan.punkty), [0, 100, 200]);
    });
  });

  test('nazwy z warstwy punktów: najbliższy obiekt, szczyt przed wiatą', () {
    final n = PunktyNazwane.zGeojson('{"type":"FeatureCollection","features":['
        '{"type":"Feature","properties":{"t":"wiata","n":"Wiata","r":4},"geometry":{"type":"Point","coordinates":[20.1001,49.5]}},'
        '{"type":"Feature","properties":{"t":"szczyt","n":"Turbacz","e":1310,"r":1},"geometry":{"type":"Point","coordinates":[20.1003,49.5]}},'
        '{"type":"Feature","properties":{"t":"zrodlo","r":4},"geometry":{"type":"Point","coordinates":[20.1,49.5]}}]}');
    expect(n.najblizszy(20.1, 49.5)?.opis, 'Turbacz (1310 m)');
    expect(n.najblizszy(20.2, 49.5), isNull);
  });

  test('prawdziwa trasa BRoutera dzieli się na odcinki', () {
    final trasa = Trasa.zGeojsonBRoutera(File('test/dane/brouter_koninki_turbacz.geojson').readAsStringSync());
    final srodek = trasa.punkty[trasa.punkty.length ~/ 2];
    final plan = PlanTrasy([
      PunktPlanu(trasa.punkty.first.lon, trasa.punkty.first.lat, RodzajPunktu.start),
      PunktPlanu(srodek.lon, srodek.lat, RodzajPunktu.przystanek),
      PunktPlanu(trasa.punkty.last.lon, trasa.punkty.last.lat, RodzajPunktu.cel),
    ]);
    final o = odcinki(trasa, plan);
    expect(o.length, 2);
    expect(o[0].dlugosc + o[1].dlugosc, closeTo(trasa.dlugosc, 1));
  });

  group('powrót tą samą drogą', () {
    test('ślad tam i z powrotem: dwa razy dłuższy, kończy się na starcie', () {
      final tam = trasaProsta(101);
      final tamIZ = tam.zPowrotem();
      expect(tamIZ.punkty.length, 201);
      expect(tamIZ.dlugosc, closeTo(2 * tam.dlugosc, 0.5));
      expect(tamIZ.punkty.last.lon, tam.punkty.first.lon);
      expect(tamIZ.podejscia, closeTo(tam.podejscia + tam.zejscia, 1));
    });

    test('odcinki: tam (z przystankiem) i jeden odcinek powrotu do startu', () {
      final tam = trasaProsta(201);
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5)
          .dodajNaKoncu(20.2, 49.5)
          .wstaw(20.1, 49.5, RodzajPunktu.przystanek, trasa: tam);
      final o = odcinki(tam, plan, powrot: true);
      expect(o.length, 3);
      expect(o.last.powrot, isTrue);
      expect(o.last.doIndeksu, 0);
      expect(o.last.dlugosc, closeTo(tam.dlugosc, 0.5));
      // powrót: podejścia = zejścia drogi tam i odwrotnie
      expect(o.last.podejscia, closeTo(tam.zejscia, 1));
      expect(o.last.zejscia, closeTo(tam.podejscia, 1));
    });

    test('bez powrotu nie ma odcinka powrotnego', () {
      final tam = trasaProsta(51);
      final plan = const PlanTrasy().dodajNaKoncu(20.0, 49.5).dodajNaKoncu(20.05, 49.5);
      expect(odcinki(tam, plan).single.powrot, isFalse);
    });
  });
}
