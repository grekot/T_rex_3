import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trening/dane/magazyn.dart';
import 'package:trening/dane/stan.dart';
import 'package:trening/silnik/flagi.dart';
import 'package:trening/silnik/kalendarz.dart';
import 'package:trening/trening/przebieg.dart';
import 'package:trening/trening/rozpiska.dart';

import 'pomoc.dart';

void main() {
  late Directory katalog;

  setUp(() => katalog = Directory.systemTemp.createTempSync('trening_stan_'));
  tearDown(() => katalog.deleteSync(recursive: true));

  Stan przyklad() => Stan(
        start: DateTime.utc(2026, 11, 23),
        etapy: [WpisEtapu(1, DateTime.utc(2026, 11, 23))],
        testKierunkowy: WynikTestuKierunkowego(
          data: DateTime.utc(2026, 11, 25),
          wynik: WynikTestu.lepiej,
          bolPrzed: 4,
          zasiegPrzed: Zasieg.posladek,
          bolPo: 2,
          zasiegPo: Zasieg.brak,
        ),
        treningi: {
          '2026-11-25': ZapisTreningu(
            data: DateTime.utc(2026, 11, 25),
            sesja: 'R',
            stan: StanDnia.skrocone,
            wykonane: ['bird-dog'],
            bolesne: ['deska-boczna/kolana'],
            czesci: [0],
          ),
        },
        widzianeTechniki: {'bird-dog'},
      );

  test('zapis i odczyt stan.json bez strat', () async {
    final m = Magazyn(katalog);
    await m.zapisz(przyklad());
    final s = await m.wczytaj();
    expect(s.toJson(), przyklad().toJson());
    expect(s.flagi(DateTime(2026, 11, 26)), contains('wyprostPomaga'));
  });

  test('brak pliku → nowy stan z domyślnym startem 23.11.2026', () async {
    final s = await Magazyn(katalog).wczytaj();
    expect(s.start, DateTime.utc(2026, 11, 23));
    expect(s.etapy.single.nr, 1);
  });

  test('uszkodzony stan.json → odczyt z kopii .bak', () async {
    final m = Magazyn(katalog);
    await m.zapisz(przyklad());
    await m.zapisz(przyklad()..slizgiOdFizjo = true); // poprzednia wersja idzie do .bak
    File('${katalog.path}/stan.json').writeAsStringSync('{ucięty');
    final s = await m.wczytaj();
    expect(s.testKierunkowy!.wynik, WynikTestu.lepiej);
    expect(s.slizgiOdFizjo, isFalse);
  });

  test('dwie krótsze wersje jednego dnia łączą się w trening wykonany', () async {
    final zegar = Zegar(DateTime(2026, 11, 25, 19));
    final dane = daneTestowe(zegar.call);
    WynikPrzebiegu doKonca(Rozpiska r) {
      final p = Przebieg(r, zegar: zegar.call);
      while (!p.koniec) {
        p.dalej();
      }
      return p.wynik();
    }

    final a = dane.rozpiszDzis(czesc: 0);
    await dane.zapiszTrening(a, doKonca(a), czesc: 0);
    expect(dane.treningDzis!.stan, StanDnia.skrocone);
    final b = dane.rozpiszDzis(czesc: 1);
    await dane.zapiszTrening(b, doKonca(b), czesc: 1);
    expect(dane.treningDzis!.stan, StanDnia.wykonane);
    expect(dane.treningDzis!.czesci, [0, 1]);
    expect(dane.treningDzis!.wykonane, hasLength(9));
  });
}
