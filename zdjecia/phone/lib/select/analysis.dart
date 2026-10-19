// Wynik analizy jednego zdjęcia - zapamiętywany, żeby przy kolejnych odświeżeniach
// analizować tylko nowe zdjęcia.
import 'quality.dart';

/// Zwiększ, gdy zmieni się sposób analizy - stare wyniki zostaną policzone od nowa.
const int analysisVersion = 1;

class FaceBox {
  const FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.smile,
    this.eyesOpen,
  });

  /// Położenie w ułamkach szerokości / wysokości zdjęcia (0..1)
  final double left;
  final double top;
  final double width;
  final double height;

  /// Prawdopodobieństwa z ML Kit (null = nieznane)
  final double? smile;
  final double? eyesOpen;

  double get area => width * height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  Map<String, Object?> toJson() => {
        'l': _r(left),
        't': _r(top),
        'w': _r(width),
        'h': _r(height),
        if (smile != null) 's': _r(smile!),
        if (eyesOpen != null) 'e': _r(eyesOpen!),
      };

  factory FaceBox.fromJson(Map<String, dynamic> j) => FaceBox(
        left: (j['l'] as num).toDouble(),
        top: (j['t'] as num).toDouble(),
        width: (j['w'] as num).toDouble(),
        height: (j['h'] as num).toDouble(),
        smile: (j['s'] as num?)?.toDouble(),
        eyesOpen: (j['e'] as num?)?.toDouble(),
      );
}

class LabelHit {
  const LabelHit(this.name, this.confidence);

  final String name;
  final double confidence;

  List<Object> toJson() => [name, _r(confidence)];

  factory LabelHit.fromJson(List<dynamic> j) => LabelHit(j[0] as String, (j[1] as num).toDouble());
}

class PhotoAnalysis {
  const PhotoAnalysis({
    required this.id,
    required this.assetId,
    required this.taken,
    required this.favorite,
    required this.quality,
    this.faces = const [],
    this.labels = const [],
    this.textChars = -1,
  });

  /// Identyfikator dla zegarka (zmienia się po edycji zdjęcia)
  final String id;
  final String assetId;
  final DateTime taken;
  final bool favorite;
  final QualityMetrics quality;
  final List<FaceBox> faces;
  final List<LabelHit> labels;

  /// Liczba liter i cyfr rozpoznanych na zdjęciu (-1 = nie sprawdzano, bo były twarze)
  final int textChars;

  double get aspect => quality.width / quality.height;

  Map<String, Object> toJson() => {
        'v': analysisVersion,
        'id': id,
        'asset': assetId,
        'taken': taken.millisecondsSinceEpoch,
        'fav': favorite,
        'q': quality.toJson(),
        'faces': [for (final f in faces) f.toJson()],
        'labels': [for (final l in labels) l.toJson()],
        'text': textChars,
      };

  static PhotoAnalysis? fromJson(Map<String, dynamic> j) {
    if (j['v'] != analysisVersion) return null;
    return PhotoAnalysis(
      id: j['id'] as String,
      assetId: j['asset'] as String,
      taken: DateTime.fromMillisecondsSinceEpoch(j['taken'] as int),
      favorite: j['fav'] as bool? ?? false,
      quality: QualityMetrics.fromJson((j['q'] as Map).cast<String, dynamic>()),
      faces: [for (final f in j['faces'] as List) FaceBox.fromJson((f as Map).cast<String, dynamic>())],
      labels: [for (final l in j['labels'] as List) LabelHit.fromJson(l as List)],
      textChars: j['text'] as int? ?? -1,
    );
  }
}

double _r(double v) => (v * 1000).roundToDouble() / 1000;
