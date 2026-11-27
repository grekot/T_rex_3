/// Styl mapy z paczki (`styl.json` z repozytorium danych) ze znacznikami podmienianymi
/// na ścieżki plików w telefonie.
///
/// MapLibre Native czyta PMTiles z dysku przez `pmtiles://file:///…` (z odczytem zakresów
/// bajtów), a GeoJSON, glify i sprite'y przez `file:///…`. Ścieżki muszą być bezwzględne.
String przygotujStyl(
  String szablon, {
  required String paczka,
  required String szlaki,
  required String glify,
  required String sprite,
}) {
  for (final s in [paczka, szlaki, glify, sprite]) {
    if (!s.startsWith('/')) throw ArgumentError('Ścieżka musi być bezwzględna: $s');
  }
  return szablon
      .replaceAll('{PACZKA}', 'file://$paczka')
      .replaceAll('{SZLAKI}', 'file://$szlaki')
      .replaceAll('{GLIFY}', 'file://$glify')
      .replaceAll('{SPRITE}', 'file://$sprite');
}
