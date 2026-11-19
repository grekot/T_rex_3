// Odpowiedź `GET /api/weather/compare` (pkt 11, hub 0.3.43+) do testów: Open-Meteo i MET Norway (MET bez porywów
// i szansy opadu - null).

Map<String, Object?> compareJson(
  DateTime now, {
  String source = 'openmeteo',
  String active = 'openmeteo',
  bool met = true,
}) {
  final start = DateTime(now.year, now.month, now.day, now.hour);
  int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  String day(int i) => start.add(Duration(days: i)).toIso8601String().substring(0, 10);
  Map<String, Object?> src({required double dt, required bool gust, int? next}) => {
    'at': unix(now.subtract(const Duration(minutes: 20))),
    'next': ?next,
    'current': {'temp': 4.0 + dt, 'feels': 1.5, 'hum': 81, 'wind': 14, 'gust': gust ? 30 : null, 'icon': 3, 'mm': 0.0},
    'hourly': [
      for (var i = 0; i < 24; i++)
        [unix(start.add(Duration(hours: i))), 4.0 + i % 4 + dt, i == 5 ? 1.2 : 0.0, gust ? 40 : null, 3],
    ],
    'daily': [
      for (var i = 0; i < 7; i++) [day(i), -2.0 + i + dt, 6.0 + i + dt, 1.0, gust ? 40 : null, 4],
    ],
  };
  return {
    'source': source,
    'active': active,
    'openmeteo': src(dt: 0, gust: true),
    'metno': met ? src(dt: 1, gust: false, next: unix(now.add(const Duration(minutes: 40)))) : null,
  };
}
