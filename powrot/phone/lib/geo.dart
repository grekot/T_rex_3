import 'dart:math';

/// Geometria na kuli ziemskiej i kompas - czyste funkcje (testy w test/geo_test.dart).
/// Te same obliczenia co na zegarku w `watch/utils/geo.js`.

const _r = 6371000.0; // promień Ziemi w metrach

/// Odległość, przy której uznajemy, że jesteś na miejscu (jak na zegarku)
const arrivedM = 15.0;

/// Po „Na miejscu!” kolejny alarm dopiero po oddaleniu się na tyle metrów
const rearmM = 30.0;

double _rad(double d) => d * pi / 180;
double _deg(double r) => r * 180 / pi;

/// Kąt sprowadzony do 0..360
double normalize(double deg) {
  final d = deg % 360;
  return d < 0 ? d + 360 : d;
}

/// Odległość w metrach (wzór haversine)
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) + cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * _r * atan2(sqrt(a), sqrt(1 - a));
}

/// Kierunek do celu: stopnie od północy geograficznej, zgodnie z ruchem wskazówek (0 = N, 90 = E)
double bearing(double lat1, double lon1, double lat2, double lon2) {
  final y = sin(_rad(lon2 - lon1)) * cos(_rad(lat2));
  final x = cos(_rad(lat1)) * sin(_rad(lat2)) - sin(_rad(lat1)) * cos(_rad(lat2)) * cos(_rad(lon2 - lon1));
  return normalize(_deg(atan2(y, x)));
}

/// O ile obrócić strzałkę: kierunek do celu minus kierunek, w który patrzy góra telefonu
double relativeAngle(double targetBearing, double heading) => normalize(targetBearing - heading);

/// Wygładzanie drgań kompasu - interpolacja po najkrótszym łuku (359° -> 1° to 2°, nie 358°)
double smoothAngle(double? prev, double next, double factor) {
  if (prev == null) return normalize(next);
  final diff = ((next - prev + 540) % 360) - 180;
  return normalize(prev + diff * factor);
}

/// Najkrótsza różnica kątów -180..180 (do obrotu strzałki bez „przeskoku” przez 360°)
double angleDiff(double from, double to) => ((to - from + 540) % 360) - 180;

/// 7 m, 350 m, 1,25 km, 12,3 km, 152 km
String formatDistance(double m) {
  if (!m.isFinite) return '–';
  if (m < 1000) return '${m.round()} m';
  if (m < 10000) return '${(m / 1000).toStringAsFixed(2).replaceAll('.', ',')} km';
  if (m < 100000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  return '${(m / 1000).round()} km';
}

const _cardinal = ['Pn', 'Pn-Wsch', 'Wsch', 'Pd-Wsch', 'Pd', 'Pd-Zach', 'Zach', 'Pn-Zach'];

/// 45 -> "Pn-Wsch"
String cardinal(double deg) => _cardinal[(normalize(deg) / 45).round() % 8];

/// "Pn-Wsch · 47°"
String formatBearing(double deg) {
  final d = normalize(deg).round() % 360;
  return '${cardinal(deg)} · $d°';
}

/// Alarm „Na miejscu!”: włącza się w promieniu [arrivedM], a ponownie zadziała dopiero
/// po oddaleniu się na [rearmM] (żeby drgania GPS przy granicy nie wibrowały bez końca).
class ArrivalTracker {
  bool _armed = true;
  bool _here = false;

  /// Czy jesteś teraz na miejscu (do napisu na ekranie)
  bool get here => _here;

  /// Nowa odległość; zwraca true, gdy właśnie trzeba zawibrować
  bool update(double meters) {
    if (meters <= arrivedM) {
      _here = true;
      if (_armed) {
        _armed = false;
        return true;
      }
      return false;
    }
    if (meters >= rearmM) {
      _armed = true;
      _here = false;
    } else if (_armed) {
      _here = false;
    }
    return false;
  }
}

// --- Deklinacja magnetyczna ---------------------------------------------------------------
//
// Kompas telefonu (flutter_compass, czujnik TYPE_ROTATION_VECTOR) podaje kierunek względem
// północy MAGNETYCZNEJ, a azymut z GPS liczymy względem geograficznej. W Polsce różnica
// (deklinacja) to ok. 5-8° na wschód - na 1 km marszu daje to ok. 100 m odchyłki, więc ją
// poprawiamy. Pełny model WMM to kilkaset współczynników; do marszu po Polsce i okolicach
// wystarcza siatka policzona kalkulatorem NOAA z modelu WMM2025 na 1.01.2027 ze zmianą
// roczną (ta sama co w aplikacji Szczyty na zegarku: `szczyty/utils/declination.js`).
// Poza siatką (z marginesem) nie zgadujemy - zwracamy null i ekran pokazuje kierunek
// magnetyczny z adnotacją.

const _lat0 = 48.0;
const _latStep = 1.5;
const _lon0 = 12.0;
const _lonStep = 2.5;
const _epoch = 2027.0;
const _margin = 3.0; // stopnie poza siatką, w których jeszcze bierzemy najbliższy brzeg

// wiersze: szerokość 48, 49.5, 51, 52.5, 54, 55.5; kolumny: długość 12, 14.5, 17, 19.5, 22, 24.5
const _decl = [
  [4.47, 4.994, 5.494, 5.971, 6.428, 6.864],
  [4.586, 5.153, 5.695, 6.215, 6.715, 7.194],
  [4.706, 5.32, 5.909, 6.477, 7.024, 7.551],
  [4.833, 5.497, 6.138, 6.758, 7.356, 7.935],
  [4.966, 5.686, 6.383, 7.059, 7.714, 8.348],
  [5.109, 5.888, 6.645, 7.381, 8.096, 8.791],
];
// zmiana roczna w stopniach
const _sv = [
  [0.117, 0.11, 0.103, 0.096, 0.09, 0.084],
  [0.124, 0.117, 0.11, 0.103, 0.097, 0.09],
  [0.131, 0.124, 0.117, 0.111, 0.104, 0.098],
  [0.139, 0.132, 0.125, 0.119, 0.112, 0.106],
  [0.148, 0.141, 0.134, 0.128, 0.121, 0.115],
  [0.157, 0.15, 0.144, 0.137, 0.131, 0.125],
];

double _bilinear(List<List<double>> grid, double lat, double lon) {
  final rows = grid.length, cols = grid[0].length;
  final fr = ((lat - _lat0) / _latStep).clamp(0.0, rows - 1.0);
  final fc = ((lon - _lon0) / _lonStep).clamp(0.0, cols - 1.0);
  final r = min(fr.floor(), rows - 2);
  final c = min(fc.floor(), cols - 2);
  final tr = fr - r, tc = fc - c;
  final top = grid[r][c] * (1 - tc) + grid[r][c + 1] * tc;
  final bottom = grid[r + 1][c] * (1 - tc) + grid[r + 1][c + 1] * tc;
  return top * (1 - tr) + bottom * tr;
}

/// Deklinacja w stopniach (dodatnia = wschodnia) albo null poza obszarem modelu
double? declination(double lat, double lon, DateTime when) {
  final latMax = _lat0 + _latStep * (_decl.length - 1);
  final lonMax = _lon0 + _lonStep * (_decl[0].length - 1);
  if (lat < _lat0 - _margin || lat > latMax + _margin || lon < _lon0 - _margin || lon > lonMax + _margin) {
    return null;
  }
  final year = when.year + (when.month - 1) / 12;
  final dt = (year - _epoch).clamp(-3.0, 5.0); // poza 2024-2032 nie ekstrapolujemy
  return _bilinear(_decl, lat, lon) + _bilinear(_sv, lat, lon) * dt;
}

/// Kierunek magnetyczny + deklinacja wschodnia = kierunek geograficzny
double trueHeading(double magnetic, double decl) => normalize(magnetic + decl);

/// Ocena dokładności kompasu z flutter_compass (Android: 15 / 30 / 45° albo null = nieznana
/// lub „unreliable” - wymaga kalibracji).
enum CompassQuality { good, medium, poor, unknown }

CompassQuality compassQuality(double? accuracyDeg) {
  if (accuracyDeg == null) return CompassQuality.unknown;
  if (accuracyDeg <= 15) return CompassQuality.good;
  if (accuracyDeg <= 30) return CompassQuality.medium;
  return CompassQuality.poor;
}
