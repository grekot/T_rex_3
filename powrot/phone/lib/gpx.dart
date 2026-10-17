import 'dart:math';

/// Plik GPX do zaimportowania w aplikacji Zepp (trasa + punkt docelowy).
/// Zepp nawiguje po trasach, więc zapisujemy odcinek od [from] (moja pozycja) do celu;
/// bez pozycji startowej trasa ma tylko punkt docelowy (zegarek pokaże go na mapie).
String buildGpx({
  required String name,
  required double lat,
  required double lon,
  ({double lat, double lon})? from,
  DateTime? time,
}) {
  final t = (time ?? DateTime.now()).toUtc().toIso8601String();
  final safe = _xml(name);
  final points = <({double lat, double lon})>[
    if (from != null) ..._interpolate(from, (lat: lat, lon: lon)),
    (lat: lat, lon: lon),
  ];
  final trkpts = points.map((p) => '      <trkpt lat="${_c(p.lat)}" lon="${_c(p.lon)}"></trkpt>').join('\n');
  return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Powrot" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>$safe</name>
    <time>$t</time>
  </metadata>
  <wpt lat="${_c(lat)}" lon="${_c(lon)}">
    <name>$safe</name>
  </wpt>
  <trk>
    <name>$safe</name>
    <trkseg>
$trkpts
    </trkseg>
  </trk>
</gpx>
''';
}

/// Punkty pośrednie co ok. 50 m (bez ostatniego) - część aplikacji źle traktuje trasy z 2 punktów
List<({double lat, double lon})> _interpolate(({double lat, double lon}) a, ({double lat, double lon}) b) {
  final dist = distanceMeters(a.lat, a.lon, b.lat, b.lon);
  final steps = max(1, min(200, (dist / 50).ceil()));
  return [
    for (var i = 0; i < steps; i++)
      (lat: a.lat + (b.lat - a.lat) * i / steps, lon: a.lon + (b.lon - a.lon) * i / steps),
  ];
}

double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}

String formatDistance(double m) {
  if (m < 1000) return '${m.round()} m';
  if (m < 10000) return '${(m / 1000).toStringAsFixed(2).replaceAll('.', ',')} km';
  return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Nazwa pliku bez polskich znaków i spacji: "Auto pod blokiem" -> "auto-pod-blokiem.gpx"
String gpxFileName(String name) {
  const from = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';
  const to = 'acelnoszzACELNOSZZ';
  final buf = StringBuffer();
  for (final ch in name.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  final slug = buf.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return '${slug.isEmpty ? 'miejsce' : slug}.gpx';
}

/// Link do nawigacji w Google Maps (pieszo / autem)
Uri mapsDirectionsUri(double lat, double lon, {bool driving = false}) => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${_c(lat)},${_c(lon)}',
      'travelmode': driving ? 'driving' : 'walking',
    });

/// Link do samego punktu na mapie (do wysłania komuś)
Uri mapsPlaceUri(double lat, double lon) =>
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '${_c(lat)},${_c(lon)}'});

String _c(double v) => v.toStringAsFixed(6);

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
