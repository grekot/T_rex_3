import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../dane/magazyn.dart';
import 'plan.dart';
import 'trasa.dart';

class BladTrasy implements Exception {
  BladTrasy(this.komunikat);
  final String komunikat;
  @override
  String toString() => komunikat;
}

/// Liczenie tras profilem pieszym górskim BRoutera (`hiking-mountain`).
abstract class Trasownik {
  /// GeoJSON trasy z BRoutera dla punktów (lon, lat) i parametrów profilu.
  /// Błędy zgłasza jako [BladTrasy].
  Future<String> geojson(List<(double, double)> punkty, Map<String, String> parametry);

  /// [punkty]: (lon, lat) w kolejności start, punkty pośrednie, cel.
  ///
  /// Z unikaniem stromych liczy też tryby bardziej przywiązane do szlaków i zwraca
  /// najkrótszą trasę (patrz [trybyDoPorownania]). Błąd w dodatkowym trybie nie psuje wyniku.
  Future<Trasa> oblicz(
    List<(double, double)> punkty, {
    TrybTrasy tryb = TrybTrasy.szlakami,
    bool unikajStromych = false,
  }) async {
    final tryby = trybyDoPorownania(tryb, unikajStromych: unikajStromych);
    var najlepsza = await _jedna(punkty, tryby.first, unikajStromych);
    for (final t in tryby.skip(1)) {
      try {
        final inna = await _jedna(punkty, t, unikajStromych);
        if (inna.dlugosc < najlepsza.dlugosc) najlepsza = inna;
      } on BladTrasy {
        // zostaje wynik wybranego trybu
      }
    }
    return najlepsza;
  }

  Future<Trasa> _jedna(List<(double, double)> punkty, TrybTrasy tryb, bool unikajStromych) async =>
      Trasa.zGeojsonBRoutera(
          await geojson(punkty, parametryTrasy(tryb, unikajStromych: unikajStromych)));
}

/// Trasy offline w telefonie: BRouter jako biblioteka Java (Trasy.kt).
class BRouter extends Trasownik {
  BRouter(this.magazyn);

  static const _kanal = MethodChannel('pl.grekot.mapychodzone/trasy');
  final Magazyn magazyn;

  @override
  Future<String> geojson(List<(double, double)> punkty, Map<String, String> parametry) async {
    try {
      final wynik = await _kanal.invokeMethod<String>('oblicz', {
        'segmenty': magazyn.segmenty,
        'profil': magazyn.profilPieszy,
        'punkty': [
          for (final (lon, lat) in punkty) [lon, lat],
        ],
        'parametry': parametry,
        'czasMs': 60000,
      });
      return wynik!;
    } on PlatformException catch (e) {
      throw BladTrasy(opisBleduBRoutera(e.message ?? e.code));
    }
  }
}

/// Trasy w przeglądarce: publiczny serwer brouter.de z tym samym profilem
/// (`hiking-mountain`, identyczny z kopią w assets/brouter) i tymi samymi parametrami.
/// Wymaga internetu; serwer zezwala na zapytania z innych stron (CORS).
class BRouterOnline extends Trasownik {
  BRouterOnline({http.Client? klient}) : _klient = klient ?? http.Client();

  final http.Client _klient;

  @override
  Future<String> geojson(List<(double, double)> punkty, Map<String, String> parametry) async {
    final http.Response odp;
    try {
      odp = await _klient.get(adresBRouteraOnline(punkty, parametry)).timeout(const Duration(seconds: 60));
    } on Object {
      throw BladTrasy('Brak połączenia z serwerem tras (brouter.de).');
    }
    final tekst = utf8.decode(odp.bodyBytes, allowMalformed: true);
    if (odp.statusCode != 200) throw BladTrasy(opisBleduBRoutera(tekst.trim()));
    return tekst;
  }
}

/// Zapytanie do brouter.de: parametry profilu jako `profile:nazwa=wartość`.
Uri adresBRouteraOnline(List<(double, double)> punkty, Map<String, String> parametry) {
  final lonlaty = punkty.map((p) => '${p.$1},${p.$2}').join('|');
  final param = [
    'lonlats=$lonlaty',
    'profile=hiking-mountain',
    'alternativeidx=0',
    'format=geojson',
    for (final e in parametry.entries) 'profile:${e.key}=${e.value}',
  ].join('&');
  return Uri.parse('https://brouter.de/brouter?$param');
}

/// Komunikaty BRoutera po angielsku → zrozumiały opis.
String opisBleduBRoutera(String komunikat) {
  final k = komunikat.toLowerCase();
  if (k.contains('not mapped') || (k.contains('datafile') && k.contains('not found')) || k.contains('segment')) {
    return 'Punkt leży poza pobranymi danymi tras.';
  }
  if (k.contains('no track found') || k.contains('nie znaleziono')) {
    return 'Nie da się dojść między tymi punktami po ścieżkach z mapy.';
  }
  if (k.contains('timeout') || k.contains('operation killed')) {
    return 'Liczenie trasy trwało za długo. Spróbuj z punktem pośrednim.';
  }
  return 'Nie udało się wyznaczyć trasy: $komunikat';
}
