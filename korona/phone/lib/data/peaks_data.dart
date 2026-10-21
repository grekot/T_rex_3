import 'climbs.dart';
import 'peaks.dart';
import 'stats.dart';

/// Stan widoczny na ekranach: lista szczytów + zdobycia (z Firestore albo przykładowe)
class PeaksData {
  PeaksData({required this.catalog, required this.doc, this.demo = false});

  final PeakCatalog catalog;
  final ClimbsDoc doc;

  /// Przykładowe dane zamiast zdobyć z zegarka
  final bool demo;

  Climb? climbOf(String peakId) => doc.climbs[peakId];

  late final List<GroupProgress> progress = [for (final g in catalog.groups) groupProgress(catalog, doc, g)];

  late final List<TimelineEntry> entries = timeline(catalog, doc);
}
