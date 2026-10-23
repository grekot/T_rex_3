import 'package:flutter_test/flutter_test.dart';
import 'package:waga/data/activity.dart';
import 'package:waga/data/weights.dart';

void main() {
  test('dokument: nagrobki i złe wpisy odpadają, sortowanie, cel', () {
    final doc = WeightDoc.fromMap({
      'e': {
        '2026-10-23': {'w': 823, 't': 5},
        '2026-10-21': {'w': 830, 't': 1},
        '2026-10-22': {'w': 0, 't': 9}, // usunięty
        'zle': {'w': 800, 't': 1},
        '2026-10-20': {'w': 10, 't': 1},
      },
      'goal': 780,
    });
    expect(doc.entries.map((e) => '${e.day}:${e.w}'), ['2026-10-21:830', '2026-10-23:823']);
    expect(doc.goal, 780);
    expect(doc.lastBefore('2026-10-23')!.w, 830);
    expect(WeightDoc.fromMap(null).isEmpty, true);
  });

  test('formatowanie i wpisywanie wagi', () {
    expect(formatKg(823), '82,3');
    expect(formatDelta(-4), '−0,4');
    expect(formatDelta(12), '+1,2');
    expect(parseKg('82,3'), 823);
    expect(parseKg(' 82.35 kg'), 824);
    expect(parseKg('8'), null);
    expect(parseKg('abc'), null);
  });

  test('daty: kolejne dni przez zmianę czasu', () {
    final days = daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 27)).map(dayKey).toList();
    expect(days, ['2026-10-24', '2026-10-25', '2026-10-26', '2026-10-27']);
    expect(shortDate(DateTime(2026, 10, 23)), 'pt 23.10');
  });

  test('trend wygładza i stoi w dni bez pomiaru', () {
    final entries = [const Entry('2026-10-01', 900, 0), const Entry('2026-10-03', 800, 0)];
    final t = trend(entries, DateTime(2026, 10, 4));
    expect(t['2026-10-01'], 900);
    expect(t['2026-10-02'], 900);
    expect(t['2026-10-03'], closeTo(890, 1e-9));
    expect(t['2026-10-04'], closeTo(890, 1e-9));
  });

  test('tempo i prognoza celu', () {
    // równo -1 kg na tydzień przez 6 tygodni
    final entries = [
      for (var i = 0; i < 42; i++)
        Entry(dayKey(DateTime(2026, 9, 1).add(Duration(days: i))), (900 - i * 10 / 7).round(), 0),
    ];
    final today = DateTime(2026, 10, 12);
    final t = trend(entries, today, alpha: 1); // bez wygładzania - same pomiary
    final rate = weeklyRate(t, today)!;
    expect(rate, closeTo(-10, 0.5));
    final f = forecastGoal(current: t[dayKey(today)]!, goal: t[dayKey(today)]!.round() - 20, ratePerWeek: rate, today: today);
    expect(f, isNotNull);
    expect(f!.difference(today).inDays, inInclusiveRange(12, 16));
    // waga rośnie, a cel niżej - brak prognozy
    expect(forecastGoal(current: 800, goal: 780, ratePerWeek: 5, today: today), isNull);
    expect(weeklyRate({}, today), isNull);
  });

  test('średnia z okresu', () {
    final entries = [const Entry('2026-10-01', 800, 0), const Entry('2026-10-05', 810, 0), const Entry('2026-10-09', 900, 0)];
    expect(averageBetween(entries, DateTime(2026, 10, 1), DateTime(2026, 10, 7)), 805);
    expect(averageBetween(entries, DateTime(2026, 11, 1), DateTime(2026, 11, 7)), isNull);
  });

  test('aktywność: suma na dzień, bez podwójnego liczenia dwóch aplikacji', () {
    final samples = [
      Sample(DateTime(2026, 10, 23, 8), 100, 'Zepp'),
      Sample(DateTime(2026, 10, 23, 9), 150, 'Zepp'),
      Sample(DateTime(2026, 10, 23, 9), 200, 'Fit'),
      Sample(DateTime(2026, 10, 24, 9), 50, 'Zepp'),
    ];
    expect(perDay(samples), {'2026-10-23': 250, '2026-10-24': 50});
    final a = ActivityData.build(total: samples, active: const [], steps: const [], workouts: const []);
    expect(a.averageOf((d) => d.totalKcal, DateTime(2026, 10, 22), DateTime(2026, 10, 24)), 150);
  });

  test('aktywność: formaty', () {
    expect(formatThousands(12345.6), '12 346');
    expect(formatThousands(999), '999');
    expect(formatDistance(5230), '5,2 km');
    expect(formatDistance(640), '640 m');
    expect(formatDuration(const Duration(minutes: 65)), '1:05 h');
    expect(workoutLabel('RUNNING'), 'Bieg');
    expect(workoutLabel('WATER_POLO'), 'water polo');
  });
}
