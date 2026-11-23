import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trening/main.dart';
import 'package:trening/ui/ekran_treningu.dart';

import 'pomoc.dart';

void main() {
  testWidgets('Dziś: dzień planu, rutyna ze Startem, test kierunkowy, pominięte wyprosty', (tester) async {
    final zegar = Zegar(DateTime(2026, 11, 25, 19));
    final dane = daneTestowe(zegar.call);
    await tester.pumpWidget(TreningApp(dane: Future.value(dane)));
    await tester.pump();

    expect(find.text('Dzień 3 planu · Etap 1: Wyciszenie · tydzień 1'), findsOneWidget);
    expect(find.text('Kręgosłup 15 min'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Najpierw zrób test kierunkowy.'), 200);
    await tester.scrollUntilVisible(find.text('Test kierunkowy (ok. 5 min)'), 200);
    await tester.scrollUntilVisible(find.textContaining('Drążek'), 200);
  });

  testWidgets('trening: przygotowanie z rysunkiem, opis techniki otwiera się raz, Start → oddechy', (tester) async {
    final zegar = Zegar(DateTime(2026, 11, 25, 19));
    final dane = daneTestowe(zegar.call);
    await tester.pumpWidget(MaterialApp(
      home: EkranTreningu(dane: dane, rozpiska: dane.rozpiszDzis(), zegar: zegar.call),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // pierwszy raz: arkusz „Technika” z atlasem
    expect(find.text('Po co'), findsOneWidget);
    expect(dane.stan.widzianeTechniki, contains('oddychanie-90-90'));
    await tester.tapAt(const Offset(10, 10)); // zamknij arkusz
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Oddychanie przeponowe 90/90'), findsOneWidget);
    expect(find.text('Przygotuj się'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Oddychanie'), findsOneWidget);
    expect(find.textContaining('0 / 6 oddechów'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // zamyka ekran i jego timer
  });

  testWidgets('cała rutyna na ekranie telefonu (360 × 780 dp) bez przepełnień układu', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final zegar = Zegar(DateTime(2026, 11, 25, 19));
    final dane = daneTestowe(zegar.call)..stan.widzianeTechniki.addAll(atlasTestowy.cwiczenia.keys);
    final r = dane.rozpiszDzis();
    await tester.pumpWidget(MaterialApp(home: EkranTreningu(dane: dane, rozpiska: r, zegar: zegar.call)));
    await tester.pump();

    final glowne = find.byType(FilledButton);
    for (var i = 0; i < r.fazy.length; i++) {
      expect(tester.takeException(), isNull, reason: 'faza $i: ${r.fazy[i].runtimeType}');
      await tester.tap(glowne.last);
      await tester.pump();
    }
    expect(find.text('Brawo, trening zrobiony!'), findsOneWidget);
    expect((dane.magazyn as MagazynWPamieci).zapisany!.treningi.values.single.wykonane, hasLength(9));
    await tester.pumpWidget(const SizedBox());
  });
}
