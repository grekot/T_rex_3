import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waga/data/activity.dart';
import 'package:waga/data/health_source.dart';
import 'package:waga/data/weights.dart';
import 'package:waga/ui/activity_tab.dart';
import 'package:waga/ui/chart_tab.dart';
import 'package:waga/ui/entries_tab.dart';

WeightDoc sampleDoc() {
  final today = DateTime.now();
  final e = <String, dynamic>{};
  for (var i = 0; i < 40; i++) {
    if (i % 5 == 3) continue; // dni bez ważenia
    final d = today.subtract(Duration(days: i));
    e[dayKey(d)] = {'w': 820 + i ~/ 3 + (i % 2), 't': i};
  }
  return WeightDoc.fromMap({'e': e, 'goal': 790});
}

ActivityData sampleActivity() {
  final today = DateTime.now();
  return ActivityData.build(
    total: [for (var i = 0; i < 20; i++) Sample(today.subtract(Duration(days: i)), 2300.0 + i * 10, 'Zepp')],
    active: [for (var i = 0; i < 20; i++) Sample(today.subtract(Duration(days: i)), 500.0, 'Zepp')],
    steps: [for (var i = 0; i < 20; i++) Sample(today.subtract(Duration(days: i)), 8000.0, 'Zepp')],
    workouts: [
      Workout(
        start: today.subtract(const Duration(days: 1, hours: 2)),
        end: today.subtract(const Duration(days: 1, hours: 1)),
        type: 'RUNNING',
        kcal: 640,
        distanceM: 9100,
      ),
    ],
  );
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('wykres: podsumowanie, cel, zmiana zakresu', (tester) async {
    await tester.pumpWidget(wrap(ChartTab(doc: sampleDoc(), activity: sampleActivity(), healthReady: true, onSetGoal: () {})));
    expect(find.text('82,0'), findsOneWidget);
    expect(find.textContaining('Trend'), findsOneWidget);
    expect(find.textContaining('79,0 kg'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Spalone kalorie (dziennie)'), 200);
    expect(find.text('Spalone kalorie (dziennie)'), findsOneWidget);
    // dla całej historii kalorie się nie mieszczą (Health Connect czyta 120 dni)
    await tester.scrollUntilVisible(find.text('Wszystko'), -200);
    await tester.tap(find.text('Wszystko'));
    await tester.pumpAndSettle();
    expect(find.text('Spalone kalorie (dziennie)'), findsNothing);
  });

  testWidgets('wykres bez pomiarów', (tester) async {
    await tester.pumpWidget(wrap(ChartTab(doc: WeightDoc.empty, activity: ActivityData.empty, healthReady: false, onSetGoal: () {})));
    expect(find.textContaining('Brak pomiarów'), findsOneWidget);
  });

  testWidgets('lista pomiarów od najnowszego z różnicą', (tester) async {
    await tester.pumpWidget(wrap(EntriesTab(doc: sampleDoc(), activity: sampleActivity(), onEdit: (_) async {})));
    expect(find.text('82,0 kg'), findsWidgets);
    await tester.tap(find.text('82,0 kg').first);
    await tester.pumpAndSettle();
    expect(find.text('Popraw pomiar'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('82,1'), findsOneWidget);
  });

  testWidgets('aktywność: średnie, dni i treningi', (tester) async {
    await tester.pumpWidget(wrap(ActivityTab(
      state: HealthState.ready,
      activity: sampleActivity(),
      doc: sampleDoc(),
      onConnect: () async {},
      onRefresh: () async {},
    )));
    expect(find.textContaining('Ostatnie 7 dni'), findsOneWidget);
    expect(find.text('8 000'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bieg'), 300);
    expect(find.textContaining('9,1 km'), findsOneWidget);
  });

  testWidgets('aktywność: prośba o zgodę', (tester) async {
    var asked = false;
    await tester.pumpWidget(wrap(ActivityTab(
      state: HealthState.needsPermission,
      activity: ActivityData.empty,
      doc: WeightDoc.empty,
      onConnect: () async => asked = true,
      onRefresh: () async {},
    )));
    await tester.tap(find.text('Połącz z Health Connect'));
    expect(asked, true);
  });
}
