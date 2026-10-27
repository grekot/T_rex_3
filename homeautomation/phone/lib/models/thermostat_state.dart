import 'json_utils.dart';

/// Tryb pracy: ręczny albo tygodniowy harmonogram.
enum ThermostatMode {
  manual('manual'),
  auto('auto');

  const ThermostatMode(this.wire);

  /// Wartość w JSON-ie.
  final String wire;

  static ThermostatMode fromWire(String? v) => v == 'auto' ? ThermostatMode.auto : ThermostatMode.manual;
}

/// `outdoor` ze State: pogoda z OpenWeatherMap.
class OutdoorWeather {
  const OutdoorWeather({this.temp, required this.icon, required this.age});

  final double? temp;

  /// Kod ikony pogody (jak w firmware).
  final int icon;

  /// Wiek danych w sekundach.
  final int age;

  factory OutdoorWeather.fromJson(Json j) => OutdoorWeather(
    temp: asDoubleOrNull(j['temp'], 'outdoor.temp'),
    icon: asInt(j['icon'], 'outdoor.icon'),
    age: asInt(j['age'], 'outdoor.age'),
  );

  Json toJson() => {'temp': temp, 'icon': icon, 'age': age};
}

/// Obiekt **State** z pkt 5 kontraktu (tylko do odczytu).
class ThermostatState {
  const ThermostatState({
    required this.id,
    required this.ts,
    required this.temp,
    required this.hum,
    required this.press,
    required this.lux,
    required this.target,
    required this.heating,
    required this.sensorFault,
    required this.power,
    required this.mode,
    required this.override,
    required this.comfortNow,
    required this.nextChange,
    required this.timeKnown,
    required this.night,
    this.protect,
    required this.outdoor,
    required this.wifiRssi,
    required this.cloud,
    required this.uptime,
  });

  final String id;

  /// Czas termostatu (unix, s); 0 = brak czasu.
  final int ts;

  /// °C, null przy awarii czujnika.
  final double? temp;

  /// %, null gdy czujnik nie odpowiada.
  final double? hum;

  /// hPa, null bez BMP280.
  final double? press;

  /// lx, null bez BH1750.
  final double? lux;

  /// Nastawa obowiązująca teraz.
  final double target;

  /// Przekaźnik zwarty.
  final bool heating;

  /// Awaria czujnika - grzanie zablokowane.
  final bool sensorFault;

  /// System włączony (OFF = nie grzeje).
  final bool power;

  final ThermostatMode mode;

  /// AUTO: chwilowe nadpisanie gałką/aplikacją.
  final bool override;

  /// AUTO: okres komfortu wg planu.
  final bool comfortNow;

  /// AUTO: najbliższa granica okresu (`HH:MM`), null = brak.
  final String? nextChange;

  final bool timeKnown;

  /// Ekran w trybie nocnym.
  final bool night;

  /// Ochrona przed zamarzaniem działa teraz: `frost` (OFF, pilnuje `frost.temp`), `faultDuty`
  /// (awaria czujnika, grzanie cykliczne); null = nie.
  final String? protect;

  /// null bez pogody.
  final OutdoorWeather? outdoor;

  final int? wifiRssi;

  /// Połączenie termostatu z Firebase.
  final bool cloud;

  /// Czas pracy w sekundach.
  final int uptime;

  factory ThermostatState.fromJson(Json j) {
    final outdoor = asObjectOrNull(j['outdoor'], 'outdoor');
    return ThermostatState(
      id: asString(j['id'], 'id'),
      ts: asInt(j['ts'], 'ts'),
      temp: asDoubleOrNull(j['temp'], 'temp'),
      hum: asDoubleOrNull(j['hum'], 'hum'),
      press: asDoubleOrNull(j['press'], 'press'),
      lux: asDoubleOrNull(j['lux'], 'lux'),
      target: asDouble(j['target'], 'target'),
      heating: asBool(j['heating'], 'heating'),
      sensorFault: asBool(j['sensorFault'], 'sensorFault'),
      power: asBool(j['power'], 'power', true),
      mode: ThermostatMode.fromWire(asStringOrNull(j['mode'], 'mode')),
      override: asBool(j['override'], 'override'),
      comfortNow: asBool(j['comfortNow'], 'comfortNow'),
      nextChange: asStringOrNull(j['nextChange'], 'nextChange'),
      timeKnown: asBool(j['timeKnown'], 'timeKnown'),
      night: asBool(j['night'], 'night'),
      protect: asStringOrNull(j['protect'], 'protect'),
      outdoor: outdoor == null ? null : OutdoorWeather.fromJson(outdoor),
      wifiRssi: asIntOrNull(j['wifiRssi'], 'wifiRssi'),
      cloud: asBool(j['cloud'], 'cloud'),
      uptime: asInt(j['uptime'], 'uptime'),
    );
  }

  Json toJson() => {
    'id': id,
    'ts': ts,
    'temp': temp,
    'hum': hum,
    'press': press,
    'lux': lux,
    'target': target,
    'heating': heating,
    'sensorFault': sensorFault,
    'power': power,
    'mode': mode.wire,
    'override': override,
    'comfortNow': comfortNow,
    'nextChange': nextChange,
    'timeKnown': timeKnown,
    'night': night,
    'protect': protect,
    'outdoor': outdoor?.toJson(),
    'wifiRssi': wifiRssi,
    'cloud': cloud,
    'uptime': uptime,
  };
}
