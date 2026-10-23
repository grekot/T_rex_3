// Przygotowanie zdjęcia dla zegarka: kwadratowy kadr (CropBox), 480×480, czarne narożniki
// (okrągły ekran i tak ich nie pokaże, a jednolity kolor lepiej się kompresuje), PNG.
// Zegarek (image.convert w aplikacji Zepp) przyjmuje tylko PNG i nie zmienia rozmiaru.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../select/crop.dart';

const int watchSize = 480;

/// Wersja obróbki kolorów - zmiana daje nowe pliki PNG i nowe zdjęcia dla zegarka
const int pngStyleVersion = 3;

/// Żywsze kolory pod mały ekran AMOLED oglądany z ręki, ale bez prześwietleń (wersja 3):
/// - kontrast jako łagodna krzywa S: w środku ×1,08, a czerń i biel zostają na miejscu
///   (wersja 2 miała kontrast liniowy - wszystko od ok. 92% jasności robiło się białe),
/// - półcienie zależnie od zdjęcia: ciemne lekko rozjaśnione, jasne lekko przyciemnione,
/// - nasycenie do ×1,2, coraz słabsze w jasnych miejscach (niebo, odblaski, jasna skóra); gdy kolor
///   wyszedłby poza zakres, piksel dostaje mniej nasycenia zamiast przycięcia kanału (barwa zostaje).
const double vividSaturation = 1.2;
const double vividContrast = 0.08;

/// Gamma półcieni od średniej jasności zdjęcia (0..1) i udziału prawie białych pikseli (0..1):
/// zdjęcie ciemne (średnia 0,3) → 0,92 (jaśniej), przeciętne (ok. 0,49) → 1,0, jasne (0,6) → 1,08 (ciemniej);
/// dużo prawie białych pikseli dodatkowo przyciemnia, żeby jasne partie nie zlały się w biel.
double toneGamma(double meanLuma, double nearWhite) =>
    (0.94 + 0.7 * (meanLuma - 0.40) + 0.5 * nearWhite).clamp(0.92, 1.10).toDouble();

/// Krzywa tonów (0..255 → 0..255): krzywa S z kontrastem [vividContrast] w środku, potem gamma.
/// Zawsze rosnąca, 0 → 0 i 255 → 255, więc niczego nie przycina.
Uint8List toneLut(double gamma) {
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    final x = v / 255;
    final s = x - vividContrast / (2 * math.pi) * math.sin(2 * math.pi * x);
    lut[v] = (math.pow(s.clamp(0.0, 1.0), gamma) * 255).round().clamp(0, 255);
  }
  return lut;
}

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

double _luma(num r, num g, num b) => 0.299 * r + 0.587 * g + 0.114 * b;

/// Średnia jasność (0..1) i udział prawie białych pikseli (jasność ≥ 235) w kole widocznym na zegarku
({double mean, double nearWhite}) lumaStats(img.Image image) {
  final cx = image.width / 2, cy = image.height / 2;
  final r2 = cx * cx;
  var sum = 0.0;
  var count = 0;
  var white = 0;
  for (final p in image) {
    final dx = p.x + 0.5 - cx, dy = p.y + 0.5 - cy;
    if (dx * dx + dy * dy > r2) continue;
    final y = _luma(p.r, p.g, p.b);
    sum += y;
    if (y >= 235) white++;
    count++;
  }
  if (count == 0) return (mean: 0.5, nearWhite: 0.0);
  return (mean: sum / count / 255, nearWhite: white / count);
}

/// Nasycenie piksela: [vividSaturation] w ciemnych i średnich tonach, w jasnych (jasność 180 → 240)
/// spada do zera. Wykorzystuje najwyżej 60% zapasu do granicy 0..255: kanał nie dochodzi do 255,
/// więc jasne barwy (zachód słońca) nie robią się płaskie, a barwa piksela się nie zmienia.
double _saturationFor(double y, double maxD, double minD) {
  final t = ((y - 180) / 60).clamp(0.0, 1.0);
  final highlight = t * t * (3 - 2 * t);
  var s = 1 + (vividSaturation - 1) * (1 - highlight);
  var fit = double.infinity;
  if (maxD > 0) fit = math.min(fit, (255 - y) / maxD);
  if (minD < 0) fit = math.min(fit, y / -minD);
  if (fit.isFinite) s = math.min(s, 1 + (fit - 1) * 0.6);
  return math.max(s, 1.0);
}

/// Własna obróbka zamiast img.adjustColor (tam przy nasyconych kolorach kanały zawijały się 0 ↔ 255):
/// krzywa tonów dobrana do zdjęcia, potem nasycenie względem jasności piksela (jak „saturate” w CSS).
void vivid(img.Image image) {
  final stats = lumaStats(image);
  final lut = toneLut(toneGamma(stats.mean, stats.nearWhite));
  for (final p in image) {
    final r = lut[p.r.toInt()].toDouble(), g = lut[p.g.toInt()].toDouble(), b = lut[p.b.toInt()].toDouble();
    final y = _luma(r, g, b);
    final dr = r - y, dg = g - y, db = b - y;
    final s = _saturationFor(y, math.max(dr, math.max(dg, db)), math.min(dr, math.min(dg, db)));
    p
      ..r = (y + dr * s).round().clamp(0, 255)
      ..g = (y + dg * s).round().clamp(0, 255)
      ..b = (y + db * s).round().clamp(0, 255);
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
