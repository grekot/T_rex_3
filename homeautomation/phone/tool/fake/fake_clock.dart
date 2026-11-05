part of 'fake_thermostat_server.dart';

/// Zegar-termometr (type `clock`, kontrakt pkt 10.2, `nodes/deskclock`): pokój, pogoda, ekrany, noc, strony
/// z widżetami. Węzeł klasy B - bez własnej chmury (`cloudCapable = false`), parowanie kodem z ekranu.
class FakeClock extends FakeDevice {
  FakeClock({
    super.id = 'zegar-ab12cd',
    String name = 'Biurko',
    super.fw = '0.1.0-fake',
    super.token,
    super.statePeriod,
    super.clock,
    super.log,
    super.random,
    this.lux = false,
    this.warmup = false,
  }) : _name = name {
    cloudCapable = false;
  }

  String _name;

  /// Czujnik światła BH1750 (pole `lux`, tryb nocny `lux|both`).
  final bool lux;
  bool warmup;
  bool sensorFault = false;
  double temp = 21.4, hum = 46, press = 1016;
  String screen = 'main';

  /// Przyciski lewy, środkowy, prawy (`in1`-`in3`).
  final buttons = [false, false, false];

  Map<String, dynamic> screens = {
    'list': ['main', 'hours', 'days', 'chart'],
    'intervalS': 15,
    'mainFactor': 2,
    'transition': 'cards',
  };
  Map<String, dynamic> display = {'brightness': 80, 'auto': true, 'rotation': 0};
  Map<String, dynamic> night = {
    'mode': 'schedule',
    'window': '23:00-06:30',
    'darkLux': 5,
    'brightness': 3,
    'screen': 'clock',
  };
  Map<String, dynamic> clockCfg = {'seconds': false, 'dateFormat': 'long'};
  Map<String, dynamic> units = {'temp': 'C', 'press': 'hPa', 'wind': 'kmh'};
  Map<String, dynamic> weather = {'lat': 49.894, 'lon': 20.609, 'place': 'Kraków'};
  Map<String, dynamic> sensor = {'tempOffset': 0.0, 'humOffset': 0, 'comp': true};
  List<dynamic> pages = [];
  int wantsVer = 1;
  int identifies = 0;

  /// Odczyty od huba (`ext`): para `device/point` → `v`.
  final ext = <String, Object?>{};

  @override
  String get typeWire => 'clock';

  @override
  String get deviceName => _name;

  @override
  Map<String, Object?> get extraInfo => {'fwId': 'deskclock-n16r8'};

  String get _comfort => hum < 35
      ? 'sucho'
      : hum > 60
      ? 'wilgotno'
      : temp < 19
      ? 'chłodno'
      : temp > 25
      ? 'ciepło'
      : 'komfort';

  @override
  Map<String, dynamic> stateJson() => {
    'id': id,
    'ts': _clock().millisecondsSinceEpoch ~/ 1000,
    'temp': warmup || sensorFault ? null : temp,
    'hum': sensorFault ? null : hum,
    'press': press,
    if (lux) 'lux': 120.0,
    'sensorFault': sensorFault,
    'warmup': warmup,
    'outTemp': 9.1,
    'outdoor': {'temp': 9.1, 'icon': 2, 'day': true, 'age': 600},
    'night': false,
    'brightness': display['brightness'],
    'screen': screen,
    'comfort': _comfort,
    for (final (i, b) in buttons.indexed) 'in${i + 1}': b,
    'tempRaw': temp + 1.8,
    'humRaw': hum - 4,
    'chipTemp': 41.0,
    'wantsVer': wantsVer,
    'uptime': 3600,
  };

  @override
  Map<String, dynamic> configJson() => {
    'name': _name,
    'screens': screens,
    'display': display,
    'night': night,
    'clock': clockCfg,
    'units': units,
    'weather': weather,
    'sensor': sensor,
    'pages': pages,
  };

  static const _builtIn = {'main', 'hours', 'days', 'chart', 'calendar', 'air'};
  static const _views = {'value', 'status', 'values', 'level', 'gauge', 'chart', 'thermostat', 'group', 'room', 'hub'};
  static const _commands = {'next', 'prev', 'home', 'wake', 'info'};

  bool _num(Object? v, num min, num max) => v is num && v >= min && v <= max;

  /// Pary z `pages` jak `Wants.cpp` (bez powtórzeń).
  static Set<String> pairsOf(List<dynamic> pages) => {
    for (final p in pages)
      if (p is Map)
        for (final w in (p['widgets'] as List? ?? const []))
          if (w is Map) ...[
            if (w['device'] is String && w['point'] is String) '${w['device']}/${w['point']}',
            if (w['device'] is String)
              for (final k in (w['points'] as List? ?? const [])) '${w['device']}/$k',
            for (final key in ['items', 'series', 'members'])
              for (final i in (w[key] as List? ?? const []))
                if (i is Map) '${i['device']}/${i['point']}',
          ],
  };

  Map<String, String> _pagesErrors(Object? v) {
    if (v is! List) return {'pages': 'type'};
    if (utf8.encode(jsonEncode(v)).length > 6144) return {'pages': 'length'};
    if (v.length > 4 || pairsOf(v).length > 24) return {'pages': 'too_many'};
    final errors = <String, String>{};
    for (final p in v) {
      if (p is! Map || p['id'] is! String) return {'pages': 'value'};
      final widgets = p['widgets'] as List? ?? const [];
      if (widgets.length > 10) return {'pages': 'too_many'};
      for (final w in widgets) {
        final key = 'pages.${p['id']}.${w is Map ? w['id'] : '?'}';
        if (w is! Map || !_views.contains(w['view'])) {
          errors[key] = 'view';
          continue;
        }
        final x = (w['x'] as num?) ?? 0, y = (w['y'] as num?) ?? 0;
        final ww = (w['w'] as num?) ?? 1, hh = (w['h'] as num?) ?? 1;
        if (x < 0 || y < 0 || ww < 1 || hh < 1 || x + ww > 4 || y + hh > 3) errors[key] = 'value';
      }
    }
    return errors;
  }

  @override
  Map<String, String> applySet(Map<String, dynamic> v) {
    final errors = <String, String>{};
    if (v['name'] case final String n) _name = n;
    if (v.containsKey('pages')) {
      final e = _pagesErrors(v['pages']);
      if (e.isEmpty) {
        final before = pairsOf(pages);
        pages = v['pages'] as List;
        if (!before.containsAll(pairsOf(pages)) || !pairsOf(pages).containsAll(before)) wantsVer++;
      } else {
        errors.addAll(e);
      }
    }
    if (v['screens'] case final Map s) {
      final ids = {
        for (final p in pages)
          if (p is Map) 'page:${p['id']}',
      };
      final list = s['list'];
      if (list != null &&
          (list is! List ||
              list.isEmpty ||
              list.length > 6 ||
              list.any((k) => !_builtIn.contains(k) && !ids.contains(k)))) {
        errors['screens.list'] = 'value';
      } else if (s.containsKey('intervalS') && !(s['intervalS'] == 0 || _num(s['intervalS'], 5, 300))) {
        errors['screens.intervalS'] = 'range';
      } else if (s.containsKey('mainFactor') && !_num(s['mainFactor'], 1, 4)) {
        errors['screens.mainFactor'] = 'range';
      } else if (s.containsKey('transition') &&
          !const {'cards', 'slide', 'cover', 'fade', 'none'}.contains(s['transition'])) {
        errors['screens.transition'] = 'value';
      } else {
        screens = {...screens, ...s.cast<String, dynamic>()};
      }
    }
    if (v['display'] case final Map d) {
      if (d.containsKey('brightness') && !_num(d['brightness'], 5, 100)) {
        errors['display.brightness'] = 'range';
      } else if (d.containsKey('rotation') && d['rotation'] != 0 && d['rotation'] != 180) {
        errors['display.rotation'] = 'value';
      } else {
        display = {...display, ...d.cast<String, dynamic>()};
      }
    }
    if (v['night'] case final Map n) {
      final mode = n['mode'];
      if (mode != null && !const {'off', 'schedule', 'lux', 'both'}.contains(mode) ||
          (!lux && (mode == 'lux' || mode == 'both'))) {
        errors['night.mode'] = 'value';
      } else if (n.containsKey('window') && !RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}$').hasMatch('${n['window']}')) {
        errors['night.window'] = 'format';
      } else if (n.containsKey('brightness') && !_num(n['brightness'], 0, 30)) {
        errors['night.brightness'] = 'range';
      } else {
        night = {...night, ...n.cast<String, dynamic>()};
      }
    }
    if (v['clock'] case final Map c) clockCfg = {...clockCfg, ...c.cast<String, dynamic>()};
    if (v['units'] case final Map u) units = {...units, ...u.cast<String, dynamic>()};
    if (v['weather'] case final Map w) {
      if (w.containsKey('lat') && !_num(w['lat'], -90, 90) || w.containsKey('lon') && !_num(w['lon'], -180, 180)) {
        errors['weather'] = 'range';
      } else if (w['place'] is String && utf8.encode(w['place'] as String).length > 32) {
        errors['weather.place'] = 'length';
      } else {
        weather = {...weather, ...w.cast<String, dynamic>()};
      }
    }
    if (v['sensor'] case final Map s) {
      if (s.containsKey('tempOffset') && !_num(s['tempOffset'], -5, 5)) {
        errors['sensor.tempOffset'] = 'range';
      } else if (s.containsKey('humOffset') && !_num(s['humOffset'], -10, 10)) {
        errors['sensor.humOffset'] = 'range';
      } else {
        sensor = {...sensor, ...s.cast<String, dynamic>()};
      }
    }
    if (v['showScreen'] case final String s) {
      final ids = {
        for (final p in pages)
          if (p is Map) 'page:${p['id']}',
      };
      if (_commands.contains(s)) {
        if (s == 'home') screen = 'main';
      } else if (_builtIn.contains(s) || ids.contains(s)) {
        screen = s;
      } else {
        errors['showScreen'] = 'value';
      }
    }
    if (v['identify'] == true) identifies++;
    if (v['ext'] case final List list) {
      for (final e in list) {
        if (e is Map) ext['${e['device']}/${e['point']}'] = e['v'];
      }
    }
    _broadcastState();
    return errors;
  }

  @override
  Map<String, dynamic> describeJson() => {
    'type': 'clock',
    'points': [
      {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1, 'history': 't'},
      {'key': 'hum', 'name': 'Wilgotność', 'kind': 'sensor', 'unit': '%', 'history': 'hum'},
      {'key': 'press', 'name': 'Ciśnienie', 'kind': 'sensor', 'unit': 'hPa', 'min': 960, 'max': 1050},
      {'key': 'outTemp', 'name': 'Na zewnątrz', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
      {'key': 'night', 'name': 'Tryb nocny', 'kind': 'status'},
      {
        'key': 'showScreen',
        'name': 'Pokaż ekran',
        'kind': 'select',
        'options': [..._commands, ...(screens['list'] as List)],
        'access': 'control',
      },
      {'key': 'identify', 'name': 'Pokaż, który to', 'kind': 'action', 'access': 'control'},
      for (final (i, n) in const ['lewy', 'środkowy', 'prawy'].indexed)
        {'key': 'in${i + 1}', 'name': 'Przycisk $n', 'kind': 'status', 'inputKind': 'button'},
      if (lux) {'key': 'lux', 'name': 'Światło', 'kind': 'sensor', 'unit': 'lx'},
    ],
  };

  /// Klawisz `w`: rozgrzewanie wł./wył.; `b`: lewy przycisk wciśnięty / puszczony.
  void toggleWarmup() {
    warmup = !warmup;
    _broadcastState();
  }

  void toggleButton([int i = 0]) {
    buttons[i] = !buttons[i];
    _broadcastState();
  }
}
