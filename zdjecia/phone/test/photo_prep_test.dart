import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zdjecia/bridge/photo_prep.dart';
import 'package:zdjecia/select/crop.dart';

void main() {
  test('zdjęcie poziome staje się PNG 480×480 z czarnymi narożnikami', () {
    final src = img.Image(width: 1200, height: 800);
    img.fill(src, color: img.ColorRgb8(200, 120, 40));
    final png = preparePng(Uint8List.fromList(img.encodeJpg(src, quality: 90)));

    final out = img.decodePng(png)!;
    expect(out.width, watchSize);
    expect(out.height, watchSize);
    expect(out.numChannels, 3);
    final corner = out.getPixel(2, 2);
    expect([corner.r, corner.g, corner.b], [0, 0, 0]);
    final center = out.getPixel(240, 240);
    expect(center.r, closeTo(200, 6));
    expect(center.g, closeTo(120, 6));
  });

  test('kadr wycina wskazaną część zdjęcia', () {
    final src = img.Image(width: 1600, height: 1200);
    img.fill(src, color: img.ColorRgb8(0, 0, 255));
    img.fillRect(src, x1: 1200, y1: 0, x2: 1599, y2: 1199, color: img.ColorRgb8(255, 0, 0));
    final bytes = Uint8List.fromList(img.encodeJpg(src, quality: 95));
    // kadr przy prawej krawędzi: środek zdjęcia na zegarku ma być czerwony
    final right = img.decodePng(preparePng(bytes, crop: const CropBox(cx: 0.875, cy: 0.5, side: 0.3)))!;
    expect(right.getPixel(240, 240).r, greaterThan(200));
    final left = img.decodePng(preparePng(bytes, crop: const CropBox(cx: 0.2, cy: 0.5, side: 0.3)))!;
    expect(left.getPixel(240, 240).b, greaterThan(200));
  });

  test('nieczytelne dane to błąd', () {
    expect(() => preparePng(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('id zdjęcia pasuje do formatu zegarka', () {
    expect(photoId('1234', 1700000000), '1234_1700000000');
    expect(photoId('a/b:c', 5), 'a_b_c_5');
    final long = photoId('x' * 60, 1);
    expect(long.length, 40);
    expect(RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(long), isTrue);
  });
}
