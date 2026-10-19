// Punktacja „ciekawości” zdjęcia. Ostrość i kolorowość liczone względem pozostałych zdjęć
// z tego samego okresu (centyl), bo każdy aparat daje inne wartości bezwzględne.
import 'dart:math' as math;

import 'analysis.dart';
import 'labels.dart';

class ScoredPhoto {
  const ScoredPhoto({
    required this.analysis,
    required this.score,
    required this.tags,
    this.rejected,
  });

  final PhotoAnalysis analysis;
  final double score;

  /// Powody wyboru (najważniejsze najpierw), np. ["ulubione", "2 twarze", "uśmiech"]
  final List<String> tags;

  /// Powód odrzucenia albo null
  final String? rejected;

  String get id => analysis.id;
  DateTime get taken => analysis.taken;
  bool get accepted => rejected == null;
}

/// Bardzo rozmyte niezależnie od reszty zdjęć
const double minSharpness = 20;

/// Ten ułamek najmniej ostrych zdjęć z okresu odpada (chyba że ulubione)
const double blurryShare = 0.12;

/// Twarze mniejsze niż ten ułamek powierzchni to tło (przechodnie), nie bohaterowie zdjęcia
const double minFaceArea = 0.005;

List<ScoredPhoto> scoreAll(List<PhotoAnalysis> photos, {required DateTime now, required int days}) {
  final sharpRank = _percentiles([for (final p in photos) math.log(1 + p.quality.sharpness)]);
  final colorRank = _percentiles([for (final p in photos) p.quality.colorfulness]);
  return [
    for (var i = 0; i < photos.length; i++)
      scorePhoto(photos[i], sharpRank: sharpRank[i], colorRank: colorRank[i], now: now, days: days),
  ];
}

ScoredPhoto scorePhoto(
  PhotoAnalysis a, {
  required double sharpRank,
  required double colorRank,
  required DateTime now,
  required int days,
}) {
  final q = a.quality;
  final tags = <_Tag>[];
  final faces = mainFaces(a.faces);

  String? rejected;
  if (_isDocument(a, faces)) {
    rejected = 'dokument / tekst';
  } else if (!a.favorite && (q.sharpness < minSharpness || sharpRank < blurryShare)) {
    rejected = 'nieostre';
  } else if (!a.favorite && (q.brightness < 0.08 || q.brightness > 0.95)) {
    rejected = q.brightness < 0.08 ? 'za ciemne' : 'prześwietlone';
  }

  var score = 0.35 * sharpRank + 0.15 * colorRank;
  final exposure = 1 - math.min(1.0, (q.brightness - 0.48).abs() / 0.4);
  score += 0.2 * exposure;
  if (q.dark + q.bright > 0.35) score -= 0.3;
  if (sharpRank > 0.8) tags.add(_Tag('ostre', 0.1));
  if (colorRank > 0.85) tags.add(_Tag('kolorowe', 0.08));

  if (faces.isNotEmpty) {
    final largest = faces.map((f) => f.area).reduce(math.max);
    var faceScore = 0.6 + math.min(0.3, largest * 3) + 0.05 * math.min(faces.length, 4);
    tags.add(_Tag(faces.length == 1 ? 'twarz' : '${faces.length} twarze', faceScore));
    final smiles = faces.map((f) => f.smile).whereType<double>().toList();
    if (smiles.isNotEmpty) {
      final smile = smiles.reduce((x, y) => x + y) / smiles.length;
      faceScore += 0.25 * smile;
      if (smile > 0.6) tags.add(_Tag('uśmiech', 0.25 * smile));
    }
    if (faces.any((f) => f.eyesOpen != null && f.eyesOpen! < 0.2 && f.area >= largest * 0.5)) faceScore -= 0.3;
    score += faceScore;
  }

  final groupScores = <String, double>{};
  var labelScore = 0.0;
  for (final group in labelGroups) {
    final best = a.labels.where((l) => group.labels.contains(l.name)).fold<double>(0, (m, l) => math.max(m, l.confidence));
    if (best == 0) continue;
    labelScore += group.weight * best;
    if (group.tag.isNotEmpty) groupScores[group.tag] = group.weight * best;
  }
  score += labelScore.clamp(-0.6, 0.8);
  groupScores.forEach((tag, value) => tags.add(_Tag(tag, value)));

  if (a.favorite) {
    score += 1.0;
    tags.add(_Tag('ulubione', 1.0));
  }

  final ageDays = now.difference(a.taken).inHours / 24;
  score += 0.15 * (1 - (ageDays / math.max(days, 1)).clamp(0.0, 1.0));

  tags.sort((x, y) => y.value.compareTo(x.value));
  return ScoredPhoto(
    analysis: a,
    score: score,
    tags: [for (final t in tags.take(3)) t.name],
    rejected: rejected,
  );
}

/// Twarze bohaterów zdjęcia (bez malutkich twarzy w tle)
List<FaceBox> mainFaces(List<FaceBox> faces) {
  final visible = faces.where((f) => f.area >= minFaceArea).toList();
  if (visible.isEmpty) return const [];
  final largest = visible.map((f) => f.area).reduce(math.max);
  return visible.where((f) => f.area >= largest * 0.25).toList();
}

bool _isDocument(PhotoAnalysis a, List<FaceBox> faces) {
  if (a.labels.any((l) => documentLabels.contains(l.name) && l.confidence >= documentConfidence)) return true;
  return faces.isEmpty && a.textChars >= documentTextChars;
}

/// Centyle 0..1 (najmniejsza wartość = 0, największa = 1, równe wartości - ten sam centyl)
List<double> _percentiles(List<double> values) {
  if (values.isEmpty) return const [];
  if (values.length == 1) return const [0.5];
  final sorted = [...values]..sort();
  return [
    for (final v in values) _lowerBound(sorted, v) / (sorted.length - 1),
  ];
}

int _lowerBound(List<double> sorted, double v) {
  var lo = 0, hi = sorted.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (sorted[mid] < v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

class _Tag {
  _Tag(this.name, this.value);

  final String name;
  final double value;
}
