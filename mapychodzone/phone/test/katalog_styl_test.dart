import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapychodzone/dane/katalog.dart';
import 'package:mapychodzone/dane/magazyn.dart';
import 'package:mapychodzone/dane/pobieranie.dart';
import 'package:mapychodzone/dane/zrodlo.dart';
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
      expect(k.wydanie, 'dane-2026-11-27');
      expect(
        k.adres('wyspowy-gorce.pmtiles'),
        'https://github.com/grekot/mapychodzone-dane/releases/download/dane-2026-11-27/wyspowy-gorce.pmtiles',
      );
      expect(k.adresRd5('E20_N45'), 'https://brouter.de/brouter/segments4/E20_N45.rd5');
    });

    test('nieznana wersja katalogu', () {
      expect(() => Katalog.zJson({'wersja': 2}), throwsFormatException);
    });
  });

  group('styl', () {
    const szablon = '{"glyphs":"{GLIFY}/{fontstack}/{range}.pbf","sprite":"{SPRITE}/light",'
        '"sources":{"protomaps":{"url":"pmtiles://{PACZKA}"},"szlaki":{"data":"{SZLAKI}"},"punkty":{"data":"{PUNKTY}"}}}';

    test('telefon: adresy file:// z magazynu, {fontstack}/{range} zostają', () {
      final m = Magazyn('/data/user/0/pl.grekot.mapychodzone/files');
      final s = przygotujStyl(
        szablon,
        paczka: m.adres('r.pmtiles'),
        szlaki: m.adres('r-szlaki.geojson'),
        punkty: m.adres('r-punkty.geojson'),
        glify: m.adresGlifow,
        sprite: m.adresSprite,
      );
      final j = jsonDecode(s) as Map<String, dynamic>;
      const f = 'file:///data/user/0/pl.grekot.mapychodzone/files';
      expect(j['glyphs'], '$f/zasoby/glify/{fontstack}/{range}.pbf');
      expect(j['sprite'], '$f/zasoby/sprite/light');
      expect(j['sources']['protomaps']['url'], 'pmtiles://$f/mapy/r.pmtiles');
      expect(j['sources']['szlaki']['data'], '$f/mapy/r-szlaki.geojson');
      expect(j['sources']['punkty']['data'], '$f/mapy/r-punkty.geojson');
    });

    test('przeglądarka: adresy https:// względem strony', () {
      final w = ZrodloWww(strona: Uri.parse('https://mapychodzone.web.app/'));
      final s = przygotujStyl(
        szablon,
        paczka: w.adres('r.pmtiles'),
        szlaki: w.adres('r-szlaki.geojson'),
        punkty: w.adres('r-punkty.geojson'),
        glify: w.adresGlifow,
        sprite: w.adresSprite,
      );
      final j = jsonDecode(s) as Map<String, dynamic>;
      expect(j['sources']['protomaps']['url'], 'pmtiles://https://mapychodzone.web.app/dane/r.pmtiles');
      expect(j['glyphs'], 'https://mapychodzone.web.app/assets/assets/mapa/glify/{fontstack}/{range}.pbf');
      expect(j['sprite'], 'https://mapychodzone.web.app/assets/assets/mapa/sprite/light');
      expect(w.pobieranieRegionow, isFalse);
    });

    test('poziomice: adres w źródle albo usunięcie źródła i warstw, gdy region ich nie ma', () {
      const z = '{"sources":{"protomaps":{"url":"pmtiles://{PACZKA}"},"szlaki":{"data":"{SZLAKI}"},'
          '"poziomice":{"type":"vector","url":"pmtiles://{POZIOMICE}"},'
          '"teren":{"type":"raster-dem","url":"pmtiles://{TEREN}"}},'
          '"layers":[{"id":"ziemia","source":"protomaps"},{"id":"poziomice_10","source":"poziomice"},'
          '{"id":"poziomice_opisy","source":"poziomice"},{"id":"cieniowanie","source":"teren"}],'
          '"glyphs":"{GLIFY}","sprite":"{SPRITE}"}';
      String styl(String? poziomice, String? teren) => przygotujStyl(z,
          paczka: 'file:///r.pmtiles', szlaki: 'file:///s', punkty: null, poziomice: poziomice, teren: teren,
          glify: 'file:///g', sprite: 'file:///p');
      final z1 = jsonDecode(styl('file:///r-poziomice.pmtiles', 'file:///r-teren.pmtiles')) as Map<String, dynamic>;
      expect(z1['sources']['poziomice']['url'], 'pmtiles://file:///r-poziomice.pmtiles');
      expect(z1['sources']['teren']['url'], 'pmtiles://file:///r-teren.pmtiles');
      expect((z1['layers'] as List).length, 4);
      final bez = jsonDecode(styl(null, null)) as Map<String, dynamic>;
      expect((bez['sources'] as Map).keys, ['protomaps', 'szlaki']);
      expect((bez['layers'] as List).map((l) => l['id']), ['ziemia']);
      final bezTerenu = jsonDecode(styl('file:///r-poziomice.pmtiles', null)) as Map<String, dynamic>;
      expect((bezTerenu['layers'] as List).map((l) => l['id']), ['ziemia', 'poziomice_10', 'poziomice_opisy']);
    });

    test('odrzuca adresy bez schematu', () {
      expect(
        () => przygotujStyl(szablon, paczka: '/r.pmtiles', szlaki: 'file:///s', punkty: 'file:///u', glify: 'file:///g', sprite: 'file:///p'),
        throwsArgumentError,
      );
    });

    test('styl z punktami wymaga pliku punktów', () {
      expect(
        () => przygotujStyl(szablon, paczka: 'file:///r.pmtiles', szlaki: 'file:///s', punkty: null, glify: 'file:///g', sprite: 'file:///p'),
        throwsArgumentError,
      );
    });
  });

  test('megabajty', () {
    expect(megabajty(69783648), '67 MB');
    expect(megabajty(7575725), '7,2 MB');
  });

  test('przeglądarka: tekst z serwera jako UTF-8, nawet bez charset w nagłówku', () async {
    final klient = MockClient((req) async {
      expect(req.url.toString(), 'https://x.web.app/dane/punkty.geojson');
      return http.Response.bytes(utf8.encode('Śnieżnica'), 200, headers: {'content-type': 'application/geo+json'});
    });
    final w = ZrodloWww(strona: Uri.parse('https://x.web.app/'), klient: klient);
    expect(await w.tekst('punkty.geojson'), 'Śnieżnica');
  });
}
