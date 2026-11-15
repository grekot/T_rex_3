import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zdjecia/bridge/photo_prep.dart';
import 'package:zdjecia/select/analysis.dart';
import 'package:zdjecia/select/crop.dart';
import 'package:zdjecia/select/quality.dart';

/// Zdjęcie 4:3 (albo inne) z równym profilem ciekawości
CropFrame frame({
  double aspect = 4 / 3,
  List<FaceBox> faces = const [],
  List<double>? profile,
  List<double>? focus,
  List<double>? subject,
  CropBox? manual,
}) =>
    CropFrame(
      aspect: aspect,
      faces: faces,
      profile: profile ?? List.filled(profileBins, 1 / profileBins),
      focus: focus,
      subject: subject,
      manual: manual,
    );

/// Proporcje kadru w pikselach zdjęcia
double ratioOf(RectBox r, double aspect) => r.w * aspect / r.h;

bool inside(RectBox r, double x, double y) =>
    x >= r.left - 1e-6 && x <= r.left + r.w + 1e-6 && y >= r.top - 1e-6 && y <= r.top + r.h + 1e-6;

void expectInPhoto(RectBox r) {
  expect(r.left, greaterThanOrEqualTo(-1e-9));
  expect(r.top, greaterThanOrEqualTo(-1e-9));
  expect(r.left + r.w, lessThanOrEqualTo(1 + 1e-9));
  expect(r.top + r.h, lessThanOrEqualTo(1 + 1e-9));
}

/// Czy nagłówek JPEG (segmenty przed danymi obrazu) ma marker 0xFF[marker]:
/// C0 = SOF0 baseline, C2 = SOF2 progresywny, E1 = APP1 (EXIF)
bool hasMarker(List<int> jpg, int marker) {
  expect([jpg[0], jpg[1]], [0xFF, 0xD8]);
  var i = 2;
  while (i + 3 < jpg.length) {
    expect(jpg[i], 0xFF);
    final m = jpg[i + 1];
    if (m == marker) return true;
    if (m == 0xDA) return false; // początek danych obrazu
    i += 2 + (jpg[i + 2] << 8 | jpg[i + 3]);
  }
  return false;
}

void main() {
  const ratio = 320 / 240;

  test('kadr prostokątny z fragmentu od AI: proporcje zegara, fragment w środku i cały w kadrze', () {
    // fragment w prawej części zdjęcia 16:9: x 0.6-0.9, y 0.3-0.7
    final f = frame(aspect: 16 / 9, focus: [0.6, 0.3, 0.3, 0.4], subject: [0.1, 0.1, 0.2, 0.2]);
    final r = rectCropWithSource(f, ratio);
    expect(r.source, CropSource.ai);
    expect(ratioOf(r.box, 16 / 9), closeTo(ratio, 1e-6));
    expectInPhoto(r.box);
    expect(r.box.cx, closeTo(0.75, 0.01));
    expect(r.box.cy, closeTo(0.5, 0.01));
    for (final (x, y) in [(0.6, 0.3), (0.9, 0.7)]) {
      expect(inside(r.box, x, y), isTrue);
    }
    // wypełnia: wysokość fragmentu (0.4 zdjęcia) + 8%
    expect(r.box.h, closeTo(0.4 * rectFocusPad, 0.01));
    // kwadrat (salonowy zegar 260×260) też w swoich proporcjach
    final sq = rectCrop(f, 1);
    expect(ratioOf(sq, 16 / 9), closeTo(1, 1e-6));
    expect(inside(sq, 0.6, 0.3) && inside(sq, 0.9, 0.7), isTrue);
  });

  test('fragment ucinający twarz: kadr obejmuje oba, a gdy się nie da - wyraźna twarz wygrywa', () {
    const face = FaceBox(left: 0.45, top: 0.35, width: 0.08, height: 0.1);
    final r = rectCropWithSource(frame(faces: const [face], focus: [0.6, 0.3, 0.3, 0.4]), ratio);
    expect(r.source, CropSource.ai);
    expect(inside(r.box, face.left, face.top) && inside(r.box, face.left + face.width, face.top + face.height), isTrue);
    expect(inside(r.box, 0.75, 0.5), isTrue);

    // portret 3:4, twarz na górze, fragment na dole: w kadrze 4:3 oba się nie zmieszczą
    const big = FaceBox(left: 0.4, top: 0.05, width: 0.2, height: 0.12);
    final p = rectCropWithSource(frame(aspect: 3 / 4, faces: const [big], focus: [0.3, 0.8, 0.4, 0.15]), ratio);
    expect(p.source, CropSource.faces);
    expect(inside(p.box, 0.5, 0.11), isTrue);
    expect(ratioOf(p.box, 3 / 4), closeTo(ratio, 1e-6));
  });

  test('bez fragmentu od AI: twarze, potem motyw, potem pas; zawsze w proporcjach i w zdjęciu', () {
    const face = FaceBox(left: 0.4, top: 0.3, width: 0.2, height: 0.25);
    expect(rectCropWithSource(frame(faces: const [face]), ratio).source, CropSource.faces);
    expect(rectCropWithSource(frame(subject: [0.2, 0.2, 0.3, 0.3]), ratio).source, CropSource.subject);
    expect(rectCropWithSource(frame(), ratio).source, CropSource.band);
    // zdjęcie 4:3 w kadrze 4:3 bez motywu = całe zdjęcie
    final full = rectCrop(frame(), 4 / 3);
    expect([full.cx, full.cy, full.w, full.h], [closeTo(0.5, 1e-9), closeTo(0.5, 1e-9), closeTo(1, 1e-9), closeTo(1, 1e-9)]);
    for (final aspect in [4 / 3, 3 / 4, 16 / 9, 1.0]) {
      for (final r in [ratio, 1.0, 0.75, 2.0]) {
        final box = rectCrop(frame(aspect: aspect, faces: const [face], focus: [0.0, 0.0, 1.0, 1.0]), r);
        expect(ratioOf(box, aspect), closeTo(r, 1e-6), reason: 'zdjęcie $aspect, kadr $r');
        expectInPhoto(box);
      }
    }
  });

  test('najciekawszy pas: portret w kadrze poziomym przesuwa się do ciekawej części', () {
    // zdjęcie 3:4, cała ciekawość w dolnej ćwiartce
    final profile = [for (var i = 0; i < profileBins; i++) i >= profileBins * 3 ~/ 4 ? 0.25 : 0.0];
    final r = rectCrop(frame(aspect: 3 / 4, profile: profile), ratio);
    expect(r.w, closeTo(1, 1e-9)); // cała szerokość
    expect(r.cy, greaterThan(0.7));
    expectInPhoto(r);
  });

  test('ręczny kadr kwadratowy: ten sam środek, rozszerzony do proporcji zegara', () {
    const manual = CropBox(cx: 0.4, cy: 0.5, side: 0.5);
    final r = rectCropWithSource(frame(manual: manual, focus: [0.7, 0.1, 0.2, 0.2]), ratio);
    expect(r.source, CropSource.manual);
    expect([r.box.cx, r.box.cy], [closeTo(0.4, 1e-9), closeTo(0.5, 1e-9)]);
    // wysokość = bok kwadratu, szerokość = bok × 4/3 (kwadrat cały w kadrze)
    expect(r.box.h, closeTo(0.5, 1e-9));
    expect(r.box.w * 4 / 3, closeTo(0.5 * ratio, 1e-9));
    // kwadrat przy krawędzi i większy niż mieści się w proporcjach: w granicach zdjęcia
    final edge = rectCrop(frame(aspect: 3 / 4, manual: const CropBox(cx: 0.5, cy: 0.2, side: 1)), ratio);
    expectInPhoto(edge);
    expect(ratioOf(edge, 3 / 4), closeTo(ratio, 1e-6));
  });

  test('dane kadru przechodzą przez JSON (published.json)', () {
    final a = PhotoAnalysis(
      id: 'p',
      assetId: '42',
      taken: DateTime(2026, 10, 1),
      favorite: false,
      faces: const [FaceBox(left: 0.4, top: 0.3, width: 0.2, height: 0.25, smile: 0.9)],
      quality: QualityMetrics(
        width: 400,
        height: 300,
        sharpness: 500,
        brightness: 0.5,
        dark: 0,
        bright: 0,
        colorfulness: 40,
        hash: '0000000000000000',
        profile: List.filled(profileBins, 1 / profileBins),
      ),
    );
    final f = CropFrame.of(a, focus: [0.1, 0.2, 0.3, 0.4], subject: [0.5, 0.5, 0.2, 0.2],
        manual: const CropBox(cx: 0.5, cy: 0.5, side: 0.8));
    final back = CropFrame.fromJson(f.toJson());
    expect(back.aspect, closeTo(4 / 3, 1e-3));
    expect(back.faces.single.width, 0.2);
    expect(back.profile.length, profileBins);
    expect(back.focus, [0.1, 0.2, 0.3, 0.4]);
    expect(back.subject, [0.5, 0.5, 0.2, 0.2]);
    expect(back.manual, const CropBox(cx: 0.5, cy: 0.5, side: 0.8));
    final bare = CropFrame.fromJson(const CropFrame(aspect: 1.5).toJson());
    expect(bare.faces, isEmpty);
    expect((bare.focus, bare.manual), (null, null));
  });

  test('piksele kadru: proporcje, granice obrazu, powiększenie zbyt małego kadru', () {
    const box = RectBox(cx: 0.9, cy: 0.5, w: 0.3, h: 0.3);
    final r = rectPixels(box, 1600, 1200, outWidth: 320, outHeight: 240);
    expect(r.x + r.w, lessThanOrEqualTo(1600));
    expect(r.w / r.h, closeTo(1600 / 1200, 0.01));
    // mały kadr na małym obrazie: powiększony do rozmiaru wyjścia, o ile obraz pozwala
    final small = rectPixels(const RectBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2), 640, 480, outWidth: 320, outHeight: 240);
    expect((small.w, small.h), (320, 240));
    final tiny = rectPixels(const RectBox(cx: 0.5, cy: 0.5, w: 0.5, h: 0.5), 200, 150, outWidth: 320, outHeight: 240);
    expect((tiny.x, tiny.y, tiny.w, tiny.h), (0, 0, 200, 150));
  });

  test('JPEG dla zegara: dokładny rozmiar, baseline, bez EXIF, obróbka kolorów, kadr ze wskazanej części', () {
    final src = img.Image(width: 1600, height: 1200);
    img.fill(src, color: img.ColorRgb8(0, 0, 255));
    img.fillRect(src, x1: 1200, y1: 0, x2: 1599, y2: 1199, color: img.ColorRgb8(200, 120, 40));
    src.exif.imageIfd['Make'] = img.IfdValueAscii('Telefon');
    final bytes = Uint8List.fromList(img.encodeJpg(src, quality: 95));
    expect(hasMarker(bytes, 0xE1), isTrue); // źródło ma EXIF

    final jpg = prepareJpeg(bytes, rect: const RectBox(cx: 0.875, cy: 0.5, w: 0.25, h: 0.25), width: 320, height: 240);
    expect(jpg.length, lessThanOrEqualTo(maxJpegBytes));
    expect(hasMarker(jpg, 0xC0), isTrue); // SOF0 = baseline
    expect(hasMarker(jpg, 0xC2), isFalse); // bez SOF2 (progresywny)
    expect(hasMarker(jpg, 0xE1), isFalse); // bez APP1 (EXIF)
    final out = img.decodeJpg(jpg)!;
    expect((out.width, out.height), (320, 240));
    final c = out.getPixel(160, 120);
    // pomarańczowy z prawej części, żywszy niż w oryginale
    expect(c.r - c.b, greaterThan(200 - 40));
    expect(c.r, inInclusiveRange(195, 240));
  });

  test('JPEG z szumem w największym rozmiarze nie przekracza 96 KB (niższa jakość)', () {
    final rnd = math.Random(1);
    final src = img.Image(width: 800, height: 800);
    for (final p in src) {
      p
        ..r = rnd.nextInt(256)
        ..g = rnd.nextInt(256)
        ..b = rnd.nextInt(256);
    }
    final bytes = Uint8List.fromList(img.encodePng(src));
    final jpg = prepareJpeg(bytes, rect: RectBox.full, width: maxJpegSide, height: maxJpegSide);
    expect(jpg.length, lessThanOrEqualTo(maxJpegBytes));
    expect(img.decodeJpg(jpg)!.width, maxJpegSide);
    // nietypowe, nieparzyste wymiary też (4:2:0)
    final odd = img.decodeJpg(prepareJpeg(bytes, rect: RectBox.full, width: 65, height: 99))!;
    expect((odd.width, odd.height), (65, 99));
  });
}
