import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trening/plan/model.dart';
import 'package:trening/silnik/daty.dart';
import 'package:trening/silnik/kalendarz.dart';

void main() {
  final plan = Plan.zJson(jsonDecode(File('assets/plan/plan.json').readAsStringSync()));
  final start = DateTime(2026, 11, 23); // poniedziałek
  DateTime dzienNr(int nr) => dodajDni(start, nr - 1);

  group('nowy plan (dziś = dzień 1)', () {
    final k = Kalendarz.wylicz(plan, start, [], start);

    test('84 okienka, etapy 1–21, 22–56, 57–84', () {
      expect(k.dlugosc, 84);
      expect(k.dni.first.data, DateTime.utc(2026, 11, 23));
      expect(k.dni.last.data, DateTime.utc(2027, 2, 14));
      expect([for (final nr in [1, 21, 22, 56, 57, 84]) k.dni[nr - 1].etap], [1, 1, 2, 2, 3, 3]);
      expect(k.koniecMinimum, DateTime.utc(2026, 12, 14));
    });

    test('etap 1 odblokowany, kolejne zablokowane do czasu kryteriów', () {
      expect(k.dni.take(21).every((d) => !d.zablokowany), isTrue);
      expect(k.dni.skip(21).every((d) => d.zablokowany), isTrue);
    });

    test('sesje: R w etapie 1, potem A B C A B C C', () {
      expect(k.dni.take(21).map((d) => d.sesja).toSet(), {'R'});
      expect(k.dni.sublist(21, 28).map((d) => d.sesja), ['A', 'B', 'C', 'A', 'B', 'C', 'C']);
      expect(k.dni[21].data.weekday, DateTime.monday);
    });

    test('tydzień liczony od początku etapu', () {
      expect((k.dni[0].tydzienEtapu, k.dni[20].tydzienEtapu), (1, 3));
      expect((k.dni[21].etap, k.dni[21].tydzienEtapu, k.dni[21].dzienEtapu), (2, 1, 1));
      expect(k.dni[56].tydzienEtapu, 1);
    });

    test('zadania: test kierunkowy w 1. tygodniu, drążek co 3 dni od 3. dnia', () {
      expect([for (final d in k.dni.take(10)) d.zadania.contains('test-kierunkowy')],
          [true, true, true, true, true, true, true, false, false, false]);
      expect([for (final d in k.dni.take(21)) if (d.zadania.contains('drazek-lekki')) d.nr], [3, 6, 9, 12, 15, 18, 21]);
    });
  });

  test('etap 1 trwa dłużej: kolejne etapy przesuwają się, siatka rośnie', () {
    final k = Kalendarz.wylicz(plan, start, [], dzienNr(25));
    expect(k.naDzien(dzienNr(25))!.etap, 1);
    expect(k.naDzien(dzienNr(25))!.zablokowany, isFalse);
    final jutro = k.naDzien(dzienNr(26))!;
    expect((jutro.etap, jutro.zablokowany, jutro.dzienEtapu), (2, true, 1));
    expect(k.dlugosc, 84 + 4);
  });

  test('przejście do etapu 2 w dniu 22: etap 2 odblokowany, etap 3 czeka', () {
    final k = Kalendarz.wylicz(plan, start, [WpisEtapu(1, start), WpisEtapu(2, dzienNr(22))], dzienNr(22));
    expect((k.naDzien(dzienNr(22))!.etap, k.naDzien(dzienNr(22))!.zablokowany), (2, false));
    expect(k.naDzien(dzienNr(56))!.zablokowany, isFalse);
    expect((k.naDzien(dzienNr(57))!.etap, k.naDzien(dzienNr(57))!.zablokowany), (3, true));
    expect(k.dlugosc, 84);
  });

  test('cofnięcie do etapu 1 (🔴): minimum 7 dni, potem etap 2 od nowa', () {
    final historia = [WpisEtapu(1, start), WpisEtapu(2, dzienNr(22)), WpisEtapu(1, dzienNr(30))];
    final k = Kalendarz.wylicz(plan, start, historia, dzienNr(30));
    expect(k.naDzien(dzienNr(25))!.etap, 2, reason: 'przeszłość zostaje taka, jaka była');
    final dzis = k.naDzien(dzienNr(30))!;
    expect((dzis.etap, dzis.dzienEtapu, dzis.sesja), (1, 1, 'R'));
    expect(k.koniecMinimum, dzienNr(37));
    expect((k.naDzien(dzienNr(37))!.etap, k.naDzien(dzienNr(37))!.zablokowany), (2, true));
    expect(k.dlugosc, 36 + 35 + 28);
  });

  test('w ostatnim etapie po minimum siatka sięga do dziś', () {
    final historia = [WpisEtapu(1, start), WpisEtapu(2, dzienNr(22)), WpisEtapu(3, dzienNr(57))];
    final k = Kalendarz.wylicz(plan, start, historia, dzienNr(100));
    expect(k.dlugosc, 100);
    expect(k.koniecMinimum, isNull);
    expect(k.dni.last.etap, 3);
  });

  test('zmiana czasu na letni nie przesuwa dni', () {
    final k = Kalendarz.wylicz(plan, DateTime(2027, 3, 22), [], DateTime(2027, 3, 22));
    expect(iso(k.dni[7].data), '2027-03-29');
    expect(k.dni[7].data.weekday, DateTime.monday);
  });

  test('cel spaceru według tygodnia etapu', () {
    expect(celSpaceru(plan.etap(1), 1)!.minuty, const Zakres(20, 30));
    expect(celSpaceru(plan.etap(1), 3)!.kroki, const Zakres(6000, 8000));
    expect(celSpaceru(plan.etap(2), 4)!.kroki, const Zakres(8000, 10000));
  });
}
