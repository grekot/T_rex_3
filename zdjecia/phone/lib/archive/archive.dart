// Archiwum z biblioteki Zdjęć Google (Takeout → narzędzie na PC → Firestore, ARCHIWUM.md): wpisy spisu
// i losowanie - wspomnienia dla zegarka i zdjęcia dla zegarów biurkowych. Czysta logika (testy).
import 'dart:convert';
import 'dart:math' as math;

import '../ai/photo_rating.dart';

/// Prefiks id w galerii (assetId) dla zdjęć z archiwum
const String archiveAssetPrefix = 'archiwum:';

/// Pokazane wspomnienie z archiwum wraca najwcześniej po tylu dniach (chyba że brakuje innych)
const Duration archiveRest = Duration(days: 120);

/// Szansa, że losujemy „ten sam tydzień X lat temu” (gdy są takie zdjęcia)
const double archiveAnniversaryChance = 0.35;
const int anniversaryWindowDays = 7;

/// Już zajęte lata (inne wspomnienia w puli) mają mniejszą szansę - wspomnienia z różnych lat
const double sameYearWeight = 0.3;

class ArchiveEntry {
  const ArchiveEntry({
    required this.id,
    required this.taken,
    this.caption = '',
    this.score = 7,
    this.width = 0,
    this.height = 0,
    this.focus,
    this.subject,
  });

  final String id;
  final DateTime taken;
  final String caption;
  final int score;
  final int width;
  final int height;
  final List<double>? focus;
  final List<double>? subject;

  /// Id w puli (bez kadru)
  String get photoId => 'a_$id';
  String get assetId => '$archiveAssetPrefix$id';

  /// Ocena jak od Gemini - zdjęcie z archiwum nie idzie już do AI
  PhotoRating get rating => PhotoRating(
        score: score.clamp(1, 10),
        keep: true,
        category: 'archiwum',
        caption: caption,
        reason: '',
        subject: subject,
        focus: focus,
        prefsHash: 'archiwum',
      );

  static final _id = RegExp(r'^[0-9a-f]{6,32}$');

  static ArchiveEntry? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['t'] is! num) return null;
    final id = j['id'] as String;
    if (!_id.hasMatch(id)) return null;
    List<double>? box(Object? v) {
      if (v is! List || v.length != 4 || v.any((x) => x is! num)) return null;
      final b = [for (final x in v) (x as num).toDouble()];
      return b.every((x) => x >= 0 && x <= 1) && b[2] > 0 && b[3] > 0 ? b : null;
    }

    return ArchiveEntry(
      id: id,
      taken: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
      caption: j['c'] is String ? j['c'] as String : '',
      score: j['s'] is num ? (j['s'] as num).toInt() : 7,
      width: j['w'] is num ? (j['w'] as num).toInt() : 0,
      height: j['h'] is num ? (j['h'] as num).toInt() : 0,
      focus: box(j['f']),
      subject: box(j['m']),
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        't': taken.millisecondsSinceEpoch,
        if (caption.isNotEmpty) 'c': caption,
        's': score,
        if (width > 0) 'w': width,
        if (height > 0) 'h': height,
        'f': ?focus,
        'm': ?subject,
      };
}

/// Spis z pola `items` (JSON jako tekst); błędne wpisy są pomijane
List<ArchiveEntry> parseArchiveItems(String json) {
  try {
    final list = jsonDecode(json);
    if (list is! List) return const [];
    final seen = <String>{};
    final out = <ArchiveEntry>[];
    for (final j in list) {
      final e = ArchiveEntry.fromJson(j);
      if (e != null && seen.add(e.id)) out.add(e);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String? archiveIdOf(String assetId) =>
    assetId.startsWith(archiveAssetPrefix) ? assetId.substring(archiveAssetPrefix.length) : null;

/// Dzień roku bez względu na rok przestępny (odległość w dniach po kole roku)
int _yearDayDistance(DateTime a, DateTime b) {
  int day(DateTime d) => d.difference(DateTime(d.year)).inDays;
  final diff = (day(a) - day(b)).abs();
  return math.min(diff, 365 - diff);
}

/// Losuje [count] zdjęć z archiwum:
///  - pomija [exclude] (już w puli / w strumieniu) i zdjęcia z ostatnich [recentDays] dni (to „świeże”, nie wspomnienia),
///  - pokazane w ciągu [rest] czekają; gdy brakuje innych - najdawniej pokazane najpierw,
///  - z szansą [archiveAnniversaryChance] „ten sam tydzień w innym roku”,
///  - lepsze oceny częściej, lata już zajęte ([avoidYears] i wybrane wcześniej) rzadziej.
List<ArchiveEntry> pickArchive(
  List<ArchiveEntry> entries, {
  required int count,
  required DateTime now,
  required math.Random random,
  Map<String, DateTime> shown = const {},
  Set<String> exclude = const {},
  Set<int> avoidYears = const {},
  int recentDays = 30,
  Duration rest = archiveRest,
}) {
  if (count <= 0) return const [];
  final cutoff = now.subtract(Duration(days: recentDays));
  final usable = [for (final e in entries) if (!exclude.contains(e.id) && e.taken.isBefore(cutoff)) e];
  bool rested(ArchiveEntry e) {
    final at = shown[e.id];
    return at == null || now.difference(at) >= rest;
  }

  final fresh = [for (final e in usable) if (rested(e)) e];
  final out = <ArchiveEntry>[];
  final years = {...avoidYears};
  final left = [...fresh];
  while (out.length < count && left.isNotEmpty) {
    var from = left;
    if (random.nextDouble() < archiveAnniversaryChance) {
      final near = [for (final e in left) if (e.taken.year != now.year && _yearDayDistance(e.taken, now) <= anniversaryWindowDays) e];
      if (near.isNotEmpty) from = near;
    }
    final weights = [for (final e in from) math.max(1, e.score - 4) * (years.contains(e.taken.year) ? sameYearWeight : 1.0)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var r = random.nextDouble() * total;
    var pick = from.last;
    for (var i = 0; i < from.length; i++) {
      r -= weights[i];
      if (r <= 0) {
        pick = from[i];
        break;
      }
    }
    out.add(pick);
    left.remove(pick);
    years.add(pick.taken.year);
  }
  if (out.length < count) {
    // Wszystkie odpoczywają: najdawniej pokazane wracają pierwsze
    final waiting = [for (final e in usable) if (!rested(e) && !out.contains(e)) e]
      ..sort((a, b) => shown[a.id]!.compareTo(shown[b.id]!));
    out.addAll(waiting.take(count - out.length));
  }
  return out;
}
