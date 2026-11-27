import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'katalog.dart';

/// Pliki aplikacji w prywatnym katalogu telefonu:
///
/// ```
/// <filesDir>/
///   mapy/katalog.json, styl.json, <region>.pmtiles, <region>-szlaki.geojson
///   brouter/segments4/*.rd5          dane tras z brouter.de
///   brouter/profile/*.brf, lookups.dat  (kopia z assets)
///   zasoby/glify/<font>/<zakres>.pbf, zasoby/sprite/light*.json|png  (kopia z assets)
/// ```
class Magazyn {
  Magazyn(this.katalog);

  /// Zmienić, gdy zmienią się pliki w assets/brouter albo assets/mapa (wymusza ponowną kopię).
  static const wersjaZasobow = 1;

  final String katalog;

  String get mapy => '$katalog/mapy';
  String get segmenty => '$katalog/brouter/segments4';
  String get profile => '$katalog/brouter/profile';
  String get profilPieszy => '$profile/hiking-mountain.brf';
  String get glify => '$katalog/zasoby/glify';
  String get sprite => '$katalog/zasoby/sprite';

  String get plikKatalogu => '$mapy/katalog.json';
  String get plikStylu => '$mapy/styl.json';
  String plikMapy(String nazwa) => '$mapy/$nazwa';
  String plikRd5(String nazwa) => '$segmenty/$nazwa.rd5';

  /// Kopiuje fonty, sprite'y i profil BRoutera z assets do katalogu aplikacji,
  /// bo MapLibre i BRouter czytają zwykłe pliki (file://), nie assets APK.
  Future<void> przygotujZasoby() async {
    final znacznik = File('$katalog/zasoby/wersja');
    if (znacznik.existsSync() && znacznik.readAsStringSync().trim() == '$wersjaZasobow') return;

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets()) {
      final String cel;
      if (asset.startsWith('assets/mapa/glify/')) {
        cel = '$glify/${asset.substring('assets/mapa/glify/'.length)}';
      } else if (asset.startsWith('assets/mapa/sprite/')) {
        cel = '$sprite/${asset.substring('assets/mapa/sprite/'.length)}';
      } else if (asset.startsWith('assets/brouter/')) {
        cel = '$profile/${asset.substring('assets/brouter/'.length)}';
      } else {
        continue;
      }
      final dane = await rootBundle.load(asset);
      final plik = File(Uri.decodeFull(cel));
      await plik.parent.create(recursive: true);
      await plik.writeAsBytes(dane.buffer.asUint8List(dane.offsetInBytes, dane.lengthInBytes), flush: true);
    }
    await znacznik.parent.create(recursive: true);
    await znacznik.writeAsString('$wersjaZasobow', flush: true);
  }

  /// Katalog paczek zapisany przy ostatnim pobraniu (null = jeszcze nic nie pobrano).
  Katalog? wczytajKatalog() {
    final plik = File(plikKatalogu);
    if (!plik.existsSync()) return null;
    try {
      return Katalog.zJson(jsonDecode(plik.readAsStringSync()) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  /// Czy region ma na telefonie wszystko: mapę, szlaki, styl i dane tras.
  bool regionGotowy(Katalog k, RegionPaczki r) {
    bool jest(String sciezka, [int? rozmiar]) {
      final f = File(sciezka);
      return f.existsSync() && (rozmiar == null || f.lengthSync() == rozmiar);
    }

    return jest(plikStylu, k.styl.rozmiar) &&
        jest(plikMapy(r.mapa.plik), r.mapa.rozmiar) &&
        jest(plikMapy(r.szlaki.plik), r.szlaki.rozmiar) &&
        r.rd5.every((n) => jest(plikRd5(n)));
  }

  /// Pierwszy region z zapisanego katalogu, który jest kompletny na telefonie.
  RegionPaczki? gotowyRegion() {
    final k = wczytajKatalog();
    if (k == null) return null;
    for (final r in k.regiony) {
      if (regionGotowy(k, r)) return r;
    }
    return null;
  }
}
