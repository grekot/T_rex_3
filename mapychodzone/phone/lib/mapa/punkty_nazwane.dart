import 'dart:convert';

import '../trasa/trasa.dart';

/// Nazwany obiekt z warstwy punktów paczki (szczyt, schronisko, przełęcz…).
class ObiektNaMapie {
  const ObiektNaMapie(this.typ, this.nazwa, this.lon, this.lat, this.wysokosc);
  final String typ;
  final String nazwa;
  final double lon;
  final double lat;
  final int? wysokosc;

  /// „Turbacz (1310 m)”
  String get opis => wysokosc == null ? nazwa : '$nazwa ($wysokosc m)';
}

/// Wyszukiwanie najbliższego nazwanego obiektu, żeby przystanek dostał nazwę z mapy.
class PunktyNazwane {
  PunktyNazwane(this.obiekty);

  final List<ObiektNaMapie> obiekty;

  /// GeoJSON z `narzedzia/punkty.mjs` (właściwości t, n, e).
  factory PunktyNazwane.zGeojson(String tekst) {
    final cechy = (jsonDecode(tekst) as Map<String, dynamic>)['features'] as List;
    return PunktyNazwane([
      for (final c in cechy.cast<Map<String, dynamic>>())
        if ((c['properties'] as Map)['n'] != null)
          ObiektNaMapie(
            (c['properties'] as Map)['t'] as String,
            (c['properties'] as Map)['n'] as String,
            (((c['geometry'] as Map)['coordinates'] as List)[0] as num).toDouble(),
            (((c['geometry'] as Map)['coordinates'] as List)[1] as num).toDouble(),
            ((c['properties'] as Map)['e'] as num?)?.toInt(),
          ),
    ]);
  }

  /// Najbliższy obiekt w promieniu [promienM] (szczyty, schroniska i przełęcze mają pierwszeństwo
  /// przed wiatami czy źródłami w tej samej odległości ±30 m).
  ObiektNaMapie? najblizszy(double lon, double lat, {double promienM = 150}) {
    ObiektNaMapie? wynik;
    var najlepiej = double.infinity;
    for (final o in obiekty) {
      final d = odlegloscM(lat, lon, o.lat, o.lon);
      if (d > promienM) continue;
      final kara = const {'szczyt', 'schronisko', 'przelecz', 'chatka'}.contains(o.typ) ? 0 : 30;
      if (d + kara < najlepiej) {
        najlepiej = d + kara;
        wynik = o;
      }
    }
    return wynik;
  }
}
