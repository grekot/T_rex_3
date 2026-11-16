// Nowe zdjęcia z telefonu do archiwum (od 0.12.0): najlepsze według oceny Gemini, którą telefon i tak już ma
// (bez dodatkowych zapytań), po kilku dniach od zrobienia, z limitami na wydarzenie i dzień jak przy wyborze na PC.
// Bez tego zdjęcia zrobione po eksporcie Takeout nigdy nie wróciłyby jako wspomnienia. Czysta logika (testy).
import 'dart:convert';

import '../ai/photo_rating.dart';
import 'archive.dart';

/// Najniższa ocena Gemini, od której zdjęcie samo trafia do archiwum
const int addMinScore = 7;

/// Zdjęcie czeka tyle od zrobienia (czas na usunięcie nieudanych, seria się kończy)
const Duration addAfter = Duration(days: 3);

/// Najwięcej zdjęć z jednego wydarzenia (zdjęcia w odstępie do [addEventWindow]) i z jednego dnia
const int addPerEvent = 2;
const Duration addEventWindow = Duration(hours: 3);
const int addPerDay = 3;

/// Najwięcej wysyłanych przy jednym odświeżeniu (reszta przy następnym)
const int addPerRun = 12;

/// Ocena zdjęć bez oceny AI (przypięte, dodane ręcznie)
const int addDefaultScore = 7;

/// Wpis spisu dodany z telefonu (narzędzie na PC go zachowuje)
const String phoneSource = 'tel';

/// Podpis w spisie: najwyżej tyle znaków (zegarek dopisuje „ · rok”)
const int archiveCaptionLimit = 28;

/// To samo ujęcie: ta sama nazwa pliku i czas do tylu godzin różnicy (strefa czasowa telefonu vs Zdjęć Google)
const Duration sameShotWindow = Duration(hours: 14);

class AddCandidate {
  const AddCandidate({
    required this.photoId,
    required this.assetId,
    required this.name,
    required this.taken,
    this.rating,
    this.pinned = false,
    this.manual = false,
  });

  /// Id w puli (galeria telefonu)
  final String photoId;
  final String assetId;

  /// Nazwa pliku (np. 20261115_123456.jpg) - po niej rozpoznaje się to samo zdjęcie w Takeoucie
  final String name;
  final DateTime taken;
  final PhotoRating? rating;
  final bool pinned;

  /// „Dodaj do archiwum” - bez czekania i bez limitów
  final bool manual;

  bool get _good => rating != null && rating!.keep && rating!.score >= addMinScore;
}

/// Id w archiwum dla zdjęcia z telefonu: 12 znaków hex z nazwy i czasu (stałe - ponowna wysyłka nadpisuje)
String phoneArchiveId(String name, DateTime taken) {
  // FNV-1a 64-bit (Dart na telefonie: int 64-bit z przepełnieniem)
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode('tel|${name.toLowerCase()}|${taken.millisecondsSinceEpoch}')) {
    h ^= b;
    h *= 0x100000001b3;
  }
  return (h & 0xffffffffffff).toRadixString(16).padLeft(12, '0');
}

bool sameShot(String? nameA, DateTime takenA, String? nameB, DateTime takenB) {
  if (nameA == null || nameB == null || nameA.isEmpty) return false;
  if (nameA.toLowerCase() != nameB.toLowerCase()) return false;
  return takenA.difference(takenB).abs() <= sameShotWindow;
}

/// Podpis skrócony jak na PC: na granicy słowa, bez kończących znaków interpunkcji
String clipCaption(String text, [int limit = archiveCaptionLimit]) {
  final t = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (t.length <= limit) return t;
  final head = t.substring(0, limit + 1);
  final space = head.lastIndexOf(' ');
  final cut = space >= limit ~/ 2 ? head.substring(0, space) : t.substring(0, limit);
  return cut.replaceAll(RegExp(r'[ ,.;:-]+$'), '');
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Które zdjęcia wysłać teraz:
///  - ręcznie dodane zawsze (od razu, bez limitów),
///  - przypięte i z oceną AI ≥ [addMinScore] (keep) po [addAfter] od zrobienia,
///  - pomija już dodane ([added] - id w puli), usunięte z puli ([removed]) i te, które już są w spisie (to samo ujęcie),
///  - najlepsze najpierw, najwyżej [addPerEvent] z wydarzenia i [addPerDay] z dnia (licząc to, co już jest w spisie).
List<AddCandidate> chooseAdditions(
  List<AddCandidate> candidates, {
  required List<ArchiveEntry> existing,
  required Set<String> added,
  required DateTime now,
  Set<String> removed = const {},
  int perRun = addPerRun,
}) {
  final eligible = [
    for (final c in candidates)
      if (!added.contains(c.photoId) &&
          (c.manual || !removed.contains(c.photoId)) &&
          !existing.any((e) => sameShot(e.name, e.taken, c.name, c.taken)) &&
          (c.manual || ((c.pinned || c._good) && now.difference(c.taken) >= addAfter)))
        c,
  ];
  int rank(AddCandidate c) => c.manual ? 2 : (c.pinned ? 1 : 0);
  eligible.sort((a, b) {
    final r = rank(b).compareTo(rank(a));
    if (r != 0) return r;
    final s = (b.rating?.score ?? 0).compareTo(a.rating?.score ?? 0);
    return s != 0 ? s : a.taken.compareTo(b.taken);
  });
  final times = [for (final e in existing) e.taken];
  final out = <AddCandidate>[];
  final seen = <String>{};
  for (final c in eligible) {
    if (out.length >= perRun) break;
    if (!seen.add(c.photoId)) continue;
    if (!c.manual && !c.pinned) {
      final event = times.where((t) => t.difference(c.taken).abs() < addEventWindow).length;
      final day = times.where((t) => _sameDay(t, c.taken)).length;
      if (event >= addPerEvent || day >= addPerDay) continue;
    }
    out.add(c);
    times.add(c.taken);
  }
  return out;
}

/// Wpis spisu dla zdjęcia z telefonu (ARCHIWUM.md): ocena, podpis i kadr od Gemini, nazwa pliku i źródło „tel”
Map<String, Object> phoneEntry(AddCandidate c, String id, int width, int height) {
  final r = c.rating;
  final caption = clipCaption(r?.caption ?? '');
  return {
    'id': id,
    't': c.taken.millisecondsSinceEpoch,
    if (caption.isNotEmpty) 'c': caption,
    's': (r?.score ?? addDefaultScore).clamp(1, 10),
    'w': width,
    'h': height,
    'f': ?r?.focus,
    'm': ?r?.subject,
    'n': c.name,
    'src': phoneSource,
  };
}

/// Spis po dopisaniu [add] do [itemsJson]: wpisy, których telefon nie zna, zostają bez zmian (pola z PC);
/// bez dubli id i bez drugiego wpisu tego samego ujęcia. Zwraca nowy JSON i liczbę wpisów.
({String json, int count}) mergeItems(String itemsJson, List<Map<String, Object>> add) {
  List<Object?> list;
  try {
    final decoded = jsonDecode(itemsJson);
    list = decoded is List ? [...decoded] : [];
  } catch (_) {
    list = [];
  }
  final ids = {for (final x in list) if (x is Map && x['id'] is String) x['id'] as String};
  bool known(Map<String, Object> e) => list.any((x) =>
      x is Map &&
      x['t'] is num &&
      sameShot(x['n'] as String?, DateTime.fromMillisecondsSinceEpoch((x['t'] as num).toInt()), e['n'] as String?,
          DateTime.fromMillisecondsSinceEpoch(e['t'] as int)));
  for (final e in add) {
    if (ids.contains(e['id']) || known(e)) continue;
    ids.add(e['id'] as String);
    list.add(e);
  }
  int t(Object? x) => x is Map && x['t'] is num ? (x['t'] as num).toInt() : 0;
  list.sort((a, b) => t(a).compareTo(t(b)));
  return (json: jsonEncode(list), count: list.length);
}
