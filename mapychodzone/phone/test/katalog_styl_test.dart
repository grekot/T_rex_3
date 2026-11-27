import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapychodzone/dane/katalog.dart';
import 'package:mapychodzone/dane/pobieranie.dart';
import 'package:mapychodzone/mapa/styl.dart';

void main() {
  group('katalog paczek', () {
    final k = Katalog.zJson(
      jsonDecode(File('test/dane/katalog.json').readAsStringSync()) as Map<String, dynamic>,
    );

    test('region testowy i jego pliki', () {
      final r = k.region('wyspowy-gorce')!;
      expect(r.nazwa, 'Beskid Makowski, Wyspowy i Gorce');
      expect(r.rd5, ['E15_N45', 'E20_N45']);
      expect(r.mapa.plik, 'wyspowy-gorce.pmtiles');
      expect(r.mapa.sha256, hasLength(64));
      expect(r.zawiera(20.11, 49.54), isTrue); // Turbacz
      expect(r.zawiera(19.95, 49.23), isFalse); // Zakopane
    });

    test('adresy plików z konkretnego wydania', () {
      expect(k.wydanie, 'dane-2026-11-26');
      expect(
        k.adres('wyspowy-gorce.pmtiles'),
        'https://github.com/grekot/mapychodzone-dane/releases/download/dane-2026-11-26/wyspowy-gorce.pmtiles',
      );
      expect(k.adresRd5('E20_N45'), 'https://brouter.de/brouter/segments4/E20_N45.rd5');
    });

    test('nieznana wersja katalogu', () {
      expect(() => Katalog.zJson({'wersja': 2}), throwsFormatException);
    });
  });

  group('styl', () {
    const szablon = '{"glyphs":"{GLIFY}/{fontstack}/{range}.pbf","sprite":"{SPRITE}/light",'
        '"sources":{"protomaps":{"url":"pmtiles://{PACZKA}"},"szlaki":{"data":"{SZLAKI}"}}}';

    test('podmienia znaczniki na file:// i zostawia {fontstack}/{range}', () {
      final s = przygotujStyl(
        szablon,
        paczka: '/data/user/0/pl.grekot.mapychodzone/files/mapy/r.pmtiles',
        szlaki: '/d/szlaki.geojson',
        glify: '/d/glify',
        sprite: '/d/sprite',
      );
      final j = jsonDecode(s) as Map<String, dynamic>;
      expect(j['glyphs'], 'file:///d/glify/{fontstack}/{range}.pbf');
      expect(j['sprite'], 'file:///d/sprite/light');
      expect(j['sources']['protomaps']['url'],
          'pmtiles://file:///data/user/0/pl.grekot.mapychodzone/files/mapy/r.pmtiles');
      expect(j['sources']['szlaki']['data'], 'file:///d/szlaki.geojson');
    });

    test('odrzuca ścieżki względne', () {
      expect(
        () => przygotujStyl(szablon, paczka: 'r.pmtiles', szlaki: '/s', glify: '/g', sprite: '/p'),
        throwsArgumentError,
      );
    });
  });

  test('megabajty', () {
    expect(megabajty(69783648), '67 MB');
    expect(megabajty(7575725), '7,2 MB');
  });
}
