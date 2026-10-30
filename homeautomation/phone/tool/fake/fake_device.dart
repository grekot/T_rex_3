part of 'fake_thermostat_server.dart';

/// Wspólna część atrap urządzeń HomeAutomation (kontrakt v2): /api/info z `type`, parowanie kodem,
/// token, /api/state|config|set, /ws, /api/wifi/reset, /api/cloud, /api/ota.
abstract class FakeDevice {
  FakeDevice({
    required this.id,
    this.fw = '2.1.0-fake',
    String? token,
    this.statePeriod = const Duration(seconds: 30),
    Clock? clock,
    this.log = _noLog,
    Random? random,
  }) : _random = random ?? Random(),
       _clock = clock ?? DateTime.now {
    this.token = token ?? _hex(32);
    // Telefon, który „skonfigurował” atrapę - pełny dostęp, jak po ha-pair.
    phones.add(FakePhone(this.token, 'Atrapa', '', 'config', true));
  }

  static void _noLog(String _) {}

  /// `type` w /api/info, TXT mDNS i chmurze.
  String get typeWire;

  /// Nazwa z Config.
  String get deviceName;

  Map<String, dynamic> stateJson();

  Map<String, dynamic> configJson();

  /// Stosuje Set jak firmware: błędne pola trafiają do wyniku, poprawne są stosowane.
  Map<String, String> applySet(Map<String, dynamic> v);

  /// Opis punktów danych (pkt 14).
  Map<String, dynamic> describeJson();

  /// Start/stop symulacji danego typu.
  void _onStart() {}

  void _onStop() {}

  final String id;

  /// Wersja oprogramowania; zmienia się po udanym OTA.
  String fw;
  late final String _baseFw = fw;

  /// OTA: stan dla `GET /api/ota`, opóźnienie na kawałek (postęp widać w UI) i czas „restartu”.
  Map<String, Object?> _ota = {'state': 'idle', 'progress': 0};
  Duration otaDelay = const Duration(milliseconds: 20);
  Duration otaRestart = const Duration(seconds: 3);
  int otaCount = 0;
  final Duration statePeriod;
  final void Function(String) log;
  final Random _random;
  final Clock _clock;

  /// Token urządzenia (jeden dla wszystkich telefonów, jak w firmware).
  late String token;

  /// Sparowane telefony - każdy z własnym tokenem i poziomem (pkt 2, 12); najwyżej 16.
  final phones = <FakePhone>[];

  /// Jak długo „trwa” sprawdzanie `idToken` w Google po parowaniu kodem.
  Duration idTokenDelay = const Duration(seconds: 1);

  /// Atrapa nie pyta Google: `idToken` w postaci `fake:<uid>:<poziom>` daje ten poziom, inny - `control`.
  (String, String) Function(String idToken) verifyIdToken = _fakeVerify;

  static (String, String) _fakeVerify(String t) {
    final p = t.split(':');
    return p.length == 3 && p[0] == 'fake' ? (p[1], p[2]) : ('uid-z-tokenu', 'control');
  }

  FakePhone? _phone(Request req) {
    final auth = req.headers['authorization'];
    final t = auth != null && auth.startsWith('Bearer ') ? auth.substring(7) : req.url.queryParameters['token'];
    return phones.where((p) => p.token == t).firstOrNull;
  }

  static const _levels = ['view', 'control', 'config'];
  static int _rank(String level) => _levels.indexOf(level);

  /// Pola, które wolno zmieniać z poziomem `control` (jak CONTROL_KEYS w firmware + światła).
  static const controlKeys = {'power', 'target', 'mode', 'on', 'level', 'toggle', 'identify'};

  /// Pola ponad poziom telefonu → `forbidden`, reszta idzie do [applySet] (jak firmware Control.cpp).
  Map<String, String> _applyAs(String level, Map<String, dynamic> v) {
    final errors = <String, String>{};
    final allowed = <String, dynamic>{};
    if (level == 'config' && v.containsKey('firmwareUrl')) {
      errors.addAll(_firmwareUrl(v['firmwareUrl'], v['firmwareSha256']));
      v = {...v}
        ..remove('firmwareUrl')
        ..remove('firmwareSha256');
    }
    for (final e in v.entries) {
      if (e.key == 'notify' && level == 'config') {
        errors.addAll(_applyNotify(e.value));
        continue;
      }
      final ok =
          level == 'config' ||
          (level == 'control' && (controlKeys.contains(e.key) || RegExp(r'^(on|toggle)\d+$').hasMatch(e.key)));
      if (ok) {
        allowed[e.key] = e.value;
      } else {
        errors[e.key] = 'forbidden';
      }
    }
    return {...errors, ...applySet(allowed)};
  }

  /// Wariant firmware w `/api/info` (pkt 3e); null = starszy firmware bez `fwId`.
  late String? fwId = switch (typeWire) {
    'thermostat' => 'thermostat-n16r8',
    'hub' => 'hub-n16r8',
    'switch' || 'dimmer' => 'switch4-s2mini',
    _ => null,
  };

  /// Adresy z Set `firmwareUrl` (pkt 3a / 3e) - atrapa nic nie pobiera, tylko udaje postęp i restart.
  final firmwareUrls = <String>[];

  /// Kolejne Set `firmwareUrl` kończą się błędem `sha256` (jak plik niezgodny z sumą).
  bool firmwareSha256Mismatch = false;

  Map<String, String> _firmwareUrl(Object? url, Object? sha) {
    if (url is! String || !url.startsWith('https://')) return {'firmwareUrl': 'format'};
    if (sha != null && (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha))) {
      return {'firmwareSha256': 'format'};
    }
    if (_ota['state'] == 'running') return {'firmwareUrl': 'busy'};
    firmwareUrls.add(url);
    final version = RegExp(r'-(\d+\.\d+\.\d+)\.bin$').firstMatch(url)?.group(1);
    unawaited(_download(version));
    return const {};
  }

  /// „Pobieranie” w 4 krokach co [otaDelay], potem restart po [otaRestart] z nową wersją.
  Future<void> _download(String? version) async {
    for (var p = 0; p <= 100; p += 25) {
      _ota = {'state': 'running', 'progress': p};
      await Future<void>.delayed(otaDelay);
    }
    if (firmwareSha256Mismatch) {
      _ota = {'state': 'error', 'progress': 0, 'error': 'sha256'};
      return;
    }
    _ota = {'state': 'done', 'progress': 100};
    otaCount++;
    this.log('OTA z adresu: pobrano, restart');
    Timer(otaRestart, () {
      fw = version ?? '$_baseFw+ota$otaCount';
      _ota = {'state': 'idle', 'progress': 0};
      for (final c in _clients.toList()) {
        c.sink.close();
      }
      this.log('OTA: „restart” - nowa wersja $fw');
    });
  }

  /// Powiadomienia ntfy (pkt 3d) - wspólne dla wszystkich typów; próbne tylko liczone w [notifyTests].
  bool notifyEnabled = false;
  String notifyServer = 'https://ntfy.sh';
  late String notifyTopic = 'ha-${_hex(8)}';
  String? notifyToken;
  int notifyTests = 0;

  Map<String, dynamic> get _notifyJson => {
    'enabled': notifyEnabled,
    'ntfyServer': notifyServer,
    'ntfyTopic': notifyTopic,
    'ntfyTokenSet': notifyToken != null,
  };

  /// Config typu + `notify`.
  Map<String, dynamic> _fullConfig() => {...configJson(), 'notify': _notifyJson};

  Map<String, String> _applyNotify(Object? v) {
    if (v is! Map) return {'notify': 'type'};
    final errors = <String, String>{};
    final enabled = v['enabled'], topic = v['ntfyTopic'], token = v['ntfyToken'], server = v['ntfyServer'];
    if (enabled != null && enabled is! bool) errors['notify.enabled'] = 'type';
    if (topic != null &&
        (topic is! String || (topic.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(topic)))) {
      errors['notify.ntfyTopic'] = topic is String ? 'format' : 'type';
    }
    if (token != null && (token is! String || token.length > 128)) {
      errors['notify.ntfyToken'] = token is String ? 'length' : 'type';
    }
    if (server != null && (server is! String || (server.isNotEmpty && !server.startsWith('https://')))) {
      errors['notify.ntfyServer'] = server is String ? 'format' : 'type';
    }
    if (errors.isNotEmpty) return errors;
    if (enabled is bool) notifyEnabled = enabled;
    if (topic is String) notifyTopic = topic.isEmpty ? 'ha-${_hex(8)}' : topic;
    if (token is String) notifyToken = token.isEmpty ? null : token;
    if (server is String) notifyServer = server.isEmpty ? 'https://ntfy.sh' : server;
    if (v['test'] == true && notifyEnabled) {
      notifyTests++;
      this.log('ntfy: próbne powiadomienie na $notifyServer/$notifyTopic');
    }
    _broadcastConfig();
    return const {};
  }

  bool _paired = false;

  /// Ile razy wywołano `POST /api/wifi/reset`.
  int wifiResets = 0;

  /// Dom, z którym atrapa jest połączona w chmurze (null = niepołączona).
  String? cloudHomeId;

  /// Czy aplikacja przypisała konto urządzenia do domu (`homes/{h}/deviceAccounts`); null = od razu.
  bool Function(String deviceUid)? cloudBound;

  /// Jak długo atrapa „zakłada konto” po `POST /api/cloud`.
  Duration cloudLinkDelay = const Duration(seconds: 2);
  Map<String, Object?> _cloudStatus = {'status': 'none'};
  Timer? _cloudTimer;

  /// Symulacja zajętego urządzenia: `set` dostaje 503 / ack z `error: busy`.
  bool busy = false;
  final DateTime _started = DateTime.now();

  // Parowanie.
  String? _pairCode;
  DateTime? _pairExpires;
  int _pairAttempts = 0;

  /// Po 3 złych kodach `POST /api/pair/start` przez 60 s zwraca `429 locked`.
  DateTime? _pairLockedUntil;

  /// Kod widoczny „na OLED-zie” (null poza parowaniem).
  String? get pairCode => _pairCode;

  /// Urządzenie bez ekranu: kodem parowania jest PoP z naklejki (`"pair":"pop"`, pkt 2).
  String? pop;

  /// Bez Bluetooth - konfiguracja przez SoftAP (`"prov":"softap"`, pkt 9.4).
  bool softAp = false;

  /// `false` = węzeł klasy B (`"cloud":false`, bez `/api/cloud`).
  bool cloudCapable = true;

  /// Liczba kanałów i wejść w `/api/info` (pkt 10.1).
  int get channelCount => 1;
  int get inputCount => 0;

  /// Dodatkowe pola `/api/info` danego typu (np. `wifiReconnects`, `tempSensor` przełącznika, pkt 10.1).
  Map<String, Object?> get extraInfo => const {};

  HttpServer? _server;
  Timer? _periodicTimer;
  final _clients = <WebSocketChannel>{};

  int get port => _server!.port;
  int get clientCount => _clients.length;

  Future<void> start({int port = 8080, InternetAddress? address}) async {
    final handler = const Pipeline().addMiddleware(_cors()).addHandler(_router().call);
    _server = await shelf_io.serve(handler, address ?? InternetAddress.anyIPv4, port);
    _onStart();
    _periodicTimer = Timer.periodic(statePeriod, (_) => _broadcastState());
  }

  Future<void> stop() async {
    _cloudTimer?.cancel();
    _onStop();
    _periodicTimer?.cancel();
    for (final c in _clients.toList()) {
      await c.sink.close();
    }
    await _server?.close(force: true);
  }

  // ---------------------------------------------------------------- HTTP

  Router _router() {
    final r = Router()
      ..get(
        '/api/info',
        (Request req) => _json({
          'id': id,
          'type': typeWire,
          'name': deviceName,
          'fw': fw,
          'fwId': ?fwId,
          'api': 2,
          'paired': _paired || phones.length > 1,
          if (softAp) 'prov': 'softap',
          if (pop != null) 'pair': 'pop',
          if (!cloudCapable) 'cloud': false,
          if (channelCount > 1) 'channels': channelCount,
          if (inputCount > 0) 'inputs': inputCount,
          ...extraInfo,
        }),
      )
      ..post('/api/pair/start', _pairStart)
      ..post('/api/pair/confirm', _pairConfirm)
      ..get('/api/state', _auth((req) => _json(stateJson())))
      ..get('/api/config', _auth((req) => _json(_fullConfig())))
      ..post('/api/set', _auth(_httpSet))
      ..get('/api/describe', _auth((req) => _json(describeJson())))
      ..get('/api/me', _auth(_me))
      ..get('/api/clients', _auth(_clientsGet, 'config'))
      ..delete('/api/clients', _auth(_clientsDelete, 'config'))
      ..patch('/api/clients', _auth(_clientsPatch, 'config'))
      ..post('/api/clients', _auth(_clientsPost, 'config'))
      ..post('/api/wifi/reset', _auth(_wifiReset, 'config'))
      ..post('/api/cloud', _auth(_cloud, 'config'))
      ..get('/api/cloud', _auth(_cloudGet, 'config'))
      ..post('/api/ota', _auth(_otaPost, 'config'))
      ..get('/api/ota', _auth((req) => _json(_ota)))
      ..get('/ws', _ws);
    _extraRoutes(r);
    return r;
  }

  /// Dodatkowe API danego typu (hub, pkt 11).
  void _extraRoutes(Router r) {}

  Middleware _cors() =>
      (inner) => (req) async {
        // Dla podglądu aplikacji w przeglądarce (flutter run -d chrome).
        const headers = {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        };
        if (req.method == 'OPTIONS') return Response.ok('', headers: headers);
        final res = await inner(req);
        return res.change(headers: headers);
      };

  /// Token telefonu (401) i poziom (403 `forbidden`) - pkt 3.
  Handler _auth(FutureOr<Response> Function(Request) h, [String level = 'view']) => (req) {
    final phone = _phone(req);
    if (phone == null) return _json({'ok': false, 'error': 'unauthorized'}, status: 401);
    if (_rank(phone.access) < _rank(level)) return _json({'ok': false, 'error': 'forbidden'}, status: 403);
    return h(req);
  };

  Response _me(Request req) {
    final p = _phone(req)!;
    return _json({'id': p.token.substring(0, 8), 'uid': p.uid, 'access': p.access});
  }

  Response _clientsGet(Request req) => _json([for (final p in phones) p.toJson()]);

  Response _clientsDelete(Request req) {
    final id = req.url.queryParameters['id'] ?? '';
    final before = phones.length;
    phones.removeWhere((p) => p.token.startsWith(id) && id.length == 8);
    if (phones.length == before) return _json({'ok': false, 'error': 'not_found'}, status: 404);
    this.log('Telefon $id usunięty');
    return _json({'ok': true});
  }

  /// `PATCH /api/clients {"id","access"}` - ręczna zmiana poziomu.
  Future<Response> _clientsPatch(Request req) async {
    final body = await _body(req);
    final id = body?['id'], access = body?['access'];
    if (id is! String || !const ['view', 'control', 'config'].contains(access)) {
      return _json({'ok': false, 'error': 'fields'}, status: 400);
    }
    final p = phones.where((p) => p.token.startsWith(id) && id.length == 8).firstOrNull;
    if (p == null) return _json({'ok': false, 'error': 'not_found'}, status: 404);
    p.access = access as String;
    this.log('Telefon $id: poziom $access');
    return _json({'ok': true});
  }

  /// `POST /api/clients {"name","access"}` - token bez parowania (hub, skrypt).
  Future<Response> _clientsPost(Request req) async {
    final body = await _body(req);
    final name = body?['name'], access = body?['access'];
    if (name is! String || name.isEmpty || !const ['view', 'control', 'config'].contains(access)) {
      return _json({'ok': false, 'error': 'fields'}, status: 400);
    }
    if (phones.length >= 16) return _json({'ok': false, 'error': 'too_many_clients'}, status: 507);
    final t = addPhone(name, access: access as String, verified: false);
    return _json({'ok': true, 'id': t.substring(0, 8), 'token': t, 'access': access});
  }

  /// Telefon z Bluetooth (`ha-pair`): pełny dostęp, tożsamość potwierdzona.
  String addPhone(String name, {String uid = '', String access = 'config', bool verified = true}) {
    final t = _hex(32);
    phones.add(FakePhone(t, name, uid, access, verified));
    return t;
  }

  Response _json(Object body, {int status = 200}) =>
      Response(status, body: jsonEncode(body), headers: {'Content-Type': 'application/json; charset=utf-8'});

  Future<Map<String, dynamic>?> _body(Request req) async {
    try {
      final v = jsonDecode(await req.readAsString());
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  Response _pairStart(Request req) {
    final locked = _pairLockedUntil;
    if (locked != null && _clock().isBefore(locked)) {
      final left = locked.difference(_clock()).inSeconds + 1;
      return _json({'ok': false, 'error': 'locked', 'retryIn': left}, status: 429);
    }
    _pairCode = pop ?? (_random.nextInt(900000) + 100000).toString();
    _pairExpires = _clock().add(const Duration(seconds: 120));
    _pairAttempts = 0;
    if (pop != null) {
      log('Parowanie: kod = PoP z naklejki ($pop)');
      return _json({'ok': true, 'expiresIn': 120, 'pair': 'pop'});
    }
    log('');
    log('  ┌──────────────────────┐');
    log('  │ OLED:  PAROWANIE     │');
    log('  │        $_pairCode        │');
    log('  └──────────────────────┘');
    return _json({'ok': true, 'expiresIn': 120});
  }

  // Odpowiedzi jak w firmware (src/LocalApi.cpp): 400 json, 409 not_pairing, 403 bad_code + attemptsLeft.
  Future<Response> _pairConfirm(Request req) async {
    final body = await _body(req);
    if (body == null) return _json({'ok': false, 'error': 'json'}, status: 400);
    if (_pairCode == null || _clock().isAfter(_pairExpires!)) {
      _pairCode = null;
      return _json({'ok': false, 'error': 'not_pairing'}, status: 409);
    }
    final code = body['code'];
    final match = pop != null ? code is String && code.toLowerCase() == _pairCode : code == _pairCode;
    if (!match) {
      final left = 3 - ++_pairAttempts;
      if (left <= 0) {
        _pairCode = null;
        _pairLockedUntil = _clock().add(const Duration(seconds: 60));
        log('Parowanie przerwane: 3 błędne próby.');
      }
      return _json({'ok': false, 'error': 'bad_code', 'attemptsLeft': left < 0 ? 0 : left}, status: 403);
    }
    _pairCode = null;
    if (phones.length >= 16) return _json({'ok': false, 'error': 'too_many_clients'}, status: 507);
    _paired = true;
    final client = body['client'] is String ? body['client'] as String : 'telefon';
    // Własny token telefonu; `view`, dopóki „Google” nie potwierdzi idToken (pkt 2).
    // Węzeł bez chmury nie sprawdzi idToken - nowy telefon dostaje `control`.
    final noCloud = !cloudCapable;
    final phone = FakePhone(_hex(32), client, '', noCloud ? 'control' : 'view', false);
    phones.add(phone);
    final idToken = noCloud ? null : body['idToken'];
    if (idToken is String && idToken.isNotEmpty) {
      Timer(idTokenDelay, () {
        final (uid, level) = verifyIdToken(idToken);
        phone
          ..uid = uid
          ..access = level
          ..verified = true;
        this.log('Telefon $client potwierdzony: $uid → $level');
      });
    }
    this.log('Sparowano: $client');
    return _json({
      'ok': true,
      'token': phone.token,
      'id': id,
      'access': phone.access,
      'pending': idToken is String && idToken.isNotEmpty,
    });
  }

  /// 200 przy sukcesie, 400 przy błędach pól (także ze `state` i `config`), 503 `busy`.
  Future<Response> _httpSet(Request req) async {
    if (busy) return _json({'ok': false, 'error': 'busy'}, status: 503);
    final body = await _body(req);
    final errors = body == null ? {'_': 'json'} : _applyAs(_phone(req)!.access, body);
    return _json({
      'ok': errors.isEmpty,
      'errors': errors,
      'state': stateJson(),
      'config': _fullConfig(),
    }, status: errors.isEmpty ? 200 : 400);
  }

  /// `POST /api/wifi/reset` (pkt 9.3): po ~1 s „restart” w trybie konfiguracji Bluetooth -
  /// atrapa nie ma BLE, więc tylko zamyka WebSockety i to odnotowuje.
  Response _wifiReset(Request req) {
    wifiResets++;
    log('WiFi: reset - restart w trybie konfiguracji Bluetooth (HA_$id)');
    Timer(const Duration(seconds: 1), () {
      for (final c in _clients.toList()) {
        c.sink.close();
      }
    });
    return _json({'ok': true});
  }

  /// `POST /api/cloud` (pkt 8.2): konto anonimowe urządzenia. `202 linking`, po [cloudLinkDelay]
  /// `binding` z `deviceUid`; gdy aplikacja przypisze konto do domu ([cloudBound]) - `linked`.
  /// `apiKey` = `zly` daje błąd Google.
  Future<Response> _cloud(Request req) async {
    final body = await _body(req);
    if (body == null) return _json({'ok': false, 'error': 'json'}, status: 400);
    if (body['disconnect'] == true) {
      _cloudTimer?.cancel();
      cloudHomeId = null;
      _cloudStatus = {'status': 'none'};
      log('Chmura: odłączono');
      _broadcastState();
      return _json({'ok': true, 'status': 'none'});
    }
    final fieldsOk =
        const ['apiKey', 'dbUrl', 'homeId'].every((k) => body[k] is String && (body[k] as String).isNotEmpty) &&
        (body['dbUrl'] as String).startsWith('https://');
    if (!fieldsOk) return _json({'ok': false, 'error': 'fields'}, status: 400);

    final homeId = body['homeId'] as String;
    final wrong = body['apiKey'] == 'zly';
    _cloudStatus = {'status': 'linking'};
    _cloudTimer?.cancel();
    _cloudTimer = Timer(cloudLinkDelay, () {
      if (wrong) {
        _cloudStatus = {'status': 'error', 'error': 'API_KEY_INVALID'};
        log('Chmura: zły klucz API');
        return;
      }
      _cloudStatus = {'status': 'binding', 'deviceUid': deviceUid, '_home': homeId};
      log('Chmura: konto urządzenia $deviceUid czeka na przypisanie do domu $homeId');
    });
    return _json({'ok': true, 'status': 'linking'}, status: 202);
  }

  /// Konto anonimowe atrapy (stałe, jak w NVS urządzenia).
  String get deviceUid => 'anon-$id';

  /// `GET /api/cloud`; w `binding` sprawdza przypisanie ([cloudBound], domyślnie od razu).
  Response _cloudGet(Request req) {
    if (_cloudStatus['status'] == 'binding' && (cloudBound?.call(deviceUid) ?? true)) {
      cloudHomeId = _cloudStatus['_home'] as String?;
      _cloudStatus = {'status': 'linked', 'deviceUid': deviceUid};
      log('Chmura: połączono z domem $cloudHomeId');
      _broadcastState();
    }
    return _json({
      for (final e in _cloudStatus.entries)
        if (!e.key.startsWith('_')) e.key: e.value,
      'connected': cloudHomeId != null,
    });
  }

  /// `POST /api/ota` (pkt 3a): przyjmuje obraz, pokazuje postęp w `GET /api/ota`,
  /// po „restarcie” (zamknięte WebSockety) zgłasza nową wersję `fw`.
  Future<Response> _otaPost(Request req) async {
    if (_ota['state'] == 'running') return _json({'ok': false, 'error': 'busy'}, status: 409);
    final total = req.contentLength ?? 0;
    if (total == 0) return _json({'ok': false, 'error': 'empty'}, status: 400);
    _ota = {'state': 'running', 'progress': 0};
    var received = 0;
    int? first;
    await for (final chunk in req.read()) {
      if (chunk.isEmpty) continue;
      first ??= chunk.first;
      received += chunk.length;
      _ota = {'state': 'running', 'progress': received * 100 ~/ total};
      if (otaDelay > Duration.zero) await Future<void>.delayed(otaDelay);
    }
    // Obraz aplikacji ESP32 zaczyna się bajtem 0xE9 - jak biblioteka Update w firmware.
    if (first != 0xE9) {
      _ota = {'state': 'error', 'progress': 0, 'error': 'Wrong Magic Byte'};
      return _json({'ok': false, 'error': 'Wrong Magic Byte'}, status: 400);
    }
    _ota = {'state': 'done', 'progress': 100};
    otaCount++;
    log('OTA: przyjęto $received B, restart za 2 s');
    Timer(otaRestart, () {
      fw = '$_baseFw+ota$otaCount';
      _ota = {'state': 'idle', 'progress': 0};
      for (final c in _clients.toList()) {
        c.sink.close();
      }
      log('OTA: „restart” - nowa wersja $fw');
    });
    return _json({'ok': true, 'restartIn': 2});
  }

  /// Udawany uid konta Firebase dla e-maila.

  // ----------------------------------------------------------- WebSocket

  FutureOr<Response> _ws(Request req) {
    // Token w `?token=` albo w nagłówku Authorization (jak firmware).
    final phone = _phone(req);
    if (phone == null) return _json({'ok': false, 'error': 'unauthorized'}, status: 401);
    return webSocketHandler((WebSocketChannel ws, String? _) {
      _clients.add(ws);
      _wsPhone[ws] = phone;
      log('WS: klient połączony (${_clients.length})');
      ws.sink.add(jsonEncode({'type': 'config', 'data': _fullConfig()}));
      ws.sink.add(jsonEncode({'type': 'state', 'data': stateJson()}));
      ws.stream.listen(
        (raw) => _onWsMessage(ws, raw),
        onDone: () {
          _clients.remove(ws);
          log('WS: klient rozłączony (${_clients.length})');
        },
        onError: (_) => _clients.remove(ws),
      );
    })(req);
  }

  void _onWsMessage(WebSocketChannel ws, dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } on Object {
      return;
    }
    if (msg['type'] != 'set') return;
    if (busy) {
      ws.sink.add(jsonEncode({'type': 'ack', 'id': msg['id'], 'ok': false, 'error': 'busy'}));
      return;
    }
    final values = msg['values'];
    final level = _wsPhone[ws]?.access ?? 'view';
    final errors = values is Map<String, dynamic> ? _applyAs(level, values) : {'_': 'json'};
    ws.sink.add(jsonEncode({'type': 'ack', 'id': msg['id'], 'ok': errors.isEmpty, 'errors': errors}));
  }

  final _wsPhone = <WebSocketChannel, FakePhone>{};

  void _broadcast(Map<String, dynamic> msg) {
    final s = jsonEncode(msg);
    for (final c in _clients) {
      c.sink.add(s);
    }
  }

  void _broadcastState() => _broadcast({'type': 'state', 'data': stateJson()});

  void _broadcastConfig() => _broadcast({'type': 'config', 'data': _fullConfig()});

  String _hex(int bytes) {
    final r = Random.secure();
    return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Sparowany telefon atrapy.
class FakePhone {
  FakePhone(this.token, this.name, this.uid, this.access, this.verified);

  final String token;
  final String name;
  String uid;
  String access;
  bool verified;

  Map<String, dynamic> toJson() => {
    'id': token.substring(0, 8),
    'name': name,
    'uid': uid,
    'access': access,
    'verified': verified,
  };
}
