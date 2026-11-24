import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trening/dane/stan.dart';
import 'package:trening/main.dart';
import 'package:trening/ui/ekran_bezpieczenstwa.dart';
import 'package:trening/ui/ekran_treningu.dart';

import 'pomoc.dart';

/// Ekran S23 w dp (1080 × 2340 px przy gęstości 3).
void telefon(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('powitanie: „Zaczynam” dopiero po „Rozumiem”, potem ekran Dziś', (tester) async {
    telefon(tester);
    final zegar = Zegar(DateTime(2026, 11, 30, 18));
    final dane = daneTestowe(zegar.call, stan: Stan(start: DateTime.utc(2026, 11, 30)));
    final wywolania = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('pl.grekot.trening/urzadzenie'),
      (c) async {
        wywolania.add(c.method);
        return c.method == 'poprosOPowiadomienia' ? true : null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pl.grekot.trening/urzadzenie'), null));
    await tester.pumpWidget(TreningApp(dane: Future.value(dane)));
    await tester.pump();

    expect(find.text('Zanim zaczniesz'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('30 listopada 2026'), 300);
    await tester.scrollUntilVisible(find.text('Zaczynam'), 300);
    await tester.ensureVisible(find.text('Zaczynam'));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Zaczynam')).onPressed, isNull);
    await tester.scrollUntilVisible(find.text('Rozumiem'), -300);
    await tester.ensureVisible(find.text('Rozumiem'));
    await tester.tap(find.text('Rozumiem'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Zaczynam'), 300);
    await tester.ensureVisible(find.text('Zaczynam'));
    await tester.tap(find.text('Zaczynam'));
    await tester.pumpAndSettle();

    expect(wywolania, contains('poprosOPowiadomienia'));
    expect(dane.stan.powitanieZrobione, isTrue);
    expect(find.text('Dzień 1 planu · Etap 1: Wyciszenie · tydzień 1'), findsOneWidget);
    expect(find.text('Kalendarz'), findsOneWidget); // pasek dolny
    expect(tester.takeException(), isNull);
  });

  testWidgets('poranny check-in z Dziś zapisuje ból i pokazuje wynik', (tester) async {
    telefon(tester);
    final zegar = Zegar(DateTime(2026, 11, 26, 7));
    final dane = daneTestowe(zegar.call);
    await tester.pumpWidget(TreningApp(dane: Future.value(dane)));
    await tester.pump();

    await tester.tap(find.text('Jak plecy rano?'));
    await tester.pumpAndSettle();
    expect(find.text('Dzień dobry! Jak plecy rano?'), findsOneWidget);
    await tester.tap(find.text('Pośladek'));
    await tester.pump();
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();

    expect(dane.checkinDzis!.zasieg.name, 'posladek');
    expect(find.text('Rano: ból 0/10, pośladek'), findsOneWidget);
    expect(find.text('Jak plecy rano?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kalendarz: siatka bez przepełnień, drzwiczki dzisiejszego okienka, „zrobiłem bez aplikacji”',
      (tester) async {
    telefon(tester);
    final zegar = Zegar(DateTime(2026, 11, 26, 20));
    final dane = daneTestowe(zegar.call);
    await tester.pumpWidget(TreningApp(dane: Future.value(dane)));
    await tester.pump();
    await tester.tap(find.text('Kalendarz'));
    await tester.pumpAndSettle();

    expect(find.text('Treningi w tym tygodniu: 0/7'), findsOneWidget);
    expect(find.textContaining('Etap 2 najwcześniej od 14 grudnia'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // dzisiejsze okienko: zamknięte drzwiczki z numerem dnia
    final dzis = find.bySemanticsLabel(RegExp('^czwartek, 26 listopada'));
    expect(dzis, findsOneWidget);
    await tester.tap(dzis);
    await tester.pumpAndSettle();
    expect(dane.okienkoOtwarte, isTrue);
    expect(find.text('Dziś, jeszcze przed treningiem'), findsOneWidget);
    await tester.tap(find.text('Zrobiłem bez aplikacji'));
    await tester.pumpAndSettle();
    expect(find.text('✓ Zrobione (bez aplikacji)'), findsOneWidget);
    expect(find.text('Oceń ból po treningu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // przewinięcie całej siatki (12 tygodni) bez błędów
    Navigator.of(tester.element(find.text('Oceń ból po treningu'))).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ból po treningu'), 300);
    expect(find.text('12'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('po treningu: ocena bólu → strefa sygnalizacji i wstrzymanie ćwiczenia', (tester) async {
    telefon(tester);
    final zegar = Zegar(DateTime(2026, 11, 25, 19));
    final dane = daneTestowe(zegar.call)..stan.widzianeTechniki.addAll(atlasTestowy.cwiczenia.keys);
    final r = dane.rozpiszDzis(czesc: 0);
    await tester.pumpWidget(MaterialApp(home: EkranTreningu(dane: dane, rozpiska: r, czesc: 0, zegar: zegar.call)));
    await tester.pump();
    for (var i = 0; i < r.fazy.length; i++) {
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
    }
    expect(find.text('Jak plecy po treningu?'), findsOneWidget);

    // ból 4/10, nasiliło ostatnie ćwiczenie tej części
    final suwak = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(suwak.left + 24 + (suwak.width - 48) * 0.4, suwak.center.dy));
    await tester.pump();
    final cw = r.cwiczenia.last.cwiczenie;
    final nazwa = cw.nazwa;
    await tester.ensureVisible(find.text(nazwa));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nazwa));
    await tester.pump();
    await tester.ensureVisible(find.text('Zapisz ocenę'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz ocenę'));
    await tester.pumpAndSettle();

    final ocena = dane.treningDzis!.ocena!;
    expect(ocena.bol, 4);
    expect(ocena.nasililo, cw.id);
    expect(find.text('Żółta strefa'), findsOneWidget);
    expect(find.textContaining('Jutro rano zapytam'), findsOneWidget);
    await tester.ensureVisible(find.text('Wstrzymaj „$nazwa” na 7 dni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wstrzymaj „$nazwa” na 7 dni'));
    await tester.pumpAndSettle();
    expect(dane.stan.wstrzymane, contains(cw.id));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Więcej: przypomnienia i instrukcja dla Samsunga bez przepełnień', (tester) async {
    telefon(tester);
    final zegar = Zegar(DateTime(2026, 11, 26, 12));
    final dane = daneTestowe(zegar.call);
    await tester.pumpWidget(TreningApp(dane: Future.value(dane)));
    await tester.pump();
    await tester.tap(find.text('Więcej'));
    await tester.pumpAndSettle();

    expect(find.text('Przerwy w siedzeniu'), findsOneWidget);
    expect(find.text('co 40 min, 8:00–16:00, Pn–Pt'), findsOneWidget);
    await tester.tap(find.text('co 30 min'));
    await tester.pumpAndSettle();
    expect(dane.stan.przypomnienia.przerwyCo, 30);
    await tester.scrollUntilVisible(find.text('Data startu planu'), 300);
    expect(find.text('23 listopada 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bezpieczeństwo: 112, czego unikać z datą', (tester) async {
    telefon(tester);
    final zegar = Zegar(DateTime(2026, 11, 26, 12));
    final dane = daneTestowe(zegar.call);
    await tester.pumpWidget(MaterialApp(home: EkranBezpieczenstwa(dane: dane)));
    await tester.pump();
    expect(find.text('Zadzwoń 112'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('do ok. 18 stycznia'), 300);
    expect(tester.takeException(), isNull);
  });
}
