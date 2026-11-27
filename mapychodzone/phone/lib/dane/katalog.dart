/// Katalog paczek map z repozytorium `grekot/mapychodzone-dane` (plik `katalog.json`
/// w każdym wydaniu, budowany przez `narzedzia/katalog.mjs`).
library;

const repozytoriumDanych = 'https://github.com/grekot/mapychodzone-dane';

/// Format paczek, który ta wersja aplikacji umie pokazać (2 = z warstwą punktów i znacznikiem
/// {PUNKTY} w stylu, 3 = do tego poziomice i model terenu do cieniowania, znaczniki {POZIOMICE} i {TEREN}). Starszy katalog na telefonie
/// trzeba zaktualizować.
const wymaganyFormatPaczek = 3;

/// Najnowszy katalog. Pliki paczek pobieramy potem z konkretnego wydania ([Katalog.wydanie]),
/// żeby nowe wydanie opublikowane w trakcie pobierania nie pomieszało plików.
const adresKatalogu = '$repozytoriumDanych/releases/latest/download/katalog.json';

class PlikPaczki {
  const PlikPaczki({required this.plik, required this.rozmiar, required this.sha256});

  final String plik;
  final int rozmiar;
  final String sha256;

  factory PlikPaczki.zJson(Map<String, dynamic> j) => PlikPaczki(
        plik: j['plik'] as String,
        rozmiar: (j['rozmiar'] as num).toInt(),
        sha256: j['sha256'] as String,
      );
}

class RegionPaczki {
  const RegionPaczki({
    required this.id,
    required this.nazwa,
    required this.opis,
    required this.bbox,
    required this.mapa,
    required this.szlaki,
    this.punkty,
    this.poziomice,
    this.teren,
    this.przeszkody,
    required this.rd5,
  });

  final String id;
  final String nazwa;
  final String opis;

  /// [lon_min, lat_min, lon_max, lat_max]
  final List<double> bbox;
  final PlikPaczki mapa;
  final PlikPaczki szlaki;

  /// Szczyty, schroniska, przełęcze… (od formatu 2).
  final PlikPaczki? punkty;

  /// Poziomice (PMTiles z DEM Copernicus GLO-30, od formatu 3).
  final PlikPaczki? poziomice;

  /// Model terenu do cieniowania rzeźby (PMTiles, PNG terrarium, od formatu 3).
  final PlikPaczki? teren;

  /// Przeszkody do trasy na przełaj: urwiska, woda, piargi, parki narodowe (GeoJSON, od formatu 3).
  final PlikPaczki? przeszkody;

  /// Pliki danych tras BRouter (np. `E20_N45`) potrzebne w tym regionie.
  final List<String> rd5;

  /// Pliki regionu z wydania (bez stylu i danych tras, które są wspólne).
  List<PlikPaczki> get pliki => [mapa, szlaki, ?punkty, ?poziomice, ?teren, ?przeszkody];

  double get srodekLon => (bbox[0] + bbox[2]) / 2;
  double get srodekLat => (bbox[1] + bbox[3]) / 2;

  bool zawiera(double lon, double lat) =>
      lon >= bbox[0] && lon <= bbox[2] && lat >= bbox[1] && lat <= bbox[3];

  factory RegionPaczki.zJson(Map<String, dynamic> j) => RegionPaczki(
        id: j['id'] as String,
        nazwa: j['nazwa'] as String,
        opis: (j['opis'] as String?) ?? '',
        bbox: (j['bbox'] as List).map((e) => (e as num).toDouble()).toList(),
        mapa: PlikPaczki.zJson(j['mapa'] as Map<String, dynamic>),
        szlaki: PlikPaczki.zJson(j['szlaki'] as Map<String, dynamic>),
        punkty: j['punkty'] == null ? null : PlikPaczki.zJson(j['punkty'] as Map<String, dynamic>),
        poziomice: j['poziomice'] == null ? null : PlikPaczki.zJson(j['poziomice'] as Map<String, dynamic>),
        teren: j['teren'] == null ? null : PlikPaczki.zJson(j['teren'] as Map<String, dynamic>),
        przeszkody: j['przeszkody'] == null ? null : PlikPaczki.zJson(j['przeszkody'] as Map<String, dynamic>),
        rd5: (j['rd5'] as List).cast<String>(),
      );
}

class Katalog {
  const Katalog({
    required this.wersja,
    this.format = 1,
    required this.wydanie,
    required this.daneOsm,
    required this.styl,
    required this.rd5Zrodlo,
    required this.regiony,
  });

  final int wersja;

  /// Format paczek (patrz [wymaganyFormatPaczek]).
  final int format;

  bool get aktualny => format >= wymaganyFormatPaczek;

  /// Tag wydania w repozytorium danych, np. `dane-2026-11-26`.
  final String wydanie;

  /// Data danych OpenStreetMap (RRRR-MM-DD).
  final String daneOsm;
  final PlikPaczki styl;
  final String rd5Zrodlo;
  final List<RegionPaczki> regiony;

  /// Adres pliku z tego wydania.
  String adres(String plik) => '$repozytoriumDanych/releases/download/$wydanie/$plik';

  /// Adres pliku danych tras BRouter (np. `E20_N45` → …/E20_N45.rd5).
  String adresRd5(String nazwa) => '$rd5Zrodlo$nazwa.rd5';

  RegionPaczki? region(String id) {
    for (final r in regiony) {
      if (r.id == id) return r;
    }
    return null;
  }

  factory Katalog.zJson(Map<String, dynamic> j) {
    final wersja = (j['wersja'] as num).toInt();
    if (wersja != 1) {
      throw FormatException('Nieznana wersja katalogu paczek: $wersja. Zaktualizuj aplikację.');
    }
    final daneOsm = j['daneOsm'] as String;
    return Katalog(
      wersja: wersja,
      format: (j['format'] as num?)?.toInt() ?? 1,
      wydanie: (j['wydanie'] as String?) ?? 'dane-$daneOsm',
      daneOsm: daneOsm,
      styl: PlikPaczki.zJson(j['styl'] as Map<String, dynamic>),
      rd5Zrodlo: j['rd5Zrodlo'] as String,
      regiony: (j['regiony'] as List)
          .map((e) => RegionPaczki.zJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
