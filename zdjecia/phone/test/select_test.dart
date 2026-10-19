import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zdjecia/select/analysis.dart';
import 'package:zdjecia/select/candidates.dart';
import 'package:zdjecia/select/crop.dart';
import 'package:zdjecia/select/pool.dart';
import 'package:zdjecia/select/quality.dart';
import 'package:zdjecia/select/scoring.dart';
import 'package:zdjecia/select/store.dart';

final now = DateTime(2026, 10, 19, 12);

QualityMetrics q({
  double sharp = 500,
  double lum = 0.5,
  double color = 40,
  String hash = '0000000000000000',
  int w = 512,
  int h = 384,
  List<double>? profile,
}) =>
    QualityMetrics(
      width: w,
      height: h,
      sharpness: sharp,
      brightness: lum,
      dark: 0.01,
      bright: 0.01,
      colorfulness: color,
      hash: hash,
      profile: profile ?? List.filled(profileBins, 1 / profileBins),
    );

PhotoAnalysis photo(
  String id, {
  DateTime? taken,
  QualityMetrics? quality,
  bool fav = false,
  List<FaceBox> faces = const [],
  List<LabelHit> labels = const [],
  int text = -1,
}) =>
    PhotoAnalysis(
      id: id,
      assetId: id,
      taken: taken ?? now.subtract(const Duration(days: 1)),
      favorite: fav,
      quality: quality ?? q(),
      faces: faces,
      labels: labels,
      textChars: text,
    );

ScoredPhoto scored(String id, double score, DateTime taken, {String hash = '0000000000000000', String? rejected}) =>
    ScoredPhoto(analysis: photo(id, taken: taken, quality: q(hash: hash)), score: score, tags: const [], rejected: rejected);

img.Image checkerboard({int size = 256, int cell = 8}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final on = ((x ~/ cell) + (y ~/ cell)).isEven;
      image.setPixelRgb(x, y, on ? 230 : 20, on ? 120 : 40, on ? 40 : 200);
    }
  }
  return image;
}

void main() {
  group('jakość', () {
    test('rozmyte zdjęcie ma dużo mniejszą ostrość niż ostre', () {
      final sharp = checkerboard();
      final blurry = img.gaussianBlur(checkerboard(), radius: 6);
      expect(measureImage(sharp).sharpness, greaterThan(measureImage(blurry).sharpness * 10));
    });

    test('odcisk: lekko zmienione zdjęcie jest podobne, inne - nie', () {
      final a = measureImage(checkerboard());
      final b = measureImage(img.adjustColor(checkerboard(), brightness: 1.05));
      final c = measureImage(img.flipHorizontal(checkerboard(cell: 37)));
      expect(hammingDistance(a.hash, b.hash), lessThan(6));
      expect(hammingDistance(a.hash, c.hash), greaterThan(burstMaxHamming));
    });

    test('profil sumuje się do 1 i wskazuje ciekawszą część', () {
      final image = img.Image(width: 400, height: 200);
      img.fill(image, color: img.ColorRgb8(90, 90, 90));
      // prawa część pełna krawędzi i koloru
      img.compositeImage(image, checkerboard(size: 200, cell: 6), dstX: 200);
      final m = measureImage(image);
      expect(m.profile.reduce((a, b) => a + b), closeTo(1, 1e-6));
      expect(m.profile.last, greaterThan(m.profile.first));
      expect(autoCrop(photo('p', quality: m)).cx, greaterThan(0.6));
    });

    test('zapis i odczyt wyników', () {
      final a = photo(
        'x',
        fav: true,
        faces: const [FaceBox(left: 0.1, top: 0.2, width: 0.3, height: 0.3, smile: 0.9)],
        labels: const [LabelHit('Dog', 0.87)],
        text: 3,
      );
      final back = PhotoAnalysis.fromJson(a.toJson());
      expect(back!.faces.single.smile, 0.9);
      expect(back.labels.single.name, 'Dog');
      expect(back.quality.hash, a.quality.hash);
      expect(PhotoAnalysis.fromJson({...a.toJson(), 'v': analysisVersion + 1}), isNull);
    });
  });

  group('punktacja', () {
    test('dokumenty i paragony odpadają, ulubione mają premię', () {
      final list = scoreAll([
        photo('paragon', labels: const [LabelHit('Receipt', 0.8)]),
        photo('kartka', text: 200),
        photo('pies', labels: const [LabelHit('Dog', 0.9)]),
        photo('ulubione', fav: true),
        photo('zwykle'),
      ], now: now, days: 30);
      final byId = {for (final s in list) s.id: s};
      expect(byId['paragon']!.rejected, 'dokument / tekst');
      expect(byId['kartka']!.rejected, 'dokument / tekst');
      expect(byId['pies']!.tags, contains('zwierzę'));
      expect(byId['ulubione']!.tags.first, 'ulubione');
      expect(byId['ulubione']!.score, greaterThan(byId['zwykle']!.score + 0.8));
    });

    test('tekst na zdjęciu z twarzą nie robi z niego dokumentu', () {
      final s = scoreAll([
        photo('t', text: 200, faces: const [FaceBox(left: 0.4, top: 0.3, width: 0.2, height: 0.25)]),
      ], now: now, days: 30).single;
      expect(s.accepted, isTrue);
    });

    test('najmniej ostre odpadają, uśmiech i twarze podnoszą punkty', () {
      final list = scoreAll([
        for (var i = 0; i < 9; i++) photo('ostre$i', quality: q(sharp: 400.0 + i)),
        photo('rozmyte', quality: q(sharp: 30)),
        photo('usmiech', faces: const [
          FaceBox(left: 0.4, top: 0.3, width: 0.2, height: 0.25, smile: 0.95, eyesOpen: 0.9),
        ]),
      ], now: now, days: 30);
      final byId = {for (final s in list) s.id: s};
      expect(byId['rozmyte']!.rejected, 'nieostre');
      expect(byId['usmiech']!.tags, containsAll(['twarz', 'uśmiech']));
      expect(byId['usmiech']!.score, greaterThan(byId['ostre5']!.score));
    });

    test('malutkie twarze w tle się nie liczą', () {
      final faces = mainFaces(const [
        FaceBox(left: 0.4, top: 0.3, width: 0.3, height: 0.3),
        FaceBox(left: 0.05, top: 0.05, width: 0.05, height: 0.05),
        FaceBox(left: 0.9, top: 0.9, width: 0.01, height: 0.01),
      ]);
      expect(faces.length, 1);
    });
  });

  group('pula', () {
    final day1 = DateTime(2026, 10, 10, 9);
    final day2 = DateTime(2026, 10, 11, 9);

    test('z serii zostaje najlepsze ujęcie', () {
      final groups = groupBursts([
        scored('a', 1.0, day1),
        scored('b', 2.0, day1.add(const Duration(seconds: 2)), hash: 'ffffffffffffffff'),
        scored('c', 1.5, day1.add(const Duration(seconds: 40))),
        scored('d', 3.0, day1.add(const Duration(minutes: 30))),
      ]);
      expect(groups.map((g) => g.map((s) => s.id).toList()).toList(), [
        ['b', 'c', 'a'],
        ['d'],
      ]);
    });

    test('najwyżej 2 zdjęcia z dnia, z różnych wydarzeń; przypięte i usunięte', () {
      final photos = [
        scored('rano', 5, day1),
        scored('rano2', 4.9, day1.add(const Duration(minutes: 30)), hash: 'ffffffffffffffff'),
        scored('wieczor', 4, day1.add(const Duration(hours: 10))),
        scored('noc', 3.9, day1.add(const Duration(hours: 13))),
        scored('nastepny', 1, day2),
        scored('slabe', 0.1, day2.add(const Duration(hours: 5)), rejected: 'nieostre'),
        scored('usuniete', 9, day2.add(const Duration(hours: 8))),
      ];
      final pool = choosePool(photos, const PoolRules(size: 4, pinned: {'slabe'}, removed: {'usuniete'}));
      expect(pool.map((s) => s.id).toList(), ['slabe', 'rano', 'wieczor', 'nastepny']);
    });

    test('gdy brakuje zdjęć, zasady łagodnieją', () {
      final photos = [
        for (var i = 0; i < 5; i++) scored('p$i', 5.0 - i, day1.add(Duration(hours: i * 3)), hash: '${i}000000000000000'),
      ];
      expect(choosePool(photos, const PoolRules(size: 5)).length, 5);
    });
  });

  group('kadr', () {
    test('twarze mieszczą się w kole', () {
      const face = FaceBox(left: 0.6, top: 0.2, width: 0.12, height: 0.16);
      final c = autoCrop(photo('f', quality: q(w: 400, h: 300), faces: const [face]));
      // przeliczenie na piksele zdjęcia o krótszym boku 1
      const w = 4 / 3, h = 1.0;
      final side = c.side, cx = c.cx * w, cy = c.cy * h;
      for (final p in [
        [face.left * w, face.top * h],
        [(face.left + face.width) * w, face.top * h],
        [face.left * w, (face.top + face.height) * h],
        [(face.left + face.width) * w, (face.top + face.height) * h],
      ]) {
        final d = math.sqrt(math.pow(p[0] - cx, 2) + math.pow(p[1] - cy, 2));
        expect(d, lessThanOrEqualTo(side / 2));
      }
      expect(side, greaterThanOrEqualTo(minSide));
      expect(cx - side / 2, greaterThanOrEqualTo(-1e-9));
      expect(cx + side / 2, lessThanOrEqualTo(w + 1e-9));
    });

    test('kwadratowe zdjęcie bez twarzy - cały kadr', () {
      expect(autoCrop(photo('k', quality: q(w: 300, h: 300))), CropBox.full);
    });

    test('prostokąt kadru w pikselach nie jest mniejszy niż 480, gdy się da', () {
      final r = cropRect(const CropBox(cx: 0.5, cy: 0.5, side: 0.3), 1600, 1200);
      expect((r.x, r.y, r.size), (560, 360, 480));
      final edge = cropRect(const CropBox(cx: 0.99, cy: 0.01, side: 1), 1600, 1200);
      expect((edge.x, edge.y, edge.size), (400, 0, 1200));
    });
  });

  group('kandydaci i identyfikatory', () {
    test('tylko aparat, bez zrzutów i komunikatorów', () {
      expect(isCameraPath('DCIM/Camera/'), isTrue);
      expect(isCameraPath('DCIM/100ANDRO/'), isTrue);
      expect(isCameraPath('DCIM/Screenshots/'), isFalse);
      expect(isCameraPath('Pictures/Screenshots/'), isFalse);
      expect(isCameraPath('Android/media/com.whatsapp/WhatsApp/Media/'), isFalse);
      expect(isCameraPath('Download/'), isFalse);
      expect(isCameraPath(null), isTrue);
    });

    test('identyfikator na zegarku zależy od kadru i mieści się w 40 znakach', () {
      const a = CropBox(cx: 0.5, cy: 0.5, side: 1);
      const b = CropBox(cx: 0.4, cy: 0.5, side: 0.8);
      expect(watchPhotoId('1234_5', a), isNot(watchPhotoId('1234_5', b)));
      expect(watchPhotoId('1234_5', a), watchPhotoId('1234_5', a));
      final long = watchPhotoId('x' * 40, a);
      expect(long.length, 40);
      expect(RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(long), isTrue);
    });
  });

  test('pamięć: ustawienia i wyniki analizy przetrwają ponowne uruchomienie', () async {
    final dir = await Directory.systemTemp.createTemp('zdjecia_test');
    try {
      final store = SelectStore(dir);
      final prefs = await store.loadPrefs();
      expect((prefs.days, prefs.size), (30, 20));
      prefs.pinned.add('a');
      prefs.crops['a'] = const CropBox(cx: 0.3, cy: 0.4, side: 0.6);
      prefs.pinnedAssets['a'] = '99';
      await store.savePrefs(prefs);
      await store.saveAnalyses({'a': photo('a')});

      final again = SelectStore(dir);
      final p2 = await again.loadPrefs();
      expect(p2.pinned, {'a'});
      expect(p2.crops['a'], const CropBox(cx: 0.3, cy: 0.4, side: 0.6));
      expect(p2.pinnedAssets, {'a': '99'});
      expect((await again.loadAnalyses()).keys, ['a']);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
