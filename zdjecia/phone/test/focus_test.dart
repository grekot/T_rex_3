import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:zdjecia/ai/photo_rating.dart';
import 'package:zdjecia/select/analysis.dart';
import 'package:zdjecia/select/crop.dart';
import 'package:zdjecia/select/quality.dart';
import 'package:zdjecia/select/store.dart';

PhotoAnalysis photo({List<FaceBox> faces = const [], int w = 400, int h = 300}) => PhotoAnalysis(
      id: 'p',
      assetId: 'p',
      taken: DateTime(2026, 10, 1),
      favorite: false,
      faces: faces,
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

/// Czy punkt (w ułamkach zdjęcia) leży w kole kadru
bool inCircle(CropBox c, double x, double y, {double aspect = 4 / 3}) {
  final w = math.max(aspect, 1.0), h = math.max(1 / aspect, 1.0);
  final dx = x * w - c.cx * w, dy = y * h - c.cy * h;
  return dx * dx + dy * dy <= (c.side / 2) * (c.side / 2) + 1e-9;
}

void main() {
  test('AI zwraca najciekawszy fragment obok głównego motywu', () {
    final out = parseRatings({
      'photos': [
        {
          'n': 1,
          'score': 8,
          'keep': true,
          'category': 'zwierzęta',
          'caption': 'Pies',
          'reason': 'x',
          'subject': [300, 500, 900, 900],
          'focus': [200, 400, 800, 800],
        },
      ],
    }, 1, 'h');
    final focus = out.single!.focus!;
    for (final (i, v) in [0.4, 0.2, 0.4, 0.6].indexed) {
      expect(focus[i], closeTo(v, 1e-9));
    }
    expect(ratingSchema.toString(), contains('focus'));
    expect(ratingSystemPrompt, contains('OKRĄGŁYM'));
  });

  test('kadr wypełnia się fragmentem od AI (bez twarzy)', () {
    // fragment w prawej części zdjęcia 4:3: x 0.6-0.9, y 0.3-0.7
    final r = autoCropWithSource(photo(), focus: [0.6, 0.3, 0.3, 0.4], subject: [0.1, 0.1, 0.2, 0.2]);
    expect(r.source, CropSource.ai);
    // środek fragmentu = środek kadru (w granicach zdjęcia), fragment wypełnia kadr
    expect(r.box.cx, closeTo(0.75, 0.01));
    expect(r.box.side, closeTo(0.4 * 1.08, 0.01));
  });

  test('fragment ucinający twarz rozszerza się, żeby twarz była w kole', () {
    // twarz tuż obok fragmentu - kadr obejmie oba
    const face = FaceBox(left: 0.45, top: 0.35, width: 0.08, height: 0.1);
    final r = autoCropWithSource(photo(faces: const [face]), focus: [0.6, 0.3, 0.3, 0.4]);
    expect(r.source, CropSource.ai);
    expect(inCircle(r.box, face.left, face.top), isTrue);
    expect(inCircle(r.box, face.left + face.width, face.top + face.height), isTrue);
    expect(inCircle(r.box, 0.75, 0.5), isTrue); // środek fragmentu też
  });

  test('twarz i fragment na przeciwnych końcach: wyraźna twarz wygrywa, malutka nie', () {
    const big = FaceBox(left: 0.05, top: 0.3, width: 0.12, height: 0.16);
    final r = autoCropWithSource(photo(faces: const [big]), focus: [0.7, 0.3, 0.25, 0.4]);
    expect(r.source, CropSource.faces);
    expect(inCircle(r.box, big.left + big.width / 2, big.top + big.height / 2), isTrue);
    const tiny = FaceBox(left: 0.05, top: 0.3, width: 0.06, height: 0.08);
    final t = autoCropWithSource(photo(faces: const [tiny]), focus: [0.7, 0.3, 0.25, 0.4]);
    expect(t.source, CropSource.ai);
    expect(inCircle(t.box, 0.825, 0.5), isTrue);
  });

  test('bez fragmentu od AI: twarze, potem motyw, potem pas', () {
    const face = FaceBox(left: 0.4, top: 0.3, width: 0.2, height: 0.25);
    expect(autoCropWithSource(photo(faces: const [face])).source, CropSource.faces);
    expect(autoCropWithSource(photo(), subject: [0.2, 0.2, 0.3, 0.3]).source, CropSource.subject);
    expect(autoCropWithSource(photo()).source, CropSource.band);
  });

  test('zdjęcia z puli oceniane ponownie, gdy ocena nie ma kadru AI', () {
    const old = PhotoRating(score: 8, keep: true, category: 'ludzie', caption: '', reason: '', prefsHash: 'h');
    const withFocus = PhotoRating(
      score: 8,
      keep: true,
      category: 'ludzie',
      caption: '',
      reason: '',
      prefsHash: 'h',
      focus: [0.1, 0.1, 0.5, 0.5],
    );
    expect(needsRating(null, 'h'), isTrue);
    expect(needsRating(old, 'inne'), isTrue);
    expect(needsRating(old, 'h'), isFalse);
    expect(needsRating(old, 'h', inPool: true), isTrue);
    expect(needsRating(withFocus, 'h', inPool: true), isFalse);
  });

  test('pule ze starszych wersji: id zdjęcia z id na zegarku', () {
    final p = PublishedPhoto.fromJson({'id': '1234_1700000000_abc1234', 'path': 'x', 'size': 1, 'taken': 0});
    expect(p.photoId, '1234_1700000000');
    final n = PublishedPhoto.fromJson({'id': 'x_abc1234', 'photo': 'zdjecie', 'path': 'x', 'size': 1, 'taken': 0});
    expect(n.photoId, 'zdjecie');
  });
}
