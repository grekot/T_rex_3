part of 'fake_thermostat_server.dart';

/// Hub (type `hub`, kontrakt pkt 11): urządzenia podrzędne, wykrywanie, automatyki i sceny z `updatedAt`,
/// dziennik, Set `runScene` / `location` / `reload`, `POST /api/time`. Bez prawdziwych Shelly - urządzenia
/// „odpowiadają” od razu, a `host` kończący się na `.99` symuluje urządzenie, które nie odpowiada w 3 s (202).
class FakeHub extends FakeDevice {
  FakeHub({
    super.id = 'hub-51e96c',
    String name = 'Hub',
    super.fw = '0.2.0-fake',
    super.token,
    super.statePeriod,
    super.clock,
    super.log,
    super.random,
  }) : _name = name;

  String _name;
  Map<String, dynamic>? location;
  bool timeKnown = true;
  String timeSource = 'ntp';
  int reloads = 0;

  /// Urządzenia podrzędne (jak `GET /api/devices`).
  final children = <String, Map<String, dynamic>>{};

  /// Wynik następnego wykrywania (`GET /api/discover`).
  List<Map<String, dynamic>> discoverable = [
    {'adapter': 'shelly', 'host': '192.168.1.50', 'id': 'shelly-b12345', 'model': 'Plus1PM', 'type': 'switch'},
    {'adapter': 'tasmota', 'host': '192.168.1.51', 'id': 'tasmota-0a0b0c', 'type': 'switch'},
    {
      'adapter': 'ewelink',
      'host': '192.168.1.52',
      'id': 'ewelink-1000a1b2c3',
      'deviceId': '1000a1b2c3',
      'model': 'strip',
    },
    {
      'adapter': 'ewelink',
      'host': '192.168.1.53',
      'id': 'ewelink-1000d4e5f6',
      'deviceId': '1000d4e5f6',
      'model': 'plug',
    },
  ];

  /// eWeLink: poprawny `devicekey` urządzeń (deviceId → klucz); inny klucz - `error: "key"` jak po nieudanym
  /// odszyfrowaniu ogłoszenia. Brak wpisu = każdy poprawny UUID pasuje.
  final ewelinkKeys = <String, String>{};

  /// Ile odpytań `discover` trwa skan (aplikacja odpytuje co 1 s).
  int discoverPolls = 2;
  int _discoverLeft = -1;

  final automations = <String, Map<String, dynamic>>{};
  final scenes = <String, Map<String, dynamic>>{};
  final logEntries = <Map<String, dynamic>>[];

  /// Aktualizacje własnych węzłów (`GET /api/updates`, pkt 3e): wpisy `{id,fwId,current,available,next,ready,
  /// state,error}`; `next` = co zainstaluje najbliższe zatwierdzenie (wersja pośrednia albo `available`).
  final nodeUpdates = <Map<String, dynamic>>[];

  /// Kiedy hub „sprawdził” manifest (unix, s) i data manifestu.
  int updatesChecked = 1793000000;
  String updatesManifest = '2026-11-02T10:00:00Z';

  /// Jeden krok kolejki (queued → updating → observing → done) co tyle; zero = tylko [advanceUpdates].
  Duration updateStep = Duration.zero;

  /// Węzeł, którego aktualizacja się nie uda (zatrzymuje kolejkę).
  String? failUpdateOf;

  Map<String, dynamic> get _updatesJson => {
    'checked': updatesChecked,
    'manifest': updatesManifest,
    'devices': nodeUpdates,
  };

  /// Ile razy aplikacja kazała sprawdzić manifest od razu.
  int updateChecks = 0;

  /// null = przyjęte; `'type'` / `'value'` - zła lista; mapa id → `unknown|busy|not_ready` (nic nie trafia do kolejki).
  Object? _applyUpdates(Object? ids) {
    if (ids is! List || ids.any((x) => x is! String)) return 'type';
    if (ids.isEmpty) return 'value';
    final errors = <String, String>{};
    for (final id in ids) {
      final e = nodeUpdates.where((u) => u['id'] == id).firstOrNull;
      if (e == null || e['next'] == null) {
        errors[id as String] = 'unknown';
      } else if (const ['queued', 'updating', 'observing'].contains(e['state'])) {
        errors[id as String] = 'busy';
      } else if (e['ready'] != true) {
        errors[id as String] = 'not_ready';
      }
    }
    if (errors.isNotEmpty) return errors;
    for (final e in nodeUpdates) {
      if (ids.contains(e['id'])) {
        e
          ..['state'] = 'queued'
          ..['error'] = null;
      }
    }
    this.log('Aktualizacje węzłów: ${ids.join(', ')}');
    if (updateStep > Duration.zero) _stepLater();
    return null;
  }

  void _stepLater() => Timer(updateStep, () {
    if (advanceUpdates()) _stepLater();
  });

  /// Jeden krok kolejki: pierwszy aktywny wpis przechodzi dalej. false = kolejka pusta albo zatrzymana.
  bool advanceUpdates() {
    final e =
        nodeUpdates.where((u) => const ['updating', 'observing'].contains(u['state'])).firstOrNull ??
        nodeUpdates.where((u) => u['state'] == 'queued').firstOrNull;
    if (e == null) return false;
    switch (e['state']) {
      case 'queued':
        e['state'] = 'updating';
      case 'updating':
        if (e['id'] == failUpdateOf) {
          e
            ..['state'] = 'failed'
            ..['error'] = 'rollback';
          for (final q in nodeUpdates.where((u) => u['state'] == 'queued')) {
            q['state'] = 'idle';
          }
          return false;
        }
        e['state'] = 'observing';
      case 'observing':
        final installed = e['next'] as String;
        e
          ..['state'] = 'done'
          ..['current'] = installed
          // Po wersji pośredniej - drugi krok do zatwierdzenia.
          ..['next'] = installed == e['available'] ? null : e['available'];
    }
    return true;
  }

  /// Id, które hub odrzuca jako błędną regułę (`400 invalid`).
  String? rejectId;

  @override
  String get typeWire => 'hub';

  @override
  String get deviceName => _name;

  @override
  Map<String, dynamic> stateJson() => {
    'id': id,
    'devices': children.length,
    'online': children.values.where((c) => c['online'] == true).length,
    'scenes': scenes.length,
    'automations': automations.length,
    'running': 0,
    'lastRun': logEntries.isEmpty
        ? null
        : {'id': logEntries.first['id'], 'kind': logEntries.first['kind'], 'ok': true, 'at': logEntries.first['ts']},
    'ble': false,
    'link': 'wifi',
    'timeKnown': timeKnown,
    'timeSource': timeKnown ? timeSource : 'none',
    'rtc': false,
    'cloud': cloudHomeId != null,
    'ts': _clock().millisecondsSinceEpoch ~/ 1000,
    'heap': 180000,
    'wifiRssi': -55,
    'uptime': DateTime.now().difference(_started).inSeconds,
  };

  @override
  Map<String, dynamic> configJson() => {'name': _name, 'location': location};

  @override
  Map<String, dynamic> describeJson() => {
    'type': 'hub',
    'points': [
      {'key': 'devices', 'name': 'Urządzenia', 'kind': 'sensor'},
      {'key': 'online', 'name': 'Dostępne', 'kind': 'sensor'},
    ],
  };

  void _logRun(String kind, String id) => logEntries.insert(0, {
    'ts': _clock().millisecondsSinceEpoch,
    'kind': kind,
    'id': id,
    'name': (kind == 'scene' ? scenes[id] : automations[id])?['name'],
    'source': 'app',
    'ok': true,
  });

  @override
  Map<String, String> applySet(Map<String, dynamic> v) {
    final errors = <String, String>{};
    var configChanged = false;
    for (final e in v.entries) {
      switch (e.key) {
        case 'name':
          final x = e.value;
          if (x is! String || x.trim().isEmpty || x.length > 32) {
            errors['name'] = 'length';
          } else {
            _name = x.trim();
            configChanged = true;
          }
        case 'location':
          final x = e.value;
          final lat = x is Map ? x['lat'] : null, lon = x is Map ? x['lon'] : null;
          if (lat is! num || lon is! num) {
            errors['location'] = 'type';
          } else if (lat.abs() > 90 || lon.abs() > 180) {
            errors['location'] = 'range';
          } else {
            location = {'lat': lat, 'lon': lon};
            configChanged = true;
          }
        case 'reload':
          if (e.value == true) reloads++;
        case 'applyUpdates':
          switch (_applyUpdates(e.value)) {
            case final String err:
              errors['applyUpdates'] = err;
            case final Map<String, String> byId:
              for (final x in byId.entries) {
                errors['applyUpdates.${x.key}'] = x.value;
              }
          }
        case 'checkUpdates':
          updateChecks++;
        case 'runScene':
          if (scenes.containsKey(e.value)) {
            _logRun('scene', e.value as String);
          } else {
            errors['runScene'] = 'value';
          }
        default:
          errors[e.key] = 'value';
      }
    }
    this.log('SET ${jsonEncode(v)}${errors.isEmpty ? '' : '  błędy: ${jsonEncode(errors)}'}');
    if (configChanged) _broadcastConfig();
    _broadcastState();
    return errors;
  }

  @override
  void _extraRoutes(Router r) {
    r
      ..get('/api/devices', _auth((req) => _json(children.values.toList())))
      ..get('/api/updates', _auth((req) => _json(_updatesJson)))
      ..post(
        '/api/updates/apply',
        _auth((Request req) async {
          final b = await _body(req);
          return switch (_applyUpdates(b?['devices'])) {
            null => _json({'ok': true}),
            final Map<String, String> byId => _json({'ok': false, 'errors': byId}, status: 409),
            final err => _json({'ok': false, 'error': err == 'type' ? 'json' : 'devices'}, status: 400),
          };
        }, 'config'),
      )
      ..post(
        '/api/updates/check',
        _auth((Request req) {
          updateChecks++;
          return _json({'ok': true});
        }, 'config'),
      )
      ..post('/api/devices', _auth(_addDevice, 'config'))
      ..delete('/api/devices', _auth(_deleteDevice, 'config'))
      ..get('/api/devices/<id>/state', _auth(_childState))
      ..post('/api/devices/<id>/set', _auth(_childSet, 'control'))
      ..get('/api/discover', _auth(_discover, 'config'))
      ..get('/api/automations', _auth(_automationsGet))
      ..get('/api/automations/log', _auth((req) => _json(logEntries.where((e) => e['kind'] != 'scene').toList())))
      ..get('/api/automations/<id>', _auth((req) => _doc(automations, req)))
      ..put('/api/automations/<id>', _auth((req) => _put(automations, req, 'when'), 'config'))
      ..delete('/api/automations/<id>', _auth((req) => _del(automations, req), 'config'))
      ..post('/api/automations/<id>/run', _auth((req) => _run(automations, 'automation', req), 'config'))
      ..get('/api/scenes', _auth((req) => _json({'items': scenes})))
      ..get('/api/scenes/log', _auth((req) => _json(logEntries.where((e) => e['kind'] == 'scene').toList())))
      ..get('/api/scenes/<id>', _auth((req) => _doc(scenes, req)))
      ..put('/api/scenes/<id>', _auth((req) => _put(scenes, req, 'actions'), 'config'))
      ..delete('/api/scenes/<id>', _auth((req) => _del(scenes, req), 'config'))
      ..post('/api/scenes/<id>/run', _auth((req) => _run(scenes, 'scene', req), 'control'))
      ..post('/api/time', _auth(_time, 'config'));
  }

  Future<Response> _addDevice(Request req) async {
    final b = await _body(req);
    if (b == null) return _json({'ok': false, 'error': 'json'}, status: 400);
    final adapter = b['adapter'];
    if (!const ['ownNode', 'shelly', 'sonoffDiy', 'ewelink', 'tasmota', 'tuya'].contains(adapter)) {
      return _json({'ok': false, 'error': 'adapter'}, status: 400);
    }
    if (adapter == 'tuya') return _json({'ok': false, 'error': 'unsupported'}, status: 501);
    final host = b['host'];
    if (host is! String || !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
      return _json({'ok': false, 'error': 'host'}, status: 400);
    }
    if (adapter == 'ownNode') {
      if (b['id'] is! String) return _json({'ok': false, 'error': 'id'}, status: 400);
      final t = b['token'];
      if (t is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(t)) {
        return _json({'ok': false, 'error': 'token'}, status: 400);
      }
    }
    String? keyError;
    if (adapter == 'ewelink') {
      final deviceId = b['deviceId'], key = b['localKey'];
      if (deviceId is! String || deviceId.isEmpty) return _json({'ok': false, 'error': 'deviceId'}, status: 400);
      if (key is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(key)) {
        return _json({'ok': false, 'error': 'localKey'}, status: 400);
      }
      final good = ewelinkKeys[deviceId];
      if (good != null && good.toLowerCase() != key.toLowerCase()) keyError = 'key';
      if (b['id'] is! String) {
        final ch = b['channel'];
        b['id'] = ch is int ? 'ewelink-$deviceId-${ch + 1}' : 'ewelink-$deviceId';
      }
    }
    final existing = b['id'] is String ? children[b['id']] : null;
    if (existing == null && children.length >= 30) {
      return _json({'ok': false, 'error': 'too_many_devices'}, status: 507);
    }
    final last = host.split('.').map(int.parse).skip(1).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final id = b['id'] as String? ?? '$adapter-$last';
    children[id] = {
      'id': id,
      'type': b['type'] ?? 'switch',
      'adapter': adapter,
      'host': host,
      'name': b['name'] ?? id,
      'channel': ?b['channel'],
      'mirror': b['mirror'] != false,
      'linked': false,
      'online': !host.endsWith('.99') && keyError == null,
      'error': ?keyError,
      'deviceId': ?b['deviceId'],
      'model': ?b['model'],
      'state': {'on': false},
    };
    // Wielokanałowe eWeLink: urządzenie znika z wykrywania dopiero po dodaniu (każdy kanał osobno).
    discoverable.removeWhere((d) => d['host'] == host);
    this.log('Hub: dodano $id ($adapter, $host)');
    _broadcastState();
    return _json({'ok': true, 'id': id});
  }

  Response _deleteDevice(Request req) {
    final id = req.url.queryParameters['id'];
    if (children.remove(id) == null) return _json({'ok': false, 'error': 'not_found'}, status: 404);
    _broadcastState();
    return _json({'ok': true});
  }

  Response _childState(Request req) {
    final c = children[req.params['id']];
    if (c == null) return _json({'ok': false, 'error': 'not_found'}, status: 404);
    return _json({...c['state'] as Map, 'online': c['online'], 'cloud': cloudHomeId != null, 'ts': 0});
  }

  Future<Response> _childSet(Request req) async {
    final c = children[req.params['id']];
    if (c == null) return _json({'ok': false, 'error': 'not_found'}, status: 404);
    final b = await _body(req) ?? const {};
    if (c['online'] != true) {
      return _json({
        'ok': false,
        'errors': {'_': 'offline'},
        'state': c['state'],
      }, status: 400);
    }
    if ((c['host'] as String).endsWith('.98')) return _json({'ok': true, 'pending': true}, status: 202);
    final state = c['state'] as Map<String, dynamic>;
    if (b['on'] is bool) state['on'] = b['on'];
    if (b['toggle'] == true) state['on'] = state['on'] != true;
    return _json({'ok': true, 'state': state});
  }

  Response _discover(Request req) {
    if (_discoverLeft < 0) _discoverLeft = discoverPolls;
    final scanning = _discoverLeft > 0;
    if (scanning) {
      _discoverLeft--;
    } else {
      _discoverLeft = -1;
    }
    return _json({'scanning': scanning, 'age': scanning ? null : 0, 'found': scanning ? const [] : discoverable});
  }

  Response _automationsGet(Request req) => _json({
    'items': automations,
    'pendingSync': 0,
    'count': automations.length,
    'enabled': automations.values.where((a) => a['enabled'] != false).length,
    'problems': [
      for (final e in automations.entries)
        if ((e.value['when'] as List?)?.isEmpty ?? true) '${e.key}: when empty',
    ],
    'sunrise': location == null ? null : '06:41',
    'sunset': location == null ? null : '16:32',
    'scenes': scenes.length,
    'timeKnown': timeKnown,
    'timeSource': timeKnown ? timeSource : 'none',
  });

  Response _doc(Map<String, Map<String, dynamic>> docs, Request req) {
    final id = req.params['id']!;
    final d = docs[id];
    return d == null ? _json({'ok': false, 'error': 'not_found'}, status: 404) : _json(d);
  }

  Future<Response> _put(Map<String, Map<String, dynamic>> docs, Request req, String required) async {
    final id = req.params['id']!;
    if (!RegExp(r'^[a-z0-9-]{3,40}$').hasMatch(id)) return _json({'ok': false, 'error': 'id'}, status: 400);
    final b = await _body(req);
    if (b == null) return _json({'ok': false, 'error': 'json'}, status: 400);
    if (b[required] is! List || id == rejectId) {
      return _json({
        'ok': false,
        'error': 'invalid',
        'problems': ['$id: $required'],
      }, status: 400);
    }
    if (!docs.containsKey(id) && docs.length >= 50) return _json({'ok': false, 'error': 'limit'}, status: 507);
    final updatedAt = b['updatedAt'] is num ? b['updatedAt'] as num : _clock().millisecondsSinceEpoch;
    docs[id] = {...b, 'updatedAt': updatedAt};
    _broadcastState();
    return _json({'ok': true, 'updatedAt': updatedAt});
  }

  Response _del(Map<String, Map<String, dynamic>> docs, Request req) {
    if (docs.remove(req.params['id']) == null) return _json({'ok': false, 'error': 'not_found'}, status: 404);
    _broadcastState();
    return _json({'ok': true});
  }

  Response _run(Map<String, Map<String, dynamic>> docs, String kind, Request req) {
    final id = req.params['id']!;
    if (!docs.containsKey(id)) return _json({'ok': false, 'error': 'not_found'}, status: 404);
    _logRun(kind, id);
    _broadcastState();
    return _json({'ok': true});
  }

  Future<Response> _time(Request req) async {
    final b = await _body(req);
    final ts = b?['ts'];
    if (ts is! num || ts < 1700000000) return _json({'ok': false, 'error': 'range'}, status: 400);
    timeKnown = true;
    timeSource = 'manual';
    _broadcastState();
    return _json({'ok': true, 'time': ts, 'timeSource': 'manual'});
  }
}
