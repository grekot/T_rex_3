import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapychodzone/konto/zapisana_trasa.dart';
import 'package:mapychodzone/trasa/plan.dart';
import 'package:mapychodzone/trasa/trasa.dart';

void main() {
  test('ślad: kodowanie i dekodowanie (także ujemne różnice i brak wysokości)', () {
    const punkty = [
      PunktTrasy(20.11091, 49.54321, 1310.4, 0),
      PunktTrasy(20.10002, 49.55001, 1205.0, 0),
      PunktTrasy(-3.5, -12.25, null, 0),
      PunktTrasy(19.9, 49.2, -2.3, 0),
    ];
    final tekst = zakodujSlad(punkty);
    final wynik = odkodujSlad(tekst);
    expect(wynik.length, punkty.length);
    for (var i = 0; i < punkty.length; i++) {
      expect(wynik[i].lon, closeTo(punkty[i].lon, 1e-5));
      expect(wynik[i].lat, closeTo(punkty[i].lat, 1e-5));
      if (punkty[i].wysokosc == null) {
        expect(wynik[i].wysokosc, isNull);
      } else {
        expect(wynik[i].wysokosc, closeTo(punkty[i].wysokosc!, 0.05));
      }
    }
    expect(wynik.first.odStartu, 0);
    expect(wynik[1].odStartu, greaterThan(1000));
    expect(odkodujSlad(''), isEmpty);
  });

  test('prawdziwa trasa z BRoutera: zapis i odczyt dają te same liczby', () {
    final tam = Trasa.zGeojsonBRoutera(File('test/dane/brouter_hala_kozi_wierch.geojson').readAsStringSync());
    const plan = PlanTrasy([
      PunktPlanu(20.0, 49.2, RodzajPunktu.start, nazwa: 'Hala Gąsienicowa'),
      PunktPlanu(20.01, 49.21, RodzajPunktu.przez),
      PunktPlanu(20.02, 49.22, RodzajPunktu.cel, nazwa: 'Kozi Wierch (2291 m)'),
    ]);
    final z = ZapisanaTrasa(
      nazwa: 'Kozi',
      region: 'tatry',
      plan: plan,
      tryb: TrybTrasy.najkrocej,
      powrot: true,
      unikajStromych: true,
      tam: tam,
    );
    final mapa = z.doMapy();
    // Firestore: bez tablic w tablicach
    for (final w in mapa.values) {
      if (w is List) expect(w.any((e) => e is List), isFalse);
    }
    expect((mapa['slad'] as String).length, lessThan(tam.punkty.length * 16));
    final o = ZapisanaTrasa.zMapy('abc', mapa);
    expect(o.id, 'abc');
    expect(o.region, 'tatry');
    expect(o.tryb, TrybTrasy.najkrocej);
    expect(o.powrot, isTrue);
    expect(o.unikajStromych, isTrue);
    expect([for (final p in o.plan.punkty) p.rodzaj], [RodzajPunktu.start, RodzajPunktu.przez, RodzajPunktu.cel]);
    expect(o.plan.punkty.last.nazwa, 'Kozi Wierch (2291 m)');
    expect(o.tam.punkty.length, tam.punkty.length);
    expect(o.tam.dlugosc, closeTo(tam.dlugosc, 1));
    expect(o.tam.podejscia, closeTo(tam.podejscia, 3));
    expect(o.tam.trudnyTeren.keys, tam.trudnyTeren.keys);
    expect(o.trasa.dlugosc, closeTo(2 * tam.dlugosc, tam.dlugosc * 0.004));
    final opis = OpisTrasy.zMapy('abc', mapa);
    expect(opis.dlugosc, closeTo(2 * tam.dlugosc, 1));
    expect(opis.tryb, TrybTrasy.najkrocej);
  });

  test('trasa na azymut zachowuje odcinki i uwagi', () {
    final tam = Trasa(
      const [PunktTrasy(20, 49, 500, 0), PunktTrasy(20.01, 49.01, 600, 1340)],
      uwagi: const ['Trasa przechodzi przez Tatrzański Park Narodowy'],
      azymuty: const [OdcinekAzymutu(32.5, 1340)],
    );
    final z = ZapisanaTrasa(
      nazwa: 'Azymut',
      region: 'tatry',
      plan: const PlanTrasy([PunktPlanu(20, 49, RodzajPunktu.start), PunktPlanu(20.01, 49.01, RodzajPunktu.cel)]),
      tryb: TrybTrasy.azymut,
      powrot: false,
      unikajStromych: false,
      tam: tam,
    );
    final o = ZapisanaTrasa.zMapy('x', z.doMapy());
    expect(o.tryb, TrybTrasy.azymut);
    expect(o.tam.azymuty.single.azymut, 32.5);
    expect(o.tam.uwagi, tam.uwagi);
  });

  test('proponowana nazwa', () {
    final data = DateTime(2026, 11, 28);
    PunktPlanu p(String? n, RodzajPunktu r) => PunktPlanu(20, 49, r, nazwa: n);
    expect(
      proponowanaNazwa(PlanTrasy([p('Rabka-Zdrój', RodzajPunktu.start), p('Turbacz (1310 m)', RodzajPunktu.cel)]), data),
      'Rabka-Zdrój → Turbacz',
    );
    expect(
      proponowanaNazwa(PlanTrasy([p(null, RodzajPunktu.start), p('Turbacz (1310 m)', RodzajPunktu.cel)]), data),
      'Turbacz · 28.11.2026',
    );
    expect(proponowanaNazwa(PlanTrasy([p(null, RodzajPunktu.start), p(null, RodzajPunktu.cel)]), data), 'Trasa 28.11.2026');
    expect(proponowanaNazwa(PlanTrasy([p('Turbacz', RodzajPunktu.start), p('Turbacz', RodzajPunktu.cel)]), data), 'Turbacz');
  });
}
