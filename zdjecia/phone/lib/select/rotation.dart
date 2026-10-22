// Rotacja świeżych zdjęć: każde jest w puli [freshStayMin]-[freshStayMax], potem odpoczywa [freshRest],
// a jego miejsce zajmuje inne dobre zdjęcie (losowane, lepsze częściej). Zdjęcia zrobione niedawno
// i jeszcze nie pokazane wchodzą od razu. Ważność rozłożona losowo, więc pula zmienia się po trochu,
// a nie cała naraz. Czysta logika (testy).
import 'dart:math' as math;

import 'pool.dart';
import 'scoring.dart';

const Duration freshStayMin = Duration(days: 2);
const Duration freshStayMax = Duration(days: 4);

/// Po zejściu z puli zdjęcie tyle czeka, zanim znów może wejść (chyba że brakuje innych)
const Duration freshRest = Duration(days: 14);

/// Zdjęcie zrobione tak niedawno i jeszcze niepokazane wchodzi do puli od razu
const Duration newPhotoAge = Duration(days: 3);
const int maxNewPerRefresh = 2;

/// Ile świeżych zdjęć wymienia ręczne „Odśwież”
const int freshSwapOnRefresh = 3;

class FreshSlot {
  const FreshSlot({required this.photoId, required this.addedAt, required this.expiresAt});

  final String photoId;
  final DateTime addedAt;
  final DateTime expiresAt;

  Map<String, Object> toJson() => {
        'id': photoId,
        'added': addedAt.millisecondsSinceEpoch,
        'expires': expiresAt.millisecondsSinceEpoch,
      };

  factory FreshSlot.fromJson(Map<String, dynamic> j) => FreshSlot(
        photoId: j['id'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(j['added'] as int),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(j['expires'] as int),
      );
}

class FreshRotation {
  FreshRotation({List<FreshSlot>? slots, Map<String, DateTime>? resting})
      : slots = slots ?? [],
        resting = resting ?? {};

  /// Świeże zdjęcia teraz w puli (bez przypiętych - te są na stałe)
  List<FreshSlot> slots;

  /// Zdjęcia, które były w puli: id -> do kiedy odpoczywają
  final Map<String, DateTime> resting;

  bool get isEmpty => slots.isEmpty && resting.isEmpty;

  Map<String, Object> toJson() => {
        'slots': [for (final s in slots) s.toJson()],
        'resting': {for (final e in resting.entries) e.key: e.value.millisecondsSinceEpoch},
      };

  factory FreshRotation.fromJson(Map<String, dynamic> j) => FreshRotation(
        slots: [
          for (final s in (j['slots'] as List? ?? const []))
            if (s is Map) FreshSlot.fromJson(s.cast<String, dynamic>()),
        ],
        resting: {
          for (final e in ((j['resting'] as Map?) ?? const {}).entries)
            e.key as String: DateTime.fromMillisecondsSinceEpoch(e.value as int),
        },
      );
}

/// Świeża część puli z rotacją; [state] jest aktualizowany. [swap] = ile zdjęć wymienić od razu
/// (te, którym najbliżej do końca).
List<ScoredPhoto> rotateFresh(
  List<ScoredPhoto> photos,
  PoolRules rules,
  FreshRotation state,
  DateTime now,
  math.Random random, {
  int swap = 0,
}) {
  final hadHistory = !state.isEmpty;
  state.resting.removeWhere((_, until) => !until.isAfter(now));
  void rest(String id) => state.resting[id] = now.add(freshRest);

  final byId = {for (final p in photos) p.id: p};
  bool usable(String id) {
    final p = byId[id];
    return p != null && p.accepted && !rules.removed.contains(id) && !rules.pinned.contains(id);
  }

  // Zostają te, którym nie minął czas; wygasłe idą odpocząć
  final kept = <FreshSlot>[];
  for (final s in state.slots) {
    if (!usable(s.photoId)) continue;
    if (s.expiresAt.isAfter(now)) {
      kept.add(s);
    } else {
      rest(s.photoId);
    }
  }
  kept.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  for (final s in kept.take(swap).toList()) {
    kept.remove(s);
    rest(s.photoId);
  }

  // Nowo zrobione, jeszcze niepokazane, co najmniej przeciętne - od razu, w razie potrzeby
  // zamiast zdjęć, którym najbliżej do końca. Przy pierwszej rotacji wszystko jest „niepokazane”.
  final keptIds = {for (final s in kept) s.photoId};
  final accepted = [for (final p in photos) if (usable(p.id)) p]..sort((a, b) => b.score.compareTo(a.score));
  final fresh = <ScoredPhoto>[];
  if (hadHistory && accepted.isNotEmpty) {
    final median = accepted[accepted.length ~/ 2].score;
    fresh.addAll(accepted
        .where((p) =>
            now.difference(p.taken) < newPhotoAge &&
            !keptIds.contains(p.id) &&
            !state.resting.containsKey(p.id) &&
            p.score >= median)
        .take(maxNewPerRefresh));
  }
  final room = rules.size - rules.pinned.where(byId.containsKey).length;
  while (kept.isNotEmpty && kept.length + fresh.length > room) {
    rest(kept.removeAt(0).photoId);
  }

  // Reszta miejsc: losowanie z przewagą lepszych; odpoczywające tylko gdy brakuje innych
  final rank = {for (var i = 0; i < accepted.length; i++) accepted[i].id: i};
  final scale = math.max(1, rules.size);
  final priority = <String, double>{};
  for (final p in photos) {
    final r = rank[p.id];
    if (r == null) {
      priority[p.id] = -2;
    } else if (state.resting.containsKey(p.id)) {
      priority[p.id] = -1 - r / (accepted.length + 1);
    } else {
      // Klucz Efraimidisa-Spirakisa: u^(1/w), waga łagodnie maleje z miejscem w rankingu
      final w = 1 / (1 + r / scale);
      priority[p.id] = math.pow(1 - random.nextDouble(), 1 / w).toDouble();
    }
  }
  final chosen = choosePool(
    photos,
    PoolRules(
      size: rules.size,
      perDay: rules.perDay,
      eventGap: rules.eventGap,
      pinned: {...rules.pinned, ...kept.map((s) => s.photoId), ...fresh.map((p) => p.id)},
      removed: rules.removed,
    ),
    priority: (p) => priority[p.id] ?? -2,
  );

  final keptById = {for (final s in kept) s.photoId: s};
  state.slots = [
    for (final p in chosen)
      if (!rules.pinned.contains(p.id))
        keptById[p.id] ??
            FreshSlot(
              photoId: p.id,
              addedAt: now,
              expiresAt: now.add(freshStayMin +
                  Duration(minutes: random.nextInt((freshStayMax - freshStayMin).inMinutes + 1))),
            ),
  ];
  for (final s in state.slots) {
    state.resting.remove(s.photoId);
  }
  return chosen;
}
