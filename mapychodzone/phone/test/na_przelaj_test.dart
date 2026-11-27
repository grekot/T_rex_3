import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapychodzone/teren/model_terenu.dart';
import 'package:mapychodzone/teren/pmtiles.dart';
import 'package:mapychodzone/trasa/na_przelaj.dart';
import 'package:mapychodzone/trasa/trasa.dart';

/// Fragment terenu spod Turbacza (z12, 4 kafelki) wycięty z wyspowy-gorce-teren.pmtiles.
PMTiles _turbacz() {
  final plik = File('test/dane/teren_turbacz.pmtiles').readAsBytesSync();
  return PMTiles((od, dl) async => Uint8List.sublistView(plik, od, od + dl));
}

/// Płaska siatka w×h (25 m) z opcjonalnym zboczem i przeszkodami.
SiatkaKosztow _siatka(int w, int h, {double Function(int x, int y)? wysokosc, Set<int>? zakaz}) {
  final surowe = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      surowe[y * w + x] = wysokosc?.call(x, y) ?? 500;
    }
  }
  final rodzaj = Uint8List(w * h);
  for (final i in zakaz ?? const <int>{}) {
    rodzaj[i] = 3;
  }
  return siatkaKosztow(
      px0: 0, py0: 0, w: w, h: h, mpp: 25, surowe: surowe, rodzaj: rodzaj, ustawienia: const UstawieniaPrzelaju());
}

void main() {
  test('PMTiles: id kafelków na krzywej Hilberta jak w specyfikacji', () {
    expect(idKafelka(0, 0, 0), 0);
    expect([idKafelka(1, 0, 0), idKafelka(1, 0, 1), idKafelka(1, 1, 1), idKafelka(1, 1, 0)], [1, 2, 3, 4]);
    expect(idKafelka(2, 0, 0), 5);
  });

  test('model terenu z PMTiles: wysokość Turbacza ok. 1300 m, brak danych poza fragmentem', () async {
    final model = ModelTerenu(_turbacz());
    expect(await _turbacz().maxZoom, 12);
    // szczyt Turbacza 1310 m (model 25 m, wierzchołek wygładzony)
    final x = lonNaPx(20.1109).floor(), y = latNaPx(49.5432).floor();
    final s = await model.siatka(x - 2, y - 2, 5, 5);
    final max = s.reduce(math.max);
    expect(max, inInclusiveRange(1280, 1320));
    expect(await model.kafel(0, 0), isNull);
  });

  test('ściana (urwisko) wymusza objazd, a prosta droga to jeden odcinek', () {
    const w = 60, h = 40;
    // pionowa ściana x = 30 od y = 5 do y = 34: trzeba ją obejść górą albo dołem
    final s = _siatka(w, h, zakaz: {for (var y = 5; y < 35; y++) y * w + 30});
    final start = 20 * w + 10, cel = 20 * w + 50;
    final droga = szukajDrogi(s, start, cel)!;
    expect(droga.first, start);
    expect(droga.last, cel);
    expect(droga.any((i) => i % w == 30 && i ~/ w >= 5 && i ~/ w < 35), isFalse);
    final uproszczona = uproscDroge(s, droga);
    expect(uproszczona.length, inInclusiveRange(3, 6));
    // bez ściany: prosto, bez załamań
    final prosto = uproscDroge(_siatka(w, h), szukajDrogi(_siatka(w, h), start, cel)!);
    expect(prosto, [start, cel]);
  });

  test('stok ponad 35° jest zakazany, łagodniejszy tylko droższy', () {
    expect(mnoznikNachylenia(10, const UstawieniaPrzelaju()), 1);
    expect(mnoznikNachylenia(30, const UstawieniaPrzelaju()), greaterThan(2));
    expect(mnoznikNachylenia(36, const UstawieniaPrzelaju()), double.infinity);
    expect(mnoznikNachylenia(26, const UstawieniaPrzelaju.lagodnie()), double.infinity);
    const w = 60, h = 40;
    // grzbiet w środku: pas x 26–34 ze ścianką 45° (podniesiony o 25 m na komórkę), poza nim płasko
    double wys(int x, int y) => y >= 10 && y < 30 ? 500.0 + 25 * (x - 26).clamp(0, 8) * (x <= 30 ? 1 : 0) : 500;
    final s = _siatka(w, h, wysokosc: wys);
    final droga = szukajDrogi(s, 20 * w + 10, 20 * w + 50)!;
    // nie przechodzi przez stromą ściankę w środku pasa
    expect(droga.every((i) => s.kat[i] < 35), isTrue);
  });

  test('azymut: północ 0°, wschód ok. 90°, odcinek w drugą stronę +180°', () {
    expect(azymut(20, 49, 20, 49.1), closeTo(0, 0.01));
    expect(azymut(20, 49, 20.1, 49), closeTo(90, 0.1));
    expect(const OdcinekAzymutu(350, 100).odwrotny.azymut, 170);
    expect(opisAzymutu(359.6), '0°');
  });

  test('trasa na przełaj na prawdziwym terenie pod Turbaczem', () async {
    final trasa = await trasaNaPrzelaj(
      [(20.100, 49.540), (20.118, 49.548)],
      model: ModelTerenu(_turbacz()),
      przeszkody: Przeszkody.pusty,
    );
    final prosta = odlegloscM(49.540, 20.100, 49.548, 20.118);
    expect(trasa.dlugosc, greaterThanOrEqualTo(prosta - 1));
    expect(trasa.dlugosc, lessThan(prosta * 1.4));
    expect(trasa.azymuty, isNotEmpty);
    expect(trasa.azymuty.fold<double>(0, (a, o) => a + o.dlugosc), closeTo(trasa.dlugosc, 5));
    expect(trasa.punkty.first.wysokosc, isNotNull);
    expect(trasa.zPowrotem().azymuty.length, trasa.azymuty.length * 2);
  });

  test('przeszkody z GeoJSON i park narodowy', () {
    final p = Przeszkody.zGeojson('{"type":"FeatureCollection","features":['
        '{"type":"Feature","properties":{"t":"urwisko"},"geometry":{"type":"LineString","coordinates":[[20,49],[20.01,49]]}},'
        '{"type":"Feature","properties":{"t":"park","n":"TPN"},"geometry":{"type":"Polygon","coordinates":[[[19,48],[21,48],[21,50],[19,48]]]}}]}');
    expect(p.linie.length, 1);
    expect(p.parki.single.$1, 'TPN');
    expect(wWielokacie(20.5, 48.5, p.parki.single.$2), isTrue);
    expect(wWielokacie(19.1, 49.9, p.parki.single.$2), isFalse);
  });
}
