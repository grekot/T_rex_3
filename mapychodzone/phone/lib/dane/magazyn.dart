import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../trasa/brouter.dart';
import 'katalog.dart';
import 'zrodlo.dart';

/// Pliki aplikacji w prywatnym katalogu telefonu:
///
/// ```
/// <filesDir>/
///   mapy/katalog.json, styl.json, <region>.pmtiles, <region>-szlaki.geojson
///   brouter/segments4/*.rd5          dane tras z brouter.de
///   brouter/profile/*.brf, lookups.dat  (kopia z assets)
///   zasoby/glify/<font>/<zakres>.pbf, zasoby/sprite/light*.json|png  (kopia z assets)
/// ```
class Magazyn implements ZrodloDanych {
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

  /// Id regionu otwieranego na starcie (ostatnio oglądany).
  String get plikAktywnego => '$mapy/aktywny.txt';
  String get plikStylu => '$mapy/styl.json';
  String plikMapy(String nazwa) => '$mapy/$nazwa';
  String plikRd5(String nazwa) => '$segmenty/$nazwa.rd5';

  @override
  Future<String> tekst(String plik) => File(plikMapy(plik)).readAsString();

  @override
  Future<Uint8List> zakres(String plik, int od, int dlugosc) async {
    final f = await File(plikMapy(plik)).open();
    try {
      await f.setPosition(od);
      return await f.read(dlugosc);
    } finally {
      await f.close();
    }
  }

  // MapLibre Native czyta pliki przez file:///… (ścieżki bezwzględne)
  @override
  String adres(String plik) => 'file://${plikMapy(plik)}';

  @override
  String get adresGlifow => 'file://$glify';

  @override
  String get adresSprite => 'file://$sprite';

  @override
  bool get pobieranieRegionow => true;

  @override
  late final Trasownik trasownik = BRouter(this);

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

  /// Czy region ma na telefonie wszystko: mapę, szlaki, punkty, styl i dane tras.
  bool regionGotowy(Katalog k, RegionPaczki r) {
    bool jest(String sciezka, [int? rozmiar]) {
      final f = File(sciezka);
      return f.existsSync() && (rozmiar == null || f.lengthSync() == rozmiar);
    }

    return jest(plikStylu, k.styl.rozmiar) &&
        r.pliki.every((p) => jest(plikMapy(p.plik), p.rozmiar)) &&
        r.rd5.every((n) => jest(plikRd5(n)));
  }

  /// Czy na telefonie leży cokolwiek z regionu (np. starsza wersja do aktualizacji).
  bool regionCzesciowo(RegionPaczki r) => r.pliki.any((p) => File(plikMapy(p.plik)).existsSync());

  /// Regiony z katalogu, które są kompletne na telefonie.
  List<RegionPaczki> gotoweRegiony(Katalog k) => [
        for (final r in k.regiony)
          if (regionGotowy(k, r)) r,
      ];

  String? get aktywnyRegion {
    final f = File(plikAktywnego);
    return f.existsSync() ? f.readAsStringSync().trim() : null;
  }

  Future<void> ustawAktywny(String id) async {
    await File(plikAktywnego).parent.create(recursive: true);
    await File(plikAktywnego).writeAsString(id, flush: true);
  }

  /// Region do otwarcia na starcie: aktywny, jeśli jest kompletny, inaczej pierwszy kompletny.
  /// Null także wtedy, gdy katalog ma starszy format niż wymaga aplikacja (trzeba dociągnąć dane).
  RegionPaczki? gotowyRegion() {
    final k = wczytajKatalog();
    if (k == null || !k.aktualny) return null;
    final gotowe = gotoweRegiony(k);
    for (final r in gotowe) {
      if (r.id == aktywnyRegion) return r;
    }
    return gotowe.firstOrNull;
  }

  /// Miejsce zajmowane przez pliki regionu (bez wspólnych danych tras).
  int zajeteMiejsce(RegionPaczki r) => r.pliki.fold(0, (s, p) {
        final f = File(plikMapy(p.plik));
        return s + (f.existsSync() ? f.lengthSync() : 0);
      });

  /// Usuwa pliki regionu. Dane tras (*.rd5) zostają, jeśli potrzebuje ich inny region,
  /// który jest na telefonie (choćby częściowo).
  Future<void> usunRegion(Katalog k, RegionPaczki r) async {
    for (final p in r.pliki) {
      final f = File(plikMapy(p.plik));
      if (f.existsSync()) await f.delete();
    }
    final potrzebne = {
      for (final inny in k.regiony)
        if (inny.id != r.id && regionCzesciowo(inny)) ...inny.rd5,
    };
    for (final n in r.rd5) {
      final f = File(plikRd5(n));
      if (!potrzebne.contains(n) && f.existsSync()) await f.delete();
    }
  }
}
