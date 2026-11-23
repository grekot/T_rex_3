import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trening/plan/model.dart';
import 'package:trening/silnik/flagi.dart';

void main() {
  final plan = Plan.zJson(jsonDecode(File('assets/plan/plan.json').readAsStringSync()));
  final dzis = DateTime(2026, 11, 30);
  DateTime przed(int dni) => dzis.subtract(Duration(days: dni));

  Set<String> aktywneR(Set<String> flagi) => {
        for (final b in plan.sesje['R']!.bloki)
          for (final k in b.kroki)
            if (cwiczenieAktywne(plan.cwiczenia[k.cwiczenie]!, flagi)) k.cwiczenie,
      };

  test('przed testem kierunkowym wyprosty czekają, ślizgi nerwu są wyłączone', () {
    final f = obliczFlagi(dzis: dzis);
    expect(f, isEmpty);
    final r = aktywneR(f);
    expect(r, hasLength(9));
    expect(r.contains('wyprosty-w-lezeniu'), isFalse);
    expect(r.contains('slizgi-nerwu'), isFalse);
  });

  test('test „lepiej”: wyprosty w rutynie i w ciągu dnia', () {
    final f = obliczFlagi(dzis: dzis, test: WynikTestu.lepiej);
    expect(f, {'testKierunkowyZrobiony', 'wyprostNieSzkodzi', 'lezenieNaBrzuchuOk', 'wyprostPomaga'});
    expect(aktywneR(f).contains('wyprosty-w-lezeniu'), isTrue);
    expect(cwiczenieAktywne(plan.cwiczenia['wyprost-w-staniu']!, f), isTrue);
  });

  test('test „bez zmian”: wyprosty zostają w rutynie, ale bez przypomnień w ciągu dnia', () {
    final f = obliczFlagi(dzis: dzis, test: WynikTestu.bezZmian);
    expect(aktywneR(f).contains('wyprosty-w-lezeniu'), isTrue);
    expect(cwiczenieAktywne(plan.cwiczenia['wyprost-w-staniu']!, f), isFalse);
  });

  test('test „gorzej”: bez wyprostów i bez leżenia na brzuchu', () {
    final f = obliczFlagi(dzis: dzis, test: WynikTestu.gorzej);
    expect(f, {'testKierunkowyZrobiony'});
    expect(aktywneR(f).contains('wyprosty-w-lezeniu'), isFalse);
  });

  test('ból schodzi dziś niżej niż w poprzednim tygodniu: wyprosty wypadają', () {
    final f = obliczFlagi(dzis: dzis, test: WynikTestu.lepiej, zasiegi: {
      przed(3): Zasieg.brak,
      dzis: Zasieg.posladek,
    });
    expect(f.contains('zasiegSchodziNizej'), isTrue);
    expect(aktywneR(f).contains('wyprosty-w-lezeniu'), isFalse);
  });

  test('ból na udzie w ostatnich 7 dniach włącza ślizgi nerwu; starszy wpis już nie', () {
    expect(obliczFlagi(dzis: dzis, zasiegi: {przed(6): Zasieg.udo}).contains('objawyUdoLubNizej'), isTrue);
    expect(obliczFlagi(dzis: dzis, zasiegi: {przed(7): Zasieg.udo}).contains('objawyUdoLubNizej'), isFalse);
    expect(aktywneR(obliczFlagi(dzis: dzis, zasiegi: {przed(1): Zasieg.ponizejKolana})).contains('slizgi-nerwu'),
        isTrue);
  });

  test('ślizgi z zalecenia fizjoterapeuty', () {
    expect(aktywneR(obliczFlagi(dzis: dzis, slizgiOdFizjo: true)).contains('slizgi-nerwu'), isTrue);
  });

  test('ból cofa się (centralizacja) to nie „schodzi niżej”', () {
    final f = obliczFlagi(dzis: dzis, zasiegi: {przed(2): Zasieg.posladek, dzis: Zasieg.brak});
    expect(f.contains('zasiegSchodziNizej'), isFalse);
  });
}
