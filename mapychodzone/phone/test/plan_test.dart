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

    // Trasa użytkownika z 28.11 (Kotówka → Ćwilin, „Skróty”): punkty „przez” zapisały się w kolejności
    // 1, 2, 3, 4, 5, 6, 7, 8, a trasa wracała pod górę do 7 i schodziła znowu (3,66 km zamiast 2,87 km).
    // Logiczna kolejność schodzenia: 1, 2, 3, 7, 6, 5, 4, 8.
    test(
      'wstawianie punktów „przez” pod Ćwilinem: kolejność jak przy schodzeniu, niezależnie od kolejności klikania',
      () {
        const p = {
          1: (20.18048, 49.69844),
          2: (20.18192, 49.69632),
          3: (20.18222, 49.69521),
          4: (20.18484, 49.68943),
          5: (20.18286, 49.68959),
          6: (20.18034, 49.68961),
          7: (20.18192, 49.692),
          8: (20.18672, 49.68899),
        };
        const logiczna = [1, 2, 3, 7, 6, 5, 4, 8];
        for (final klikanie in const [
          [1, 2, 3, 4, 5, 6, 7, 8],
          [1, 2, 3, 7, 6, 5, 4, 8],
          [4, 5, 6, 8, 1, 2, 3, 7],
          [8, 6, 1, 3, 4, 2, 7, 5],
        ]) {
          var plan = const PlanTrasy().dodajNaKoncu(20.17873, 49.6998).dodajNaKoncu(20.19143, 49.68876);
          for (final k in klikanie) {
            plan = plan.wstaw(p[k]!.$1, p[k]!.$2, RodzajPunktu.przez);
          }
          final kolejnosc = [
            for (final q in plan.punkty.sublist(1, plan.dlugosc - 1))
              p.entries.firstWhere((e) => e.value.$1 == q.lon && e.value.$2 == q.lat).key,
          ];
          expect(kolejnosc, logiczna, reason: 'klikanie $klikanie');
        }
      },
    );

    test('zmiana kolejności: start i cel zawsze na końcach, „przez” zostaje „przez”', () {
      final plan = const PlanTrasy()
          .dodajNaKoncu(20.0, 49.5, nazwa: 'A')
          .dodajNaKoncu(20.3, 49.5, nazwa: 'D')
          .wstaw(20.1, 49.5, RodzajPunktu.przez, nazwa: 'B')
          .wstaw(20.2, 49.5, RodzajPunktu.przystanek, nazwa: 'C');
      String opis(PlanTrasy p) => [for (final q in p.punkty) '${q.nazwa}:${q.rodzaj.name}'].join(' ');
      expect(opis(plan), 'A:start B:przez C:przystanek D:cel');
      // „przez” w dół o jedno miejsce
      expect(opis(plan.zmienKolejnosc(1, 2)), 'A:start C:przystanek B:przez D:cel');
      // cel na początek: staje się startem, dawny start – przystankiem, ostatni punkt – celem
      expect(opis(plan.zmienKolejnosc(3, 0)), 'D:start A:przystanek B:przez C:cel');
      // start na koniec
      expect(opis(plan.zmienKolejnosc(0, 3)), 'B:start C:przystanek D:przystanek A:cel');
      // bez zmian i poza zakresem
      expect(identical(plan.zmienKolejnosc(2, 2), plan), isTrue);
      expect(identical(plan.zmienKolejnosc(0, 9), plan), isTrue);
      expect(plan.zmienKolejnosc(1, 2).indeksyCelow, [1, 3]);
    });

    test('usunięcie startu: następny punkt zostaje startem', () {
      final plan = const PlanTrasy().dodajNaKoncu(20.0, 49.5).dodajNaKoncu(20.1, 49.5).dodajNaKoncu(20.2, 49.5).usun(0);
      expect(plan.punkty.map((p) => p.rodzaj), [RodzajPunktu.start, RodzajPunktu.cel]);
    });

    test('zmiana rodzaju tylko dla punktów pośrednich', () {
      final plan = const PlanTrasy().dodajNaKoncu(20.0, 49.5).dodajNaKoncu(20.1, 49.5).dodajNaKoncu(20.2, 49.5);
      expect(plan.zmienRodzaj(1, RodzajPunktu.przez).punkty[1].rodzaj, RodzajPunktu.przez);
      expect(plan.zmienRodzaj(0, RodzajPunktu.przez).punkty[0].rodzaj, RodzajPunktu.start);
      expect(plan.zmienRodzaj(2, RodzajPunktu.przez).punkty[2].rodzaj, RodzajPunktu.cel);
    });

    test('tryby trasy przekazują BRouterowi siłę trzymania się szlaków', () {
      expect(TrybTrasy.szlakami.parametryBRoutera, {'hiking_routes_preference': '5.0', 'SAC_scale_limit': '6'});
      // najkrócej: bez kary za trudność ścieżki (inaczej omijał krótkie podejście T3 na Modyń)
      expect(TrybTrasy.najkrocej.parametryBRoutera, {
        'hiking_routes_preference': '0.0',
        'SAC_scale_limit': '6',
        'SAC_K1': '0',
        'SAC_K2': '0',
      });
    });

    test('unikanie stromych dokłada koszt podejść ponad 15 %, bez kary za zejścia', () {
      expect(parametryTrasy(TrybTrasy.szlakami), {'hiking_routes_preference': '5.0', 'SAC_scale_limit': '6'});
      final p = parametryTrasy(TrybTrasy.szlakiISkroty, unikajStromych: true);
      expect(p['hiking_routes_preference'], '1.0');
      expect(p['consider_elevation'], '1');
      expect(p['uphillcutoffvalue'], '15');
      expect(p['downhillcostvalue'], '0');
    });

    test('z unikaniem stromych tryb porównuje się z trybami bliżej szlaków', () {
      // bez unikania: tylko wybrany tryb
      for (final t in TrybTrasy.values) {
        expect(trybyDoPorownania(t), [t]);
      }
      // z unikaniem: Najkrócej nie może wyjść dłuższa niż Ze skrótami i Szlakami (Modyń: 2,44 vs 1,88 km)
      expect(trybyDoPorownania(TrybTrasy.najkrocej, unikajStromych: true), [
        TrybTrasy.najkrocej,
        TrybTrasy.szlakami,
        TrybTrasy.szlakiISkroty,
      ]);
      expect(trybyDoPorownania(TrybTrasy.szlakiISkroty, unikajStromych: true), [
        TrybTrasy.szlakiISkroty,
        TrybTrasy.szlakami,
      ]);
      expect(trybyDoPorownania(TrybTrasy.szlakami, unikajStromych: true), [TrybTrasy.szlakami]);
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
          .wstaw(20.05, 49.5, RodzajPunktu.przez)
          .wstaw(20.12, 49.5, RodzajPunktu.przystanek);
      expect(plan.punkty.map((p) => p.rodzaj), [
        RodzajPunktu.start,
        RodzajPunktu.przez,
        RodzajPunktu.przystanek,
        RodzajPunktu.cel,
      ]);
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
        punkty.add(
          PunktTrasy(p.lon, p.lat, p.wysokosc, punkty.last.odStartu + odlegloscM(49.5, punkty.last.lon, 49.5, p.lon)),
        );
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
    final n = PunktyNazwane.zGeojson(
      '{"type":"FeatureCollection","features":['
      '{"type":"Feature","properties":{"t":"wiata","n":"Wiata","r":4},"geometry":{"type":"Point","coordinates":[20.1001,49.5]}},'
      '{"type":"Feature","properties":{"t":"szczyt","n":"Turbacz","e":1310,"r":1},"geometry":{"type":"Point","coordinates":[20.1003,49.5]}},'
      '{"type":"Feature","properties":{"t":"zrodlo","r":4},"geometry":{"type":"Point","coordinates":[20.1,49.5]}}]}',
    );
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
          .wstaw(20.1, 49.5, RodzajPunktu.przystanek);
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
