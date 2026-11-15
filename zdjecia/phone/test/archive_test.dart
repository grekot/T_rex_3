import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zdjecia/archive/archive.dart';
import 'package:zdjecia/archive/archive_source.dart';
import 'package:zdjecia/cloud/firebase_rest.dart';
import 'package:zdjecia/select/clock_stream.dart';
import 'package:zdjecia/select/crop.dart';

final now = DateTime(2026, 11, 15, 12);

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
      for (var h = 1; h <= 8; h++) {
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
      expect(s.slots.last.ref, 'a8x3');
      // Zegar (np. 20 miejsc) bierze najnowsze - same zdjęcia z archiwum z ostatnich 5 godzin
      final newest = s.slots.reversed.take(20).toList();
      expect(newest.every((x) => x.archive), isTrue);
      expect(s.shown['a8x0'], now.add(const Duration(hours: 8)));
      expect(s.lastArchive, now.add(const Duration(hours: 8)));

      final back = ClockStream.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.slots.length, s.slots.length);
      expect(back.slots.last.frame?.focus, [0.1, 0.1, 0.5, 0.5]);
      expect(back.slots.last.caption, 'Las · 2018');
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
}
