import 'dart:convert';
import 'dart:math' as math;

/// Punkt trasy: współrzędne, wysokość (m n.p.m.) i odległość od startu (m).
class PunktTrasy {
  const PunktTrasy(this.lon, this.lat, this.wysokosc, this.odStartu);
  final double lon;
  final double lat;
  final double? wysokosc;
  final double odStartu;
}

/// Prosty odcinek trasy na przełaj: azymut geograficzny (0–360°) i długość (m).
class OdcinekAzymutu {
  const OdcinekAzymutu(this.azymut, this.dlugosc);
  final double azymut;
  final double dlugosc;

  /// Ten sam odcinek przechodzony w drugą stronę.
  OdcinekAzymutu get odwrotny => OdcinekAzymutu((azymut + 180) % 360, dlugosc);
}

/// Wyznaczona trasa z BRoutera i liczby, które pokazujemy: długość, podejścia, zejścia, czas.
class Trasa {
  Trasa(this.punkty, {this.trudnyTeren = const {}, this.uwagi = const [], this.azymuty = const []})
      : dlugosc = punkty.isEmpty ? 0 : punkty.last.odStartu,
        _przewyzszenia = sumaPrzewyzszen([
          for (final p in punkty)
            if (p.wysokosc != null) p.wysokosc!,
        ]);

  final List<PunktTrasy> punkty;

  /// Metry trasy w trudnym terenie według skali SAC (4 = T4 … 6 = T6), z danych OSM (`sac_scale`).
  /// Pusta mapa: trasa nie wychodzi ponad T3.
  final Map<int, double> trudnyTeren;

  /// Ostrzeżenia do pokazania pod trasą (np. park narodowy, bród).
  final List<String> uwagi;

  /// Trasa na przełaj: kolejne odcinki proste z azymutem (pusta dla tras z BRoutera).
  final List<OdcinekAzymutu> azymuty;

  /// Metry.
  final double dlugosc;
  final (double, double) _przewyzszenia;

  /// Suma podejść (m), z filtrem drobnych wahań wysokości.
  double get podejscia => _przewyzszenia.$1;

  /// Suma zejść (m).
  double get zejscia => _przewyzszenia.$2;

  double? get najwyzej => _skrajna(math.max);
  double? get najnizej => _skrajna(math.min);

  double? _skrajna(double Function(double, double) f) {
    double? w;
    for (final p in punkty) {
      final h = p.wysokosc;
      if (h == null) continue;
      w = w == null ? h : f(w, h);
    }
    return w;
  }

  /// Czas przejścia według normy DIN 33466 (jak na niemieckich i austriackich drogowskazach).
  Duration get czas => czasPrzejscia(dlugoscM: dlugosc, podejsciaM: podejscia, zejsciaM: zejscia);

  /// Linia trasy jako GeoJSON do warstwy na mapie.
  Map<String, dynamic> get geojson => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in punkty) [p.lon, p.lat],
              ],
            },
          },
        ],
      };

  /// Trasa tam i z powrotem dokładnie tą samą drogą: do śladu dochodzi ten sam ślad w odwrotnej
  /// kolejności (bez drugiego liczenia w BRouterze, więc powrót na pewno idzie tędy samo).
  Trasa zPowrotem() {
    if (punkty.length < 2) return this;
    final wynik = [...punkty];
    for (final p in punkty.reversed.skip(1)) {
      final ost = wynik.last;
      wynik.add(PunktTrasy(p.lon, p.lat, p.wysokosc, ost.odStartu + odlegloscM(ost.lat, ost.lon, p.lat, p.lon)));
    }
    return Trasa(
      wynik,
      trudnyTeren: {for (final e in trudnyTeren.entries) e.key: e.value * 2},
      uwagi: uwagi,
      azymuty: [...azymuty, for (final o in azymuty.reversed) o.odwrotny],
    );
  }

  /// Wynik BRoutera (FormatJson): FeatureCollection z jedną linią `[lon, lat, wysokość]`.
  factory Trasa.zGeojsonBRoutera(String tekst) {
    final json = jsonDecode(tekst) as Map<String, dynamic>;
    final cechy = json['features'] as List;
    if (cechy.isEmpty) throw const FormatException('BRouter nie zwrócił trasy');
    final geometria = (cechy.first as Map<String, dynamic>)['geometry'] as Map<String, dynamic>;
    final wsp = geometria['coordinates'] as List;
    final punkty = <PunktTrasy>[];
    double suma = 0;
    for (var i = 0; i < wsp.length; i++) {
      final p = wsp[i] as List;
      final lon = (p[0] as num).toDouble();
      final lat = (p[1] as num).toDouble();
      final h = p.length > 2 ? (p[2] as num).toDouble() : null;
      if (i > 0) suma += odlegloscM(punkty.last.lat, punkty.last.lon, lat, lon);
      punkty.add(PunktTrasy(lon, lat, h, suma));
    }
    final wlasciwosci = (cechy.first as Map<String, dynamic>)['properties'];
    final komunikaty = wlasciwosci is Map ? wlasciwosci['messages'] : null;
    return Trasa(punkty, trudnyTeren: komunikaty is List ? trudnyTerenZKomunikatow(komunikaty) : const {});
  }
}

/// Stopień trudności SAC (1–6) z tagu OSM `sac_scale`; null dla nieznanych.
int? stopienSac(String sacScale) => switch (sacScale) {
      'hiking' => 1,
      'mountain_hiking' => 2,
      'demanding_mountain_hiking' => 3,
      'alpine_hiking' => 4,
      'demanding_alpine_hiking' => 5,
      'difficult_alpine_hiking' => 6,
      _ => null,
    };

/// Metry trasy w terenie T4+ z tabeli `messages` BRoutera: pierwszy wiersz to nagłówki
/// (m.in. „Distance” i „WayTags”), kolejne to odcinki dróg z ich tagami OSM.
Map<int, double> trudnyTerenZKomunikatow(List komunikaty) {
  if (komunikaty.length < 2 || komunikaty.first is! List) return const {};
  final naglowki = (komunikaty.first as List).map((e) => '$e').toList();
  final iDl = naglowki.indexOf('Distance');
  final iTagi = naglowki.indexOf('WayTags');
  if (iDl < 0 || iTagi < 0) return const {};
  final wynik = <int, double>{};
  for (final w in komunikaty.skip(1)) {
    if (w is! List || w.length <= math.max(iDl, iTagi)) continue;
    final sac = RegExp(r'sac_scale=([a-z_]+)').firstMatch('${w[iTagi]}')?.group(1);
    final stopien = sac == null ? null : stopienSac(sac);
    if (stopien == null || stopien < 4) continue;
    wynik[stopien] = (wynik[stopien] ?? 0) + (double.tryParse('${w[iDl]}') ?? 0);
  }
  return wynik;
}

/// Ostrzeżenie o trudnym terenie albo null, gdy trasa nie wychodzi ponad T3.
String? ostrzezenieTrudnosci(Map<int, double> trudnyTeren) {
  final metry = trudnyTeren.values.fold<double>(0, (a, b) => a + b);
  if (metry < 1) return null;
  final stopnie = trudnyTeren.keys.toList()..sort();
  final zakres = stopnie.first == stopnie.last ? 'T${stopnie.first}' : 'T${stopnie.first}–T${stopnie.last}';
  return '${opisDlugosci(metry)} trasy to trudny teren $zakres (ekspozycja, łańcuchy, wspinaczka). '
      'Sprawdź warunki i czy to szlak dla Ciebie.';
}

/// Odległość po kuli (haversine), w metrach.
double odlegloscM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8;
  final f1 = lat1 * math.pi / 180;
  final f2 = lat2 * math.pi / 180;
  final df = (lat2 - lat1) * math.pi / 180;
  final dl = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(df / 2), 2) + math.cos(f1) * math.cos(f2) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// Suma podejść i zejść z histerezą: zmiana kierunku liczy się dopiero po [prog] metrach,
/// więc szum danych wysokościowych nie zawyża wyniku.
(double, double) sumaPrzewyzszen(List<double> wysokosci, {double prog = 5}) {
  if (wysokosci.length < 2) return (0, 0);
  double gora = 0, dol = 0;
  var odniesienie = wysokosci.first;
  for (final h in wysokosci.skip(1)) {
    final roznica = h - odniesienie;
    if (roznica >= prog) {
      gora += roznica;
      odniesienie = h;
    } else if (roznica <= -prog) {
      dol -= roznica;
      odniesienie = h;
    }
  }
  return (gora, dol);
}

/// DIN 33466: poziomo 4 km/h, w górę 300 m/h, w dół 500 m/h.
/// Czas = większy z czasów (poziomy, pionowy) + połowa mniejszego.
Duration czasPrzejscia({
  required double dlugoscM,
  required double podejsciaM,
  required double zejsciaM,
  double kmNaGodzine = 4,
}) {
  final poziomo = dlugoscM / 1000 / kmNaGodzine;
  final pionowo = podejsciaM / 300 + zejsciaM / 500;
  final godziny = math.max(poziomo, pionowo) + math.min(poziomo, pionowo) / 2;
  return Duration(minutes: (godziny * 60).round());
}

/// Deklinacja magnetyczna w polskich górach w 2026 r.: ok. 6–7° na wschód (Sudety ok. 5,5°,
/// Bieszczady ok. 7,5°). Kompas pokazuje azymut magnetyczny: geograficzny minus deklinacja.
const deklinacjaMagnetyczna = 6.5;

/// „137°” – azymut geograficzny zaokrąglony do stopnia.
String opisAzymutu(double azymut) => '${azymut.round() % 360}°';

/// „12,4 km” albo „850 m”.
String opisDlugosci(double metry) {
  if (metry < 1000) return '${metry.round()} m';
  final km = metry / 1000;
  return '${km.toStringAsFixed(km < 10 ? 2 : 1).replaceAll('.', ',')} km';
}

/// „3 h 05 min” albo „45 min”.
String opisCzasu(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')} min';
}
