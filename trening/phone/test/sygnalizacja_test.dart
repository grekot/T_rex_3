import 'package:flutter_test/flutter_test.dart';
import 'package:trening/silnik/flagi.dart';
import 'package:trening/silnik/sygnalizacja.dart';

void main() {
  WynikSygnalizacji ocen(int bol, Zasieg z, {Zasieg? ref = Zasieg.brak, bool? minelo, bool mrowienie = false}) =>
      ocenStrefe(OcenaBolu(bol: bol, zasieg: z, mrowienie: mrowienie), odniesienie: ref, minelo: minelo);

  test('ból 0–2 bez zmiany zasięgu: zielona', () {
    expect(ocen(0, Zasieg.brak).strefa, Strefa.zielona);
    expect(ocen(2, Zasieg.posladek, ref: Zasieg.posladek).strefa, Strefa.zielona);
  });

  test('ból 3–4: żółta, a gdy nie minął do rana: czerwona', () {
    expect(ocen(3, Zasieg.brak).strefa, Strefa.zolta);
    expect(ocen(4, Zasieg.brak, minelo: true).strefa, Strefa.zolta);
    expect(ocen(4, Zasieg.brak, minelo: false).strefa, Strefa.czerwona);
  });

  test('ból ≥ 5: czerwona i pytanie o czerwone flagi', () {
    final w = ocen(5, Zasieg.brak);
    expect(w.strefa, Strefa.czerwona);
    expect(w.pytajOFlagi, isTrue);
    expect(ocen(4, Zasieg.brak).pytajOFlagi, isFalse);
  });

  test('zasięg schodzi niżej niż w ostatnich 7 dniach: czerwona', () {
    final w = ocen(1, Zasieg.posladek, ref: Zasieg.brak);
    expect(w.strefa, Strefa.czerwona);
    expect(w.schodziNizej, isTrue);
  });

  test('bez historii ostrożnie: udo lub niżej to „schodzi niżej”, pośladek nie', () {
    expect(ocen(1, Zasieg.posladek, ref: null).strefa, Strefa.zielona);
    expect(ocen(1, Zasieg.udo, ref: null).strefa, Strefa.czerwona);
  });

  test('udo bez pogorszenia: co najmniej żółta i pytanie o czerwone flagi', () {
    final w = ocen(1, Zasieg.udo, ref: Zasieg.udo);
    expect(w.strefa, Strefa.zolta);
    expect(w.pytajOFlagi, isTrue);
  });

  test('poniżej kolana albo mrowienie: czerwona i objawy nerwowe', () {
    final w = ocen(1, Zasieg.ponizejKolana, ref: Zasieg.ponizejKolana);
    expect(w.strefa, Strefa.czerwona);
    expect(w.objawyNerwowe, isTrue);
    expect(ocen(0, Zasieg.brak, mrowienie: true).strefa, Strefa.czerwona);
  });

  test('ból cofa się w stronę kręgosłupa: dobry znak', () {
    final w = ocen(2, Zasieg.brak, ref: Zasieg.posladek);
    expect(w.strefa, Strefa.zielona);
    expect(w.cofaSie, isTrue);
  });

  test('najgorszy zasięg z 7 dni przed dniem oceny (bez tego dnia)', () {
    final dzis = DateTime.utc(2026, 12, 10);
    final z = {
      DateTime.utc(2026, 12, 10): Zasieg.ponizejKolana, // ten sam dzień: pomijany
      DateTime.utc(2026, 12, 9): Zasieg.brak,
      DateTime.utc(2026, 12, 5): Zasieg.posladek,
      DateTime.utc(2026, 12, 2): Zasieg.udo, // 8 dni wcześniej: poza oknem
    };
    expect(najgorszyZasieg(z, dzis), Zasieg.posladek);
    expect(najgorszyZasieg(const {}, dzis), isNull);
  });
}
