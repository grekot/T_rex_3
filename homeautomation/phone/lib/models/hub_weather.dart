// Pogoda w hubie (kontrakt pkt 11 „Pogoda w hubie”): bieżąca z State huba (`weather`), prognoza z `GET /api/weather`
// albo `homes/{h}/devices/{hubId}/weather`. Ikona 1-9 jak termostat (pkt 5).

import 'json_utils.dart';

double? _num(Object? v) => v is num ? v.toDouble() : null;
int? _int(Object? v) => v is num ? v.toInt() : null;

/// Bieżąca pogoda (`weather` w State huba).
class HubWeatherNow {
  const HubWeatherNow({
    this.temp,
    this.feels,
    this.hum,
    this.wind,
    this.gust,
    this.icon,
    this.day = true,
    this.mm,
    this.rain3h,
    this.tMin24h,
    this.place,
    this.age,
  });

  final double? temp;
  final double? feels;
  final int? hum;
  final double? wind;
  final double? gust;
  final int? icon;
  final bool day;
  final double? mm;
  final double? rain3h;
  final double? tMin24h;
  final String? place;

  /// Sekundy od pobrania przez hub.
  final int? age;

  static HubWeatherNow? fromJson(Object? j) {
    if (j is! Map) return null;
    return HubWeatherNow(
      temp: _num(j['temp']),
      feels: _num(j['feels']),
      hum: _int(j['hum']),
      wind: _num(j['wind']),
      gust: _num(j['gust']),
      icon: _int(j['icon']),
      day: j['day'] != false,
      mm: _num(j['mm']),
      rain3h: _num(j['rain3h']),
      tMin24h: _num(j['tMin24h']),
      place: j['place'] is String && (j['place'] as String).isNotEmpty ? j['place'] as String : null,
      age: _int(j['age']),
    );
  }
}

/// Hub obsługuje pogodę (pole `weather` w State, także `null` = wyłączona albo bez położenia).
bool hubHasWeather(Json? hubState) => hubState?.containsKey('weather') ?? false;

typedef HourForecast = ({DateTime ts, double? t, int? icon, int? pp, double? mm});
typedef DayForecast = ({DateTime date, double? tMax, double? tMin, int? icon, int? pp, double? mm});

/// Prognoza: 48 h co godzinę i 7 dni.
class HubForecast {
  const HubForecast({this.place, this.at, this.current, this.hourly = const [], this.daily = const []});

  final String? place;
  final DateTime? at;
  final HubWeatherNow? current;
  final List<HourForecast> hourly;
  final List<DayForecast> daily;

  static DateTime? _time(Object? v) {
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static HubForecast? fromJson(Object? j) {
    if (j is! Map) return null;
    return HubForecast(
      place: j['place'] is String ? j['place'] as String : null,
      at: _time(j['at']),
      current: HubWeatherNow.fromJson(j['current']),
      hourly: [
        for (final h in (j['hourly'] is List ? j['hourly'] as List : const []))
          if (h is Map && _time(h['ts']) != null)
            (ts: _time(h['ts'])!, t: _num(h['t']), icon: _int(h['icon']), pp: _int(h['pp']), mm: _num(h['mm'])),
      ],
      daily: [
        for (final d in (j['daily'] is List ? j['daily'] as List : const []))
          if (d is Map && _time(d['date']) != null)
            (
              date: _time(d['date'])!,
              tMax: _num(d['tMax']),
              tMin: _num(d['tMin']),
              icon: _int(d['icon']),
              pp: _int(d['pp']),
              mm: _num(d['mm']),
            ),
      ],
    );
  }

  /// Godziny od teraz (bez minionych).
  List<HourForecast> hoursFrom(DateTime now) => [
    for (final h in hourly)
      if (!h.ts.isBefore(now.subtract(const Duration(minutes: 59)))) h,
  ];

  /// Dni od dziś.
  List<DayForecast> daysFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (final d in daily)
        if (!DateTime(d.date.year, d.date.month, d.date.day).isBefore(today)) d,
    ];
  }
}

/// Hub ma dane do reguł i kafelków pogody: `weather`, `astro` albo `air` w State (pkt 11).
bool hubHasSky(Json? hubState) =>
    hubState != null && const ['weather', 'astro', 'air'].any(hubState.containsKey);

/// Słońce i księżyc (`astro` w State huba, liczone w hubie z `location`).
class HubAstro {
  const HubAstro({
    this.sunrise,
    this.sunset,
    this.day,
    this.dayDelta,
    this.dawn,
    this.dusk,
    this.moonrise,
    this.moonset,
    this.moonPhase,
    this.moonIllum,
    this.moonName,
    this.fullMoon,
    this.newMoon,
  });

  final String? sunrise;
  final String? sunset;

  /// Długość dnia `9:31`; [dayDelta] - minuty względem wczoraj.
  final String? day;
  final int? dayDelta;
  final String? dawn;
  final String? dusk;
  final String? moonrise;
  final String? moonset;

  /// 0 nów, 0,5 pełnia.
  final double? moonPhase;
  final int? moonIllum;
  final String? moonName;
  final DateTime? fullMoon;
  final DateTime? newMoon;

  static String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;

  static HubAstro? fromJson(Object? j) {
    if (j is! Map) return null;
    return HubAstro(
      sunrise: _s(j['sunrise']),
      sunset: _s(j['sunset']),
      day: _s(j['day']),
      dayDelta: _int(j['dayDelta']),
      dawn: _s(j['dawn']),
      dusk: _s(j['dusk']),
      moonrise: _s(j['moonrise']),
      moonset: _s(j['moonset']),
      moonPhase: _num(j['moonPhase']),
      moonIllum: _int(j['moonIllum']),
      moonName: _s(j['moonName']),
      fullMoon: j['fullMoon'] is String ? DateTime.tryParse(j['fullMoon'] as String) : null,
      newMoon: j['newMoon'] is String ? DateTime.tryParse(j['newMoon'] as String) : null,
    );
  }
}

/// Powietrze, pyłki, UV (`air` w State huba, Open-Meteo Air Quality).
class HubAir {
  const HubAir({
    this.aqi,
    this.aqiLevel,
    this.pm25,
    this.pm10,
    this.uv,
    this.uvMax,
    this.pollen = const {},
    this.pollenLevel,
    this.age,
  });

  /// European AQI.
  final int? aqi;
  final String? aqiLevel;
  final double? pm25;
  final double? pm10;
  final double? uv;
  final double? uvMax;

  /// Ziarna/m³: `alder`, `birch`, `grass`, `mugwort`, `ragweed`.
  final Map<String, double> pollen;

  /// `brak` / `niskie` / `średnie` / `wysokie`.
  final String? pollenLevel;
  final int? age;

  static HubAir? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['pollen'];
    return HubAir(
      aqi: _int(j['aqi']),
      aqiLevel: j['aqiLevel'] is String ? j['aqiLevel'] as String : null,
      pm25: _num(j['pm25']),
      pm10: _num(j['pm10']),
      uv: _num(j['uv']),
      uvMax: _num(j['uvMax']),
      pollen: {
        if (p is Map)
          for (final e in p.entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble(),
      },
      pollenLevel: j['pollenLevel'] is String ? j['pollenLevel'] as String : null,
      age: _int(j['age']),
    );
  }

  /// Pyłek z najwyższym stężeniem (nazwa po polsku) albo null poza sezonem.
  String? get topPollen {
    final top = pollen.entries.where((e) => e.value > 0).fold<MapEntry<String, double>?>(
      null,
      (a, e) => a == null || e.value > a.value ? e : a,
    );
    return top == null ? null : (pollenNames[top.key] ?? top.key);
  }
}

const pollenNames = {
  'alder': 'olcha',
  'birch': 'brzoza',
  'grass': 'trawy',
  'mugwort': 'bylica',
  'ragweed': 'ambrozja',
};
