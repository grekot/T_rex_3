import 'device_type.dart';
import 'json_utils.dart';
import 'thermostat_config.dart';
import 'thermostat_state.dart';

/// `schedule` w Set: można podać tylko wybrane dni.
class SchedulePatch {
  const SchedulePatch({this.weekday, this.saturday, this.sunday});

  final String? weekday;
  final String? saturday;
  final String? sunday;

  bool get isEmpty => weekday == null && saturday == null && sunday == null;

  factory SchedulePatch.fromJson(Json j) => SchedulePatch(
    weekday: asStringOrNull(j['weekday'], 'schedule.weekday'),
    saturday: asStringOrNull(j['saturday'], 'schedule.saturday'),
    sunday: asStringOrNull(j['sunday'], 'schedule.sunday'),
  );

  Json toJson() {
    final j = <String, dynamic>{};
    putIfNotNull(j, 'weekday', weekday);
    putIfNotNull(j, 'saturday', saturday);
    putIfNotNull(j, 'sunday', sunday);
    return j;
  }
}

class ScreenPatch {
  const ScreenPatch({this.mode, this.night, this.timeoutMin});

  final ScreenMode? mode;
  final String? night;
  final int? timeoutMin;

  bool get isEmpty => mode == null && night == null && timeoutMin == null;

  factory ScreenPatch.fromJson(Json j) {
    final mode = asStringOrNull(j['mode'], 'screen.mode');
    return ScreenPatch(
      mode: mode == null ? null : ScreenMode.fromWire(mode),
      night: asStringOrNull(j['night'], 'screen.night'),
      timeoutMin: asIntOrNull(j['timeoutMin'], 'screen.timeoutMin'),
    );
  }

  Json toJson() {
    final j = <String, dynamic>{};
    putIfNotNull(j, 'mode', mode?.wire);
    putIfNotNull(j, 'night', night);
    putIfNotNull(j, 'timeoutMin', timeoutMin);
    return j;
  }
}

class WeatherPatch {
  const WeatherPatch({this.apiKey, this.lat, this.lon});

  /// Klucz OpenWeatherMap; null = bez zmiany.
  final String? apiKey;
  final String? lat;
  final String? lon;

  bool get isEmpty => apiKey == null && lat == null && lon == null;

  factory WeatherPatch.fromJson(Json j) => WeatherPatch(
    apiKey: asStringOrNull(j['apiKey'], 'weather.apiKey'),
    lat: asStringOrNull(j['lat'], 'weather.lat'),
    lon: asStringOrNull(j['lon'], 'weather.lon'),
  );

  Json toJson() {
    final j = <String, dynamic>{};
    putIfNotNull(j, 'apiKey', apiKey);
    putIfNotNull(j, 'lat', lat);
    putIfNotNull(j, 'lon', lon);
    return j;
  }
}

/// Obiekt **Set** z pkt 7 kontraktu: wszystkie pola opcjonalne,
/// w JSON-ie wysyłamy tylko te, które są ustawione.
class SetValues {
  const SetValues({
    this.power,
    this.target,
    this.mode,
    this.name,
    this.comfort,
    this.eco,
    this.hystLow,
    this.hystHigh,
    this.schedule,
    this.screen,
    this.darkLux,
    this.frostTemp,
    this.frostFaultDutyMin,
    this.weather,
    this.firmwareUrl,
  });

  final bool? power;

  /// MANUAL: nowa nastawa; AUTO: chwilowe nadpisanie do następnej granicy.
  final double? target;
  final ThermostatMode? mode;
  final String? name;
  final double? comfort;
  final double? eco;
  final double? hystLow;
  final double? hystHigh;
  final SchedulePatch? schedule;
  final ScreenPatch? screen;

  /// `light.darkLux`.
  final int? darkLux;

  /// `frost.temp`: 0 albo 4-12 °C.
  final double? frostTemp;

  /// `frost.faultDutyMin`: 0 albo 5-20.
  final int? frostFaultDutyMin;
  final WeatherPatch? weather;

  /// OTA z adresu https (pkt 3a) - termostat sam pobiera plik. Na razie bez UI.
  final String? firmwareUrl;

  bool get isEmpty => toJson().isEmpty;

  factory SetValues.fromJson(Json j) {
    final mode = asStringOrNull(j['mode'], 'mode');
    final schedule = asObjectOrNull(j['schedule'], 'schedule');
    final screen = asObjectOrNull(j['screen'], 'screen');
    final light = asObjectOrNull(j['light'], 'light');
    final frost = asObjectOrNull(j['frost'], 'frost');
    final weather = asObjectOrNull(j['weather'], 'weather');
    return SetValues(
      power: j['power'] == null ? null : asBool(j['power'], 'power'),
      target: asDoubleOrNull(j['target'], 'target'),
      mode: mode == null ? null : ThermostatMode.fromWire(mode),
      name: asStringOrNull(j['name'], 'name'),
      comfort: asDoubleOrNull(j['comfort'], 'comfort'),
      eco: asDoubleOrNull(j['eco'], 'eco'),
      hystLow: asDoubleOrNull(j['hystLow'], 'hystLow'),
      hystHigh: asDoubleOrNull(j['hystHigh'], 'hystHigh'),
      schedule: schedule == null ? null : SchedulePatch.fromJson(schedule),
      screen: screen == null ? null : ScreenPatch.fromJson(screen),
      darkLux: light == null ? null : asIntOrNull(light['darkLux'], 'light.darkLux'),
      frostTemp: frost == null ? null : asDoubleOrNull(frost['temp'], 'frost.temp'),
      frostFaultDutyMin: frost == null ? null : asIntOrNull(frost['faultDutyMin'], 'frost.faultDutyMin'),
      weather: weather == null ? null : WeatherPatch.fromJson(weather),
      firmwareUrl: asStringOrNull(j['firmwareUrl'], 'firmwareUrl'),
    );
  }

  Json toJson() {
    final j = <String, dynamic>{};
    putIfNotNull(j, 'power', power);
    putIfNotNull(j, 'target', target);
    putIfNotNull(j, 'mode', mode?.wire);
    putIfNotNull(j, 'name', name);
    putIfNotNull(j, 'comfort', comfort);
    putIfNotNull(j, 'eco', eco);
    putIfNotNull(j, 'hystLow', hystLow);
    putIfNotNull(j, 'hystHigh', hystHigh);
    if (schedule != null && !schedule!.isEmpty) j['schedule'] = schedule!.toJson();
    if (screen != null && !screen!.isEmpty) j['screen'] = screen!.toJson();
    if (darkLux != null) j['light'] = {'darkLux': darkLux};
    if (frostTemp != null || frostFaultDutyMin != null) {
      j['frost'] = {'temp': ?frostTemp, 'faultDutyMin': ?frostFaultDutyMin};
    }
    if (weather != null && !weather!.isEmpty) j['weather'] = weather!.toJson();
    putIfNotNull(j, 'firmwareUrl', firmwareUrl);
    return j;
  }
}

/// Wynik `POST /api/set` albo `ack` z WebSocketu (każdy typ urządzenia).
/// State/Config są surowe; [state]/[config] to wygodny odczyt dla termostatu.
class SetResult {
  const SetResult({required this.ok, this.errors = const {}, this.error, this.stateJson, this.configJson});

  final bool ok;

  /// Błędy pól, np. `{"schedule.weekday": "format"}`. Pozostałe pola zostały zastosowane.
  /// Kody: `type`, `range`, `format`, `value`, `length`, `json` (pod kluczem `_`).
  final Map<String, String> errors;

  /// Błąd całego polecenia, np. `busy` (nic nie zastosowano).
  final String? error;
  final Json? stateJson;
  final Json? configJson;

  ThermostatState? get state => stateJson == null ? null : ThermostatState.fromJson(stateJson!);
  ThermostatConfig? get config => configJson == null ? null : ThermostatConfig.fromJson(configJson!);

  factory SetResult.fromJson(Json j) => SetResult(
    ok: asBool(j['ok'], 'ok'),
    errors: asErrors(j['errors']),
    error: asStringOrNull(j['error'], 'error'),
    stateJson: asObjectOrNull(j['state'], 'state'),
    configJson: asObjectOrNull(j['config'], 'config'),
  );
}

final thermostatCodec = DeviceCodec<ThermostatState, ThermostatConfig>(
  state: ThermostatState.fromJson,
  config: ThermostatConfig.fromJson,
  nameOf: (c) => c.name,
  stateToJson: (s) => s.toJson(),
);
