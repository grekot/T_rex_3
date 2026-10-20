import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:korona/data/climbs.dart';
import 'package:korona/data/demo.dart';
import 'package:korona/data/peaks.dart';
import 'package:korona/data/stats.dart';
import 'package:korona/ui/format.dart';

void main() {
  // Prawdziwa lista z assetów (kopia korona/data/peaks.json)
  final catalog = PeakCatalog.fromJsonString(File('assets/peaks.json').readAsStringSync());

  group('peaks.json', () {
    test('kopia w assetach jest aktualna (node tools/copy_peaks.mjs)', () {
      final source = File('../data/peaks.json');
      if (!source.existsSync()) return;
      // Assety mogą być nowsze niż data/ na tej gałęzi, ale nie mogą gubić szczytów ani grup
      final shared = PeakCatalog.fromJsonString(source.readAsStringSync());
      expect(catalog.byId.keys, containsAll(shared.byId.keys));
      expect(catalog.groups.map((g) => g.id), containsAll(shared.groups.map((g) => g.id)));
    });

    test('dopisek z Wikipedii rozróżnia powtarzające się nazwy', () {
      Peak peak(String wiki) =>
          Peak.fromJson({'id': 'x', 'name': 'Kiczora', 'lat': 1, 'lon': 2, 'range': 'Gorce', 'wiki': wiki});
      expect(peak('Kiczora (Pasmo Łososińskie)').wikiNote, 'Pasmo Łososińskie');
      expect(peak('Kiczora (szczyt)').wikiNote, isNull);
      expect(peak('Kiczora (Gorce)').wikiNote, isNull);
      expect(peak('Kiczora (839 m)').wikiNote, isNull);
      expect(peak('Kiczora').wikiNote, isNull);
      expect(catalog.peaks.where((p) => p.name == 'Kiczora').length, greaterThan(1));
    });

    test('każdy szczyt ma znaną grupę, warianty wskazują istniejący szczyt', () {
      expect(catalog.groups, isNotEmpty);
      final ids = catalog.groups.map((g) => g.id).toSet();
      for (final p in catalog.peaks) {
        expect(p.groups, isNotEmpty, reason: p.id);
        expect(ids.containsAll(p.groups), isTrue, reason: p.id);
        if (p.variantOf != null) expect(catalog.byId[p.variantOf], isNotNull, reason: p.id);
      }
      expect(catalog.byId.length, catalog.peaks.length, reason: 'powtórzone id');
    });

    test('KGP: 28 do zdobycia, warianty osobno', () {
      final kgp = catalog.group('kgp')!;
      final p = groupProgress(catalog, const ClimbsDoc.empty(), kgp);
      expect(p.counted, 28);
      expect(p.main.length, 28);
      expect(p.variants.map((v) => v.id), contains('borowa'));
      expect(p.main.first.id, 'rysy');
    });

    test('grupa bez counted liczy wszystkie szczyty bez wariantów', () {
      final c = PeakCatalog.fromJsonString('''
        {"groups":[{"id":"g","name":"Gorce"}],
         "peaks":[{"id":"a","name":"A","lat":1,"lon":2,"groups":["g"]},
                  {"id":"b","name":"B","lat":1,"lon":2,"h":900,"groups":["g"]}]}''');
      final p = groupProgress(c, ClimbsDoc.fromMap({'climbs': {'a': {'d': '2025-01-02'}}}), c.groups.first);
      expect(p.counted, 2);
      expect(p.climbed, 1);
      expect(p.main.first.id, 'b', reason: 'bez wysokości na końcu');
      expect(c.groups.first.short, 'Gorce');
    });
  });

  group('dokument korona/{uid}', () {
    test('czyta climbs i custom, pomija złe wpisy', () {
      final doc = ClimbsDoc.fromMap({
        'climbs': {
          'rysy': {'d': '2024-07-15', 'gps': true},
          'babia': {'d': '2023-02-30'},
          'sniezka': {'d': 'wczoraj'},
          'tarnica': 'zle',
          'turbacz': {'d': '2022-08-01'},
        },
        'custom': {
          'c1': {'name': 'Gęsia Szyja', 'lat': 49.26, 'lon': 20.08, 'd': '2025-06-01', 'gps': true},
          'c2': {'name': '', 'lat': 49.0, 'lon': 20.0, 'd': '2025-07-01'},
          'c3': {'name': 'Bez pozycji', 'd': '2025-07-01'},
        },
        'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 20, 14, 5)),
        'v': 1,
      });
      expect(doc.climbs.keys, unorderedEquals(['rysy', 'turbacz']));
      expect(doc.climbs['rysy']!.gps, isTrue);
      expect(doc.climbs['turbacz']!.gps, isFalse);
      expect(doc.climbs['rysy']!.date, DateTime(2024, 7, 15));
      expect(doc.custom.map((c) => c.id), ['c2', 'c1'], reason: 'od najnowszego');
      expect(doc.custom.first.name, 'Szczyt');
      expect(doc.updatedAt, DateTime(2026, 10, 20, 14, 5));
      expect(doc.exists, isTrue);
    });

    test('brak dokumentu', () {
      final doc = ClimbsDoc.fromMap(null);
      expect(doc.exists, isFalse);
      expect(doc.total, 0);
    });

    test('parseDay', () {
      expect(parseDay('2024-02-29'), DateTime(2024, 2, 29));
      expect(parseDay('2023-02-29'), isNull);
      expect(parseDay('2024-13-01'), isNull);
      expect(parseDay(20240101), isNull);
    });
  });

  group('statystyki', () {
    final doc = ClimbsDoc.fromMap({
      'climbs': {
        'rysy': {'d': '2024-07-15', 'gps': true},
        'lysica': {'d': '2021-05-01'},
        'borowa': {'d': '2024-09-01', 'gps': true},
        'usuniety': {'d': '2024-01-01'},
      },
      'custom': {
        'c1': {'name': 'Gęsia Szyja', 'lat': 49.26, 'lon': 20.08, 'd': '2026-06-01'},
      },
    });

    test('postęp KGP nie liczy wariantów', () {
      final p = groupProgress(catalog, doc, catalog.group('kgp')!);
      expect(p.climbed, 2);
      expect(p.fraction, closeTo(2 / 28, 1e-9));
      expect(p.complete, isFalse);
    });

    test('oś czasu od najnowszego, nieznane id zostaje', () {
      final t = timeline(catalog, doc);
      expect(t.map((e) => e.id), ['c1', 'borowa', 'rysy', 'usuniety', 'lysica']);
      expect(t[3].peak, isNull);
      expect(t[3].name, 'usuniety');
      expect(t.first.custom, isNotNull);
    });

    test('zdobycia w latach bez dziur', () {
      final years = climbsPerYear(timeline(catalog, doc));
      expect(years, [(2021, 1), (2022, 0), (2023, 0), (2024, 3), (2025, 0), (2026, 1)]);
      expect(climbsPerYear(const []), isEmpty);
    });

    test('podsumowanie', () {
      final s = summarize(timeline(catalog, doc), now: DateTime(2026, 10, 20));
      expect(s.total, 5);
      expect(s.custom, 1);
      expect(s.gps, 2);
      expect(s.thisYear, 1);
      expect(s.highest!.id, 'rysy');
      expect(s.first!.id, 'lysica');
    });

    test('przykładowe dane są stałe i poprawne', () {
      final now = DateTime(2026, 10, 20);
      final a = demoClimbs(catalog, now: now), b = demoClimbs(catalog, now: now);
      expect(a.climbs.keys, b.climbs.keys);
      expect(a.climbs, isNotEmpty);
      expect(a.custom, hasLength(2));
      for (final c in a.climbs.values) {
        expect(c.date.isAfter(now), isFalse);
        expect(catalog.byId[c.peakId], isNotNull);
      }
    });
  });

  group('format', () {
    test('daty i liczby po polsku', () {
      expect(formatDay(DateTime(2024, 7, 15)), '15 lipca 2024');
      expect(formatShortDay(DateTime(2024, 7, 5)), '05.07.2024');
      expect(formatDateTime(DateTime(2026, 10, 20, 9, 5)), '20 października 2026, 9:05');
      expect(peaksCount(1), '1 szczyt');
      expect(peaksCount(3), '3 szczyty');
      expect(peaksCount(12), '12 szczytów');
      expect(peaksCount(22), '22 szczyty');
      expect(peaksCount(25), '25 szczytów');
      expect(formatHeight(null), '—');
      expect(formatLatLon(49.1795756, 20.0881081), '49,17958° N, 20,08811° E');
    });
  });
}
