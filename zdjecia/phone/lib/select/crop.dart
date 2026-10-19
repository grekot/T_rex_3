// Kadr pod okrągły ekran: kwadrat, w którym bohaterowie zdjęcia mieszczą się w KOLE (narożniki kwadratu
// zegarek obcina). Z twarzami - twarze z ramionami w środku koła, bez twarzy - najciekawszy pas zdjęcia.
import 'dart:math' as math;

import 'analysis.dart';
import 'quality.dart';
import 'scoring.dart';

class CropBox {
  const CropBox({required this.cx, required this.cy, required this.side});

  /// Środek kadru w ułamkach szerokości / wysokości zdjęcia
  final double cx;
  final double cy;

  /// Bok kwadratu jako ułamek krótszego boku zdjęcia (1 = cały krótszy bok)
  final double side;

  static const full = CropBox(cx: 0.5, cy: 0.5, side: 1);

  Map<String, double> toJson() => {'cx': _r(cx), 'cy': _r(cy), 's': _r(side)};

  factory CropBox.fromJson(Map<String, dynamic> j) => CropBox(
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        side: (j['s'] as num).toDouble(),
      );

  /// Krótki klucz do nazwy pliku z gotowym PNG
  String get key => '${(cx * 1000).round()}_${(cy * 1000).round()}_${(side * 1000).round()}';

  @override
  bool operator ==(Object other) => other is CropBox && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Najmocniejsze przybliżenie (ułamek krótszego boku) - mocniej robi się rozmyte i ciasne
const double minSide = 0.45;

/// Ułamek promienia koła, w którym mają się zmieścić twarze
const double circleMargin = 0.9;

CropBox autoCrop(PhotoAnalysis a) {
  final faces = mainFaces(a.faces);
  return faces.isEmpty ? _bestBand(a.quality, a.aspect) : _aroundFaces(faces, a.aspect);
}

CropBox _aroundFaces(List<FaceBox> faces, double aspect) {
  // Liczymy w pikselach zdjęcia o krótszym boku = 1
  final w = math.max(aspect, 1.0), h = math.max(1 / aspect, 1.0);
  var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
  for (final f in faces) {
    final fw = f.width * w, fh = f.height * h;
    left = math.min(left, f.left * w - 0.3 * fw);
    right = math.max(right, (f.left + f.width) * w + 0.3 * fw);
    top = math.min(top, f.top * h - 0.35 * fh);
    bottom = math.max(bottom, (f.top + f.height) * h + 0.8 * fh); // ramiona
  }
  final bw = right - left, bh = bottom - top;
  // Prostokąt w kole: połowa przekątnej <= promień * margines
  final side = (math.sqrt(bw * bw + bh * bh) / circleMargin).clamp(minSide, 1.0);
  return _clamped((left + right) / 2, (top + bottom) / 2, side, w, h);
}

CropBox _bestBand(QualityMetrics q, double aspect) {
  final w = math.max(aspect, 1.0), h = math.max(1 / aspect, 1.0);
  final length = math.max(w, h);
  if (length <= 1.0001) return CropBox.full;
  // Okno kwadratu wzdłuż dłuższego boku, w pasach profilu; lekka premia za środek
  final bins = q.profile.length;
  final window = math.max(1, (bins / length).round());
  var bestStart = (bins - window) / 2, bestValue = -double.infinity;
  for (var start = 0; start <= bins - window; start++) {
    var value = 0.0;
    for (var i = start; i < start + window; i++) {
      value += q.profile[i];
    }
    final center = (start + window / 2) / bins;
    value -= 0.15 * (center - 0.5).abs();
    if (value > bestValue) {
      bestValue = value;
      bestStart = start.toDouble();
    }
  }
  final center = (bestStart + window / 2) / bins * length;
  return w >= h ? _clamped(center, h / 2, 1, w, h) : _clamped(w / 2, center, 1, w, h);
}

CropBox _clamped(double cxPx, double cyPx, double side, double w, double h) {
  final half = side / 2;
  final cx = cxPx.clamp(half, w - half);
  final cy = cyPx.clamp(half, h - half);
  return CropBox(cx: cx / w, cy: cy / h, side: side);
}

/// Prostokąt kadru w pikselach konkretnego obrazu (np. miniatury 1600 px): x, y, bok.
/// Pilnuje, żeby kadr nie był mniejszy niż [outputSize], jeśli obraz na to pozwala.
({int x, int y, int size}) cropRect(CropBox box, int width, int height, {int outputSize = 480}) {
  final shortSide = math.min(width, height);
  var size = (box.side * shortSide).round();
  if (size < outputSize) size = math.min(outputSize, shortSide);
  size = size.clamp(1, shortSide);
  final x = (box.cx * width - size / 2).round().clamp(0, width - size);
  final y = (box.cy * height - size / 2).round().clamp(0, height - size);
  return (x: x, y: y, size: size);
}

double _r(double v) => (v * 1000).roundToDouble() / 1000;
