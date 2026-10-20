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
    // Kolory żywsze niż w oryginale (200, 120, 40): większa rozpiętość kanałów = większe nasycenie,
    // ale bez przesadnego przesterowania
    final center = out.getPixel(240, 240);
    expect(center.r - center.b, greaterThan(200 - 40));
    expect(center.r, inInclusiveRange(200, 235));
    expect(center.g, inInclusiveRange(105, 145));
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

  test('żywsze kolory bez przekręcania kanałów (nasycone kolory, cienie, światła)', () {
    // Paski: mocno nasycone barwy, ciemne i jasne - żaden kanał nie może „przeskoczyć” na drugi koniec
    final colors = [
      [255, 0, 0], [0, 255, 0], [0, 0, 255], [250, 120, 0], [30, 20, 10], [240, 235, 230], [128, 128, 128],
    ];
    final src = img.Image(width: 700, height: 700);
    for (var i = 0; i < colors.length; i++) {
      img.fillRect(src, x1: i * 100, y1: 0, x2: i * 100 + 99, y2: 699,
          color: img.ColorRgb8(colors[i][0], colors[i][1], colors[i][2]));
    }
    final out = img.decodePng(preparePng(Uint8List.fromList(img.encodePng(src))))!;
    for (var i = 0; i < colors.length; i++) {
      final x = ((i * 100 + 50) * watchSize / 700).round();
      final p = out.getPixel(x, 240);
      final c = colors[i];
      for (final (k, v) in [p.r, p.g, p.b].indexed) {
        // kanał bliski 0 zostaje ciemny, bliski 255 - jasny (bez zawijania 0 ↔ 255)
        if (c[k] <= 20) expect(v, lessThan(80), reason: 'kolor $c kanał $k');
        if (c[k] >= 230) expect(v, greaterThan(180), reason: 'kolor $c kanał $k');
      }
    }
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
