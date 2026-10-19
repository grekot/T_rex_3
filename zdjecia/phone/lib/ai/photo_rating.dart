// Ocena zdjęć przez Gemini: polecenie, schemat odpowiedzi, budowa zapytania z miniaturami
// i odczyt ocen. Czysta logika (bez sieci) - testowana osobno.
import 'dart:convert';
import 'dart:typed_data';

/// Zwiększ przy zmianie polecenia - stare oceny zostaną policzone od nowa
const int ratingVersion = 1;

/// Tyle zdjęć w jednym zapytaniu (mniej zapytań = mniejsze ryzyko limitu darmowego klucza)
const int ratingBatchSize = 12;

const ratingCategories = [
  'ludzie', 'dzieci', 'zwierzęta', 'krajobraz', 'wydarzenie', 'podróż', 'jedzenie', 'przedmiot', 'dokument', 'inne',
];

const String ratingSystemPrompt = '''
Jesteś kuratorem rodzinnych wspomnień. Oceniasz zdjęcia z telefonu właściciela. Najlepsze z nich będą
losowo wyskakiwać na małym, okrągłym ekranie zegarka jako miłe wspomnienie - coś, na co chętnie się zerka
i co wywołuje uśmiech.

Oceny 8-10: ludzie i rodzina w naturalnych, ciepłych chwilach, dzieci, emocje, wspólne przeżycia,
zwierzęta, wycieczki i podróże, wyjątkowe wydarzenia, naprawdę piękne krajobrazy; ostre i czytelne.
Oceny 4-7: poprawne, ale zwyczajne zdjęcia.
Oceny 1-3 i keep=false: zdjęcia „praktyczne”, robione po to, żeby coś zapamiętać lub komuś pokazać
(dokumenty, paragony, ekrany, tablice, ceny, etykiety, części, narzędzia, sprzęt, usterki, produkty,
notatki, zrzuty ekranu, zdjęcia „na pamiątkę do sklepu”), przypadkowe, nieudane, nieostre lub ciemne
ujęcia, nudne przedmioty bez kontekstu, zdjęcia krępujące.

Zdjęcie będzie małe i okrągłe, więc liczy się czytelny główny motyw.
Preferencje właściciela (jeśli podane) są ważniejsze od powyższych ogólnych zasad.

Dla każdego zdjęcia zwróć:
- n: numer zdjęcia z zapytania,
- score: ocena 1-10,
- keep: czy nadaje się na zegarek,
- category: jedna z kategorii ze schematu,
- caption: krótki, ciepły podpis po polsku, najwyżej 30 znaków, bez imion (np. „Huśtawka w ogrodzie”),
- reason: kilka słów uzasadnienia po polsku,
- subject: prostokąt głównego motywu [ymin, xmin, ymax, xmax] w skali 0-1000.
''';

final Map<String, Object> ratingSchema = {
  'type': 'object',
  'properties': {
    'photos': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'n': {'type': 'integer'},
          'score': {'type': 'integer', 'minimum': 1, 'maximum': 10},
          'keep': {'type': 'boolean'},
          'category': {'type': 'string', 'enum': ratingCategories},
          'caption': {'type': 'string'},
          'reason': {'type': 'string'},
          'subject': {
            'type': 'array',
            'items': {'type': 'number'},
          },
        },
        'required': ['n', 'score', 'keep', 'category', 'caption', 'reason', 'subject'],
      },
    },
  },
  'required': ['photos'],
};

class PhotoRating {
  const PhotoRating({
    required this.score,
    required this.keep,
    required this.category,
    required this.caption,
    required this.reason,
    this.subject,
    required this.prefsHash,
  });

  final int score;
  final bool keep;
  final String category;
  final String caption;
  final String reason;

  /// Główny motyw: left, top, width, height w ułamkach zdjęcia (0..1)
  final List<double>? subject;

  /// Skrót preferencji, z którymi oceniono (zmiana preferencji = ocena od nowa)
  final String prefsHash;

  Map<String, Object?> toJson() => {
        'v': ratingVersion,
        'score': score,
        'keep': keep,
        'cat': category,
        'caption': caption,
        'reason': reason,
        if (subject != null) 'subject': subject,
        'prefs': prefsHash,
      };

  static PhotoRating? fromJson(Map<String, dynamic> j) {
    if (j['v'] != ratingVersion) return null;
    return PhotoRating(
      score: j['score'] as int,
      keep: j['keep'] as bool,
      category: j['cat'] as String? ?? 'inne',
      caption: j['caption'] as String? ?? '',
      reason: j['reason'] as String? ?? '',
      subject: (j['subject'] as List?)?.map((v) => (v as num).toDouble()).toList(),
      prefsHash: j['prefs'] as String? ?? '',
    );
  }
}

class RatingInput {
  const RatingInput({required this.jpeg, required this.taken});

  final Uint8List jpeg;
  final DateTime taken;
}

/// Skrót preferencji użytkownika (FNV-1a), żeby wiedzieć, które oceny są nieaktualne
String prefsHash(String preferences) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode('$ratingVersion|${preferences.trim()}')) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16);
}

const _weekdays = ['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'];

String _date(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}, ${_weekdays[t.weekday - 1]}';

/// Części zapytania: preferencje, potem „Zdjęcie N (data):” + miniatura dla każdego zdjęcia
List<Map<String, Object>> ratingParts(List<RatingInput> photos, String preferences) {
  final prefs = preferences.trim();
  return [
    {
      'text': 'Oceń ${photos.length} zdjęć.'
          '${prefs.isEmpty ? '' : '\nPreferencje właściciela: $prefs'}',
    },
    for (var i = 0; i < photos.length; i++) ...[
      {'text': 'Zdjęcie ${i + 1} (zrobione ${_date(photos[i].taken)}):'},
      {
        'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(photos[i].jpeg)},
      },
    ],
  ];
}

/// Oceny z odpowiedzi; indeks listy = numer zdjęcia - 1 (null, gdy model pominął zdjęcie)
List<PhotoRating?> parseRatings(Map<String, dynamic> response, int count, String prefsHash) {
  final out = List<PhotoRating?>.filled(count, null);
  for (final item in (response['photos'] as List? ?? const [])) {
    if (item is! Map) continue;
    final n = (item['n'] as num?)?.toInt();
    if (n == null || n < 1 || n > count) continue;
    final score = ((item['score'] as num?)?.round() ?? 5).clamp(1, 10);
    final caption = (item['caption'] as String? ?? '').trim();
    out[n - 1] = PhotoRating(
      score: score,
      keep: item['keep'] as bool? ?? score >= 5,
      category: ratingCategories.contains(item['category']) ? item['category'] as String : 'inne',
      caption: caption.length <= 40 ? caption : '${caption.substring(0, 39)}…',
      reason: (item['reason'] as String? ?? '').trim(),
      subject: _subjectBox(item['subject']),
      prefsHash: prefsHash,
    );
  }
  return out;
}

/// [ymin, xmin, ymax, xmax] w skali 0-1000 → [left, top, width, height] w ułamkach
List<double>? _subjectBox(Object? raw) {
  if (raw is! List || raw.length != 4 || raw.any((v) => v is! num)) return null;
  final v = [for (final x in raw) ((x as num).toDouble() / 1000).clamp(0.0, 1.0)];
  final top = v[0] < v[2] ? v[0] : v[2], bottom = v[0] < v[2] ? v[2] : v[0];
  final left = v[1] < v[3] ? v[1] : v[3], right = v[1] < v[3] ? v[3] : v[1];
  if (right - left < 0.02 || bottom - top < 0.02) return null;
  return [left, top, right - left, bottom - top];
}
