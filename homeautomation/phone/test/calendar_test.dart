// Kalendarz domu (pkt 11): terminy (lista dat, co rok z 29 lutego, co miesiąc, co tydzień / dwa), wiek, wklejony
// harmonogram gminy, zapis w `homes/{h}/calendar`, ekran listy i edycji.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/calendar_store.dart';
import 'package:homeautomation/models/calendar.dart';
import 'package:homeautomation/ui/calendar_screen.dart';

import 'support/memory_cloud_store.dart';

void main() {
  final today = DateTime(2026, 11, 4); // środa

  test('terminy: lista dat, urodziny co rok (29 lutego), co miesiąc 31., co tydzień i co dwa; wiek', () {
    final waste = CalendarEntry(
      id: 'p',
      title: 'Plastik',
      kind: CalendarKind.waste,
      dates: [DateTime(2026, 10, 29), DateTime(2026, 11, 12), DateTime(2026, 11, 26)],
    );
    expect(waste.occurrences(today, 14), [DateTime(2026, 11, 12)]);
    expect(waste.next(today), DateTime(2026, 11, 12));
    expect(waste.next(DateTime(2026, 12, 1)), isNull);

    final ania = CalendarEntry(id: 'a', title: 'Ania', kind: CalendarKind.birthday, date: DateTime(2015, 3, 14));
    expect(ania.next(today), DateTime(2027, 3, 14));
    expect(ania.ageOn(DateTime(2027, 3, 14)), 12);
    expect(ania.ageOn(DateTime(2027, 3, 13)), 11);
    final leap = CalendarEntry(id: 'l', title: 'Leon', kind: CalendarKind.birthday, date: DateTime(2024, 2, 29));
    expect(leap.next(today), DateTime(2027, 2, 28), reason: 'rok nieprzestępny - 28 lutego');

    final rent = CalendarEntry(
      id: 'r',
      title: 'Czynsz',
      kind: CalendarKind.date,
      date: DateTime(2026, 1, 31),
      repeat: 'monthly',
    );
    expect(rent.occurrences(today, 60), [DateTime(2026, 11, 30), DateTime(2026, 12, 31)]);
    final weekly = CalendarEntry(
      id: 'w',
      title: 'Bio',
      kind: CalendarKind.date,
      date: DateTime(2026, 10, 1),
      repeat: 'biweekly',
    );
    expect(weekly.occurrences(today, 28), [DateTime(2026, 11, 12), DateTime(2026, 11, 26)]);
    final once = CalendarEntry(id: 'o', title: 'Przegląd', kind: CalendarKind.date, date: DateTime(2026, 11, 1));
    expect(once.next(today), isNull);
  });

  test('JSON jak w kontrakcie: lista dat albo data z repeat, ikona; problemy przed zapisem', () {
    final w = CalendarEntry(
      id: 'p',
      title: 'Plastik',
      kind: CalendarKind.waste,
      dates: [DateTime(2026, 11, 12), DateTime(2026, 11, 26)],
      icon: 'plastic',
    );
    expect(w.toJson(), {
      'title': 'Plastik',
      'kind': 'waste',
      'dates': ['2026-11-12', '2026-11-26'],
      'notify': true,
      'icon': 'plastic',
    });
    final b = CalendarEntry.fromJson('a', {
      'title': 'Ania',
      'kind': 'birthday',
      'date': '2015-03-14',
      'repeat': 'yearly',
      'notify': true,
    });
    expect(b.toJson(), {'title': 'Ania', 'kind': 'birthday', 'date': '2015-03-14', 'repeat': 'yearly', 'notify': true});
    expect(CalendarEntry.fromJson('x', {'title': 'X', 'kind': 'date', 'date': '2026-02-30'}).date, isNull);
    expect(const CalendarEntry(id: 'e', title: ' ', kind: CalendarKind.waste).problems(), [
      'Wpisz nazwę.',
      'Dodaj daty wywozu.',
    ]);
  });

  test('wklejony harmonogram: dd.mm bez roku (najbliższa), pełne daty, nazwy miesięcy, błędne osobno', () {
    final r = parseDateList('12.11, 26.11;\n7.01\n2027-02-04, 18 lutego, 3 marca 2027, 31.02, xyz', today);
    expect(r.dates, [
      DateTime(2026, 11, 12),
      DateTime(2026, 11, 26),
      DateTime(2027, 1, 7),
      DateTime(2027, 2, 4),
      DateTime(2027, 2, 18),
      DateTime(2027, 3, 3),
    ]);
    expect(r.bad, ['31.02', 'xyz']);
    expect(parseDateList('1.11', today).dates, [DateTime(2027, 11, 1)], reason: 'minione w tym roku - za rok');
  });

  testWidgets('ekran: wywóz z wklejonymi datami i ikoną, urodziny; lista po najbliższym terminie, usunięcie', (
    tester,
  ) async {
    final cloud = MemoryCloudStore();
    cloud.set('homes/h1/calendar/b1', {
      'title': 'Ania',
      'kind': 'birthday',
      'date': '2015-11-20',
      'repeat': 'yearly',
      'notify': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(store: CalendarStore(cloud, 'h1'), clock: () => today),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('kończy 11 lat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calSave')));
    await tester.pump();
    expect(find.text('Dodaj daty wywozu.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calIcon-plastic')));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Plastik i metal'), findsOneWidget, reason: 'nazwa z ikony');
    await tester.enterText(find.byKey(const Key('calTitle')), 'Plastik');
    await tester.tap(find.byKey(const Key('calPaste')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('calPasteText')), '12.11, 26.11, 10.12, 3x');
    await tester.tap(find.byKey(const Key('calPasteOk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calDate-2026-12-10')), findsOneWidget);
    expect(find.text('Nie rozpoznano: 3x'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calSave')));
    await tester.pumpAndSettle();

    final saved = (cloud.get('homes/h1/calendar') as Map).values.firstWhere((v) => v['kind'] == 'waste') as Map;
    expect(saved['dates'], ['2026-11-12', '2026-11-26', '2026-12-10']);
    expect((saved['icon'], saved['notify'], saved['title']), ('plastic', true, 'Plastik'));

    // Plastik (12.11) przed urodzinami (20.11).
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
    expect(tiles, ['Plastik', 'Ania']);
    expect(find.textContaining('cz 12.11 · potem jeszcze 2'), findsOneWidget);

    await tester.tap(find.text('Ania'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calDelete')));
    await tester.pumpAndSettle();
    expect(cloud.get('homes/h1/calendar/b1'), isNull);
    expect(find.text('Ania'), findsNothing);
  });
}
