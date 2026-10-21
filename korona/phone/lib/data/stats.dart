import 'climbs.dart';
import 'peaks.dart';

/// Postęp jednej grupy („12 / 28”)
class GroupProgress {
  const GroupProgress({required this.group, required this.main, required this.variants, required this.climbed});

  final PeakGroup group;

  /// Szczyty liczone do postępu, od najwyższego
  final List<Peak> main;

  /// Warianty (np. KGP: Borowa zamiast Chełmca) - rozpoznawane, nie liczą się
  final List<Peak> variants;

  /// Ile szczytów z [main] zdobyto (bez wariantów)
  final int climbed;

  /// Mianownik: `counted` z peaks.json, a bez niego liczba szczytów bez wariantów
  int get counted => group.counted ?? main.length;

  double get fraction => counted == 0 ? 0 : (climbed / counted).clamp(0.0, 1.0);

  bool get complete => counted > 0 && climbed >= counted;
}

GroupProgress groupProgress(PeakCatalog catalog, ClimbsDoc doc, PeakGroup group) {
  final all = catalog.peaksOf(group.id);
  final main = all.where((p) => !p.isVariant).toList();
  final variants = all.where((p) => p.isVariant).toList();
  final climbed = main.where((p) => doc.climbs.containsKey(p.id)).length;
  return GroupProgress(group: group, main: main, variants: variants, climbed: climbed);
}

/// Jedno zdobycie na osi czasu: szczyt z listy albo własny
class TimelineEntry {
  const TimelineEntry({required this.date, required this.gps, required this.name, this.peak, this.custom, this.id = ''});

  final DateTime date;
  final bool gps;
  final String name;

  /// Szczyt z listy (null dla własnego albo nieznanego id)
  final Peak? peak;
  final CustomPeak? custom;

  /// id zdobycia (peakId albo customId)
  final String id;

  int? get h => peak?.h;
}

/// Wszystkie zdobycia od najnowszego. Nieznane id (np. szczyt usunięty z listy) zostają z id jako nazwą.
List<TimelineEntry> timeline(PeakCatalog catalog, ClimbsDoc doc) {
  final out = <TimelineEntry>[
    for (final c in doc.climbs.values)
      TimelineEntry(
        date: c.date,
        gps: c.gps,
        name: catalog.byId[c.peakId]?.name ?? c.peakId,
        peak: catalog.byId[c.peakId],
        id: c.peakId,
      ),
    for (final c in doc.custom)
      TimelineEntry(date: c.date, gps: c.gps, name: c.name, custom: c, id: c.id),
  ];
  out.sort((a, b) {
    final d = b.date.compareTo(a.date);
    return d != 0 ? d : a.name.compareTo(b.name);
  });
  return out;
}

/// Liczba zdobyć w kolejnych latach (bez dziur: lata bez zdobyć mają 0)
List<(int, int)> climbsPerYear(List<TimelineEntry> entries) {
  if (entries.isEmpty) return const [];
  final counts = <int, int>{};
  for (final e in entries) {
    counts[e.date.year] = (counts[e.date.year] ?? 0) + 1;
  }
  final years = counts.keys.toList()..sort();
  return [for (var y = years.first; y <= years.last; y++) (y, counts[y] ?? 0)];
}

class Summary {
  const Summary({
    required this.listed,
    required this.custom,
    required this.gps,
    required this.thisYear,
    this.highest,
    this.first,
  });

  /// Zdobyte szczyty z listy (każdy liczony raz, z wariantami)
  final int listed;
  final int custom;

  /// Ile zdobyć zaliczył GPS na szczycie (reszta dodana ręcznie)
  final int gps;
  final int thisYear;
  final TimelineEntry? highest;
  final TimelineEntry? first;

  int get total => listed + custom;
}

Summary summarize(List<TimelineEntry> entries, {DateTime? now}) {
  final year = (now ?? DateTime.now()).year;
  TimelineEntry? highest;
  for (final e in entries) {
    if (e.h != null && (highest == null || e.h! > highest.h!)) highest = e;
  }
  return Summary(
    listed: entries.where((e) => e.custom == null).length,
    custom: entries.where((e) => e.custom != null).length,
    gps: entries.where((e) => e.gps).length,
    thisYear: entries.where((e) => e.date.year == year).length,
    highest: highest,
    first: entries.isEmpty ? null : entries.last,
  );
}
