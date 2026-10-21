import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Lista szczytów z assets/peaks.json (kopia korona/data/peaks.json, kontrakt w korona/SYNC.md).
/// Liczba grup i szczytów nie jest stała - lista rośnie razem z aplikacją na zegarek.
class PeakGroup {
  const PeakGroup({required this.id, required this.name, required this.short, this.counted});

  final String id;
  final String name;
  final String short;

  /// Ile szczytów liczy się do „X / N” (KGP: 28, warianty nie). Brak = wszystkie bez wariantów.
  final int? counted;

  factory PeakGroup.fromJson(Map<String, dynamic> j) => PeakGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        short: (j['short'] as String?) ?? (j['name'] as String),
        counted: (j['counted'] as num?)?.toInt(),
      );
}

class Peak {
  const Peak({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.h,
    this.range = '',
    this.groups = const [],
    this.variantOf,
    this.border = false,
    this.note,
    this.osm,
    this.wiki,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  /// m n.p.m.; brak przy szczytach bez wysokości w OSM
  final int? h;
  final String range;
  final List<String> groups;

  /// Wariant szczytu z listy KGP: rozpoznawany i zapisywany, ale nie liczy się do „X / 28”
  final String? variantOf;
  final bool border;
  final String? note;
  final int? osm;

  /// Tytuł strony w polskiej Wikipedii, np. „Kiczora (Pasmo Łososińskie)”
  final String? wiki;

  bool get isVariant => variantOf != null;

  /// Doprecyzowanie z nawiasu w tytule Wikipedii, gdy nazwy się powtarzają (7× Kiczora):
  /// „Pasmo Łososińskie”. Pomija ogólniki („szczyt”), wysokość i samo pasmo.
  String? get wikiNote {
    final m = RegExp(r'\(([^)]+)\)\s*$').firstMatch(wiki ?? '');
    final note = m?[1]?.trim();
    if (note == null || note.isEmpty || note == range) return null;
    if (RegExp(r'^(szczyt|góra|wzgórze|szczyt w .*|\d+ m)$').hasMatch(note)) return null;
    return note;
  }

  factory Peak.fromJson(Map<String, dynamic> j) => Peak(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        h: (j['h'] as num?)?.round(),
        range: (j['range'] as String?) ?? '',
        groups: [for (final g in (j['groups'] as List? ?? const [])) g as String],
        variantOf: j['variantOf'] as String?,
        border: j['border'] == true,
        note: j['note'] as String?,
        osm: (j['osm'] as num?)?.toInt(),
        wiki: j['wiki'] as String?,
      );
}

class PeakCatalog {
  PeakCatalog({required this.groups, required this.peaks, this.generated = '', this.sources = const []})
      : byId = {for (final p in peaks) p.id: p};

  final List<PeakGroup> groups;
  final List<Peak> peaks;
  final Map<String, Peak> byId;
  final String generated;
  final List<String> sources;

  factory PeakCatalog.fromJsonString(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return PeakCatalog(
      groups: [for (final g in (j['groups'] as List? ?? const [])) PeakGroup.fromJson(g as Map<String, dynamic>)],
      peaks: [for (final p in (j['peaks'] as List? ?? const [])) Peak.fromJson(p as Map<String, dynamic>)],
      generated: (j['generated'] as String?) ?? '',
      sources: [for (final s in (j['sources'] as List? ?? const [])) s as String],
    );
  }

  static Future<PeakCatalog> load() async =>
      PeakCatalog.fromJsonString(await rootBundle.loadString('assets/peaks.json'));

  PeakGroup? group(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Szczyty grupy, od najwyższego (bez wysokości na końcu)
  List<Peak> peaksOf(String groupId) => peaks.where((p) => p.groups.contains(groupId)).toList()..sort(byHeight);

  /// Warianty danego szczytu (np. Borowa dla Chełmca)
  List<Peak> variantsOf(String peakId) => peaks.where((p) => p.variantOf == peakId).toList();

  static int byHeight(Peak a, Peak b) {
    final c = (b.h ?? -1).compareTo(a.h ?? -1);
    return c != 0 ? c : a.name.compareTo(b.name);
  }
}
