// Dwa źródła pogody w hubie (kontrakt pkt 11, hub 0.3.43+): Open-Meteo i MET Norway. Wybór w Config
// `weather.source`, porównanie surowych danych z `GET /api/weather/compare`.

import 'hub_weather.dart';

const weatherSourceOpenMeteo = 'openmeteo';
const weatherSourceMetNo = 'metno';

/// Źródła w kolejności wyświetlania.
const weatherSources = [weatherSourceOpenMeteo, weatherSourceMetNo];

/// Nazwa źródła dla użytkownika.
String weatherSourceName(String? source) => switch (source) {
  weatherSourceMetNo => 'MET Norway (yr.no)',
  weatherSourceOpenMeteo || null => 'Open-Meteo',
  _ => source,
};

double? _num(Object? v) => v is num ? v.toDouble() : null;
int? _int(Object? v) => v is num ? v.toInt() : null;
DateTime? _unix(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;
Object? _at(List<Object?> row, int i) => i < row.length ? row[i] : null;

/// Jedno źródło w porównaniu: pobranie, bieżąca, 24 h i 7 dni (wiersze-tablice z huba).
class CompareSource {
  const CompareSource({this.at, this.next, this.current, this.hourly = const [], this.daily = const []});

  /// Kiedy hub pobrał dane.
  final DateTime? at;

  /// MET: kiedy hub zapyta ponownie.
  final DateTime? next;
  final HubWeatherNow? current;
  final List<HourForecast> hourly;
  final List<DayForecast> daily;

  /// `{"at","next"?,"current"|null,"hourly":[[ts,t,mm,pp,icon]…],"daily":[["YYYY-MM-DD",tMin,tMax,mm,pp,icon]…]}`.
  static CompareSource? fromJson(Object? j) {
    if (j is! Map) return null;
    final hourly = j['hourly'] is List ? j['hourly'] as List : const [];
    final daily = j['daily'] is List ? j['daily'] as List : const [];
    return CompareSource(
      at: _unix(j['at']),
      next: _unix(j['next']),
      current: HubWeatherNow.fromJson(j['current']),
      hourly: [
        for (final h in hourly)
          if (h is List && _unix(_at(h, 0)) != null)
            (
              ts: _unix(_at(h, 0))!,
              t: _num(_at(h, 1)),
              mm: _num(_at(h, 2)),
              pp: _int(_at(h, 3)),
              icon: _int(_at(h, 4)),
            ),
      ],
      daily: [
        for (final d in daily)
          if (d is List && _at(d, 0) is String && DateTime.tryParse(_at(d, 0)! as String) != null)
            (
              date: DateTime.parse(_at(d, 0)! as String),
              tMin: _num(_at(d, 1)),
              tMax: _num(_at(d, 2)),
              mm: _num(_at(d, 3)),
              pp: _int(_at(d, 4)),
              icon: _int(_at(d, 5)),
            ),
      ],
    );
  }

  /// Suma opadu w prognozie godzinowej (mm).
  double get rain24h => hourly.fold(0.0, (a, h) => a + (h.mm ?? 0));
}

/// `GET /api/weather/compare`: wybrane źródło, użyte (zapas) i dane obu.
class WeatherCompare {
  const WeatherCompare({this.source, this.active, this.sources = const {}});

  /// Wybrane w Config.
  final String? source;

  /// Faktycznie użyte (wybrane bez świeżych danych → drugie).
  final String? active;

  /// Dane źródeł; brak klucza = hub nie ma danych z tego źródła.
  final Map<String, CompareSource> sources;

  static WeatherCompare? fromJson(Object? j) {
    if (j is! Map) return null;
    return WeatherCompare(
      source: j['source'] is String ? j['source'] as String : null,
      active: j['active'] is String ? j['active'] as String : null,
      sources: {for (final s in weatherSources) s: ?CompareSource.fromJson(j[s])},
    );
  }
}

/// Różnica temperatur źródeł w tej samej godzinie: średnia i największa (°C); null bez wspólnych godzin.
({double mean, double max})? compareHourlyTemp(CompareSource a, CompareSource b) {
  final byTs = {for (final h in b.hourly) h.ts.millisecondsSinceEpoch: h.t};
  final diffs = <double>[
    for (final h in a.hourly)
      if ((h.t, byTs[h.ts.millisecondsSinceEpoch]) case (final x?, final y?)) (x - y).abs(),
  ];
  if (diffs.isEmpty) return null;
  return (mean: diffs.reduce((x, y) => x + y) / diffs.length, max: diffs.reduce((x, y) => x > y ? x : y));
}
