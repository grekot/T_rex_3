import 'dart:convert';

/// Styl mapy z paczki (`styl.json` z repozytorium danych) ze znacznikami podmienianymi
/// na adresy plików.
///
/// - Telefon: MapLibre Native czyta PMTiles z dysku przez `pmtiles://file:///…` (z odczytem
///   zakresów bajtów), a GeoJSON, glify i sprite'y przez `file:///…`.
/// - Przeglądarka: `pmtiles://https://…` (protokół z biblioteki pmtiles w index.html,
///   serwer musi obsługiwać nagłówek Range) i zwykłe `https://…`.
///
/// Adresy muszą być pełne (ze schematem), bo styl nie ma adresu bazowego.
String przygotujStyl(
  String szablon, {
  required String paczka,
  required String szlaki,
  required String? punkty,
  String? poziomice,
  String? teren,
  required String glify,
  required String sprite,
}) {
  for (final s in [paczka, szlaki, ?punkty, ?poziomice, ?teren, glify, sprite]) {
    if (!RegExp(r'^(file|https?)://').hasMatch(s)) throw ArgumentError('Adres musi być pełny: $s');
  }
  if (punkty == null && szablon.contains('{PUNKTY}')) {
    throw ArgumentError('Styl wymaga warstwy punktów, a region jej nie ma');
  }
  var s = szablon
      .replaceAll('{PACZKA}', paczka)
      .replaceAll('{SZLAKI}', szlaki)
      .replaceAll('{GLIFY}', glify)
      .replaceAll('{SPRITE}', sprite);
  if (punkty != null) s = s.replaceAll('{PUNKTY}', punkty);
  // poziomice i teren są opcjonalne (region bez nich): wtedy znika źródło i jego warstwy
  for (final (znacznik, zrodlo, adres) in [('{POZIOMICE}', 'poziomice', poziomice), ('{TEREN}', 'teren', teren)]) {
    if (adres != null) {
      s = s.replaceAll(znacznik, adres);
    } else if (s.contains(znacznik)) {
      s = bezZrodla(s, zrodlo);
    }
  }
  return s;
}

/// Styl bez źródła [zrodlo] i jego warstw (np. region bez poziomic).
String bezZrodla(String styl, String zrodlo) {
  final j = jsonDecode(styl) as Map<String, dynamic>;
  (j['sources'] as Map<String, dynamic>).remove(zrodlo);
  (j['layers'] as List).removeWhere((l) => (l as Map<String, dynamic>)['source'] == zrodlo);
  return jsonEncode(j);
}
