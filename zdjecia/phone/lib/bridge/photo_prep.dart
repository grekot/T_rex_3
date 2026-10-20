// Przygotowanie zdjęcia dla zegarka: kwadratowy kadr (CropBox), 480×480, czarne narożniki
// (okrągły ekran i tak ich nie pokaże, a jednolity kolor lepiej się kompresuje), PNG.
// Zegarek (image.convert w aplikacji Zepp) przyjmuje tylko PNG i nie zmienia rozmiaru.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../select/crop.dart';

const int watchSize = 480;

/// Wersja obróbki kolorów - zmiana daje nowe pliki PNG i nowe zdjęcia dla zegarka
const int pngStyleVersion = 2;

/// Żywsze kolory pod mały ekran AMOLED oglądany z ręki: mocniejsze nasycenie, trochę kontrastu,
/// lekko rozjaśnione półcienie (gamma < 1). Umiarkowanie - skóra ma zostać naturalna.
const double vividSaturation = 1.25;
const double vividContrast = 1.08;
const double vividGamma = 0.94;

class PrepJob {
  const PrepJob(this.source, this.crop);

  final Uint8List source;
  final CropBox crop;
}

/// Dla `compute` (osobny wątek) - jeden argument.
Uint8List preparePngJob(PrepJob job) => preparePng(job.source, crop: job.crop);

Uint8List preparePng(Uint8List source, {CropBox crop = CropBox.full}) {
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    throw const FormatException('Nie udało się odczytać zdjęcia');
  }
  final upright = img.bakeOrientation(decoded);
  final r = cropRect(crop, upright.width, upright.height, outputSize: watchSize);
  var square = img.copyResize(
    img.copyCrop(upright, x: r.x, y: r.y, width: r.size, height: r.size),
    width: watchSize,
    height: watchSize,
    interpolation: img.Interpolation.average,
  );
  if (square.numChannels != 3) square = square.convert(numChannels: 3);
  vivid(square);
  blackOutsideCircle(square);
  return img.encodePng(square, level: 6);
}

/// Własna obróbka zamiast img.adjustColor: tam przy mocno nasyconych kolorach kanały wychodziły poza
/// zakres i zawijały się (0 → 255, fioletowe plamy). Tu każdy krok jest przycięty do 0..255.
/// Nasycenie względem jasności piksela (jak „saturate” w CSS), potem tablica kontrastu i gammy.
void vivid(img.Image image) {
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    final c = (0.5 + (v / 255 - 0.5) * vividContrast).clamp(0.0, 1.0);
    lut[v] = (math.pow(c, vividGamma) * 255).round().clamp(0, 255);
  }
  for (final p in image) {
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    final gray = 0.299 * r + 0.587 * g + 0.114 * b;
    int sat(double c) => (gray + (c - gray) * vividSaturation).round().clamp(0, 255);
    p
      ..r = lut[sat(r)]
      ..g = lut[sat(g)]
      ..b = lut[sat(b)];
  }
}

void blackOutsideCircle(img.Image image) {
  final cx = image.width / 2;
  final cy = image.height / 2;
  final r2 = cx * cx;
  for (var y = 0; y < image.height; y++) {
    final dy = y + 0.5 - cy;
    for (var x = 0; x < image.width; x++) {
      final dx = x + 0.5 - cx;
      if (dx * dx + dy * dy > r2) image.setPixelRgb(x, y, 0, 0, 0);
    }
  }
}

/// Identyfikator zdjęcia dla zegarka: zmienia się, gdy zdjęcie zostanie edytowane.
/// Zegarek przyjmuje tylko [A-Za-z0-9_-], najwyżej 40 znaków.
String photoId(String assetId, int modifiedSecond) {
  final raw = '${assetId}_$modifiedSecond'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return raw.length <= 40 ? raw : raw.substring(raw.length - 40);
}
