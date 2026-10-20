// Wspomnienia: starsze zdjęcia w puli obok świeżych. Przy każdym odświeżeniu losujemy kilka okresów
// z historii galerii (część to „ten sam tydzień X lat temu”), z każdego wybieramy do 10 kandydatów
// rozłożonych w czasie, AI je ocenia, a najlepsze trafiają do puli na [memoryLifetime] - potem
// ustępują nowym, więc zegarek co jakiś czas dostaje zupełnie inne wspomnienie. Czysta logika (testy).
import 'dart:math' as math;

/// Tyle dni wspomnienie zostaje w puli (przypięte zostają na stałe)
const Duration memoryLifetime = Duration(days: 7);

/// Długość losowanego okresu
const Duration periodLength = Duration(days: 7);

/// Ile okresów najwyżej przy jednym odświeżeniu (każdy to jedno zapytanie do AI)
const int maxPeriodsPerRefresh = 6;

/// Ilu kandydatów z okresu trafia do oceny AI i ile najwyżej zostaje
const int candidatesPerPeriod = 10;
const int keepPerPeriod = 2;

/// Najniższa ocena AI, z którą zdjęcie może zostać wspomnieniem
const int minMemoryScore = 6;

/// Szansa, że okres to ten sam tydzień w którymś z poprzednich lat (rocznica)
const double anniversaryChance = 0.35;

/// Wersja listy wspomnień: wspomnienia z wcześniejszych wersji (losowane po dacie dodania pliku,
/// więc tylko z ostatnich miesięcy) są pomijane i od razu zastępowane nowymi
const int memoryFormat = 2;

class MemoryItem {
  const MemoryItem({required this.photoId, required this.assetId, required this.addedAt, required this.taken});

  final String photoId;
  final String assetId;
  final DateTime addedAt;
  final DateTime taken;

  Map<String, Object> toJson() => {
        'v': memoryFormat,
        'id': photoId,
        'asset': assetId,
        'added': addedAt.millisecondsSinceEpoch,
        'taken': taken.millisecondsSinceEpoch,
      };

  factory MemoryItem.fromJson(Map<String, dynamic> j) => MemoryItem(
        photoId: j['id'] as String,
        assetId: j['asset'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(j['added'] as int),
        taken: DateTime.fromMillisecondsSinceEpoch(j['taken'] as int),
      );
}

class Period {
  const Period(this.start, this.end, {this.anniversary = false});

  final DateTime start;
  final DateTime end;
  final bool anniversary;
}

/// Ile prób losowania, żeby trafić w rok, którego wśród wspomnień jeszcze nie ma
const int yearAttempts = 4;

/// Puste okresy (bez zdjęć) nie liczą się do limitu, ale wszystkich prób jest najwyżej tyle
const int maxPeriodAttempts = 30;

/// Losowy okres, w miarę możliwości z roku spoza [avoidYears] - wspomnienia rozłożone na różne lata
Period? randomPeriodSpread(DateTime oldest, DateTime now, int recentDays, math.Random random, Set<int> avoidYears) {
  Period? last;
  for (var i = 0; i < yearAttempts; i++) {
    last = randomPeriod(oldest, now, recentDays, random);
    if (last == null || !avoidYears.contains(last.start.year)) return last;
  }
  return last;
}

/// Losowy okres z historii [oldest .. now - recentDays]; null, gdy starszych zdjęć jeszcze nie ma.
Period? randomPeriod(DateTime oldest, DateTime now, int recentDays, math.Random random) {
  final latestEnd = now.subtract(Duration(days: recentDays));
  if (!oldest.isBefore(latestEnd)) return null;
  final years = latestEnd.year - oldest.year;
  if (years >= 1 && random.nextDouble() < anniversaryChance) {
    // Ten sam tydzień (od dziś do +7 dni) w losowym wcześniejszym roku z historii
    final yearsAgo = 1 + random.nextInt(years);
    final start = DateTime(now.year - yearsAgo, now.month, now.day);
    final end = start.add(periodLength);
    if (start.isAfter(oldest.subtract(periodLength)) && end.isBefore(latestEnd)) {
      return Period(start, end, anniversary: true);
    }
  }
  final spanMs = latestEnd.difference(oldest).inMilliseconds - periodLength.inMilliseconds;
  final startMs = oldest.millisecondsSinceEpoch + (spanMs <= 0 ? 0 : (random.nextDouble() * spanMs).floor());
  final start = DateTime.fromMillisecondsSinceEpoch(startMs);
  final end = start.add(periodLength);
  return Period(start, end.isAfter(latestEnd) ? latestEnd : end);
}

/// Wspomnienia, które jeszcze nie wygasły (przypięte zostają zawsze, usunięte znikają)
List<MemoryItem> activeMemories(List<MemoryItem> list, DateTime now, {Set<String> pinned = const {}, Set<String> removed = const {}}) => [
      for (final m in list)
        if (!removed.contains(m.photoId) && (pinned.contains(m.photoId) || now.difference(m.addedAt) < memoryLifetime)) m,
    ];

/// Ile wspomnień ma być w puli przy danej wielkości puli i udziale (procent)
int memoryTarget(int poolSize, int sharePercent) => (poolSize * sharePercent / 100).round().clamp(0, poolSize);

/// Do [count] elementów rozłożonych równomiernie w czasie, z każdej serii (odstęp < [burst]) jeden
List<T> spreadInTime<T>(List<T> items, DateTime Function(T) at, int count, {Duration burst = const Duration(seconds: 30)}) {
  final sorted = [...items]..sort((a, b) => at(a).compareTo(at(b)));
  final singles = <T>[];
  for (final item in sorted) {
    if (singles.isNotEmpty && at(item).difference(at(singles.last)) < burst) continue;
    singles.add(item);
  }
  if (singles.length <= count) return singles;
  return [for (var i = 0; i < count; i++) singles[(i * singles.length / count).floor()]];
}

/// Najlepsi według [score] (null = odrzucony), malejąco, najwyżej [count]
List<T> bestOf<T>(List<T> items, double? Function(T) score, int count) {
  final scored = [
    for (final item in items)
      if (score(item) != null) (item, score(item)!),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final e in scored.take(count)) e.$1];
}
