import 'package:flutter_test/flutter_test.dart';
import 'package:powrot/gpx.dart';

void main() {
  test('GPX z trasą od mojej pozycji do celu', () {
    final gpx = buildGpx(
      name: 'Auto <pod> "blokiem" & sklep',
      lat: 52.00085, // ok. 95 m na północ
      lon: 21.0,
      from: (lat: 52.0, lon: 21.0),
      time: DateTime.utc(2026, 10, 17, 10),
    );
    expect(gpx, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(gpx, contains('<gpx version="1.1"'));
    expect(gpx, contains('<name>Auto &lt;pod&gt; &quot;blokiem&quot; &amp; sklep</name>'));
    expect(gpx, contains('<wpt lat="52.000850" lon="21.000000">'));
    expect(gpx, contains('<time>2026-10-17T10:00:00.000Z</time>'));
    // ok. 95 m -> start + punkt pośredni (co ok. 50 m) + cel
    final pts = RegExp('<trkpt ').allMatches(gpx).length;
    expect(pts, 3);
    expect(gpx.indexOf('<trkpt lat="52.000000"'), lessThan(gpx.indexOf('<trkpt lat="52.000850"')),
        reason: 'trasa zaczyna się w mojej pozycji, kończy w celu');
  });

  test('GPX bez pozycji startowej - sam punkt docelowy', () {
    final gpx = buildGpx(name: 'Namiot', lat: 50.0, lon: 19.9);
    expect(RegExp('<trkpt ').allMatches(gpx).length, 1);
    expect(gpx, contains('<wpt lat="50.000000" lon="19.900000">'));
  });

  test('długa trasa ma ograniczoną liczbę punktów', () {
    final gpx = buildGpx(name: 'Daleko', lat: 50.05, lon: 19.93, from: (lat: 52.23, lon: 21.0));
    expect(RegExp('<trkpt ').allMatches(gpx).length, lessThanOrEqualTo(201));
  });

  test('odległość i formatowanie', () {
    expect(distanceMeters(52.0, 21.0, 52.0001, 21.0), closeTo(11.1, 0.2));
    expect(formatDistance(349.6), '350 m');
    expect(formatDistance(1250), '1,25 km');
    expect(formatDistance(12345), '12,3 km');
  });

  test('nazwa pliku', () {
    expect(gpxFileName('Auto pod blokiem'), 'auto-pod-blokiem.gpx');
    expect(gpxFileName('Żółta łąka!'), 'zolta-laka.gpx');
    expect(gpxFileName('***'), 'miejsce.gpx');
  });

  test('linki Google Maps', () {
    final walk = mapsDirectionsUri(52.1, 21.05);
    expect(walk.host, 'www.google.com');
    expect(walk.path, '/maps/dir/');
    expect(walk.queryParameters['destination'], '52.100000,21.050000');
    expect(walk.queryParameters['travelmode'], 'walking');
    expect(mapsDirectionsUri(52.1, 21.05, driving: true).queryParameters['travelmode'], 'driving');
    expect(mapsPlaceUri(52.1, 21.05).queryParameters['query'], '52.100000,21.050000');
  });
}
