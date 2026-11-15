// Kadr pod okrągły ekran: kwadrat, w którym bohaterowie zdjęcia mieszczą się w KOLE (narożniki kwadratu
// zegarek obcina). Z twarzami - twarze z ramionami w środku koła; bez twarzy - główny motyw wskazany
// przez AI, a bez niego najciekawszy pas zdjęcia. Na końcu kadr prostokątny (dowolne proporcje) dla zegarów
// z poziomymi ekranami - ta sama kolejność, ale prostokąt zamiast koła.
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

// --- Kadr prostokątny (zegary HomeAutomation z poziomymi ekranami, np. 320×240) ---

/// Wersja liczenia kadru prostokątnego - zmiana daje nowe pliki JPEG w pamięci podręcznej
const int rectCropVersion = 1;

/// Zapas wokół fragmentu od AI (jak w kadrze okrągłym: dłuższy bok fragmentu +8%)
const double rectFocusPad = 1.08;

/// Zapas wokół twarzy z ramionami i wokół głównego motywu (6% z każdej strony)
const double rectPad = 1.12;

/// Kadr prostokątny w ułamkach zdjęcia: środek oraz szerokość / wysokość (ułamek szerokości / wysokości zdjęcia)
class RectBox {
  const RectBox({required this.cx, required this.cy, required this.w, required this.h});

  final double cx;
  final double cy;
  final double w;
  final double h;

  static const full = RectBox(cx: 0.5, cy: 0.5, w: 1, h: 1);

  double get left => cx - w / 2;
  double get top => cy - h / 2;

  @override
  String toString() => 'RectBox(cx: $cx, cy: $cy, w: $w, h: $h)';
}

/// Wszystko, czego potrzeba do kadru o dowolnych proporcjach - zapisywane przy publikowaniu puli
/// (published.json), żeby usługa w tle mogła kadrować bez analizy i bez ocen.
class CropFrame {
  const CropFrame({
    required this.aspect,
    this.faces = const [],
    this.profile = const [],
    this.subject,
    this.focus,
    this.manual,
  });

  factory CropFrame.of(PhotoAnalysis a, {List<double>? subject, List<double>? focus, CropBox? manual}) => CropFrame(
        aspect: a.aspect,
        faces: mainFaces(a.faces),
        profile: a.quality.profile,
        subject: subject,
        focus: focus,
        manual: manual,
      );

  /// Szerokość / wysokość zdjęcia (już obróconego)
  final double aspect;

  /// Wyraźne twarze (ułamki zdjęcia)
  final List<FaceBox> faces;

  /// Ciekawość w pasach wzdłuż dłuższego boku (jak [QualityMetrics.profile])
  final List<double> profile;

  /// Główny motyw i najciekawszy fragment od AI: left, top, width, height (ułamki zdjęcia)
  final List<double>? subject;
  final List<double>? focus;

  /// Ręczny kadr kwadratowy użytkownika
  final CropBox? manual;

  Map<String, Object> toJson() => {
        'a': (aspect * 10000).roundToDouble() / 10000,
        if (faces.isNotEmpty) 'faces': [for (final f in faces) f.toJson()],
        if (profile.isNotEmpty) 'p': [for (final v in profile) _r(v)],
        if (subject != null) 'subject': [for (final v in subject!) _r(v)],
        if (focus != null) 'focus': [for (final v in focus!) _r(v)],
        if (manual != null) 'manual': manual!.toJson(),
      };

  factory CropFrame.fromJson(Map<String, dynamic> j) {
    List<double>? box(Object? v) => v is List && v.length == 4 ? [for (final x in v) (x as num).toDouble()] : null;
    return CropFrame(
      aspect: (j['a'] as num).toDouble(),
      faces: [for (final f in (j['faces'] as List? ?? const [])) FaceBox.fromJson((f as Map).cast<String, dynamic>())],
      profile: [for (final v in (j['p'] as List? ?? const [])) (v as num).toDouble()],
      subject: box(j['subject']),
      focus: box(j['focus']),
      manual: j['manual'] is Map ? CropBox.fromJson((j['manual'] as Map).cast<String, dynamic>()) : null,
    );
  }
}

/// Kadr o proporcjach [ratio] (szerokość / wysokość) wybrany tą samą kolejnością co kadr okrągły:
/// ręczny (ten sam środek, kwadrat rozszerzony do proporcji) → fragment od AI (o ile nie ucina twarzy) →
/// twarze → główny motyw → najciekawszy pas. Bez koła: prostokąt obejmuje sam motyw z małym zapasem.
({RectBox box, CropSource source}) rectCropWithSource(CropFrame f, double ratio) {
  final manual = f.manual;
  if (manual != null) return (box: _rectFromSquare(manual, f.aspect, ratio), source: CropSource.manual);
  final faceBoxes = [for (final face in f.faces) _faceWithShoulders(face)];
  final focus = f.focus;
  if (focus != null && focus.length == 4) {
    final r = _rectAround([focus], f.aspect, ratio, pad: rectFocusPad, minShort: minFocusSide);
    if (faceBoxes.every((b) => _insideRect(b, r.box))) return (box: r.box, source: CropSource.ai);
    // Fragment ucina twarz: kadr obejmie jedno i drugie, o ile zmieści się w zdjęciu
    final both = _rectAround([focus, ...faceBoxes], f.aspect, ratio, pad: 1, minShort: minSide);
    if (both.fits) return (box: both.box, source: CropSource.ai);
    // Nie zmieści się: wyraźna twarz wygrywa, malutka w tle nie przeszkadza wyborowi AI
    if (!f.faces.any((face) => face.area >= majorFaceArea)) return (box: r.box, source: CropSource.ai);
  }
  if (faceBoxes.isNotEmpty) {
    return (box: _rectAround(faceBoxes, f.aspect, ratio, pad: rectPad, minShort: minSide).box, source: CropSource.faces);
  }
  final subject = f.subject;
  if (subject != null && subject.length == 4) {
    return (box: _rectAround([subject], f.aspect, ratio, pad: rectPad, minShort: minSide).box, source: CropSource.subject);
  }
  return (box: _rectBand(f.profile, f.aspect, ratio), source: CropSource.band);
}

RectBox rectCrop(CropFrame f, double ratio) => rectCropWithSource(f, ratio).box;

/// Największy prostokąt o proporcjach [ratio] mieszczący się w zdjęciu (jednostki: krótszy bok = 1)
({double w, double h}) _maxFit(double pw, double ph, double ratio) =>
    ratio >= pw / ph ? (w: pw, h: pw / ratio) : (w: ph * ratio, h: ph);

/// Prostokąt o proporcjach [ratio] obejmujący prostokąty (ułamki zdjęcia) z zapasem [pad], krótszy bok
/// co najmniej [minShort]; środek na środku objętych prostokątów, przesunięty w granice zdjęcia.
/// [fits] = objęte prostokąty (bez zapasu i minimum) mieszczą się w zdjęciu w tych proporcjach.
({RectBox box, bool fits}) _rectAround(List<List<double>> boxes, double aspect, double ratio,
    {required double pad, required double minShort}) {
  final pw = math.max(aspect, 1.0), ph = math.max(1 / aspect, 1.0);
  var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
  for (final b in boxes) {
    left = math.min(left, b[0] * pw);
    right = math.max(right, (b[0] + b[2]) * pw);
    top = math.min(top, b[1] * ph);
    bottom = math.max(bottom, (b[1] + b[3]) * ph);
  }
  final max = _maxFit(pw, ph, ratio);
  final needed = math.max(right - left, (bottom - top) * ratio);
  var w = needed * pad;
  final short = math.min(w, w / ratio);
  if (short < minShort) w *= minShort / short;
  w = math.min(w, max.w);
  return (
    box: _rectClamped((left + right) / 2, (top + bottom) / 2, w, w / ratio, pw, ph),
    fits: needed <= max.w * 1.0001,
  );
}

/// Ręczny kadr kwadratowy jako prostokąt: ten sam środek, kwadrat rozszerzony wzdłuż dłuższego boku
/// prostokąta (cały kwadrat zostaje w kadrze), a gdy się nie mieści - pomniejszony do granic zdjęcia.
RectBox _rectFromSquare(CropBox c, double aspect, double ratio) {
  final pw = math.max(aspect, 1.0), ph = math.max(1 / aspect, 1.0);
  final w = math.min(ratio >= 1 ? c.side * ratio : c.side, _maxFit(pw, ph, ratio).w);
  return _rectClamped(c.cx * pw, c.cy * ph, w, w / ratio, pw, ph);
}

/// Najciekawszy pas: największy prostokąt w proporcjach, przesuwany wzdłuż dłuższego boku zdjęcia
/// (wzdłuż niego liczony jest profil ciekawości), z lekką premią za środek - jak przy kadrze kwadratowym.
RectBox _rectBand(List<double> profile, double aspect, double ratio) {
  final pw = math.max(aspect, 1.0), ph = math.max(1 / aspect, 1.0);
  final max = _maxFit(pw, ph, ratio);
  final length = math.max(pw, ph);
  final extent = pw >= ph ? max.w : max.h;
  var center = length / 2;
  final bins = profile.length;
  if (bins > 0 && extent < length - 1e-4) {
    final window = math.max(1, (bins * extent / length).round());
    var bestStart = (bins - window) / 2, bestValue = -double.infinity;
    for (var start = 0; start <= bins - window; start++) {
      var value = 0.0;
      for (var i = start; i < start + window; i++) {
        value += profile[i];
      }
      value -= 0.15 * ((start + window / 2) / bins - 0.5).abs();
      if (value > bestValue) {
        bestValue = value;
        bestStart = start.toDouble();
      }
    }
    center = (bestStart + window / 2) / bins * length;
  }
  return pw >= ph
      ? _rectClamped(center, ph / 2, max.w, max.h, pw, ph)
      : _rectClamped(pw / 2, center, max.w, max.h, pw, ph);
}

/// Czy prostokąt (ułamki zdjęcia) mieści się w kadrze
bool _insideRect(List<double> b, RectBox r) {
  const eps = 1e-4;
  return b[0] >= r.left - eps &&
      b[1] >= r.top - eps &&
      b[0] + b[2] <= r.left + r.w + eps &&
      b[1] + b[3] <= r.top + r.h + eps;
}

RectBox _rectClamped(double cxPx, double cyPx, double w, double h, double pw, double ph) {
  w = math.min(w, pw);
  h = math.min(h, ph);
  final cx = cxPx.clamp(w / 2, pw - w / 2);
  final cy = cyPx.clamp(h / 2, ph - h / 2);
  return RectBox(cx: cx / pw, cy: cy / ph, w: w / pw, h: h / ph);
}

/// Prostokąt kadru w pikselach konkretnego obrazu: x, y, szerokość, wysokość. Gdy obraz na to pozwala,
/// kadr nie jest mniejszy niż [outWidth] × [outHeight] (wtedy powiększony wokół tego samego środka).
({int x, int y, int w, int h}) rectPixels(RectBox box, int width, int height,
    {required int outWidth, required int outHeight}) {
  var w = box.w * width, h = box.h * height;
  if (w < outWidth || h < outHeight) {
    final want = math.max(outWidth / w, outHeight / h);
    final grow = math.min(want, math.min(width / w, height / h));
    if (grow > 1) {
      w *= grow;
      h *= grow;
    }
  }
  final iw = w.round().clamp(1, width), ih = h.round().clamp(1, height);
  final x = (box.cx * width - iw / 2).round().clamp(0, width - iw);
  final y = (box.cy * height - ih / 2).round().clamp(0, height - ih);
  return (x: x, y: y, w: iw, h: ih);
}
