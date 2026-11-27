import 'package:flutter/services.dart';

import '../dane/magazyn.dart';
import 'trasa.dart';

class BladTrasy implements Exception {
  BladTrasy(this.komunikat);
  final String komunikat;
  @override
  String toString() => komunikat;
}

/// Wyznaczanie tras offline przez BRouter (Trasy.kt), profil pieszy górski.
class BRouter {
  BRouter(this.magazyn);

  static const _kanal = MethodChannel('pl.grekot.mapychodzone/trasy');
  final Magazyn magazyn;

  /// [punkty]: (lon, lat) w kolejności start, punkty pośrednie, cel.
  Future<Trasa> oblicz(List<(double, double)> punkty) async {
    try {
      final geojson = await _kanal.invokeMethod<String>('oblicz', {
        'segmenty': magazyn.segmenty,
        'profil': magazyn.profilPieszy,
        'punkty': [
          for (final (lon, lat) in punkty) [lon, lat],
        ],
        'czasMs': 60000,
      });
      return Trasa.zGeojsonBRoutera(geojson!);
    } on PlatformException catch (e) {
      throw BladTrasy(opisBleduBRoutera(e.message ?? e.code));
    }
  }
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
