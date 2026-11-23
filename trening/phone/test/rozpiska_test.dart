import 'package:flutter_test/flutter_test.dart';
import 'package:trening/silnik/flagi.dart';
import 'package:trening/trening/rozpiska.dart';

import 'pomoc.dart';

void main() {
  final r = planTestowy.sesje['R']!;
  final dzis = DateTime(2026, 11, 25);

  Rozpiska rozpiska({WynikTestu? test, int? czesc}) =>
      rozpisz(planTestowy, atlasTestowy, r, obliczFlagi(dzis: dzis, test: test), czesc: czesc);

  List<Faza> fazyCwiczenia(Rozpiska x, String id) {
    final i = x.cwiczenia.indexWhere((c) => c.id == id);
    return x.fazy.where((f) => f.cwiczenie == i).toList();
  }

  test('przed testem: 9 ćwiczeń, wyprosty i ślizgi pominięte z powodem', () {
    final x = rozpiska();
    expect(x.cwiczenia, hasLength(9));
    expect(x.pominiete.map((p) => (p.cwiczenie.id, p.powod)), [
      ('wyprosty-w-lezeniu', 'Najpierw zrób test kierunkowy.'),
      ('slizgi-nerwu', planTestowy.cwiczenia['slizgi-nerwu']!.uwaga),
    ]);
  });

  test('po teście „lepiej”: 10 ćwiczeń, wyprosty jako sfinks na czas i 10 wyprostów', () {
    final x = rozpiska(test: WynikTestu.lepiej);
    expect(x.cwiczenia, hasLength(10));
    final f = fazyCwiczenia(x, 'wyprosty-w-lezeniu');
    expect(f.map((e) => e.runtimeType), [FazaPrzygotowanie, FazaTrzymanie, FazaPrzerwa, FazaPowtorzenia]);
    expect((f[1] as FazaTrzymanie).sekundy, 60);
    expect(((f[3] as FazaPowtorzenia).cel, (f[3] as FazaPowtorzenia).opis), (10, 'Wyprosty na dłoniach'));
  });

  test('każde ćwiczenie zaczyna się przygotowaniem i nie kończy przerwą', () {
    final x = rozpiska(test: WynikTestu.lepiej);
    for (final c in x.cwiczenia) {
      final f = fazyCwiczenia(x, c.id);
      expect(f.first, isA<FazaPrzygotowanie>(), reason: c.id);
      expect(f.last, isNot(isA<FazaPrzerwa>()), reason: c.id);
    }
  });

  test('deska boczna: piramida 5/3/1 na stronę = 18 trzymań po 10 s, strony L potem P', () {
    final f = fazyCwiczenia(rozpiska(), 'deska-boczna/kolana');
    final trzymania = f.whereType<FazaTrzymanie>().toList();
    expect(trzymania, hasLength(18));
    expect(trzymania.every((t) => t.sekundy == 10), isTrue);
    expect(trzymania.take(6).map((t) => t.strona), [...List.filled(5, Strona.lewa), Strona.prawa]);
    expect(f.whereType<FazaPrzerwa>().where((p) => p.powod == PowodPrzerwy.seria).map((p) => p.sekundy), [20, 20]);
  });

  test('curl-up: 9 trzymań po 8 s (dolna granica 8–10 s), bez stron', () {
    final t = fazyCwiczenia(rozpiska(), 'curl-up-mcgilla').whereType<FazaTrzymanie>().toList();
    expect(t, hasLength(9));
    expect(t.first.sekundy, 8);
    expect(t.first.zakres.toString(), '8–10');
    expect(t.every((e) => e.strona == null), isTrue);
  });

  test('bird dog: strony na zmianę, 2 serie × 6 na stronę z trzymaniem 8 s', () {
    final t = fazyCwiczenia(rozpiska(), 'bird-dog').whereType<FazaTrzymanie>().toList();
    expect(t, hasLength(24));
    expect(t.take(4).map((e) => e.strona), [Strona.lewa, Strona.prawa, Strona.lewa, Strona.prawa]);
    expect(t.first.opis, 'Powtórzenie 1/6');
  });

  test('dead bug: licznik 12 na serię (6 na stronę, na zmianę)', () {
    final p = fazyCwiczenia(rozpiska(), 'dead-bug').whereType<FazaPowtorzenia>().toList();
    expect(p.map((e) => (e.cel, e.naZmiane, e.seria)), [(12, true, 1), (12, true, 2)]);
  });

  test('skręt: 2–3 serie → 2 serie po 20 s na każdą stronę', () {
    final t = fazyCwiczenia(rozpiska(), 'skret-w-lezeniu').whereType<FazaTrzymanie>().toList();
    expect(t.map((e) => (e.seria, e.strona, e.sekundy)), [
      (1, Strona.lewa, 20), (1, Strona.prawa, 20), (2, Strona.lewa, 20), (2, Strona.prawa, 20), //
    ]);
  });

  test('oddechy: 6–8 → cel 6, wdech 4 s, wydech 6 s', () {
    final o = fazyCwiczenia(rozpiska(), 'oddychanie-90-90').whereType<FazaOddechy>().single;
    expect((o.cel, o.wdechS, o.wydechS), (6, 4, 6));
  });

  test('dwie krótsze wersje: ćwiczenia 1–5 i 6–11', () {
    final a = rozpiska(test: WynikTestu.lepiej, czesc: 0);
    final b = rozpiska(test: WynikTestu.lepiej, czesc: 1);
    expect(a.cwiczenia.map((c) => c.id), [
      'oddychanie-90-90', 'wyprosty-w-lezeniu', 'koci-grzbiet', 'mostek-biodrowy', 'curl-up-mcgilla', //
    ]);
    expect(b.cwiczenia.first.id, 'deska-boczna/kolana');
    expect(b.pominiete.single.cwiczenie.id, 'slizgi-nerwu');
  });

  test('skrót techniki i „Przerwij, jeśli” z atlasu', () {
    final x = rozpiska(test: WynikTestu.lepiej);
    final wyprost = x.cwiczenia.firstWhere((c) => c.id == 'wyprosty-w-lezeniu');
    expect(wyprost.skrot, hasLength(3));
    expect(wyprost.przerwijJesli, startsWith('ból schodzi do pośladka'));
    expect(wyprost.rysunek!.asset, 'assets/plan/img/wyprosty_w_lezeniu.jpg');
    final deska = x.cwiczenia.firstWhere((c) => c.id == 'deska-boczna/kolana');
    expect(deska.rysunek!.uwaga, isNotNull);
  });
}
