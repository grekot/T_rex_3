// Serie zdjęć (kilka ujęć tej samej sceny) i układanie puli dla zegarka:
// najlepsze zdjęcia, najwyżej [perDay] z jednego dnia, z różnych wydarzeń.
import 'quality.dart';
import 'scoring.dart';

/// Ujęcia zrobione tak blisko siebie to zawsze ta sama scena
const Duration burstAlways = Duration(seconds: 3);

/// W tym oknie podobne ujęcia (odcisk dHash) też są serią
const Duration burstWindow = Duration(seconds: 90);
const int burstMaxHamming = 14;

/// Grupy serii, każda posortowana od najlepszego zdjęcia
List<List<ScoredPhoto>> groupBursts(List<ScoredPhoto> photos) {
  final byTime = [...photos]..sort((a, b) => a.taken.compareTo(b.taken));
  final groups = <List<ScoredPhoto>>[];
  for (final p in byTime) {
    // Wystarczy podobieństwo do któregokolwiek ujęcia serii (jedno odmienne ujęcie jej nie przerywa)
    if (groups.isNotEmpty && groups.last.any((m) => _sameScene(m, p))) {
      groups.last.add(p);
    } else {
      groups.add([p]);
    }
  }
  for (final g in groups) {
    g.sort((a, b) => b.score.compareTo(a.score));
  }
  return groups;
}

bool _sameScene(ScoredPhoto a, ScoredPhoto b) {
  final gap = b.taken.difference(a.taken).abs();
  if (gap <= burstAlways) return true;
  return gap <= burstWindow && hammingDistance(a.analysis.quality.hash, b.analysis.quality.hash) <= burstMaxHamming;
}

class PoolRules {
  const PoolRules({
    required this.size,
    this.perDay = 2,
    this.eventGap = const Duration(hours: 2),
    this.pinned = const {},
    this.removed = const {},
  });

  final int size;
  final int perDay;

  /// Dwa zdjęcia z jednego dnia muszą być od siebie tak daleko w czasie (różne wydarzenia)
  final Duration eventGap;

  /// Przypięte zawsze wchodzą (także odrzucone przez punktację), usunięte nigdy
  final Set<String> pinned;
  final Set<String> removed;
}

/// Pula: przypięte, potem najlepsze z zachowaniem zasad; gdy brakuje zdjęć - zasady łagodnieją.
List<ScoredPhoto> choosePool(List<ScoredPhoto> photos, PoolRules rules) {
  final pool = <ScoredPhoto>[
    for (final p in photos)
      if (rules.pinned.contains(p.id) && !rules.removed.contains(p.id)) p,
  ]..sort((a, b) => b.score.compareTo(a.score));
  final taken = {for (final p in pool) p.id};

  // Z każdej serii tylko najlepsze ujęcie (chyba że inne ujęcie jest przypięte)
  final candidates = <ScoredPhoto>[];
  for (final group in groupBursts(photos.where((p) => p.accepted && !rules.removed.contains(p.id)).toList())) {
    if (group.any((p) => taken.contains(p.id))) continue;
    candidates.add(group.first);
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));

  void fill({required int perDay, required Duration gap}) {
    for (final c in candidates) {
      if (pool.length >= rules.size) return;
      if (taken.contains(c.id)) continue;
      final sameDay = pool.where((p) => _sameDay(p.taken, c.taken)).toList();
      if (sameDay.length >= perDay) continue;
      if (sameDay.any((p) => p.taken.difference(c.taken).abs() < gap)) continue;
      pool.add(c);
      taken.add(c.id);
    }
  }

  fill(perDay: rules.perDay, gap: rules.eventGap);
  fill(perDay: rules.perDay + 1, gap: Duration.zero);
  fill(perDay: 1 << 30, gap: Duration.zero);
  return pool;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
