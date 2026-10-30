part of 'fake_thermostat_server.dart';

/// Włącznik albo ściemniacz (type `switch` / `dimmer`, kontrakt pkt 10) i przełącznik wielokanałowy z wejściami
/// (pkt 10.1, [channels] > 1: `on1..N`, `in1..M`, `ch1..N`, `input1..M`, jak węzeł `switch4` 1.4):
/// wyłączanie po czasie, impulsy, minimalna przerwa, długie naciśnięcie, czujka ruchu, liczniki, przegrzanie.
class FakeLight extends FakeDevice {
  FakeLight({
    super.id = 'swiatlo-0c4f21',
    String name = 'Salon - sufit',
    this.dimmable = false,
    this.channels = 1,
    int? inputs,
    super.fw,
    super.token,
    super.statePeriod,
    super.clock,
    super.log,
    super.random,
  }) : inputs = inputs ?? (channels > 1 ? channels * 2 : 0),
       _name = name;

  /// true = `dimmer` (ma `level`), false = `switch`.
  final bool dimmable;

  final int channels;

  /// Wejścia zwierane do masy (`switch4`: 8).
  final int inputs;
  String _name;
  bool on = false;
  int level = 80;
  String defaultOn = 'last';

  /// Kanały (pkt 10.1): stan i ustawienia.
  late final chOn = List<bool>.filled(channels, false);
  late final chCfg = [
    for (var i = 1; i <= channels; i++)
      <String, Object>{
        'name': 'Kanał $i',
        'defaultOn': 'last',
        'autoOff': 0,
        'autoOffPress': 'off',
        'pulse': 0,
        'minOff': 0,
      },
  ];

  /// Wejścia: stan (aktywne) i ustawienia; domyślnie przycisk, wejścia k i k+N → kanał k.
  late final inDown = List<bool>.filled(inputs, false);

  /// Wejścia z usterką (`inNFault`, ponad 30 zmian w 5 s) - zablokowane.
  final inFault = <int>{};

  /// Symulacja usterki przewodu wejścia [k] (włącza / wyłącza).
  void setInputFault(int k, bool fault) {
    fault ? inFault.add(k) : inFault.remove(k);
    _broadcastState();
  }

  late final inCfg = [
    for (var k = 1; k <= inputs; k++)
      <String, Object>{
        'name': 'Wejście $k',
        'mode': 'momentary',
        'kind': 'button',
        'out': (k - 1) % channels + 1,
        'longOut': 0,
        'invert': false,
      },
  ];

  /// Diody przycisków, % (kanał włączony / wyłączony).
  int indicatorOn = 60, indicatorOff = 5;

  /// Progi temperatury, °C (0 = wyłączone).
  int tempWarn = 60, tempOff = 0;

  /// Temperatura w obudowie (null = brak czujnika DS18B20); zmiana przez [setTemp].
  double? temp = 31.4;
  bool overheat = false, overheatOff = false;

  /// Ile razy przyszło `identify`.
  int identifyCount = 0;
  int wifiReconnects = 0;

  /// Odliczanie: wyłączenie (autoOff / impuls), czekanie na minOff, ostatnie wyłączenie, początek pracy.
  late final _offAt = List<DateTime?>.filled(channels, null);
  late final _waitUntil = List<DateTime?>.filled(channels, null);
  late final _lastOff = List<DateTime?>.filled(channels, null);
  late final _onSince = List<DateTime?>.filled(channels, null);

  /// Liczniki łączeń i godzin pracy (bez bieżącego włączenia).
  late final cycles = List<int>.filled(channels, 0);
  late final _hours = List<double>.filled(channels, 0);
  Timer? _ticker;

  bool get multi => channels > 1;

  @override
  int get channelCount => channels;

  @override
  int get inputCount => inputs;

  @override
  Map<String, Object?> get extraInfo =>
      multi ? {'wifiReconnects': wifiReconnects, 'tempSensor': temp != null} : const {};

  @override
  String get typeWire => dimmable ? 'dimmer' : 'switch';

  @override
  String get deviceName => _name;

  @override
  void _onStop() {
    _ticker?.cancel();
    _ticker = null;
  }

  int _left(DateTime at) => (at.difference(_clock()).inMilliseconds / 1000).ceil().clamp(1, 1 << 30);

  double _hoursOf(int i) {
    final since = _onSince[i];
    final h = _hours[i] + (since == null ? 0 : _clock().difference(since).inSeconds / 3600);
    return (h * 10).round() / 10;
  }

  @override
  Map<String, dynamic> stateJson() => multi
      ? {
          'id': id,
          'ts': _clock().millisecondsSinceEpoch ~/ 1000,
          'channels': channels,
          'inputs': inputs,
          'on': chOn.contains(true),
          for (var i = 0; i < channels; i++) 'on${i + 1}': chOn[i],
          for (var k = 0; k < inputs; k++) 'in${k + 1}': inDown[k],
          for (final k in inFault) 'in${k}Fault': true,
          if (overheat) 'overheat': true,
          if (overheatOff) 'overheatOff': true,
          for (var i = 0; i < channels; i++) ...{
            if (_offAt[i] case final at?) 'ch${i + 1}OffIn': _left(at),
            if (_waitUntil[i] case final at?) 'ch${i + 1}Wait': _left(at),
            'ch${i + 1}Cycles': cycles[i],
            'ch${i + 1}Hours': _hoursOf(i),
          },
          'temp': ?temp,
          'wifiRssi': -60,
          'uptime': DateTime.now().difference(_started).inSeconds,
        }
      : {
          'id': id,
          'ts': _clock().millisecondsSinceEpoch ~/ 1000,
          'on': on,
          if (dimmable) 'level': level,
          'power': on ? (dimmable ? 12.5 * level / 100 : 9.0) : 0.0,
          'wifiRssi': -60,
          'cloud': cloudHomeId != null,
          'uptime': DateTime.now().difference(_started).inSeconds,
        };

  @override
  Map<String, dynamic> configJson() => multi
      ? {
          'name': _name,
          'channels': channels,
          'inputs': inputs,
          'indicator': {'on': indicatorOn, 'off': indicatorOff},
          'tempWarn': tempWarn,
          'tempOff': tempOff,
          for (var i = 0; i < channels; i++) 'ch${i + 1}': {...chCfg[i]},
          for (var k = 0; k < inputs; k++) 'input${k + 1}': {...inCfg[k]},
        }
      : {'name': _name, 'defaultOn': defaultOn};

  @override
  Map<String, dynamic> describeJson() => multi
      ? {
          'type': typeWire,
          'channels': channels,
          'inputs': inputs,
          'points': [
            {'key': 'on', 'name': 'Wszystkie', 'kind': 'switch', 'access': 'control'},
            for (var i = 1; i <= channels; i++)
              {
                'key': 'on$i',
                'name': chCfg[i - 1]['name'],
                'kind': (chCfg[i - 1]['pulse'] as int) > 0 ? 'action' : 'switch',
                'access': 'control',
                'channel': i,
              },
            for (var k = 1; k <= inputs; k++)
              {
                'key': 'in$k',
                'name': inCfg[k - 1]['name'],
                'kind': 'status',
                'inputKind': inCfg[k - 1]['kind'],
                if (_outs(inCfg[k - 1]['out']) case final o when o.length == 1) 'channel': o.single,
                if (_outs(inCfg[k - 1]['out']) case final o when o.length > 1) 'channels': o,
              },
            if (temp != null) ...[
              {'key': 'temp', 'name': 'Temperatura w obudowie', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
              {'key': 'overheat', 'name': 'Przegrzanie', 'kind': 'status'},
            ],
          ],
        }
      : _describeSingle();

  Map<String, dynamic> _describeSingle() => {
    'type': typeWire,
    'points': [
      {'key': 'on', 'name': 'Włączone', 'kind': 'switch', 'access': 'control'},
      if (dimmable)
        {
          'key': 'level',
          'name': 'Jasność',
          'kind': 'setpoint',
          'unit': '%',
          'min': 0,
          'max': 100,
          'step': 5,
          'access': 'control',
        },
      {'key': 'power', 'name': 'Moc', 'kind': 'sensor', 'unit': 'W', 'decimals': 1},
    ],
  };

  /// `out` / `longOut` z Config → lista kanałów.
  static List<int> _outs(Object? v) => switch (v) {
    final int n when n > 0 => [n],
    final List<Object?> l => [for (final x in l) x as int],
    _ => const [],
  };

  // ------------------------------------------------------------ kanały

  /// Włącza / wyłącza kanał [i] (od 0) jak firmware; zwraca kod błędu (`overheat`) albo null.
  String? _setChannel(int i, bool v) {
    final now = _clock();
    if (!v) {
      _waitUntil[i] = null;
      _offAt[i] = null;
      if (chOn[i]) {
        chOn[i] = false;
        _lastOff[i] = now;
        _hours[i] += now.difference(_onSince[i]!).inSeconds / 3600;
        _onSince[i] = null;
      }
      return null;
    }
    if (overheatOff) return 'overheat';
    if (chOn[i] || _waitUntil[i] != null) return null;
    final cfg = chCfg[i];
    final minOff = cfg['minOff'] as int;
    final last = _lastOff[i];
    if ((cfg['pulse'] as int) == 0 && minOff > 0 && last != null) {
      final ready = last.add(Duration(seconds: minOff));
      if (now.isBefore(ready)) {
        _waitUntil[i] = ready;
        _ensureTicker();
        return null;
      }
    }
    _turnOn(i, now);
    return null;
  }

  void _turnOn(int i, DateTime now) {
    final cfg = chCfg[i];
    final pulse = cfg['pulse'] as int, autoOff = cfg['autoOff'] as int;
    chOn[i] = true;
    cycles[i]++;
    _onSince[i] = now;
    _waitUntil[i] = null;
    _offAt[i] = pulse > 0
        ? now.add(Duration(milliseconds: pulse))
        : autoOff > 0
        ? now.add(Duration(seconds: autoOff))
        : null;
    if (_offAt[i] != null) _ensureTicker();
  }

  /// Przełączenie: czekający kanał rezygnuje z czekania.
  String? _toggle(int i) {
    if (_waitUntil[i] != null) {
      _waitUntil[i] = null;
      return null;
    }
    return _setChannel(i, !chOn[i]);
  }

  /// Odlicza od nowa wyłączanie po czasie świecącego kanału.
  void _restartAutoOff(int i) {
    final autoOff = chCfg[i]['autoOff'] as int;
    if (chOn[i] && autoOff > 0) {
      _offAt[i] = _clock().add(Duration(seconds: autoOff));
      _ensureTicker();
    }
  }

  void _ensureTicker() => _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => tickCountdowns());

  /// Krok odliczania (co sekundę, a w testach ręcznie): wyłącza po czasie, włącza po minimalnej przerwie.
  void tickCountdowns() {
    final now = _clock();
    for (var i = 0; i < channels; i++) {
      if (_offAt[i] case final at? when !now.isBefore(at)) _setChannel(i, false);
      if (_waitUntil[i] case final at? when !now.isBefore(at)) {
        overheatOff ? _waitUntil[i] = null : _turnOn(i, now);
      }
    }
    if (!_offAt.any((x) => x != null) && !_waitUntil.any((x) => x != null)) {
      _ticker?.cancel();
      _ticker = null;
    }
    _broadcastState();
  }

  /// Temperatura w obudowie (null = czujnik odłączony): ostrzeżenie z histerezą 3 °C, wyłączenie do spadku o 5 °C.
  void setTemp(double? t) {
    temp = t;
    if (t == null) {
      overheat = overheatOff = false;
    } else {
      overheat = tempWarn > 0 && (overheat ? t > tempWarn - 3 : t >= tempWarn);
      if (tempOff > 0 && !overheatOff && t >= tempOff) {
        overheatOff = true;
        for (var i = 0; i < channels; i++) {
          _setChannel(i, false);
        }
      } else if (overheatOff && (tempOff <= 0 || t <= tempOff - 5)) {
        overheatOff = false;
      }
    }
    _broadcastState();
  }

  /// Przycisk na ścianie (jednokanałowy) albo wejście [k] (wielokanałowy) - jak węzeł lokalnie:
  /// przycisk przełącza kanały `out` (długie naciśnięcie - `longOut`, a przy `autoOffPress: extend` krótkie odlicza
  /// od nowa, długie wyłącza), łącznik „każda zmiana” przełącza, „położenie” ustawia wg wejścia, czujka ruchu włącza.
  void press([int k = 1, bool long = false]) {
    if (!multi) {
      on = !on;
    } else if (inFault.contains(k)) {
      // zablokowane - nic się nie dzieje
    } else {
      final cfg = inCfg[k - 1];
      final outs = _outs(cfg['out']), longOuts = _outs(cfg['longOut']);
      switch (cfg['mode']) {
        case 'momentary' when long && longOuts.isNotEmpty:
          for (final o in longOuts) {
            _toggle(o - 1);
          }
        case 'momentary':
          for (final o in outs) {
            final i = o - 1;
            final extend = chCfg[i]['autoOffPress'] == 'extend' && (chCfg[i]['autoOff'] as int) > 0;
            if (extend && chOn[i]) {
              long ? _setChannel(i, false) : _restartAutoOff(i);
            } else {
              _toggle(i);
            }
          }
        case 'motion':
          for (final o in outs) {
            chOn[o - 1] ? _restartAutoOff(o - 1) : _setChannel(o - 1, true);
          }
        case final mode:
          inDown[k - 1] = !inDown[k - 1];
          for (final o in outs) {
            mode == 'follow' ? _setChannel(o - 1, inDown[k - 1]) : _toggle(o - 1);
          }
      }
    }
    _broadcastState();
  }

  String? _checkName(Object? name) =>
      name is! String || name.trim().isEmpty || utf8.encode(name.trim()).length > 32 ? 'length' : null;

  /// Liczba całkowita w zakresie (albo 0, gdy [zeroOk]); kod błędu albo null.
  static String? _checkInt(Object? x, int min, int max, {bool zeroOk = false}) => x is! int
      ? 'type'
      : (zeroOk && x == 0) || (x >= min && x <= max)
      ? null
      : 'range';

  /// `out` / `longOut` z Set: liczba 0…N albo lista kanałów 1…N → postać do Config (jeden kanał jako liczba).
  (Object?, String?) _parseOuts(Object? x) {
    if (x is int) return x < 0 || x > channels ? (null, 'range') : (x, null);
    if (x is! List || x.any((o) => o is! int)) return (null, 'type');
    final l = ({for (final o in x) o as int}.toList())..sort();
    if (l.any((o) => o < 1 || o > channels)) return (null, 'range');
    return (l.isEmpty ? 0 : (l.length == 1 ? l.single : l), null);
  }

  /// Kanały: `on`/`toggle` = wszystkie, `onN`, `toggleN`, `chN`, `inputK`, `identify`, `indicator`, progi (pkt 10.1).
  Map<String, String> _applyChannels(Map<String, dynamic> v) {
    final errors = <String, String>{};
    var configChanged = false;
    void put(Map<String, Object> cfg, String field, String errKey, Object? value, String? error) {
      if (error != null) {
        errors[errKey] = error;
      } else {
        cfg[field] = value!;
        configChanged = true;
      }
    }

    for (final key in v.keys) {
      final x = v[key];
      final m = RegExp(r'^(on|toggle|ch|input)(\d+)$').firstMatch(key);
      final n = m == null ? 0 : int.parse(m.group(2)!);
      if (m != null && (n < 1 || n > (m.group(1) == 'input' ? inputs : channels))) {
        errors[key] = 'value';
        continue;
      }
      switch ((m?.group(1), key)) {
        case (null, 'on'):
          if (x is bool) {
            for (var i = 0; i < channels; i++) {
              if (_setChannel(i, x) case final e?) errors[key] = e;
            }
          } else {
            errors[key] = 'type';
          }
        case (null, 'toggle'):
          if (x == true) {
            final any = chOn.contains(true);
            for (var i = 0; i < channels; i++) {
              if (_setChannel(i, !any) case final e?) errors[key] = e;
            }
          }
        case ('on', _):
          if (x is bool) {
            if (_setChannel(n - 1, x) case final e?) errors[key] = e;
          } else {
            errors[key] = 'type';
          }
        case ('toggle', _):
          if (x == true) {
            if (_toggle(n - 1) case final e?) errors[key] = e;
          }
        case (null, 'identify'):
          if (x == true) identifyCount++;
        case ('ch', _):
          if (x is! Map) {
            errors[key] = 'type';
            continue;
          }
          final cfg = chCfg[n - 1];
          if (x.containsKey('name')) {
            final e = _checkName(x['name']);
            put(cfg, 'name', '$key.name', e == null ? (x['name'] as String).trim() : null, e);
          }
          if (x.containsKey('defaultOn')) {
            final ok = const ['last', 'on', 'off'].contains(x['defaultOn']);
            put(cfg, 'defaultOn', '$key.defaultOn', x['defaultOn'], ok ? null : 'value');
          }
          if (x.containsKey('autoOff')) {
            put(cfg, 'autoOff', '$key.autoOff', x['autoOff'], _checkInt(x['autoOff'], 0, 86400));
          }
          if (x.containsKey('autoOffPress')) {
            final ok = const ['off', 'extend'].contains(x['autoOffPress']);
            put(cfg, 'autoOffPress', '$key.autoOffPress', x['autoOffPress'], ok ? null : 'value');
          }
          if (x.containsKey('pulse')) {
            put(cfg, 'pulse', '$key.pulse', x['pulse'], _checkInt(x['pulse'], 100, 10000, zeroOk: true));
          }
          if (x.containsKey('minOff')) {
            put(cfg, 'minOff', '$key.minOff', x['minOff'], _checkInt(x['minOff'], 0, 3600));
          }
          if (x['resetCounters'] == true) {
            cycles[n - 1] = 0;
            _hours[n - 1] = 0;
            if (_onSince[n - 1] != null) _onSince[n - 1] = _clock();
          }
        case ('input', _):
          if (x is! Map) {
            errors[key] = 'type';
            continue;
          }
          final cfg = inCfg[n - 1];
          if (x.containsKey('name')) {
            final e = _checkName(x['name']);
            put(cfg, 'name', '$key.name', e == null ? (x['name'] as String).trim() : null, e);
          }
          if (x.containsKey('mode')) {
            final ok = const ['momentary', 'edge', 'follow', 'motion'].contains(x['mode']);
            put(cfg, 'mode', '$key.mode', x['mode'], ok ? null : 'value');
          }
          if (x.containsKey('kind')) {
            final ok = const ['button', 'switch', 'contact', 'motion', 'leak', 'other'].contains(x['kind']);
            put(cfg, 'kind', '$key.kind', x['kind'], ok ? null : 'value');
          }
          for (final f in const ['out', 'longOut']) {
            if (!x.containsKey(f)) continue;
            final (value, e) = _parseOuts(x[f]);
            put(cfg, f, '$key.$f', value, e);
          }
          if (x.containsKey('invert')) {
            if (x['invert'] is! bool) {
              errors['$key.invert'] = 'type';
            } else if (x['invert'] != cfg['invert']) {
              // Ten sam styk, odwrotne znaczenie: „aktywne” się zmienia, kanały nie.
              inDown[n - 1] = !inDown[n - 1];
              put(cfg, 'invert', '$key.invert', x['invert'], null);
            }
          }
        case (null, 'indicator'):
          if (x is! Map) {
            errors[key] = 'type';
            continue;
          }
          for (final f in const ['on', 'off']) {
            if (!x.containsKey(f)) continue;
            final e = _checkInt(x[f], 0, 100);
            if (e != null) {
              errors['indicator.$f'] = e;
            } else {
              f == 'on' ? indicatorOn = x[f] as int : indicatorOff = x[f] as int;
              configChanged = true;
            }
          }
        case (null, 'tempWarn'):
          final e = _checkInt(x, 30, 100, zeroOk: true);
          if (e != null) {
            errors[key] = e;
          } else {
            tempWarn = x as int;
            configChanged = true;
          }
        case (null, 'tempOff'):
          final e = _checkInt(x, 40, 110, zeroOk: true);
          if (e != null) {
            errors[key] = e;
          } else {
            tempOff = x as int;
            configChanged = true;
          }
        case (null, 'name'):
          final e = _checkName(x);
          if (e != null) {
            errors[key] = e;
          } else {
            _name = (x as String).trim();
            configChanged = true;
          }
        default:
          errors[key] = 'value';
      }
    }
    this.log('SET ${jsonEncode(v)}${errors.isEmpty ? '' : '  błędy: ${jsonEncode(errors)}'}');
    if (configChanged) _broadcastConfig();
    _broadcastState();
    return errors;
  }

  @override
  Map<String, String> applySet(Map<String, dynamic> v) {
    if (multi) return _applyChannels(v);
    final errors = <String, String>{};
    var configChanged = false;
    for (final key in v.keys) {
      final x = v[key];
      switch (key) {
        case 'on':
          if (x is bool) {
            on = x;
          } else {
            errors[key] = 'type';
          }
        case 'toggle':
          if (x == true) on = !on;
        case 'level':
          if (!dimmable) {
            errors[key] = 'value';
          } else if (x is! num) {
            errors[key] = 'type';
          } else if (x < 0 || x > 100) {
            errors[key] = 'range';
          } else {
            level = x.round();
            on = level > 0;
          }
        case 'name':
          if (x is! String) {
            errors[key] = 'type';
          } else if (x.trim().isEmpty || x.trim().length > 24) {
            errors[key] = 'length';
          } else {
            _name = x.trim();
            configChanged = true;
          }
        case 'defaultOn':
          if (x == 'last' || x == 'on' || x == 'off') {
            defaultOn = x as String;
            configChanged = true;
          } else {
            errors[key] = 'value';
          }
      }
    }
    this.log('SET ${jsonEncode(v)}${errors.isEmpty ? '' : '  błędy: ${jsonEncode(errors)}'}');
    if (configChanged) _broadcastConfig();
    _broadcastState();
    return errors;
  }
}
