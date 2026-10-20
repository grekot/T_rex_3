import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zdjecia/ai/photo_rating.dart';
import 'package:zdjecia/pool_controller.dart';
import 'package:zdjecia/select/analysis.dart';
import 'package:zdjecia/select/candidates.dart';
import 'package:zdjecia/select/crop.dart';
import 'package:zdjecia/select/memories.dart';
import 'package:zdjecia/select/quality.dart';
import 'package:zdjecia/select/scoring.dart';
import 'package:zdjecia/select/store.dart';

final now = DateTime(2026, 10, 20, 12);

void main() {
  group('okresy', () {
    test('losowy okres zawsze w historii, przed świeżymi zdjęciami', () {
      final oldest = DateTime(2019, 3, 1);
      final latestEnd = now.subtract(const Duration(days: 30));
      final random = math.Random(1);
      var anniversaries = 0;
      for (var i = 0; i < 500; i++) {
        final p = randomPeriod(oldest, now, 30, random)!;
        expect(p.start.isBefore(p.end), isTrue);
        expect(p.end.isAfter(latestEnd), isFalse);
        expect(p.start.isBefore(oldest.subtract(const Duration(days: 8))), isFalse);
        if (p.anniversary) {
          anniversaries++;
          expect((p.start.month, p.start.day), (now.month, now.day));
          expect(p.start.year, lessThan(now.year));
        }
      }
      // Mniej więcej co trzeci okres to rocznica (ten sam tydzień lata temu)
      expect(anniversaries, inInclusiveRange(120, 230));
    });

    test('bez starszych zdjęć nie ma wspomnień', () {
      expect(randomPeriod(now.subtract(const Duration(days: 10)), now, 30, math.Random(1)), isNull);
    });

    test('krótka historia: okres mieści się w dostępnym przedziale', () {
      final oldest = now.subtract(const Duration(days: 33));
      final p = randomPeriod(oldest, now, 30, math.Random(2))!;
      expect(p.anniversary, isFalse);
      expect(p.end.isAfter(now.subtract(const Duration(days: 30))), isFalse);
    });
  });

  group('rotacja', () {
    MemoryItem m(String id, int daysAgo) => MemoryItem(
          photoId: id,
          assetId: id,
          addedAt: now.subtract(Duration(days: daysAgo)),
          taken: DateTime(2018),
        );

    test('wygasają po tygodniu, przypięte zostają, usunięte znikają', () {
      final list = [m('swieze', 2), m('stare', 8), m('przypiete', 30), m('usuniete', 1)];
      final active = activeMemories(list, now, pinned: {'przypiete'}, removed: {'usuniete'});
      expect(active.map((e) => e.photoId), ['swieze', 'przypiete']);
    });

    test('udział wspomnień w puli', () {
      expect(memoryTarget(20, 50), 10);
      expect(memoryTarget(20, 75), 15);
      expect(memoryTarget(10, 25), 3);
      expect(memoryTarget(20, 0), 0);
    });

    test('zapis i odczyt listy wspomnień', () async {
      final dir = await Directory.systemTemp.createTemp('zdjecia_mem');
      try {
        final store = SelectStore(dir);
        expect(await store.loadMemories(), isEmpty);
        await store.saveMemories([m('a', 1)]);
        final back = await SelectStore(dir).loadMemories();
        expect((back.single.photoId, back.single.taken), ('a', DateTime(2018)));
        // Lista z wersji < 0.6.1 (bez numeru formatu) jest pomijana - wspomnienia losują się od nowa
        File('${dir.path}/memories.json').writeAsStringSync(
            '{"items":[{"id":"stare","asset":"1","added":0,"taken":0}]}');
        expect(await store.loadMemories(), isEmpty);
        expect((await store.loadPrefs()).memoryShare, 50);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('kandydaci z okresu', () {
    test('z serii jedno zdjęcie, reszta równomiernie w czasie', () {
      final t0 = DateTime(2019, 7, 1, 10);
      final times = [
        t0,
        t0.add(const Duration(seconds: 5)), // seria
        t0.add(const Duration(seconds: 20)), // seria
        for (var h = 1; h <= 20; h++) t0.add(Duration(hours: h)),
      ];
      final picked = spreadInTime(times, (t) => t, 5);
      expect(picked.length, 5);
      expect(picked.first, t0);
      expect(picked.toSet().length, 5);
      expect(picked.where((t) => t.difference(t0).inSeconds < 30).length, 1);
      // mało zdjęć - wszystkie (bez serii)
      expect(spreadInTime(times.take(4).toList(), (t) => t, 10).length, 2);
    });

    test('najlepsze według oceny, odrzucone pominięte', () {
      final out = bestOf(['a', 'b', 'c', 'd'], (s) => {'a': 5.0, 'b': null, 'c': 9.0, 'd': 7.0}[s], 2);
      expect(out, ['c', 'd']);
    });
  });

  test('podpis wspomnienia na zegarku ma rok', () {
    final analysis = PhotoAnalysis(
      id: 'x',
      assetId: 'x',
      taken: DateTime(2019, 7, 14),
      favorite: false,
      quality: QualityMetrics(
        width: 4,
        height: 3,
        sharpness: 1,
        brightness: 0.5,
        dark: 0,
        bright: 0,
        colorfulness: 1,
        hash: '0000000000000000',
        profile: List.filled(profileBins, 1 / profileBins),
      ),
    );
    PoolItem item(String caption, bool memory) => PoolItem(
          scored: ScoredPhoto(
            analysis: analysis,
            score: 8,
            tags: const [],
            rating: PhotoRating(score: 8, keep: true, category: 'podróż', caption: caption, reason: '', prefsHash: ''),
          ),
          crop: CropBox.full,
          manualCrop: false,
          png: Uint8List(1),
          isMemory: memory,
        );
    expect(item('Nad jeziorem', true).watchCaption, 'Nad jeziorem · 2019');
    expect(item('', true).watchCaption, '2019');
    expect(item('Nad jeziorem', false).watchCaption, 'Nad jeziorem');
  });

  group('data zrobienia zdjęcia (zdjęcia przeniesione ze starego telefonu)', () {
    test('warunek SQL po datetaken z zapasem na zdjęcia bez daty, tylko zdjęcia', () {
      final start = DateTime.utc(2019, 7, 1), end = DateTime.utc(2019, 7, 8);
      final sql = takenBetweenSql(start: start, end: end);
      expect(sql, startsWith('media_type = 1 AND'));
      expect(sql, contains('datetaken >= ${start.millisecondsSinceEpoch}'));
      expect(sql, contains('datetaken < ${end.millisecondsSinceEpoch}'));
      expect(sql, contains('date_added >= ${start.millisecondsSinceEpoch ~/ 1000}'));
      expect(sql, contains('(datetaken IS NULL OR datetaken = 0)'));
      expect(takenBetweenSql(start: start), isNot(contains('datetaken <')));
      expect(takenBetweenSql(), 'media_type = 1');
    });

    test('wspomnienia rozkładają się na różne lata', () {
      final random = math.Random(5);
      final oldest = DateTime(2012, 1, 1);
      var repeats = 0;
      for (var i = 0; i < 200; i++) {
        final avoid = {2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020};
        final p = randomPeriodSpread(oldest, now, 30, random, avoid)!;
        if (avoid.contains(p.start.year)) repeats++;
      }
      // Bez omijania byłoby to ~55% (8 z ~14,5 lat); po 4 próbach rzadko
      expect(repeats, lessThan(40));
    });
  });
}
