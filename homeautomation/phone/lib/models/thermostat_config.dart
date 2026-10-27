import 'json_utils.dart';

/// Tryb ekranu: zawsze włączony albo wybudzany ruchem.
enum ScreenMode {
  always('always'),
  motion('motion');

  const ScreenMode(this.wire);

  final String wire;

  static ScreenMode fromWire(String? v) => v == 'motion' ? ScreenMode.motion : ScreenMode.always;
}

/// Harmonogram tygodniowy: 3 plany jako tekst `HH:MM-HH:MM,...` albo `-`.
class ScheduleConfig {
  const ScheduleConfig({required this.weekday, required this.saturday, required this.sunday});

  /// Poniedziałek-piątek.
  final String weekday;
  final String saturday;
  final String sunday;

  factory ScheduleConfig.fromJson(Json j) => ScheduleConfig(
    weekday: asString(j['weekday'], 'schedule.weekday', '-'),
    saturday: asString(j['saturday'], 'schedule.saturday', '-'),
    sunday: asString(j['sunday'], 'schedule.sunday', '-'),
  );

  Json toJson() => {'weekday': weekday, 'saturday': saturday, 'sunday': sunday};
}

class ScreenConfig {
  const ScreenConfig({required this.mode, required this.night, required this.timeoutMin});

  final ScreenMode mode;

  /// Pora nocna `HH:MM-HH:MM` (może przechodzić przez północ), `-` = brak.
  final String night;

  /// Po ilu minutach bez ruchu gasić ekran (tryb `motion`).
  final int timeoutMin;

  factory ScreenConfig.fromJson(Json j) => ScreenConfig(
    mode: ScreenMode.fromWire(asStringOrNull(j['mode'], 'screen.mode')),
    night: asString(j['night'], 'screen.night', '-'),
    timeoutMin: asInt(j['timeoutMin'], 'screen.timeoutMin', 2),
  );

  Json toJson() => {'mode': mode.wire, 'night': night, 'timeoutMin': timeoutMin};
}

class LightSensorConfig {
  const LightSensorConfig({required this.darkLux});

  /// Próg ciemności, 1-50 lx.
  final int darkLux;

  factory LightSensorConfig.fromJson(Json j) => LightSensorConfig(darkLux: asInt(j['darkLux'], 'light.darkLux', 5));

  Json toJson() => {'darkLux': darkLux};
}

/// Ochrona przed zamarzaniem (pkt 6, poziom `config`).
class FrostConfig {
  const FrostConfig({this.temp = 7, this.faultDutyMin = 0});

  /// Najniższa temperatura pilnowana zawsze (także przy OFF); 0 = wyłączona, inaczej 4-12 °C co 0,5.
  final double temp;

  /// Przy awarii czujnika: minut grzania na godzinę (gdy na zewnątrz < 5 °C albo brak pogody); 0 albo 5-20.
  final int faultDutyMin;

  factory FrostConfig.fromJson(Json j) => FrostConfig(
    temp: asDouble(j['temp'], 'frost.temp', 7),
    faultDutyMin: asInt(j['faultDutyMin'], 'frost.faultDutyMin'),
  );

  Json toJson() => {'temp': temp, 'faultDutyMin': faultDutyMin};
}

class WeatherConfig {
  const WeatherConfig({required this.lat, required this.lon, required this.apiKeySet});

  final String lat;
  final String lon;

  /// Klucz OWM jest zapisany (samego klucza termostat nie zwraca).
  final bool apiKeySet;

  factory WeatherConfig.fromJson(Json j) => WeatherConfig(
    lat: asString(j['lat'], 'weather.lat'),
    lon: asString(j['lon'], 'weather.lon'),
    apiKeySet: asBool(j['apiKeySet'], 'weather.apiKeySet'),
  );

  Json toJson() => {'lat': lat, 'lon': lon, 'apiKeySet': apiKeySet};
}

/// Obiekt **Config** z pkt 6 kontraktu (odczyt; zapis przez Set).
class ThermostatConfig {
  const ThermostatConfig({
    required this.name,
    required this.comfort,
    required this.eco,
    required this.hystLow,
    required this.hystHigh,
    required this.schedule,
    required this.screen,
    required this.light,
    this.frost = const FrostConfig(),
    required this.weather,
  });

  final String name;

  /// °C, krok 0,5.
  final double comfort;
  final double eco;

  /// °C, 0,0-1,0, krok 0,1.
  final double hystLow;
  final double hystHigh;

  final ScheduleConfig schedule;
  final ScreenConfig screen;
  final LightSensorConfig light;
  final FrostConfig frost;
  final WeatherConfig weather;

  factory ThermostatConfig.fromJson(Json j) => ThermostatConfig(
    name: asString(j['name'], 'name'),
    comfort: asDouble(j['comfort'], 'comfort', 21),
    eco: asDouble(j['eco'], 'eco', 18),
    hystLow: asDouble(j['hystLow'], 'hystLow', 0.5),
    hystHigh: asDouble(j['hystHigh'], 'hystHigh', 0.2),
    schedule: ScheduleConfig.fromJson(asObjectOrNull(j['schedule'], 'schedule') ?? const {}),
    screen: ScreenConfig.fromJson(asObjectOrNull(j['screen'], 'screen') ?? const {}),
    light: LightSensorConfig.fromJson(asObjectOrNull(j['light'], 'light') ?? const {}),
    frost: FrostConfig.fromJson(asObjectOrNull(j['frost'], 'frost') ?? const {}),
    weather: WeatherConfig.fromJson(asObjectOrNull(j['weather'], 'weather') ?? const {}),
  );

  Json toJson() => {
    'name': name,
    'comfort': comfort,
    'eco': eco,
    'hystLow': hystLow,
    'hystHigh': hystHigh,
    'schedule': schedule.toJson(),
    'screen': screen.toJson(),
    'light': light.toJson(),
    'frost': frost.toJson(),
    'weather': weather.toJson(),
  };
}
