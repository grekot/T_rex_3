// Przygotowanie zdjęcia dla zegarka: kwadrat ze środka kadru, 480×480, czarne narożniki
// (okrągły ekran i tak ich nie pokaże, a jednolity kolor lepiej się kompresuje), PNG.
// Zegarek (image.convert w aplikacji Zepp) przyjmuje tylko PNG i nie zmienia rozmiaru.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int watchSize = 480;

/// Funkcja najwyższego poziomu, żeby dało się ją wywołać przez `compute` w osobnym wątku.
Uint8List preparePng(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    throw const FormatException('Nie udało się odczytać zdjęcia');
  }
  var square = img.copyResizeCropSquare(
    img.bakeOrientation(decoded),
    size: watchSize,
    interpolation: img.Interpolation.average,
  );
  if (square.numChannels != 3) square = square.convert(numChannels: 3);
  blackOutsideCircle(square);
  return img.encodePng(square, level: 6);
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
