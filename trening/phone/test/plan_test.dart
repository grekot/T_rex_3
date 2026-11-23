// Walidacja prawdziwych danych: assets/plan/plan.json i atlas.json.
// Każda zmiana planu albo atlasu przechodzi przez ten test w CI przed wydaniem.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trening/plan/atlas.dart';
import 'package:trening/plan/model.dart';
import 'package:trening/plan/sprawdz.dart';

Object? _json(String sciezka) => jsonDecode(File(sciezka).readAsStringSync());

void main() {
  final plan = Plan.zJson(_json('assets/plan/plan.json'));
  final atlas = Atlas.zJson(_json('assets/plan/atlas.json'));

  test('plan i atlas są spójne', () {
    expect(sprawdzPlan(plan, atlas), isEmpty);
  });

  test('atlas: 28 ćwiczeń, każde ma rysunek, który istnieje, i treść', () {
    expect(atlas.cwiczenia, hasLength(28));
    expect(atlas.zasadyWspolne, isNotEmpty);
    for (final c in atlas.cwiczenia.values) {
      expect(c.rysunki, isNotEmpty, reason: c.id);
      for (final r in c.rysunki.values) {
        expect(File(r.asset).existsSync(), isTrue, reason: r.asset);
      }
      expect(c.sekcje.where((s) => s.tekst != null || s.punkty.isNotEmpty), isNotEmpty, reason: c.id);
    }
  });

  test('rysunki odbiegające od opisu mają uwagę (obowiązuje opis)', () {
    expect(atlas.cwiczenia['deska-boczna']!.rysunki['kolana']!.uwaga, startsWith('Rysunek pokazuje'));
    expect(atlas.cwiczenia['martwy-ciag-jednonoz']!.rysunek('')!.uwaga, startsWith('Rysunek pokazuje'));
  });

  test('rutyna „Kręgosłup 15 min” ma 11 kroków w kolejności z planu', () {
    final r = plan.sesje['R']!;
    expect(r.minuty, 15);
    expect([for (final b in r.bloki) b.kroki.single.cwiczenie], [
      'oddychanie-90-90', 'wyprosty-w-lezeniu', 'koci-grzbiet', 'mostek-biodrowy', 'curl-up-mcgilla', //
      'deska-boczna/kolana', 'bird-dog', 'dead-bug', 'zginacze-biodra', 'skret-w-lezeniu', 'slizgi-nerwu',
    ]);
    expect(r.krotszaWersja, [(0, 4), (5, 10)]);
  });

  test('dawki z planu', () {
    Dawka d(String c) => plan.sesje['R']!.bloki.expand((b) => b.kroki).firstWhere((k) => k.cwiczenie == c).dawka;

    final oddech = d('oddychanie-90-90') as Oddechy;
    expect((oddech.ile, oddech.wdechS, oddech.wydechS), (const Zakres(6, 8), const Zakres(3, 4), const Zakres(5, 6)));

    final curl = d('curl-up-mcgilla') as Piramida;
    expect(curl.serie, [5, 3, 1]);
    expect(curl.trzymanieS, const Zakres(8, 10));

    final deska = d('deska-boczna/kolana') as Piramida;
    expect((deska.naStrone, deska.trzymanieS.toString()), (true, '10'));

    final bird = d('bird-dog') as Powtorzenia;
    expect((bird.serie.toString(), bird.ile.toString(), bird.trzymanieS.toString(), bird.naStrone), ('2', '6', '8', true));

    final skret = d('skret-w-lezeniu') as Trzymanie;
    expect((skret.serie.toString(), skret.s.toString()), ('2–3', '20–30'));

    final wyprost = d('wyprosty-w-lezeniu') as Pozycje;
    expect(wyprost.etapy.map((e) => e.nazwa), ['Sfinks', 'Wyprosty na dłoniach']);
  });

  test('etapy: minima 21/35/28 dni = 84 dni, niedziela w etapach 2–3 to sesja C', () {
    expect(plan.etapy.map((e) => e.minDni), [21, 35, 28]);
    expect(plan.etapy.map((e) => e.minDni).reduce((a, b) => a + b), 84);
    expect(plan.etap(1).harmonogram.values.toSet(), {'R'});
    expect(plan.etap(2).harmonogram, {1: 'A', 2: 'B', 3: 'C', 4: 'A', 5: 'B', 6: 'C', 7: 'C'});
    expect(plan.etap(1).kryteria, hasLength(5));
    expect(plan.etap(2).kryteria, hasLength(3));
  });

  test('test kierunkowy i teksty bezpieczeństwa', () {
    expect(plan.testKierunkowy.kroki.map((k) => k.typ), ['ocena', 'pozycja', 'pozycja', 'powtorzenia', 'marsz', 'ocena']);
    expect(plan.testKierunkowy.wyniki.keys, ['lepiej', 'bezZmian', 'gorzej']);
    expect(plan.teksty.czerwoneFlagi, hasLength(4));
    expect(plan.teksty.sygnalizacja.keys, ['zielona', 'zolta', 'czerwona']);
  });

  test('w planie nie ma danych osobowych (repozytorium jest publiczne)', () {
    final tekst = File('assets/plan/plan.json').readAsStringSync().toLowerCase();
    for (final zakazane in ['73 kg', '68 kg', '168 cm', '44 lat', 'strugark', 'rąban']) {
      expect(tekst.contains(zakazane), isFalse, reason: zakazane);
    }
  });

  test('literówka w polu planu to błąd, a nie cisza', () {
    final zly = Map<String, Object?>.from(_json('assets/plan/plan.json')! as Map)..['minDniPoCofnieciuu'] = 7;
    expect(() => Plan.zJson(zly), throwsA(isA<BladPlanu>()));
  });
}
