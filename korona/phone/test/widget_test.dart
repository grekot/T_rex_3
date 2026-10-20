import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korona/data/peaks.dart';
import 'package:korona/ui/home_screen.dart';

void main() {
  final catalog = PeakCatalog.fromJsonString(File('assets/peaks.json').readAsStringSync());

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // Bez konta: tryb przykładowych danych
    await tester.pumpWidget(MaterialApp(home: HomeScreen(catalog: catalog)));
    await tester.pump();
  }

  testWidgets('postęp grup, lista grupy i szczegóły szczytu', (tester) async {
    await pumpHome(tester);
    expect(find.text('Przykładowe dane'), findsOneWidget);
    expect(find.text('Korona Gór Polski'), findsOneWidget);
    expect(find.text(' / 28'), findsOneWidget);

    await tester.tap(find.text('Korona Gór Polski'));
    await tester.pumpAndSettle();
    expect(find.text('Rysy'), findsOneWidget);
    expect(find.textContaining('Warianty'), findsNothing, reason: 'warianty niżej na liście');

    await tester.tap(find.text('Rysy'));
    await tester.pumpAndSettle();
    expect(find.text('2499 m n.p.m. · Tatry'), findsOneWidget);
    expect(find.text('Wierzchołek na granicy państwa'), findsOneWidget);
  });

  testWidgets('historia ze statystykami', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Historia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('zdobytych szczytów'), findsOneWidget);
    expect(find.text('Zdobycia w latach'), findsOneWidget);
  });
}
