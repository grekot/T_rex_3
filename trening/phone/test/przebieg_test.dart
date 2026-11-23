import 'package:flutter_test/flutter_test.dart';
import 'package:trening/silnik/flagi.dart';
import 'package:trening/trening/przebieg.dart';
import 'package:trening/trening/rozpiska.dart';

import 'pomoc.dart';

class Zapis extends Sygnaly {
  final zdarzenia = <String>[];

  @override
  void startTrzymania() => zdarzenia.add('start');
  @override
  void odliczanie(int sekund) => zdarzenia.add('$sekund');
  @override
  void koniecTrzymania() => zdarzenia.add('koniec');
  @override
  void zmianaStrony() => zdarzenia.add('strona');
  @override
  void koniecPrzerwy() => zdarzenia.add('przerwa');
  @override
  void celOsiagniety() => zdarzenia.add('cel');
  @override
  void koniecTreningu() => zdarzenia.add('KONIEC');
}

void main() {
  final rozpiska = rozpisz(planTestowy, atlasTestowy, planTestowy.sesje['R']!, obliczFlagi(dzis: DateTime(2026, 11, 25)));
  late Zegar zegar;
  late Zapis s;
  late Przebieg p;

  setUp(() {
    zegar = Zegar(DateTime(2026, 11, 25, 19));
    s = Zapis();
    p = Przebieg(rozpiska, zegar: zegar.call, sygnaly: s);
  });

  void czekaj(int ms) {
    for (var t = 0; t < ms; t += 100) {
      zegar.przesun(const Duration(milliseconds: 100));
      p.tick();
    }
  }

  /// Przewija do pierwszej fazy danego ćwiczenia (przygotowanie).
  void doCwiczenia(String id) {
    while (!(p.faza is FazaPrzygotowanie && p.cwiczenie.id == id)) {
      p.dalej();
    }
  }

  test('start: przygotowanie do oddychania, nic nie liczy się samo', () {
    expect(p.faza, isA<FazaPrzygotowanie>());
    expect(p.cwiczenie.id, 'oddychanie-90-90');
    czekaj(60000);
    expect(p.indeks, 0);
  });

  test('oddechy liczą się z tempa (10 s na oddech), cel 6 daje sygnał raz', () {
    p.dalej();
    expect(p.faza, isA<FazaOddechy>());
    expect(p.wdech, isTrue);
    czekaj(4500);
    expect(p.wdech, isFalse);
    czekaj(55600);
    expect(p.licznik, 6);
    czekaj(20000);
    expect(s.zdarzenia.where((e) => e == 'cel'), hasLength(1));
    expect(p.faza, isA<FazaOddechy>(), reason: 'dalej dopiero po „Gotowe”');
  });

  test('trzymanie: start, odliczanie 3-2-1, koniec, krótka przerwa i następne powtórzenie samo', () {
    doCwiczenia('curl-up-mcgilla');
    p.dalej();
    expect(p.faza, isA<FazaTrzymanie>());
    expect(p.pozostalo, 8);
    expect(s.zdarzenia.last, 'start');
    czekaj(8000);
    expect(s.zdarzenia.sublist(s.zdarzenia.length - 4), ['3', '2', '1', 'koniec']);
    expect(p.faza, isA<FazaPrzerwa>());
    expect((p.faza as FazaPrzerwa).powod, PowodPrzerwy.powtorzenie);
    czekaj(3000);
    expect(p.faza, isA<FazaTrzymanie>());
    expect((p.faza as FazaTrzymanie).opis, 'Powtórzenie 2/5');
  });

  test('pauza zatrzymuje czas, +5 s wydłuża trzymanie', () {
    doCwiczenia('curl-up-mcgilla');
    p.dalej();
    czekaj(2000);
    p.pauzuj();
    zegar.przesun(const Duration(minutes: 5));
    p.tick();
    expect(p.pozostalo, 6);
    p.wznow();
    p.dodajSekundy(5);
    expect(p.pozostalo, 11);
    czekaj(10900);
    expect(p.faza, isA<FazaTrzymanie>());
    czekaj(200);
    expect(p.faza, isA<FazaPrzerwa>());
  });

  test('licznik powtórzeń: cel daje sygnał, dalej dopiero po „Gotowe”', () {
    doCwiczenia('koci-grzbiet');
    p.dalej();
    final f = p.faza as FazaPowtorzenia;
    expect(f.cel, 8);
    for (var i = 0; i < 8; i++) {
      p.plusJeden();
    }
    expect(s.zdarzenia.last, 'cel');
    expect(p.faza, same(f));
    p.minusJeden();
    expect(p.licznik, 7);
    p.dalej();
    expect(p.faza, isA<FazaPrzygotowanie>());
    expect(p.cwiczenie.id, 'mostek-biodrowy');
  });

  test('zmiana strony daje sygnał', () {
    doCwiczenia('zginacze-biodra');
    p.dalej();
    czekaj(30000);
    expect(p.faza, isA<FazaPrzerwa>());
    expect((p.faza as FazaPrzerwa).powod, PowodPrzerwy.strona);
    expect(s.zdarzenia.last, 'strona');
  });

  test('„Boli: pomiń” pomija resztę ćwiczenia i trafia do wyniku', () {
    doCwiczenia('deska-boczna/kolana');
    p.dalej();
    p.pominCwiczenie(boli: true);
    expect(p.faza, isA<FazaPrzygotowanie>());
    expect(p.cwiczenie.id, 'bird-dog');
    final w = p.wynik();
    expect(w.bolesne, ['deska-boczna/kolana']);
    expect(w.pominiete, ['deska-boczna/kolana']);
    expect(w.wykonane, ['oddychanie-90-90', 'koci-grzbiet', 'mostek-biodrowy', 'curl-up-mcgilla']);
    expect(w.ukonczony, isFalse);
  });

  test('do końca: sygnał końca, wszystkie ćwiczenia wykonane', () {
    while (!p.koniec) {
      p.dalej();
    }
    expect(s.zdarzenia.last, 'KONIEC');
    final w = p.wynik();
    expect(w.ukonczony, isTrue);
    expect(w.wykonane, hasLength(9));
    expect(p.postep, 1);
  });

  test('przerwanie w połowie: wykonane tylko skończone ćwiczenia', () {
    doCwiczenia('mostek-biodrowy');
    p.dalej();
    p.zakonczTeraz();
    final w = p.wynik();
    expect(w.ukonczony, isFalse);
    expect(w.wykonane, ['oddychanie-90-90', 'koci-grzbiet']);
  });
}
