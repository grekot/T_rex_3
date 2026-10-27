// Atrapy urządzeń HomeAutomation zgodne z docs/API.md (v2) - do uruchamiania aplikacji i testów bez sprzętu.
// Czysty Dart (bez Fluttera): działa z `dart run` i z `flutter test`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:homeautomation/models/schedule.dart';
import 'package:homeautomation/models/thermostat_config.dart';
import 'package:homeautomation/models/thermostat_state.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'fake_device.dart';
part 'fake_light.dart';

typedef Clock = DateTime Function();

/// Termostat (type `thermostat`): symulacja temperatury, grzania z histerezą i trybu AUTO.
class FakeThermostat extends FakeDevice {
  FakeThermostat({
    super.id = 'termostat-ab12cd',
    String name = 'Salon',
    super.fw,
    super.token,
    this.simulate = true,
    this.tick = const Duration(seconds: 2),
    super.statePeriod,
    super.clock,
    super.log,
    super.random,
  }) {
    _config = ThermostatConfig(
      name: name,
      comfort: 21.0,
      eco: 18.0,
      hystLow: 0.5,
      hystHigh: 0.2,
      schedule: const ScheduleConfig(
        weekday: '06:00-08:00,15:00-22:00',
        saturday: '07:00-23:00',
        sunday: '07:00-22:00',
      ),
      screen: const ScreenConfig(mode: ScreenMode.always, night: '23:00-06:00', timeoutMin: 2),
      light: const LightSensorConfig(darkLux: 5),
      weather: const WeatherConfig(lat: '49.894', lon: '20.609', apiKeySet: true),
    );
  }

  final bool simulate;
  final Duration tick;
  Timer? _tickTimer;

  late ThermostatConfig _config;
  ThermostatConfig get config => _config;

  // Stan symulacji.
  double temp = 20.6;
  double hum = 45.0;
  bool sensorFault = false;
  bool power = true;
  ThermostatMode mode = ThermostatMode.auto;
  double manualTarget = 21.0;
  bool heating = false;

  // Chwilowe nadpisanie w AUTO: trwa do następnej granicy okresu.
  double? _overrideTarget;
  String? _overrideUntil;

  @override
  String get typeWire => 'thermostat';

  @override
  String get deviceName => _config.name;

  @override
  Map<String, dynamic> stateJson() => currentState().toJson();

  @override
  Map<String, dynamic> configJson() => _config.toJson();

  /// Jak `controlDescribeJson()` w firmware.
  @override
  Map<String, dynamic> describeJson() => {
    'type': 'thermostat',
    'points': [
      {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1, 'history': 't'},
      {'key': 'hum', 'name': 'Wilgotność', 'kind': 'sensor', 'unit': '%', 'decimals': 0},
      {'key': 'press', 'name': 'Ciśnienie', 'kind': 'sensor', 'unit': 'hPa', 'decimals': 0},
      {'key': 'lux', 'name': 'Światło', 'kind': 'sensor', 'unit': 'lx', 'decimals': 0},
      {
        'key': 'target',
        'name': 'Nastawa',
        'kind': 'setpoint',
        'unit': '°C',
        'min': 15,
        'max': 30,
        'step': 0.5,
        'access': 'control',
        'history': 'target',
      },
      {'key': 'heating', 'name': 'Grzanie', 'kind': 'status', 'history': 'heat'},
      {'key': 'sensorFault', 'name': 'Awaria czujnika', 'kind': 'status'},
      {'key': 'power', 'name': 'System', 'kind': 'switch', 'access': 'control'},
      {
        'key': 'mode',
        'name': 'Tryb',
        'kind': 'select',
        'options': ['manual', 'auto'],
        'access': 'control',
      },
      {'key': 'outdoor.temp', 'name': 'Na zewnątrz', 'kind': 'sensor', 'unit': '°C', 'decimals': 1, 'history': 'out'},
    ],
  };

  @override
  void _onStart() {
    if (simulate) _tickTimer = Timer.periodic(tick, (_) => _simulateTick());
  }

  @override
  void _onStop() => _tickTimer?.cancel();

  // ------------------------------------------------------------- logika

  DayPlan _planFor(DateTime t) {
    final s = _config.schedule;
    final raw = t.weekday <= 5 ? s.weekday : (t.weekday == 6 ? s.saturday : s.sunday);
    return DayPlan.tryParse(raw) ?? DayPlan.empty;
  }

  bool _comfortAt(DateTime t) {
    final m = t.hour * 60 + t.minute;
    return _planFor(t).periods.any((p) => p.start.minutes <= m && m < p.end.minutes);
  }

  String? _nextChange(DateTime t) {
    final m = t.hour * 60 + t.minute;
    final today = <int>{
      for (final p in _planFor(t).periods) ...[p.start.minutes, p.end.minutes],
    }.where((b) => b > m && b < 1440).toList()..sort();
    if (today.isNotEmpty) return DayTime(today.first).format();
    final tomorrow = <int>{
      for (final p in _planFor(t.add(const Duration(days: 1))).periods) ...[p.start.minutes, p.end.minutes],
    }.where((b) => b > 0 && b < 1440).toList()..sort();
    return tomorrow.isEmpty ? null : DayTime(tomorrow.first).format();
  }

  bool get _override {
    if (mode != ThermostatMode.auto || _overrideTarget == null) return false;
    // Nadpisanie kończy się na najbliższej granicy okresu.
    if (_nextChange(_clock()) != _overrideUntil) {
      _overrideTarget = null;
      _overrideUntil = null;
      return false;
    }
    return true;
  }

  double get currentTarget {
    if (mode == ThermostatMode.manual) return manualTarget;
    if (_override) return _overrideTarget!;
    return _comfortAt(_clock()) ? _config.comfort : _config.eco;
  }

  ThermostatState currentState() {
    final now = _clock();
    final auto = mode == ThermostatMode.auto;
    return ThermostatState(
      id: id,
      ts: now.millisecondsSinceEpoch ~/ 1000,
      temp: sensorFault ? null : _round1(temp),
      hum: sensorFault ? null : _round1(hum),
      press: 1013.0,
      lux: 120.0,
      target: currentTarget,
      heating: heating,
      sensorFault: sensorFault,
      power: power,
      mode: mode,
      override: auto && _override,
      comfortNow: auto && _comfortAt(now),
      nextChange: auto ? _nextChange(now) : null,
      timeKnown: true,
      night: _inNight(now),
      protect: !power && _config.frost.temp > 0
          ? 'frost'
          : sensorFault && _config.frost.faultDutyMin > 0
          ? 'faultDuty'
          : null,
      outdoor: const OutdoorWeather(temp: 4.2, icon: 69, age: 600),
      wifiRssi: -58,
      cloud: cloudHomeId != null,
      uptime: DateTime.now().difference(_started).inSeconds,
    );
  }

  bool _inNight(DateTime t) {
    final TimePeriod? p;
    try {
      p = NightPeriod.parse(_config.screen.night);
    } on FormatException {
      return false;
    }
    if (p == null) return false;
    final m = t.hour * 60 + t.minute;
    return p.start.minutes < p.end.minutes
        ? m >= p.start.minutes && m < p.end.minutes
        : m >= p.start.minutes || m < p.end.minutes;
  }

  void _updateHeating() {
    if (!power || sensorFault) {
      heating = false;
      return;
    }
    final t = currentTarget;
    if (temp < t - _config.hystLow) heating = true;
    if (temp >= t + _config.hystHigh) heating = false;
  }

  void _simulateTick() {
    final before = jsonEncode(
      currentState().toJson()
        ..remove('ts')
        ..remove('uptime'),
    );
    temp += heating ? 0.05 : -0.03;
    hum = (hum + (_random.nextDouble() - 0.5) * 0.4).clamp(30, 60);
    _updateHeating();
    final after = jsonEncode(
      currentState().toJson()
        ..remove('ts')
        ..remove('uptime'),
    );
    if (before != after) _broadcastState();
  }

  /// Zmiana „z gałki” - jak obrót o jeden ząbek.
  void knob(double delta) {
    applySet({'target': ((currentTarget + delta) * 2).round() / 2});
  }

  void toggleFault() {
    sensorFault = !sensorFault;
    _updateHeating();
    _broadcastState();
  }

  @override
  Map<String, String> applySet(Map<String, dynamic> v) {
    final errors = <String, String>{};
    var c = _config;
    var configChanged = false;

    // Walidacja jak w firmware (src/Control.cpp): liczby z zakresu zaokrąglane do kroku,
    // teksty przycinane z limitem długości, nieznane pola ignorowane.
    double? number(Object? x, String key, double lo, double hi, double step) {
      if (x is! num) {
        errors[key] = 'type';
        return null;
      }
      if (x < lo || x > hi) {
        errors[key] = 'range';
        return null;
      }
      return (x / step).round() * step;
    }

    String? text(Object? x, String key, int maxLen) {
      if (x is! String) {
        errors[key] = 'type';
        return null;
      }
      final t = x.trim();
      if (t.length > maxLen) {
        errors[key] = 'length';
        return null;
      }
      return t;
    }

    for (final key in v.keys) {
      switch (key) {
        case 'power':
          if (v[key] is bool) {
            power = v[key] as bool;
          } else {
            errors[key] = 'type';
          }
        case 'mode':
          if (v[key] == 'manual' || v[key] == 'auto') {
            final m = v[key] == 'auto' ? ThermostatMode.auto : ThermostatMode.manual;
            if (m != mode) {
              if (m == ThermostatMode.manual) manualTarget = currentTarget;
              mode = m;
              _overrideTarget = null;
            }
          } else {
            errors[key] = 'value';
          }
        case 'target':
          final t = number(v[key], key, 15, 30, 0.5);
          if (t != null) {
            if (mode == ThermostatMode.manual) {
              manualTarget = t;
            } else {
              _overrideTarget = t;
              _overrideUntil = _nextChange(_clock());
            }
          }
        case 'name':
          final n = text(v[key], key, 24);
          if (n != null && n.isEmpty) {
            errors[key] = 'length';
          } else if (n != null) {
            c = _copy(c, name: n);
            configChanged = true;
          }
        case 'comfort':
          final t = number(v[key], key, 15, 30, 0.5);
          if (t != null) {
            c = _copy(c, comfort: t);
            configChanged = true;
          }
        case 'eco':
          final t = number(v[key], key, 10, 25, 0.5);
          if (t != null) {
            c = _copy(c, eco: t);
            configChanged = true;
          }
        case 'hystLow' || 'hystHigh':
          final h = number(v[key], key, 0, 1, 0.1);
          if (h != null) {
            final r = (h * 10).round() / 10;
            c = key == 'hystLow' ? _copy(c, hystLow: r) : _copy(c, hystHigh: r);
            configChanged = true;
          }
        case 'schedule':
          final s = v[key];
          if (s is! Map) break;
          var sched = c.schedule;
          for (final day in const ['weekday', 'saturday', 'sunday']) {
            if (!s.containsKey(day)) continue;
            final raw = s[day];
            if (raw is! String) {
              errors['schedule.$day'] = 'type';
              continue;
            }
            final plan = DayPlan.tryParse(raw);
            if (plan == null || plan.validate() != null) {
              errors['schedule.$day'] = 'format';
              continue;
            }
            final f = plan.format();
            sched = ScheduleConfig(
              weekday: day == 'weekday' ? f : sched.weekday,
              saturday: day == 'saturday' ? f : sched.saturday,
              sunday: day == 'sunday' ? f : sched.sunday,
            );
            configChanged = true;
          }
          c = _copy(c, schedule: sched);
        case 'screen':
          final s = v[key];
          if (s is! Map) break;
          var scr = c.screen;
          if (s.containsKey('mode')) {
            if (s['mode'] == 'always' || s['mode'] == 'motion') {
              scr = ScreenConfig(
                mode: ScreenMode.fromWire(s['mode'] as String),
                night: scr.night,
                timeoutMin: scr.timeoutMin,
              );
              configChanged = true;
            } else {
              errors['screen.mode'] = 'value';
            }
          }
          if (s.containsKey('night')) {
            try {
              final raw = s['night'];
              if (raw is! String) throw const FormatException();
              final p = NightPeriod.parse(raw);
              scr = ScreenConfig(mode: scr.mode, night: NightPeriod.format(p), timeoutMin: scr.timeoutMin);
              configChanged = true;
            } on FormatException {
              errors['screen.night'] = 'format';
            }
          }
          if (s.containsKey('timeoutMin')) {
            final t = number(s['timeoutMin'], 'screen.timeoutMin', 1, 30, 1);
            if (t != null) {
              scr = ScreenConfig(mode: scr.mode, night: scr.night, timeoutMin: t.round());
              configChanged = true;
            }
          }
          c = _copy(c, screen: scr);
        case 'light':
          final l = v[key];
          if (l is! Map || !l.containsKey('darkLux')) break;
          final d = number(l['darkLux'], 'light.darkLux', 1, 50, 1);
          if (d != null) {
            c = _copy(c, light: LightSensorConfig(darkLux: d.round()));
            configChanged = true;
          }
        case 'frost':
          final f = v[key];
          if (f is! Map) break;
          var fc = c.frost;
          if (f.containsKey('temp')) {
            final t = number(f['temp'], 'frost.temp', 0, 12, 0.5);
            if (t != null && t != 0 && t < 4) {
              errors['frost.temp'] = 'range';
            } else if (t != null) {
              fc = FrostConfig(temp: t, faultDutyMin: fc.faultDutyMin);
              configChanged = true;
            }
          }
          if (f.containsKey('faultDutyMin')) {
            final d = number(f['faultDutyMin'], 'frost.faultDutyMin', 0, 20, 1);
            if (d != null && d != 0 && d < 5) {
              errors['frost.faultDutyMin'] = 'range';
            } else if (d != null) {
              fc = FrostConfig(temp: fc.temp, faultDutyMin: d.round());
              configChanged = true;
            }
          }
          c = _copy(c, frost: fc);
        case 'weather':
          final w = v[key];
          if (w is! Map) break;
          var wc = c.weather;
          if (w.containsKey('apiKey')) {
            final k = text(w['apiKey'], 'weather.apiKey', 64);
            if (k != null) {
              wc = WeatherConfig(lat: wc.lat, lon: wc.lon, apiKeySet: k.isNotEmpty);
              configChanged = true;
            }
          }
          for (final field in const ['lat', 'lon']) {
            if (!w.containsKey(field)) continue;
            final t = text(w[field], 'weather.$field', 12);
            if (t != null) {
              wc = WeatherConfig(
                lat: field == 'lat' ? t : wc.lat,
                lon: field == 'lon' ? t : wc.lon,
                apiKeySet: wc.apiKeySet,
              );
              configChanged = true;
            }
          }
          c = _copy(c, weather: wc);
      }
    }

    _config = c;
    _updateHeating();
    this.log('SET ${jsonEncode(v)}${errors.isEmpty ? '' : '  błędy: ${jsonEncode(errors)}'}');
    if (configChanged) _broadcastConfig();
    _broadcastState();
    return errors;
  }

  static ThermostatConfig _copy(
    ThermostatConfig c, {
    String? name,
    double? comfort,
    double? eco,
    double? hystLow,
    double? hystHigh,
    ScheduleConfig? schedule,
    ScreenConfig? screen,
    LightSensorConfig? light,
    FrostConfig? frost,
    WeatherConfig? weather,
  }) => ThermostatConfig(
    name: name ?? c.name,
    comfort: comfort ?? c.comfort,
    eco: eco ?? c.eco,
    hystLow: hystLow ?? c.hystLow,
    hystHigh: hystHigh ?? c.hystHigh,
    schedule: schedule ?? c.schedule,
    screen: screen ?? c.screen,
    light: light ?? c.light,
    frost: frost ?? c.frost,
    weather: weather ?? c.weather,
  );

  static double _round1(double x) => (x * 10).round() / 10;
}
