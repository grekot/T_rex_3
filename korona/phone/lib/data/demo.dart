import 'dart:math';

import 'climbs.dart';
import 'peaks.dart';

/// Przykładowe zdobycia do obejrzenia aplikacji bez zegarka: mniej więcej co drugi szczyt
/// każdej grupy w ostatnich latach, kilka wariantów i dwa własne szczyty.
/// Losowanie ze stałym ziarnem - za każdym razem te same dane.
ClimbsDoc demoClimbs(PeakCatalog catalog, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final rnd = Random(28);
  final climbs = <String, Climb>{};
  for (final p in catalog.peaks) {
    if (rnd.nextDouble() < 0.45) {
      final daysAgo = rnd.nextInt(365 * 4);
      final d = today.subtract(Duration(days: daysAgo));
      climbs[p.id] = Climb(peakId: p.id, date: DateTime(d.year, d.month, d.day), gps: rnd.nextDouble() < 0.7);
    }
  }
  final custom = [
    CustomPeak(
      id: 'c1',
      name: 'Gęsia Szyja',
      lat: 49.2600,
      lon: 20.0790,
      date: DateTime(today.year, today.month, 1).subtract(const Duration(days: 40)),
      gps: true,
    ),
    CustomPeak(
      id: 'c2',
      name: 'Wysoki Wierch',
      lat: 49.4027,
      lon: 20.4877,
      date: DateTime(today.year - 1, 8, 14),
    ),
  ];
  return ClimbsDoc(climbs: climbs, custom: custom, updatedAt: today);
}
