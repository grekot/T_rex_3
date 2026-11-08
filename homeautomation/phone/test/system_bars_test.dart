import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/ui/widgets.dart';

void main() {
  // Telefon 400×800 z paskiem nawigacji 48 px na dole (edge-to-edge, Android 15).
  Future<void> pump(WidgetTester tester, Widget home, {double keyboard = 0}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = FakeViewPadding(bottom: keyboard > 0 ? 0 : 48);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => aboveSystemBars(context, child!), home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('ostatni wiersz listy z jawnym padding nad paskiem nawigacji', (tester) async {
    await pump(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('Diagnostyka')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [for (var i = 0; i < 30; i++) ListTile(key: Key('row$i'), title: Text('$i'))],
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('row29'))).bottom, lessThanOrEqualTo(800 - 48 - 24));
  });

  testWidgets('przycisk na dole ekranu bez listy nad paskiem nawigacji', (tester) async {
    await pump(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Text('Zapisz', key: Key('btn')),
        ),
      ),
    );
    expect(tester.getRect(find.byKey(const Key('btn'))).bottom, lessThanOrEqualTo(800 - 48));
  });

  testWidgets('klawiatura: pole tuż nad klawiaturą, bez szczeliny o wysokość paska', (tester) async {
    await pump(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Text('pole', key: Key('field')),
        ),
      ),
      keyboard: 300,
    );
    expect(tester.getRect(find.byKey(const Key('field'))).bottom, 800 - 300);
  });
}
