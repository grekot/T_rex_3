// Pomiary jakości zdjęcia na małej miniaturze (bez ML Kit, czysty Dart - działa w osobnym wątku):
// ostrość, jasność, prześwietlenia, kolorowość, odcisk do wykrywania serii i profil „ciekawości”
// wzdłuż dłuższego boku (gdzie przesunąć kwadratowy kadr, gdy na zdjęciu nie ma twarzy).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int _workSize = 256;
const int profileBins = 16;

class QualityMetrics {
  const QualityMetrics({
    required this.width,
    required this.height,
    required this.sharpness,
    required this.brightness,
    required this.dark,
    required this.bright,
    required this.colorfulness,
    required this.hash,
    required this.profile,
  });

  /// Wymiary analizowanej miniatury (proporcje zdjęcia już po obrocie EXIF)
  final int width;
  final int height;

  /// Wariancja laplasjanu - im więcej, tym ostrzej
  final double sharpness;

  /// Średnia jasność 0..1
  final double brightness;

  /// Udział prawie czarnych / prawie białych pikseli
  final double dark;
  final double bright;

  /// Kolorowość (Hasler i Süsstrunk), mniej więcej 0..150
  final double colorfulness;

  /// dHash 64 bity jako 16 znaków hex
  final String hash;

  /// Ciekawość (krawędzie + nasycenie) w [profileBins] pasach wzdłuż dłuższego boku, suma = 1
  final List<double> profile;

  Map<String, Object> toJson() => {
        'w': width,
        'h': height,
        'sharp': _round(sharpness),
        'lum': _round(brightness),
        'dark': _round(dark),
        'bright': _round(bright),
        'color': _round(colorfulness),
        'hash': hash,
        'profile': [for (final p in profile) _round(p)],
      };

  factory QualityMetrics.fromJson(Map<String, dynamic> j) => QualityMetrics(
        width: j['w'] as int,
        height: j['h'] as int,
        sharpness: (j['sharp'] as num).toDouble(),
        brightness: (j['lum'] as num).toDouble(),
        dark: (j['dark'] as num).toDouble(),
        bright: (j['bright'] as num).toDouble(),
        colorfulness: (j['color'] as num).toDouble(),
        hash: j['hash'] as String,
        profile: [for (final p in j['profile'] as List) (p as num).toDouble()],
      );
}

double _round(double v) => (v * 1000).roundToDouble() / 1000;

/// Funkcja najwyższego poziomu dla `compute`.
QualityMetrics measureQuality(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) throw const FormatException('Nie udało się odczytać miniatury');
  return measureImage(img.bakeOrientation(decoded));
}

QualityMetrics measureImage(img.Image image) {
  final scale = _workSize / math.max(image.width, image.height);
  final small = scale < 1
      ? img.copyResize(image,
          width: (image.width * scale).round(), height: (image.height * scale).round(), interpolation: img.Interpolation.average)
      : image;
  final w = small.width, h = small.height;
  final gray = Float64List(w * h);
  final sat = Float64List(w * h);
  var sum = 0.0, dark = 0, bright = 0;
  var rgSum = 0.0, ybSum = 0.0, rgSq = 0.0, ybSq = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      gray[y * w + x] = l;
      sum += l;
      if (l < 16) dark++;
      if (l > 240) bright++;
      final rg = r - g, yb = 0.5 * (r + g) - b;
      rgSum += rg;
      ybSum += yb;
      rgSq += rg * rg;
      ybSq += yb * yb;
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      sat[y * w + x] = mx == 0 ? 0 : (mx - mn) / mx;
    }
  }
  final n = (w * h).toDouble();

  // Laplasjan 4-sąsiedzki i energia krawędzi do profilu
  var lapSum = 0.0, lapSq = 0.0, lapN = 0;
  final energy = Float64List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final v = gray[i - 1] + gray[i + 1] + gray[i - w] + gray[i + w] - 4 * gray[i];
      lapSum += v;
      lapSq += v * v;
      lapN++;
      energy[i] = v.abs() / 255 + 0.5 * sat[i];
    }
  }
  final lapMean = lapN == 0 ? 0.0 : lapSum / lapN;
  final sharpness = lapN == 0 ? 0.0 : lapSq / lapN - lapMean * lapMean;

  final rgMean = rgSum / n, ybMean = ybSum / n;
  final rgStd = math.sqrt(math.max(0, rgSq / n - rgMean * rgMean));
  final ybStd = math.sqrt(math.max(0, ybSq / n - ybMean * ybMean));
  final colorfulness = math.sqrt(rgStd * rgStd + ybStd * ybStd) +
      0.3 * math.sqrt(rgMean * rgMean + ybMean * ybMean);

  return QualityMetrics(
    width: image.width,
    height: image.height,
    sharpness: sharpness,
    brightness: sum / n / 255,
    dark: dark / n,
    bright: bright / n,
    colorfulness: colorfulness,
    hash: _dHash(small),
    profile: _profile(energy, w, h),
  );
}

String _dHash(img.Image image) {
  final tiny = img.copyResize(image, width: 9, height: 8, interpolation: img.Interpolation.average);
  var bits = BigInt.zero;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final a = tiny.getPixel(x, y).luminance, b = tiny.getPixel(x + 1, y).luminance;
      bits = (bits << 1) | (a < b ? BigInt.one : BigInt.zero);
    }
  }
  return bits.toRadixString(16).padLeft(16, '0');
}

List<double> _profile(Float64List energy, int w, int h) {
  final horizontal = w >= h;
  final length = horizontal ? w : h;
  final bins = List<double>.filled(profileBins, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final pos = horizontal ? x : y;
      bins[math.min(profileBins - 1, pos * profileBins ~/ length)] += energy[y * w + x];
    }
  }
  final total = bins.fold<double>(0, (a, b) => a + b);
  return total == 0 ? List<double>.filled(profileBins, 1 / profileBins) : [for (final b in bins) b / total];
}

/// Liczba różnych bitów dwóch odcisków dHash
int hammingDistance(String a, String b) {
  var x = BigInt.parse(a, radix: 16) ^ BigInt.parse(b, radix: 16);
  var count = 0;
  while (x > BigInt.zero) {
    if (x & BigInt.one == BigInt.one) count++;
    x = x >> 1;
  }
  return count;
}
