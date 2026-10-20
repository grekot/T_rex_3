import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zdjecia/ai/ai_errors.dart';
import 'package:zdjecia/ai/gemini_client.dart';
import 'package:zdjecia/ai/photo_rating.dart';
import 'package:zdjecia/ai/rater.dart';
import 'package:zdjecia/select/analysis.dart';
import 'package:zdjecia/select/crop.dart';
import 'package:zdjecia/select/quality.dart';
import 'package:zdjecia/select/scoring.dart';
import 'package:zdjecia/select/store.dart';

final now = DateTime(2026, 10, 19, 12);

PhotoAnalysis photo(String id, {bool fav = false, int w = 400, int h = 300}) => PhotoAnalysis(
      id: id,
      assetId: id,
      taken: now.subtract(const Duration(days: 2)),
      favorite: fav,
      quality: QualityMetrics(
        width: w,
        height: h,
        sharpness: 500,
        brightness: 0.5,
        dark: 0,
        bright: 0,
        colorfulness: 40,
        hash: '0000000000000000',
        profile: List.filled(profileBins, 1 / profileBins),
      ),
    );

PhotoRating rating(int score, {bool keep = true, List<double>? subject}) => PhotoRating(
      score: score,
      keep: keep,
      category: 'ludzie',
      caption: 'Spacer w parku',
      reason: 'ciepła chwila',
      subject: subject,
      prefsHash: 'x',
    );

/// Odpowiedź HTTP w UTF-8 (domyślny Latin-1 nie zmieści polskich znaków)
http.Response ok(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

String geminiReply(Object json) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(json)},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    });

void main() {
  group('zapytanie i odpowiedź', () {
    test('części zapytania: preferencje, opis i miniatura każdego zdjęcia', () {
      final parts = ratingParts([
        RatingInput(jpeg: Uint8List.fromList([1, 2, 3]), taken: DateTime(2026, 10, 18, 15)),
        RatingInput(jpeg: Uint8List.fromList([4]), taken: DateTime(2026, 10, 17)),
      ], '  dzieci i góry ');
      expect(parts.length, 5);
      expect(parts.first['text'], contains('Preferencje właściciela: dzieci i góry'));
      expect(parts[1]['text'], 'Zdjęcie 1 (zrobione 18.10.2026, niedziela):');
      expect((parts[2]['inline_data'] as Map)['data'], base64Encode([1, 2, 3]));
      expect(ratingParts([], '').first['text'], isNot(contains('Preferencje')));
    });

    test('odczyt ocen: numery, zakresy, prostokąt motywu, pominięte zdjęcia', () {
      final out = parseRatings({
        'photos': [
          {'n': 2, 'score': 14, 'keep': true, 'category': 'dzieci', 'caption': 'Huśtawka', 'reason': 'radość', 'subject': [100, 200, 600, 500]},
          {'n': 1, 'score': 2, 'keep': false, 'category': 'coś', 'caption': 'x' * 60, 'reason': 'paragon', 'subject': [0, 0, 1, 1]},
          {'n': 9, 'score': 5},
          'śmieć',
        ],
      }, 3, 'h1');
      expect(out[1]!.score, 10);
      expect(out[1]!.subject, [0.2, 0.1, 0.3, 0.5]);
      expect(out[0]!.keep, isFalse);
      expect(out[0]!.category, 'inne');
      expect(out[0]!.caption.length, 40);
      expect(out[0]!.subject, isNull); // zbyt mały prostokąt
      expect(out[2], isNull);
      expect(out[1]!.prefsHash, 'h1');
    });

    test('skrót preferencji zmienia się razem z preferencjami', () {
      expect(prefsHash('góry'), prefsHash(' góry '));
      expect(prefsHash('góry'), isNot(prefsHash('morze')));
    });

    test('ocena zapisuje się i odczytuje', () {
      final r = rating(8, subject: [0.1, 0.2, 0.3, 0.4]);
      final back = PhotoRating.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>)!;
      expect((back.score, back.caption), (8, 'Spacer w parku'));
      expect(back.subject, [0.1, 0.2, 0.3, 0.4]);
      expect(PhotoRating.fromJson({...r.toJson(), 'v': ratingVersion + 1}), isNull);
    });
  });

  group('punkty z oceną AI', () {
    test('ocena AI decyduje o kolejności, odrzuca nieciekawe, oszczędza ulubione', () {
      final list = scoreAll(
        [photo('a'), photo('b'), photo('c'), photo('d', fav: true), photo('bez')],
        now: now,
        days: 30,
        ratings: {'a': rating(9), 'b': rating(6), 'c': rating(2, keep: false), 'd': rating(2, keep: false)},
      );
      final byId = {for (final s in list) s.id: s};
      expect(byId['a']!.score, greaterThan(byId['b']!.score));
      expect(byId['b']!.score, greaterThan(byId['bez']!.score));
      expect(byId['c']!.rejected, 'AI: ciepła chwila');
      expect(byId['d']!.accepted, isTrue);
      expect(byId['a']!.tags.first, 'Spacer w parku');
      expect(byId['bez']!.rating, isNull);
    });

    test('kadr obejmuje główny motyw wskazany przez AI', () {
      const subject = [0.7, 0.3, 0.2, 0.4];
      final c = autoCrop(photo('s'), subject: subject);
      const w = 4 / 3, h = 1.0;
      final cx = c.cx * w, cy = c.cy * h, r = c.side / 2;
      for (final p in [
        [subject[0] * w, subject[1] * h],
        [(subject[0] + subject[2]) * w, (subject[1] + subject[3]) * h],
      ]) {
        expect(math.sqrt(math.pow(p[0] - cx, 2) + math.pow(p[1] - cy, 2)), lessThanOrEqualTo(r + 1e-9));
      }
      expect(c.cx, greaterThan(0.6));
    });
  });

  group('klient Gemini', () {
    test('wysyła klucz w nagłówku, model w adresie i schemat odpowiedzi', () async {
      late http.Request sent;
      final client = GeminiClient(
        apiKey: 'AIzaTEST',
        model: 'gemini-test',
        client: MockClient((req) async {
          sent = req;
          return ok(geminiReply({'photos': []}));
        }),
      );
      final out = await client.generateJson(system: 's', parts: const [{'text': 'x'}], schema: ratingSchema);
      expect(out, {'photos': []});
      expect(sent.headers['x-goog-api-key'], 'AIzaTEST');
      expect(sent.url.toString(), '$geminiBaseUrl/models/gemini-test:generateContent');
      final body = jsonDecode(sent.body) as Map;
      expect((body['generationConfig'] as Map)['responseMimeType'], 'application/json');
      expect((body['generationConfig'] as Map)['responseJsonSchema'], isNotNull);
    });

    test('błędy HTTP mają właściwy rodzaj, a limit jest ponawiany', () async {
      var calls = 0;
      final client = GeminiClient(
        apiKey: 'k',
        client: MockClient((req) async {
          calls++;
          if (calls < 3) return http.Response('{"error":{"message":"quota"}}', 429);
          return ok(geminiReply({'ok': true}));
        }),
      );
      final waits = <Duration>[];
      final out = await withRetry(
        () => client.generateJson(system: 's', parts: const [], schema: const {}),
        wait: (d) async => waits.add(d),
      );
      expect(out, {'ok': true});
      expect(waits, [const Duration(seconds: 5), const Duration(seconds: 10)]);

      final bad = GeminiClient(apiKey: 'k', client: MockClient((_) async => http.Response('{}', 403)));
      await expectLater(
        bad.ping(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.unauthorized)),
      );
      await expectLater(
        GeminiClient(apiKey: ' ').ping(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.noApiKey)),
      );
    });

    test('lista modeli: tylko tekstowe Gemini z generateContent', () async {
      final client = GeminiClient(
        apiKey: 'k',
        client: MockClient((req) async => http.Response(
              jsonEncode({
                'models': [
                  {'name': 'models/gemini-3.8-flash', 'supportedGenerationMethods': ['generateContent']},
                  {'name': 'models/gemini-3.8-flash-image', 'supportedGenerationMethods': ['generateContent']},
                  {'name': 'models/text-embedding-9', 'supportedGenerationMethods': ['embedContent']},
                  {'name': 'models/gemma-9', 'supportedGenerationMethods': ['generateContent']},
                ],
              }),
              200,
            )),
      );
      expect(await client.listModels(), ['gemini-3.8-flash']);
    });

    test('ocena porcji zdjęć od zapytania do ocen', () async {
      final rater = PhotoRater(
        client: GeminiClient(
          apiKey: 'k',
          client: MockClient((req) async => ok(
                geminiReply({
                  'photos': [
                    {'n': 1, 'score': 9, 'keep': true, 'category': 'zwierzęta', 'caption': 'Pies na łące', 'reason': 'radosny', 'subject': [200, 200, 800, 700]},
                  ],
                }),
              )),
        ),
        preferences: 'pies',
      );
      final out = await rater.rateBatch([RatingInput(jpeg: Uint8List(3), taken: now)]);
      expect(out.single!.caption, 'Pies na łące');
      expect(out.single!.prefsHash, prefsHash('pies'));
    });
  });

  test('sprawdzenie klucza: ucięta odpowiedź (model „myślał”) to też sukces', () async {
    late Map body;
    final client = GeminiClient(
      apiKey: 'k',
      client: MockClient((req) async {
        body = jsonDecode(req.body) as Map;
        return ok(jsonEncode({
          'candidates': [
            {'content': {'parts': []}, 'finishReason': 'MAX_TOKENS'},
          ],
        }));
      }),
    );
    await client.ping();
    expect((body['generationConfig'] as Map)['maxOutputTokens'], greaterThanOrEqualTo(1024));
    // przy ocenie zdjęć ucięta odpowiedź nadal jest błędem, ale limit ma duży zapas
    await expectLater(
      client.generateJson(system: 's', parts: const [], schema: const {}),
      throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.truncated)),
    );
    expect((body['generationConfig'] as Map)['maxOutputTokens'], 32768);
  });

  test('pamięć: ustawienia AI i oceny przetrwają ponowne uruchomienie', () async {
    final dir = await Directory.systemTemp.createTemp('zdjecia_ai_test');
    try {
      final store = SelectStore(dir);
      final prefs = await store.loadPrefs();
      expect((prefs.aiEnabled, prefs.aiModel, prefs.preferences), (true, defaultGeminiModel, ''));
      prefs.preferences = 'góry';
      prefs.aiModel = 'gemini-x';
      await store.savePrefs(prefs);
      await store.saveRatings({'a': rating(7)});
      final again = SelectStore(dir);
      final p2 = await again.loadPrefs();
      expect((p2.preferences, p2.aiModel), ('góry', 'gemini-x'));
      expect((await again.loadRatings())['a']!.score, 7);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
