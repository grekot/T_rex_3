import 'dart:math' as math;
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

  // Obraz 480×480 (bez skalowania) z poziomym przejściem kolorów - do porównań przed/po obróbce
  img.Image gradient(List<int> from, List<int> to) {
    final im = img.Image(width: watchSize, height: watchSize);
    for (final p in im) {
      final t = p.x / (watchSize - 1);
      p
        ..r = (from[0] + (to[0] - from[0]) * t).round()
        ..g = (from[1] + (to[1] - from[1]) * t).round()
        ..b = (from[2] + (to[2] - from[2]) * t).round();
    }
    return im;
  }

  // Średnia jasność i liczba prawie białych pikseli (jasność ≥ 245) w kole widocznym na zegarku
  ({double mean, int white}) stats(img.Image im) {
    var sum = 0.0, n = 0, white = 0;
    for (final p in im) {
      final dx = p.x + 0.5 - watchSize / 2, dy = p.y + 0.5 - watchSize / 2;
      if (dx * dx + dy * dy > watchSize * watchSize / 4) continue;
      final y = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      sum += y;
      if (y >= 245) white++;
      n++;
    }
    return (mean: sum / n, white: white);
  }

  img.Image prepared(img.Image src) => img.decodePng(preparePng(Uint8List.fromList(img.encodePng(src))))!;

  test('jasne zdjęcie nie robi się jaśniejsze ani bardziej prześwietlone', () {
    // niebo przechodzące w jasne chmury, jasna skóra w słońcu, śnieg
    for (final (from, to) in [
      ([150, 190, 240], [250, 250, 252]),
      ([200, 160, 140], [250, 225, 210]),
      ([210, 215, 225], [255, 255, 255]),
    ]) {
      final src = gradient(from, to);
      final before = stats(src), after = stats(prepared(src));
      expect(after.mean, lessThanOrEqualTo(before.mean), reason: '$from → $to');
      expect(after.white, lessThanOrEqualTo(before.white), reason: '$from → $to');
    }
  });

  test('ciemne zdjęcie lekko rozjaśnione', () {
    final src = gradient([10, 15, 30], [110, 90, 70]);
    expect(stats(prepared(src)).mean, greaterThan(stats(src).mean));
  });

  test('jasny nasycony kolor zachowuje barwę zamiast przyciętego kanału', () {
    final src = img.Image(width: watchSize, height: watchSize);
    img.fill(src, color: img.ColorRgb8(255, 170, 60));
    final p = prepared(src).getPixel(240, 240);
    expect(p.r, greaterThanOrEqualTo(p.g));
    expect(p.g, greaterThanOrEqualTo(p.b));
    // stosunek kanałów (barwa) jak w oryginale: (170 - 60) / (255 - 60)
    expect((p.g - p.b) / (p.r - p.b), closeTo(110 / 195, 0.03));
  });

  test('średnie, przygaszone kolory nadal żywsze', () {
    final src = img.Image(width: watchSize, height: watchSize);
    img.fill(src, color: img.ColorRgb8(120, 140, 90));
    final p = prepared(src).getPixel(240, 240);
    final spread = [p.r, p.g, p.b].reduce(math.max) - [p.r, p.g, p.b].reduce(math.min);
    expect(spread, greaterThan(140 - 90));
  });

  test('krzywa tonów: czerń i biel na miejscu, zawsze rośnie', () {
    for (final gamma in [0.92, 1.0, 1.1]) {
      final lut = toneLut(gamma);
      expect(lut[0], 0);
      expect(lut[255], 255);
      for (var v = 1; v < 256; v++) {
        expect(lut[v], greaterThanOrEqualTo(lut[v - 1]), reason: 'gamma $gamma, v $v');
      }
    }
    // jasne tony nie uciekają do bieli (wersja 2 robiła z 240 prawie 250)
    expect(toneLut(1.0)[240], lessThanOrEqualTo(243));
  });

  test('gamma: ciemne zdjęcia jaśniej, jasne ciemniej', () {
    expect(toneGamma(0.3, 0), lessThan(1));
    expect(toneGamma(0.486, 0), closeTo(1.0, 0.01));
    expect(toneGamma(0.65, 0), greaterThan(1));
    expect(toneGamma(0.5, 0.2), greaterThan(toneGamma(0.5, 0)));
    expect(toneGamma(0.0, 0), 0.92);
    expect(toneGamma(1.0, 1.0), 1.10);
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
