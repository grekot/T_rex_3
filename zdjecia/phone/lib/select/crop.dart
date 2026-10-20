// Kadr pod okrągły ekran: kwadrat, w którym bohaterowie zdjęcia mieszczą się w KOLE (narożniki kwadratu
// zegarek obcina). Z twarzami - twarze z ramionami w środku koła; bez twarzy - główny motyw wskazany
// przez AI, a bez niego najciekawszy pas zdjęcia.
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

/// Najmocniejsze przybliżenie przy fragmencie wybranym przez AI (detal może być ciaśniej)
const double minFocusSide = 0.4;

enum CropSource { manual, ai, faces, subject, band }

const cropSourceNames = {
  CropSource.manual: 'ręczny',
  CropSource.ai: 'AI – najciekawszy fragment',
  CropSource.faces: 'twarze',
  CropSource.subject: 'główny motyw (AI)',
  CropSource.band: 'najciekawszy pas (telefon)',
};

/// Kadr automatyczny i skąd się wziął. Kolejność: fragment od AI ([focus]) - o ile nie ucina twarzy
/// (wtedy obejmuje i fragment, i twarze), twarze, główny motyw od AI ([subject]), najciekawszy pas.
/// Prostokąty w ułamkach zdjęcia: left, top, width, height.
({CropBox box, CropSource source}) autoCropWithSource(PhotoAnalysis a, {List<double>? subject, List<double>? focus}) {
  final faces = mainFaces(a.faces);
  final faceBoxes = [for (final f in faces) _faceWithShoulders(f)];
  if (focus != null && focus.length == 4) {
    final box = _filling(focus, a.aspect);
    if (faceBoxes.every((f) => _insideCircle(f, box, a.aspect))) return (box: box, source: CropSource.ai);
    // Fragment ucina twarz: kadr obejmie jedno i drugie, o ile zmieści się w kwadracie
    if (_requiredSide([focus, ...faceBoxes], a.aspect) <= 1.0) {
      return (box: _aroundBoxes([focus, ...faceBoxes], a.aspect, side: 0, above: 0, below: 0), source: CropSource.ai);
    }
    // Nie zmieści się: wyraźna twarz wygrywa, malutka w tle nie przeszkadza wyborowi AI
    if (!faces.any((f) => f.area >= majorFaceArea)) return (box: box, source: CropSource.ai);
  }
  if (faces.isNotEmpty) {
    return (box: _aroundBoxes(faceBoxes, a.aspect, side: 0, above: 0, below: 0), source: CropSource.faces);
  }
  if (subject != null && subject.length == 4) {
    return (
      box: _aroundBoxes([subject], a.aspect, side: 0.06, above: 0.06, below: 0.06),
      source: CropSource.subject,
    );
  }
  return (box: _bestBand(a.quality, a.aspect), source: CropSource.band);
}

CropBox autoCrop(PhotoAnalysis a, {List<double>? subject, List<double>? focus}) =>
    autoCropWithSource(a, subject: subject, focus: focus).box;

/// Twarz od tej powierzchni (ułamek zdjęcia) jest ważniejsza niż fragment od AI, gdy nie da się objąć obu
const double majorFaceArea = 0.01;

/// Bok kwadratu (ułamek krótszego boku), w którego kole zmieściłyby się prostokąty - bez obcinania do 1
double _requiredSide(List<List<double>> boxes, double aspect) {
  final w = math.max(aspect, 1.0), h = math.max(1 / aspect, 1.0);
  var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
  for (final b in boxes) {
    left = math.min(left, b[0] * w);
    right = math.max(right, (b[0] + b[2]) * w);
    top = math.min(top, b[1] * h);
    bottom = math.max(bottom, (b[1] + b[3]) * h);
  }
  final bw = right - left, bh = bottom - top;
  return math.sqrt(bw * bw + bh * bh) / circleMargin;
}

/// Twarz z zapasem na włosy i ramiona (w ułamkach zdjęcia)
List<double> _faceWithShoulders(FaceBox f) {
  final left = f.left - 0.3 * f.width, right = f.left + f.width * 1.3;
  final top = f.top - 0.35 * f.height, bottom = f.top + f.height * 1.8;
  return [left, top, right - left, bottom - top];
}

/// Kwadrat wypełniony fragmentem: bok = dłuższy bok fragmentu z małym zapasem (fragment AI wybiera
/// już pod koło, więc nie oddalamy aż do zmieszczenia całych narożników w kole)
CropBox _filling(List<double> b, double aspect) {
  final w = math.max(aspect, 1.0), h = math.max(1 / aspect, 1.0);
  final bw = b[2] * w, bh = b[3] * h;
  final size = (math.max(bw, bh) * 1.08).clamp(minFocusSide, 1.0);
  return _clamped((b[0] + b[2] / 2) * w, (b[1] + b[3] / 2) * h, size, w, h);
}

/// Czy narożniki prostokąta mieszczą się w kole kadru
bool _insideCircle(List<double> b, CropBox box, double aspect) {
  final w = math.max(aspect, 1.0), h = math.max(1 / aspect, 1.0);
  final cx = box.cx * w, cy = box.cy * h, r = box.side / 2;
  for (final x in [b[0], b[0] + b[2]]) {
    for (final y in [b[1], b[1] + b[3]]) {
      final dx = x * w - cx, dy = y * h - cy;
      if (dx * dx + dy * dy > r * r * 1.0001) return false;
    }
  }
  return true;
}

/// Kwadrat, w którego kole mieszczą się prostokąty (w ułamkach zdjęcia) z zapasem
/// [side] / [above] / [below] (ułamki szerokości / wysokości prostokąta)
CropBox _aroundBoxes(List<List<double>> boxes, double aspect,
    {required double side, required double above, required double below}) {
  // Liczymy w pikselach zdjęcia o krótszym boku = 1
  final w = math.max(aspect, 1.0), h = math.max(1 / aspect, 1.0);
  var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
  for (final b in boxes) {
    final bw = b[2] * w, bh = b[3] * h;
    left = math.min(left, b[0] * w - side * bw);
    right = math.max(right, (b[0] + b[2]) * w + side * bw);
    top = math.min(top, b[1] * h - above * bh);
    bottom = math.max(bottom, (b[1] + b[3]) * h + below * bh);
  }
  final bw = right - left, bh = bottom - top;
  // Prostokąt w kole: połowa przekątnej <= promień * margines
  final size = (math.sqrt(bw * bw + bh * bh) / circleMargin).clamp(minSide, 1.0);
  return _clamped((left + right) / 2, (top + bottom) / 2, size, w, h);
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
