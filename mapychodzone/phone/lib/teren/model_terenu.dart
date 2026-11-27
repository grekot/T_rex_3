import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pmtiles.dart';

/// Model terenu regionu z pliku `<region>-teren.pmtiles` (PNG w kodowaniu terrarium,
/// narzedzia/teren.mjs): wysokości w siatce pikseli globalnych na zoomie [zoom]
/// (256 px na kafelek, ok. 25 m na piksel w polskich górach).
class ModelTerenu {
  ModelTerenu(this._pm);

  static const zoom = 12;
  static const rozmiar = 256;
  static const swiatPx = (1 << zoom) * rozmiar;

  final PMTiles _pm;
  final Map<int, Float32List?> _kafle = {};

  /// Wysokości kafelka (256×256, wierszami) albo null poza danymi.
  Future<Float32List?> kafel(int x, int y) async {
    final klucz = x * 100000 + y;
    if (_kafle.containsKey(klucz)) return _kafle[klucz];
    final dane = await _pm.kafelek(zoom, x, y);
    final w = dane == null ? null : wysokosciZPng(dane);
    _kafle[klucz] = w;
    return w;
  }

  /// Siatka wysokości dla pikseli globalnych [px0, px0 + w) × [py0, py0 + h); NaN poza danymi.
  Future<Float32List> siatka(int px0, int py0, int w, int h) async {
    final wynik = Float32List(w * h)..fillRange(0, w * h, double.nan);
    for (var ty = py0 ~/ rozmiar; ty <= (py0 + h - 1) ~/ rozmiar; ty++) {
      for (var tx = px0 ~/ rozmiar; tx <= (px0 + w - 1) ~/ rozmiar; tx++) {
        final k = await kafel(tx, ty);
        if (k == null) continue;
        final x0 = math.max(px0, tx * rozmiar), x1 = math.min(px0 + w, (tx + 1) * rozmiar);
        final y0 = math.max(py0, ty * rozmiar), y1 = math.min(py0 + h, (ty + 1) * rozmiar);
        for (var y = y0; y < y1; y++) {
          final zrodlo = (y - ty * rozmiar) * rozmiar - tx * rozmiar;
          final cel = (y - py0) * w - px0;
          for (var x = x0; x < x1; x++) {
            wynik[cel + x] = k[zrodlo + x];
          }
        }
      }
    }
    return wynik;
  }
}

/// PNG terrarium → wysokości (m): R·256 + G + B/256 − 32768.
Float32List wysokosciZPng(Uint8List png) {
  final obraz = img.decodePng(png);
  if (obraz == null) throw const FormatException('Uszkodzony kafelek terenu (PNG)');
  final w = obraz.width, h = obraz.height;
  final rgb = obraz.getBytes(order: img.ChannelOrder.rgb);
  final wynik = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    wynik[i] = rgb[i * 3] * 256 + rgb[i * 3 + 1] + rgb[i * 3 + 2] / 256 - 32768;
  }
  return wynik;
}

/// Piksel globalny (ułamkowy) na zoomie [ModelTerenu.zoom] ↔ długość i szerokość geograficzna.
double lonNaPx(double lon) => (lon + 180) / 360 * ModelTerenu.swiatPx;
double latNaPx(double lat) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * ModelTerenu.swiatPx;
}

double pxNaLon(double px) => px / ModelTerenu.swiatPx * 360 - 180;
double pxNaLat(double py) =>
    math.atan(_sinh(math.pi * (1 - 2 * py / ModelTerenu.swiatPx))) * 180 / math.pi;
double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// Metry na piksel siatki na danej szerokości.
double metryNaPx(double lat) => 40075016.686 * math.cos(lat * math.pi / 180) / ModelTerenu.swiatPx;
