import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:zdjecia/ai/photo_rating.dart';
import 'package:zdjecia/archive/archive.dart';
import 'package:zdjecia/archive/archive_add.dart';
import 'package:zdjecia/archive/archive_source.dart';
import 'package:zdjecia/bridge/photo_prep.dart';
import 'package:zdjecia/cloud/firebase_rest.dart';
import 'package:zdjecia/select/clock_stream.dart';
import 'package:zdjecia/select/crop.dart';

final now = DateTime(2026, 11, 15, 12);

PhotoRating rating(int score, {bool keep = true, String caption = 'Spacer', List<double>? focus}) => PhotoRating(
      score: score,
      keep: keep,
      category: 'ludzie',
      caption: caption,
      reason: '',
      focus: focus,
      prefsHash: 'h',
    );

AddCandidate cand(String id, DateTime taken,
        {int? score, bool keep = true, bool pinned = false, bool manual = false, String? name}) =>
    AddCandidate(
      photoId: id,
      assetId: 'asset-$id',
      name: name ?? '$id.jpg',
      taken: taken,
      rating: score == null ? null : rating(score, keep: keep),
      pinned: pinned,
      manual: manual,
    );

ArchiveEntry entry(String id, DateTime taken, {int score = 7, String caption = ''}) =>
    ArchiveEntry(id: id, taken: taken, score: score, caption: caption);

/// Archiwum: [perYear] zdjęć w każdym roku 2008-2025, różne dni roku
List<ArchiveEntry> library({int perYear = 20}) => [
      for (var y = 2008; y <= 2025; y++)
        for (var k = 0; k < perYear; k++)
          entry('${y.toRadixString(16)}${k.toRadixString(16).padLeft(4, '0')}aa', DateTime(y, 1 + k % 12, 1 + (k * 7) % 28),
              score: 6 + (k + y) % 5),
    ];

void main() {
  group('spis archiwum', () {
    test('odczyt wpisów: błędne pomija, duplikaty raz, złe prostokąty bez kadru', () {
      final items = jsonEncode([
        {'id': '3f9a0c1d2e4b', 't': 1404390000000, 'c': 'Nad Morskim Okiem', 's': 8, 'w': 800, 'h': 600, 'f': [0.3, 0.2, 0.4, 0.5]},
        {'id': '3f9a0c1d2e4b', 't': 1, 's': 3}, // duplikat
        {'id': 'ZLE!', 't': 1}, // złe id
        {'id': 'abcdef', 's': 9}, // bez daty
        {'id': 'abcdef12', 't': 1500000000000, 'm': [0.5, 0.5, 0, 0.2], 'f': 'x'},
        'smieci',
      ]);
      final list = parseArchiveItems(items);
      expect([for (final e in list) e.id], ['3f9a0c1d2e4b', 'abcdef12']);
      final a = list.first;
      expect((a.caption, a.score, a.width, a.height), ('Nad Morskim Okiem', 8, 800, 600));
      expect(a.focus, [0.3, 0.2, 0.4, 0.5]);
      expect((a.photoId, a.assetId), ('a_3f9a0c1d2e4b', 'archiwum:3f9a0c1d2e4b'));
      expect(list[1].subject, isNull);
      expect(list[1].focus, isNull);
      expect(parseArchiveItems('nie json'), isEmpty);
      expect(parseArchiveItems('{}'), isEmpty);
      expect(ArchiveEntry.fromJson(a.toJson())!.toJson(), a.toJson());
    });

    test('kolaż z PC (k): rozpoznany i zachowany przy zapisie', () {
      final k = ArchiveEntry.fromJson({
        'id': 'c0ffee123456', 't': 1, 'w': 800, 'h': 450, 'k': ['3f9a0c1d2e4b', 'abcdef12', 5],
      })!;
      expect(k.isCollage, isTrue);
      expect(k.parts, ['3f9a0c1d2e4b', 'abcdef12']);
      expect(k.toJson()['k'], ['3f9a0c1d2e4b', 'abcdef12']);
      expect(ArchiveEntry.fromJson({'id': 'abcdef12', 't': 1})!.isCollage, isFalse);
    });

    test('ocena ze spisu zamiast Gemini', () {
      final r = entry('abcdef', DateTime(2014), score: 9, caption: 'Las').rating;
      expect((r.score, r.keep, r.caption, r.category), (9, true, 'Las', 'archiwum'));
      expect(archiveIdOf('archiwum:abcdef'), 'abcdef');
      expect(archiveIdOf('1234'), isNull);
    });
  });

  group('losowanie z archiwum', () {
    test('bez świeżych, bez wykluczonych, bez odpoczywających', () {
      final all = [
        entry('aaaaaa', now.subtract(const Duration(days: 3))), // świeże - nie wspomnienie
        entry('bbbbbb', DateTime(2015, 3, 1)),
        entry('cccccc', DateTime(2016, 3, 1)), // wykluczone
        entry('dddddd', DateTime(2017, 3, 1)), // pokazane niedawno
        entry('eeeeee', DateTime(2018, 3, 1)),
      ];
      final picks = pickArchive(all,
          count: 2,
          now: now,
          random: math.Random(1),
          shown: {'dddddd': now.subtract(const Duration(days: 10))},
          exclude: {'cccccc'});
      expect({for (final e in picks) e.id}, {'bbbbbb', 'eeeeee'});
    });

    test('gdy wszystkie odpoczywają - najdawniej pokazane wracają pierwsze', () {
      final all = [entry('aaaaaa', DateTime(2015)), entry('bbbbbb', DateTime(2016)), entry('cccccc', DateTime(2017))];
      final picks = pickArchive(all, count: 2, now: now, random: math.Random(1), shown: {
        'aaaaaa': now.subtract(const Duration(days: 5)),
        'bbbbbb': now.subtract(const Duration(days: 50)),
        'cccccc': now.subtract(const Duration(days: 20)),
      });
      expect([for (final e in picks) e.id], ['bbbbbb', 'cccccc']);
    });

    test('różne lata, lepsze oceny częściej, rocznice', () {
      final all = library();
      final random = math.Random(42);
      var anniversaries = 0, best = 0, worst = 0, years = 0;
      for (var round = 0; round < 200; round++) {
        final picks = pickArchive(all, count: 10, now: now, random: random);
        expect(picks.length, 10);
        expect({for (final e in picks) e.id}.length, 10);
        years += {for (final e in picks) e.taken.year}.length;
        for (final e in picks) {
          final d = DateTime(now.year, e.taken.month, e.taken.day).difference(now).inDays.abs();
          if (d <= anniversaryWindowDays) anniversaries++;
          if (e.score == 10) best++;
          if (e.score == 6) worst++;
        }
      }
      // 10 wspomnień z 18 lat - lata rzadko się powtarzają (zajęte lata mają małą szansę)
      expect(years / 200, greaterThan(8));
      // Ocena 10 ma wagę 6, ocena 6 - wagę 2
      expect(best, greaterThan(worst * 2));
      // Bez preferencji rocznic byłoby ~4% (15 dni z 365); z szansą 35% na losowanie - wyraźnie więcej
      expect(anniversaries / 2000, greaterThan(0.15));
    });
  });

  group('strumień zegarów', () {
    test('zdjęcia puli: nowe dochodzą, wypadłe znikają, przycięte nie wracają', () {
      final s = ClockStream();
      final pool = [for (var i = 0; i < 20; i++) (id: 'p$i', taken: DateTime(2026, 11, 1 + i))];
      syncPoolSlots(s, pool, now);
      expect(s.slots.length, 20);
      expect(s.slots.map((x) => x.id).take(3), ['p0', 'p1', 'p2']);
      // p0 wypada z puli, dochodzi p20
      syncPoolSlots(s, [...pool.skip(1), (id: 'p20', taken: DateTime(2026, 11, 14))], now.add(const Duration(hours: 1)));
      expect(s.slots.map((x) => x.id), isNot(contains('p0')));
      expect(s.slots.last.id, 'p20');
      expect(s.slots.length, 20);
    });

    test('archiwum co godzinę w dzień, najwyżej 2 godziny zaległości', () {
      final s = ClockStream();
      expect(archiveDue(s, DateTime(2026, 11, 15, 3)), 0); // noc
      expect(archiveDue(s, DateTime(2026, 11, 15, 8)), clockArchivePerHour);
      s.lastArchive = DateTime(2026, 11, 15, 8);
      expect(archiveDue(s, DateTime(2026, 11, 15, 8, 45)), 0);
      expect(archiveDue(s, DateTime(2026, 11, 15, 9, 1)), clockArchivePerHour);
      expect(archiveDue(s, DateTime(2026, 11, 15, 22, 59)), 2 * clockArchivePerHour);
      expect(archiveDue(s, DateTime(2026, 11, 15, 23, 10)), 0);
    });

    test('dokładanie z archiwum: najnowsze na końcu, przycięcie do rozmiaru, zapis i odczyt', () {
      final s = ClockStream();
      syncPoolSlots(s, [for (var i = 0; i < 20; i++) (id: 'p$i', taken: DateTime(2026, 11, 1))], now);
      // Tyle godzin, żeby archiwum przepełniło listę (pula wypada z jej początku)
      final hours = clockStreamSize ~/ clockArchivePerHour + 2;
      for (var h = 1; h <= hours; h++) {
        final at = now.add(Duration(hours: h));
        addArchiveSlots(s, [
          for (var k = 0; k < clockArchivePerHour; k++)
            ClockSlot(
              id: clockArchiveId('a${h}x$k'),
              ref: 'a${h}x$k',
              archive: true,
              added: at,
              taken: DateTime(2010 + h),
              caption: 'Las · ${2010 + h}',
              frame: const CropFrame(aspect: 4 / 3, focus: [0.1, 0.1, 0.5, 0.5]),
            ),
        ], at);
      }
      expect(s.slots.length, clockStreamSize);
      expect(s.slots.last.ref, 'a${hours}x${clockArchivePerHour - 1}');
      // Zegar (np. 20 miejsc) bierze najnowsze - same zdjęcia z archiwum z ostatnich godzin
      final newest = s.slots.reversed.take(20).toList();
      expect(newest.every((x) => x.archive), isTrue);
      expect(s.shown['a${hours}x0'], now.add(Duration(hours: hours)));
      expect(s.lastArchive, now.add(Duration(hours: hours)));

      final back = ClockStream.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.slots.length, s.slots.length);
      expect(back.slots.last.frame?.focus, [0.1, 0.1, 0.5, 0.5]);
      expect(back.slots.last.caption, 'Las · ${2010 + hours}');
      expect(back.archiveIds, s.archiveIds);
      expect(back.poolSeen, s.poolSeen);
      expect(back.lastArchive, s.lastArchive);
      // Zdjęcia puli przycięte ze strumienia nie wracają jako „nowe”
      syncPoolSlots(back, [for (var i = 0; i < 20; i++) (id: 'p$i', taken: DateTime(2026, 11, 1))], now.add(const Duration(hours: 9)));
      expect(back.slots.where((x) => !x.archive).length, s.slots.where((x) => !x.archive).length);
    });
  });

  group('konto i Firestore (REST)', () {
    test('logowanie, odświeżanie tokenu, odczyt dokumentu z bajtami', () async {
      var clock = now;
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.host}${req.url.path}${req.url.query.isEmpty ? '' : '?${req.url.query}'}');
        if (req.url.path.endsWith('accounts:signInWithPassword')) {
          final body = jsonDecode(req.body) as Map;
          if (body['password'] != 'dobre') {
            return http.Response(jsonEncode({'error': {'message': 'INVALID_LOGIN_CREDENTIALS'}}), 400);
          }
          return http.Response(
              jsonEncode({'localId': 'u1', 'email': 'ja@x.pl', 'idToken': 't1', 'refreshToken': 'r1', 'expiresIn': '3600'}), 200);
        }
        if (req.url.host == 'securetoken.googleapis.com') {
          expect(req.body, contains('refresh_token=r1'));
          return http.Response(jsonEncode({'id_token': 't2', 'refresh_token': 'r2', 'user_id': 'u1', 'expires_in': '3600'}), 200);
        }
        if (req.url.path.endsWith('/archiwum/u1/zdjecia/abc')) {
          expect(req.headers['Authorization'], 'Bearer t2');
          return http.Response(
              jsonEncode({
                'fields': {
                  'jpeg': {'bytesValue': base64Encode([1, 2, 3])},
                  't': {'integerValue': '1404390000000'},
                  'updatedAt': {'timestampValue': '2026-11-15T10:00:00Z'},
                },
              }),
              200);
        }
        return http.Response('{}', 404);
      });
      final store = MemoryAccountStore();
      final rest = FirebaseRest(store: store, client: client, apiKey: 'k', projectId: 'p', now: () => clock);
      expect(
        () => rest.signIn('ja@x.pl', 'zle'),
        throwsA(isA<CloudException>().having((e) => e.message, 'message', 'Zły e-mail albo hasło')),
      );
      final a = await rest.signIn(' ja@x.pl ', 'dobre');
      expect((a.uid, store.account?.refreshToken), ('u1', 'r1'));
      expect(await rest.idToken(), 't1'); // z logowania, bez odświeżania
      clock = now.add(const Duration(minutes: 59));
      final doc = await rest.getDocument('archiwum/u1/zdjecia/abc');
      expect(doc!['jpeg'], Uint8List.fromList([1, 2, 3]));
      expect(doc['t'], 1404390000000);
      expect(store.account?.refreshToken, 'r2');
      expect(await rest.getDocument('archiwum/u1/zdjecia/nie-ma'), isNull);
      expect(calls.where((c) => c.contains('securetoken')).length, 1);
      await rest.signOut();
      expect(store.account, isNull);
      expect(() => rest.idToken(), throwsA(isA<CloudException>().having((e) => e.unauthorized, 'unauthorized', isTrue)));
    });
  });

  group('archiwum na telefonie', () {
    test('spis raz na godzinę, zdjęcie raz, porządki w pamięci podręcznej, wylogowanie', () async {
      final dir = await Directory.systemTemp.createTemp('zdjecia_arch');
      var clock = now;
      var updatedAt = '2026-11-15T10:00:00Z';
      var items = jsonEncode([
        {'id': 'aaaaaa', 't': 1404390000000, 's': 9},
        {'id': 'bbbbbb', 't': 1504390000000, 's': 7},
      ]);
      final calls = <String>[];
      final client = MockClient((req) async {
        final path = req.url.path;
        calls.add('$path${req.url.query.contains('mask') ? ' (mask)' : ''}');
        if (req.url.host == 'securetoken.googleapis.com') {
          return http.Response(jsonEncode({'id_token': 't', 'refresh_token': 'r', 'user_id': 'u1', 'expires_in': '3600'}), 200);
        }
        if (path.endsWith('/documents/archiwum/u1')) {
          final mask = req.url.queryParametersAll['mask.fieldPaths'] ?? const [];
          return http.Response(
              jsonEncode({
                'fields': {
                  'updatedAt': {'timestampValue': updatedAt},
                  'count': {'integerValue': '2'},
                  if (mask.isEmpty) 'items': {'stringValue': items},
                },
              }),
              200);
        }
        final m = RegExp(r'/archiwum/u1/zdjecia/(\w+)$').firstMatch(path);
        if (m != null) {
          return http.Response(jsonEncode({'fields': {'jpeg': {'bytesValue': base64Encode(utf8.encode('jpg-${m[1]}'))}}}), 200);
        }
        return http.Response('{}', 404);
      });
      final store = MemoryAccountStore();
      final source = ArchiveSource(
        Directory('${dir.path}/archiwum'),
        cloud: FirebaseRest(store: store, client: client, apiKey: 'k', projectId: 'p', now: () => clock),
        now: () => clock,
      );
      try {
        // Bez konta: pusto, bez zapytań
        var r = await source.index();
        expect(r.entries, isEmpty);
        expect(r.status.signedIn, isFalse);
        expect(calls, isEmpty);

        store.account = const Account(uid: 'u1', email: 'ja@x.pl', refreshToken: 'r');
        r = await source.index();
        expect([for (final e in r.entries) e.id], ['aaaaaa', 'bbbbbb']);
        expect((r.status.email, r.status.count), ('ja@x.pl', 2));
        expect(calls.where((c) => c.contains('archiwum/u1')).toList(),
            ['/v1/projects/p/databases/(default)/documents/archiwum/u1 (mask)', '/v1/projects/p/databases/(default)/documents/archiwum/u1']);

        // W ciągu godziny - z pliku, bez zapytań
        calls.clear();
        clock = now.add(const Duration(minutes: 30));
        expect((await source.index()).entries.length, 2);
        expect(calls, isEmpty);

        // Po godzinie: mały odczyt; spis bez zmian - bez pobierania całości
        clock = now.add(const Duration(minutes: 61));
        await source.index();
        expect(calls.where((c) => c.contains('archiwum/u1')).length, 1);

        // Nowa wysyłka z PC: zmieniony updatedAt - pełny spis
        calls.clear();
        updatedAt = '2026-11-16T10:00:00Z';
        items = jsonEncode([{'id': 'cccccc', 't': 1, 's': 8}]);
        r = await source.index(force: true);
        expect([for (final e in r.entries) e.id], ['cccccc']);

        // Zdjęcie: raz z bazy, potem z pliku
        calls.clear();
        expect(utf8.decode((await source.photo('aaaaaa'))!), 'jpg-aaaaaa');
        expect(utf8.decode((await source.photo('aaaaaa'))!), 'jpg-aaaaaa');
        expect(calls.where((c) => c.contains('zdjecia')).length, 1);
        for (final id in ['bbbbbb', 'cccccc', 'dddddd']) {
          await source.photo(id);
        }
        await source.prune({'aaaaaa'}, spare: 1);
        final left = source.photoDir.listSync().map((f) => f.uri.pathSegments.last).toSet();
        expect(left.length, 2);
        expect(left, contains('aaaaaa.jpg'));

        await source.saveShown({'aaaaaa': now});
        expect(await source.loadShown(), {'aaaaaa': now});

        await source.signOut();
        expect(store.account, isNull);
        expect(source.dir.existsSync(), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('dokładanie zdjęć z telefonu', () {
    test('id w archiwum: 12 znaków hex, stałe, zależne od nazwy i czasu', () {
      final a = phoneArchiveId('20261101_120000.jpg', DateTime(2026, 11, 1, 12));
      expect(RegExp(r'^[0-9a-f]{12}$').hasMatch(a), isTrue);
      expect(phoneArchiveId('20261101_120000.JPG', DateTime(2026, 11, 1, 12)), a);
      expect(phoneArchiveId('20261101_120000.jpg', DateTime(2026, 11, 1, 12, 0, 1)), isNot(a));
      expect(phoneArchiveId('inne.jpg', DateTime(2026, 11, 1, 12)), isNot(a));
      expect(ArchiveEntry.fromJson({'id': a, 't': 1}), isNotNull);
    });

    test('podpis skrócony na granicy słowa', () {
      expect(clipCaption('  Ognisko   nad jeziorem '), 'Ognisko nad jeziorem');
      expect(clipCaption('Długi spacer brzegiem morza o zachodzie słońca'), 'Długi spacer brzegiem morza');
      expect(clipCaption('Bardzodługiesłowobezspacjiwcalenawetjednej').length, 28);
    });

    test('wybór: ocena 7+, po 3 dniach, bez dodanych, usuniętych i tych samych ujęć; ręczne i przypięte zawsze', () {
      final day = DateTime(2026, 11, 5);
      final chosen = chooseAdditions(
        [
          cand('dobre', now.subtract(const Duration(days: 5)), score: 8),
          cand('slabe', now.subtract(const Duration(days: 5, hours: 6)), score: 6),
          cand('odrzucone', now.subtract(const Duration(days: 5, hours: 12)), score: 9, keep: false),
          cand('swieze', now.subtract(const Duration(days: 1)), score: 9),
          cand('dodane', now.subtract(const Duration(days: 6)), score: 9),
          cand('usuniete', now.subtract(const Duration(days: 7)), score: 9),
          cand('z_takeoutu', DateTime(2026, 10, 1, 13), score: 9, name: 'IMG_1.jpg'),
          // Jedno wydarzenie (najwyżej 2) i jeden dzień (najwyżej 3)
          cand('h1', day.add(const Duration(hours: 10)), score: 9),
          cand('h2', day.add(const Duration(hours: 10, minutes: 30)), score: 8),
          cand('h3', day.add(const Duration(hours: 11)), score: 7),
          cand('h4', day.add(const Duration(hours: 18)), score: 7),
          cand('h5', day.add(const Duration(hours: 21)), score: 7),
          cand('przypiete', now.subtract(const Duration(days: 4)), pinned: true),
          cand('reczne', now.subtract(const Duration(hours: 1)), manual: true),
        ],
        existing: [ArchiveEntry(id: 'aaaaaa', taken: DateTime(2026, 10, 1, 12), name: 'img_1.JPG', fromPhone: true)],
        added: {'dodane'},
        removed: {'usuniete'},
        now: now,
      );
      expect([for (final c in chosen) c.photoId], ['reczne', 'przypiete', 'h1', 'h2', 'dobre', 'h4']);
      final few = chooseAdditions([
        for (var i = 0; i < 20; i++) cand('p$i', now.subtract(Duration(days: 4 + i)), score: 8),
      ], existing: const [], added: const {}, now: now, perRun: 5);
      expect(few.length, 5);
    });

    test('wpis spisu z oceny Gemini; dopisanie zachowuje wpisy z PC, bez dubli', () {
      final c = AddCandidate(
        photoId: 'x',
        assetId: 'a',
        name: '20261101_120000.jpg',
        taken: DateTime(2026, 11, 1, 12),
        rating: rating(8, caption: 'Długi spacer brzegiem morza o zachodzie słońca', focus: [0.1, 0.2, 0.3, 0.4]),
      );
      final e = phoneEntry(c, 'abcdef123456', 800, 600);
      expect(e, {
        'id': 'abcdef123456',
        't': DateTime(2026, 11, 1, 12).millisecondsSinceEpoch,
        'c': 'Długi spacer brzegiem morza',
        's': 8,
        'w': 800,
        'h': 600,
        'f': [0.1, 0.2, 0.3, 0.4],
        'n': '20261101_120000.jpg',
        'src': 'tel',
      });
      final parsed = ArchiveEntry.fromJson(e)!;
      expect((parsed.name, parsed.fromPhone, parsed.toJson()['src']), ('20261101_120000.jpg', true, 'tel'));

      final pc = jsonEncode([
        {'id': 'cccccc', 't': DateTime(2026, 11, 3).millisecondsSinceEpoch, 's': 9, 'x': 'pole z PC'},
        {'id': 'bbbbbb', 't': DateTime(2026, 11, 1, 13).millisecondsSinceEpoch, 'n': '20261101_120000.JPG'},
      ]);
      final again = phoneEntry(c, 'abcdef000000', 800, 600); // to samo ujęcie co bbbbbb (Takeout)
      final other = {...e, 'id': '111111111111', 'n': 'inne.jpg', 't': DateTime(2026, 10, 1).millisecondsSinceEpoch};
      final merged = mergeItems(pc, [again, other, other]);
      final list = jsonDecode(merged.json) as List;
      expect(merged.count, 3);
      expect([for (final x in list) x['id']], ['111111111111', 'bbbbbb', 'cccccc']);
      expect(list.last['x'], 'pole z PC');
      expect(mergeItems('zepsute', [e]).count, 1);
    });

    test('JPEG do archiwum: ≤ 800×600, krótszy bok ≤ 600, bez EXIF', () {
      for (final (w, h, ew, eh) in [(1600, 1200, 800, 600), (1000, 1000, 600, 600), (600, 1600, 300, 800), (400, 300, 400, 300)]) {
        final src = img.Image(width: w, height: h);
        for (final p in src) {
          p
            ..r = (p.x * 7) % 256
            ..g = (p.y * 5) % 256
            ..b = 128;
        }
        src.exif.imageIfd['Make'] = 'Telefon';
        final out = prepareArchiveJpeg(img.encodeJpg(src));
        expect((out.width, out.height), (ew, eh));
        final back = img.decodeJpg(out.bytes)!;
        expect((back.width, back.height), (ew, eh));
        expect(back.exif.isEmpty, isTrue);
        expect(out.bytes.length, lessThanOrEqualTo(maxArchiveJpegBytes));
      }
      expect(archiveSize(4000, 3000), (width: 800, height: 600));
      expect(archiveSize(4000, 1800), (width: 800, height: 360));
    });

    test('REST: zapis pól, warunek wersji, konflikt', () async {
      final requests = <http.Request>[];
      var conflict = true;
      final client = MockClient((req) async {
        if (req.url.host == 'securetoken.googleapis.com') {
          return http.Response(jsonEncode({'id_token': 't', 'refresh_token': 'r', 'user_id': 'u1', 'expires_in': '3600'}), 200);
        }
        requests.add(req);
        if (req.url.queryParameters.containsKey('currentDocument.updateTime') && conflict) {
          return http.Response(jsonEncode({'error': {'status': 'FAILED_PRECONDITION', 'message': 'zmieniony'}}), 400);
        }
        return http.Response(jsonEncode({'fields': (jsonDecode(req.body) as Map)['fields'], 'updateTime': 'v2'}), 200);
      });
      final rest = FirebaseRest(
          store: MemoryAccountStore()..account = const Account(uid: 'u1', email: 'e', refreshToken: 'r'),
          client: client,
          apiKey: 'k',
          projectId: 'p');
      final doc = await rest.setDocument('archiwum/u1/zdjecia/abc', {
        'jpeg': Uint8List.fromList([1, 2]),
        't': 5,
        'ok': true,
        'x': 0.5,
        'when': DateTime.utc(2026, 11, 16, 10),
        'items': '[]',
      }, ifMissing: true);
      expect(requests.single.method, 'PATCH');
      expect(requests.single.url.query, 'currentDocument.exists=false');
      expect((jsonDecode(requests.single.body) as Map)['fields'], {
        'jpeg': {'bytesValue': 'AQI='},
        't': {'integerValue': '5'},
        'ok': {'booleanValue': true},
        'x': {'doubleValue': 0.5},
        'when': {'timestampValue': '2026-11-16T10:00:00.000Z'},
        'items': {'stringValue': '[]'},
      });
      expect((doc.updateTime, doc.fields['when']), ('v2', '2026-11-16T10:00:00.000Z'));
      expect(doc.fields['jpeg'], Uint8List.fromList([1, 2]));
      await expectLater(
        rest.setDocument('archiwum/u1', {'v': 1}, ifUpdateTime: 'v1'),
        throwsA(isA<CloudException>().having((e) => e.conflict, 'conflict', isTrue)),
      );
      conflict = false;
      await rest.setDocument('archiwum/u1', {'v': 1}, ifUpdateTime: 'v1', updateMask: ['v']);
      expect(requests.last.url.queryParametersAll['updateMask.fieldPaths'], ['v']);
      expect(requests.last.url.queryParameters['currentDocument.updateTime'], 'v1');
    });

    test('telefon: zdjęcie, potem spis z warunkiem wersji (ponowienie po zapisie z PC), spis w pamięci od razu', () async {
      final dir = await Directory.systemTemp.createTemp('zdjecia_add');
      var version = 1;
      var items = jsonEncode([{'id': 'aaaaaa', 't': 1404390000000, 's': 9}]);
      final saved = <String, Map>{};
      var pcWrites = 1; // PC zapisze spis między odczytem a zapisem telefonu
      final client = MockClient((req) async {
        if (req.url.host == 'securetoken.googleapis.com') {
          return http.Response(jsonEncode({'id_token': 't', 'refresh_token': 'r', 'user_id': 'u1', 'expires_in': '3600'}), 200);
        }
        final path = req.url.path.split('/documents/').last;
        if (req.method == 'GET' && path == 'archiwum/u1') {
          return http.Response(
              jsonEncode({
                'fields': {
                  'items': {'stringValue': items},
                  'updatedAt': {'timestampValue': 'pc-$version'},
                },
                'updateTime': 'v$version',
              }),
              200);
        }
        if (req.method == 'PATCH') {
          final fields = (jsonDecode(req.body) as Map)['fields'] as Map;
          if (path == 'archiwum/u1') {
            if (pcWrites > 0) {
              pcWrites--;
              version++;
              items = jsonEncode([
                {'id': 'aaaaaa', 't': 1404390000000, 's': 9},
                {'id': 'bbbbbb', 't': 1504390000000, 's': 8},
              ]);
            }
            if (req.url.queryParameters['currentDocument.updateTime'] != 'v$version') {
              return http.Response(jsonEncode({'error': {'status': 'FAILED_PRECONDITION'}}), 400);
            }
            items = fields['items']['stringValue'] as String;
            version++;
            return http.Response(
                jsonEncode({
                  'fields': {...fields, 'updatedAt': {'timestampValue': 'tel-$version'}},
                  'updateTime': 'v$version',
                }),
                200);
          }
          saved[path] = fields;
          return http.Response(jsonEncode({'fields': fields, 'updateTime': 'x'}), 200);
        }
        return http.Response('{}', 404);
      });
      final source = ArchiveSource(
        Directory('${dir.path}/archiwum'),
        cloud: FirebaseRest(
            store: MemoryAccountStore()..account = const Account(uid: 'u1', email: 'e', refreshToken: 'r'),
            client: client,
            apiKey: 'k',
            projectId: 'p'),
        now: () => now,
      );
      try {
        await source.uploadPhoto('abcdef123456', Uint8List.fromList([9, 9]), DateTime(2026, 11, 1));
        expect(saved['archiwum/u1/zdjecia/abcdef123456']!['t'], {'integerValue': '${DateTime(2026, 11, 1).millisecondsSinceEpoch}'});
        final count = await source.appendToIndex([
          {'id': 'abcdef123456', 't': DateTime(2026, 11, 1).millisecondsSinceEpoch, 's': 8, 'n': 'x.jpg', 'src': 'tel'},
        ]);
        expect(count, 3);
        expect([for (final x in jsonDecode(items) as List) x['id']], ['aaaaaa', 'bbbbbb', 'abcdef123456']);
        // Spis w pamięci telefonu już nowy - bez pobierania (sprawdzenie w ciągu godziny)
        final r = await source.index();
        expect([for (final e in r.entries) e.id], ['aaaaaa', 'bbbbbb', 'abcdef123456']);
        expect(r.entries.last.fromPhone, isTrue);

        await source.saveAdded({'x': 'abcdef123456'});
        expect(await source.loadAdded(), {'x': 'abcdef123456'});
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
