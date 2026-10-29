part of 'fake_thermostat_server.dart';

/// Włącznik albo ściemniacz (type `switch` / `dimmer`, kontrakt pkt 10) i przełącznik wielokanałowy z wejściami
/// (pkt 10.1, [channels] > 1: `on1..N`, `in1..M`, `ch1..N`, `input1..M`, jak węzeł `switch4`).
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
    for (var i = 1; i <= channels; i++) <String, Object>{'name': 'Kanał $i', 'defaultOn': 'last'},
  ];

  /// Wejścia: stan (zwarte) i ustawienia; domyślnie przycisk, wejścia k i k+N → kanał k.
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
      <String, Object>{'name': 'Wejście $k', 'mode': 'momentary', 'out': (k - 1) % channels + 1},
  ];

  bool get multi => channels > 1;

  @override
  int get channelCount => channels;

  @override
  int get inputCount => inputs;

  @override
  String get typeWire => dimmable ? 'dimmer' : 'switch';

  @override
  String get deviceName => _name;

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
              {'key': 'on$i', 'name': chCfg[i - 1]['name'], 'kind': 'switch', 'access': 'control', 'channel': i},
            for (var k = 1; k <= inputs; k++)
              {
                'key': 'in$k',
                'name': inCfg[k - 1]['name'],
                'kind': 'status',
                if ((inCfg[k - 1]['out'] as int) > 0) 'channel': inCfg[k - 1]['out'],
              },
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

  /// Przycisk na ścianie (jednokanałowy) albo wejście [k] (wielokanałowy) - jak węzeł lokalnie:
  /// przycisk / łącznik „każda zmiana” przełącza kanał `out`, łącznik „położenie” ustawia go wg wejścia.
  void press([int k = 1]) {
    if (!multi) {
      on = !on;
    } else if (inFault.contains(k)) {
      // zablokowane - nic się nie dzieje
    } else {
      final cfg = inCfg[k - 1];
      final out = cfg['out'] as int;
      final mode = cfg['mode'];
      if (mode == 'momentary') {
        // wciśnięcie i puszczenie
        if (out > 0) chOn[out - 1] = !chOn[out - 1];
      } else {
        inDown[k - 1] = !inDown[k - 1];
        if (out > 0) chOn[out - 1] = mode == 'follow' ? inDown[k - 1] : !chOn[out - 1];
      }
    }
    _broadcastState();
  }

  String? _checkName(Object? name) =>
      name is! String || name.trim().isEmpty || utf8.encode(name.trim()).length > 32 ? 'length' : null;

  /// Kanały: `on`/`toggle` = wszystkie, `onN`, `toggleN`, `chN`, `inputK` (pkt 10.1).
  Map<String, String> _applyChannels(Map<String, dynamic> v) {
    final errors = <String, String>{};
    var configChanged = false;
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
            chOn.fillRange(0, channels, x);
          } else {
            errors[key] = 'type';
          }
        case (null, 'toggle'):
          if (x == true) chOn.fillRange(0, channels, !chOn.contains(true));
        case ('on', _):
          if (x is bool) {
            chOn[n - 1] = x;
          } else {
            errors[key] = 'type';
          }
        case ('toggle', _):
          if (x == true) chOn[n - 1] = !chOn[n - 1];
        case ('ch', _):
          if (x is! Map) {
            errors[key] = 'type';
            continue;
          }
          final cfg = chCfg[n - 1];
          if (x.containsKey('name')) {
            final e = _checkName(x['name']);
            if (e != null) {
              errors['$key.name'] = e;
            } else {
              cfg['name'] = (x['name'] as String).trim();
              configChanged = true;
            }
          }
          if (x.containsKey('defaultOn')) {
            if (const ['last', 'on', 'off'].contains(x['defaultOn'])) {
              cfg['defaultOn'] = x['defaultOn'] as String;
              configChanged = true;
            } else {
              errors['$key.defaultOn'] = 'value';
            }
          }
        case ('input', _):
          if (x is! Map) {
            errors[key] = 'type';
            continue;
          }
          final cfg = inCfg[n - 1];
          if (x.containsKey('name')) {
            final e = _checkName(x['name']);
            if (e != null) {
              errors['$key.name'] = e;
            } else {
              cfg['name'] = (x['name'] as String).trim();
              configChanged = true;
            }
          }
          if (x.containsKey('mode')) {
            if (const ['momentary', 'edge', 'follow'].contains(x['mode'])) {
              cfg['mode'] = x['mode'] as String;
              configChanged = true;
            } else {
              errors['$key.mode'] = 'value';
            }
          }
          if (x.containsKey('out')) {
            final out = x['out'];
            if (out is! int) {
              errors['$key.out'] = 'type';
            } else if (out < 0 || out > channels) {
              errors['$key.out'] = 'range';
            } else {
              cfg['out'] = out;
              configChanged = true;
            }
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
