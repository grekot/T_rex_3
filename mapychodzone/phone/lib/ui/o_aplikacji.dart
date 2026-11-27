import 'package:flutter/material.dart';

/// Źródła danych i licencje (OSM wymaga widocznego podpisu, pozostałe – informacji o licencji).
void pokazOAplikacji(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'MapyChodzone',
    applicationLegalese: 'Piesza mapa turystyczna offline.',
    children: const [
      SizedBox(height: 12),
      Text(
        'Dane mapy i szlaków: © OpenStreetMap contributors, licencja ODbL '
        '(openstreetmap.org/copyright).\n\n'
        'Mapa bazowa: Protomaps Basemap (dane OSM).\n\n'
        'Trasy: BRouter (licencja MIT), dane tras z brouter.de (OSM, wysokości SRTM).\n\n'
        'Czas przejścia: norma DIN 33466 (4 km/h, 300 m/h w górę, 500 m/h w dół).\n\n'
        'Fonty Noto Sans (SIL Open Font License), ikony mapy: Protomaps basemaps-assets (MIT), '
        'silnik mapy: MapLibre Native (BSD).',
      ),
    ],
  );
}
