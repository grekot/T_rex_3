import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../trasa/brouter.dart';

/// Skąd ekran mapy bierze dane regionu i jak liczy trasy.
///
/// - Telefon: [Magazyn] – pobrane pliki w katalogu aplikacji, BRouter offline.
/// - Przeglądarka: [ZrodloWww] – pliki z tego samego serwera (np. Firebase Hosting),
///   trasy z publicznego serwera brouter.de.
abstract class ZrodloDanych {
  /// Treść pliku z paczki (styl.json, GeoJSON punktów).
  Future<String> tekst(String plik);

  /// Fragment pliku z paczki (bajty od [od], [dlugosc] sztuk), np. kafelek modelu terenu.
  Future<Uint8List> zakres(String plik, int od, int dlugosc);

  /// Adres pliku z paczki do wstawienia w styl mapy (`file:///…` albo `https://…`).
  String adres(String plik);

  /// Adres katalogu z glifami (fontami) mapy.
  String get adresGlifow;

  /// Adres sprite'ów mapy bez rozszerzenia katalogu (`…/sprite`).
  String get adresSprite;

  /// Czy można pobierać i aktualizować regiony (tylko w telefonie).
  bool get pobieranieRegionow;

  Trasownik get trasownik;
}

/// Wersja przeglądarkowa: wszystkie pliki z tego samego serwera co aplikacja.
///
/// ```
/// <strona>/dane/katalog.json, styl.json, <region>.pmtiles, <region>-szlaki.geojson, …
/// <strona>/assets/assets/mapa/glify, …/sprite   (assets Fluttera)
/// ```
class ZrodloWww implements ZrodloDanych {
  ZrodloWww({Uri? strona, http.Client? klient})
      : strona = strona ?? Uri.base,
        _klient = klient ?? http.Client();

  final Uri strona;
  final http.Client _klient;

  Uri get _dane => strona.resolve('dane/');

  @override
  Future<String> tekst(String plik) async {
    final odp = await _klient.get(_dane.resolve(plik));
    if (odp.statusCode != 200) throw Exception('Brak pliku $plik na serwerze (HTTP ${odp.statusCode})');
    // dane są w UTF-8; bez „charset” w nagłówku pakiet http czytałby je jako latin1 (krzaki w nazwach)
    return utf8.decode(odp.bodyBytes);
  }

  @override
  Future<Uint8List> zakres(String plik, int od, int dlugosc) async {
    final odp = await _klient.get(_dane.resolve(plik), headers: {'Range': 'bytes=$od-${od + dlugosc - 1}'});
    if (odp.statusCode == 206) return odp.bodyBytes;
    if (odp.statusCode == 200) return Uint8List.sublistView(odp.bodyBytes, od, od + dlugosc);
    throw Exception('Brak pliku $plik na serwerze (HTTP ${odp.statusCode})');
  }

  @override
  String adres(String plik) => _dane.resolve(plik).toString();

  @override
  String get adresGlifow => strona.resolve('assets/assets/mapa/glify').toString();

  @override
  String get adresSprite => strona.resolve('assets/assets/mapa/sprite').toString();

  @override
  bool get pobieranieRegionow => false;

  @override
  late final Trasownik trasownik = BRouterOnline(klient: _klient);
}
