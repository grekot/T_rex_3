import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/describe.dart';
import '../models/device_info.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import '../models/set_values.dart';
import '../models/thermostat_config.dart';
import '../models/thermostat_state.dart';
import 'errors.dart';
import 'local_endpoint.dart';

/// Wynik `POST /api/pair/confirm`.
/// `GET /api/cloud` (pkt 8.2).
class CloudLinkStatus {
  const CloudLinkStatus({required this.status, this.deviceUid, this.error, this.connected = false});

  /// `none` | `linking` | `binding` | `linked` | `error`.
  final String status;

  /// Anonimowe konto Firebase urządzenia (od `binding`).
  final String? deviceUid;

  /// Komunikat Google, np. `API_KEY_INVALID`.
  final String? error;

  /// Strumień poleceń działa (to samo co `cloud` w State).
  final bool connected;

  factory CloudLinkStatus.fromJson(Json j) => CloudLinkStatus(
    status: asString(j['status'], 'status', 'none'),
    deviceUid: asStringOrNull(j['deviceUid'], 'deviceUid'),
    error: asStringOrNull(j['error'], 'error'),
    connected: asBool(j['connected'], 'connected'),
  );
}

/// `GET /api/ota` (pkt 3a).
class OtaStatus {
  const OtaStatus({required this.state, this.progress = 0, this.error});

  /// `idle` | `running` | `done` | `error`.
  final String state;

  /// 0-100.
  final int progress;
  final String? error;

  factory OtaStatus.fromJson(Json j) => OtaStatus(
    state: asString(j['state'], 'state', 'idle'),
    progress: asInt(j['progress'], 'progress').clamp(0, 100),
    error: asStringOrNull(j['error'], 'error'),
  );
}

/// Błąd wgrywania z termostatu (kody z firmware i komunikaty biblioteki Update) → po polsku.
String describeOtaError(String? code) => switch (code) {
  'busy' => 'Trwa już inna aktualizacja.',
  'sha256' => 'Suma pobranego pliku się nie zgadza - urządzenie zostało przy obecnej wersji.',
  'empty' => 'Plik jest pusty.',
  'write' => 'Błąd zapisu do pamięci termostatu.',
  'unauthorized' => 'Urządzenie odrzuciło token. Sparuj telefon ponownie.',
  null || '' => 'Aktualizacja nie powiodła się.',
  final c when c.toLowerCase().contains('magic') => 'To nie jest plik firmware ESP32 (zły nagłówek obrazu).',
  final c when c.toLowerCase().contains('space') || c.toLowerCase().contains('size') =>
    'Plik jest za duży dla partycji termostatu ($c).',
  final c => 'Aktualizacja nie powiodła się ($c).',
};

class PairResult {
  const PairResult({required this.token, required this.id, this.access = AccessLevel.view, this.pending = false});

  final String token;
  final String id;

  /// Poziom nadany od razu (`view`, dopóki urządzenie nie sprawdzi `idToken`).
  final AccessLevel access;

  /// Urządzenie sprawdza `idToken` - właściwy poziom pokaże `GET /api/me`.
  final bool pending;
}

/// `GET /api/me` (pkt 3).
class MeInfo {
  const MeInfo({required this.id, required this.uid, required this.access});

  /// Pierwsze 8 znaków tokenu tego telefonu.
  final String id;
  final String uid;
  final AccessLevel access;

  factory MeInfo.fromJson(Json j) =>
      MeInfo(id: asString(j['id'], 'id'), uid: asString(j['uid'], 'uid'), access: AccessLevel.fromWire(j['access']));
}

/// Sparowany telefon z `GET /api/clients` (pkt 2-3).
class PhoneClient {
  const PhoneClient({
    required this.id,
    required this.name,
    required this.uid,
    required this.access,
    required this.verified,
  });

  final String id;
  final String name;
  final String uid;
  final AccessLevel access;

  /// Tożsamość potwierdzona (Bluetooth albo `idToken`).
  final bool verified;

  factory PhoneClient.fromJson(Json j) => PhoneClient(
    id: asString(j['id'], 'id'),
    name: asString(j['name'], 'name'),
    uid: asString(j['uid'], 'uid'),
    access: AccessLevel.fromWire(j['access']),
    verified: asBool(j['verified'], 'verified'),
  );
}

/// Klient HTTP termostatu w sieci lokalnej (pkt 2 i 3 kontraktu).
class LocalApi {
  LocalApi(this.endpoint, {this.token, http.Client? client, this.timeout = const Duration(seconds: 5)})
    : _client = client ?? http.Client() {
    if (!isLocalNetworkHost(endpoint.host)) {
      throw ThermostatException(
        'Adres ${endpoint.host} nie jest adresem sieci lokalnej - termostat mówi bez szyfrowania, '
        'więc łączymy się z nim tylko w domu.',
      );
    }
  }

  final LocalEndpoint endpoint;
  final String? token;
  final Duration timeout;
  final http.Client _client;

  void close() => _client.close();

  /// `GET /api/info` - bez autoryzacji.
  Future<DeviceInfo> info({Duration? timeout}) async =>
      DeviceInfo.fromJson(await _send('GET', '/api/info', timeout: timeout));

  /// `POST /api/pair/start` - termostat pokazuje kod; zwraca czas ważności w sekundach.
  Future<int> pairStart() async {
    final j = await _send('POST', '/api/pair/start', body: const {}, pairing: true);
    if (!asBool(j['ok'], 'ok')) {
      throw PairingException.fromCode(
        asStringOrNull(j['error'], 'error'),
        retryIn: asIntOrNull(j['retryIn'], 'retryIn'),
      );
    }
    return asInt(j['expiresIn'], 'expiresIn', 120);
  }

  /// `POST /api/pair/confirm`.
  /// [idToken] - token logowania Firebase: urządzenie sprawdzi go w Google i nada poziom domownika.
  Future<PairResult> pairConfirm(String code, String clientName, {String? idToken}) async {
    final j = await _send(
      'POST',
      '/api/pair/confirm',
      body: {'code': code, 'client': clientName, 'idToken': ?idToken},
      pairing: true,
    );
    if (!asBool(j['ok'], 'ok')) {
      throw PairingException.fromCode(
        asStringOrNull(j['error'], 'error'),
        attemptsLeft: asIntOrNull(j['attemptsLeft'], 'attemptsLeft'),
      );
    }
    final token = asStringOrNull(j['token'], 'token');
    final id = asStringOrNull(j['id'], 'id');
    if (token == null || token.isEmpty || id == null) {
      throw const PairingException(null, 'Urządzenie nie zwróciło tokenu.');
    }
    return PairResult(
      token: token,
      id: id,
      access: j['access'] == null ? AccessLevel.view : AccessLevel.fromWire(j['access']),
      pending: asBool(j['pending'], 'pending'),
    );
  }

  /// `GET /api/me` - poziom dostępu tego telefonu.
  Future<MeInfo> me({Duration? timeout}) async =>
      MeInfo.fromJson(_data(await _send('GET', '/api/me', timeout: timeout)));

  /// `GET /api/describe` (pkt 14).
  Future<DeviceDescription> describe() async => DeviceDescription.fromJson(await describeJson());

  Future<Json> describeJson() async => _data(await _send('GET', '/api/describe'));

  /// `GET /api/clients` - sparowane telefony (poziom `config`).
  Future<List<PhoneClient>> clients() async {
    final v = await _sendAny('GET', '/api/clients');
    if (v is Map && v['ok'] == false) throw ThermostatException(describeApiError(v['error'] as String?));
    return [
      for (final e in (v is List ? v : const []))
        if (e is Map) PhoneClient.fromJson(e.cast<String, dynamic>()),
    ];
  }

  /// `DELETE /api/clients?id=` - token tego telefonu przestaje działać.
  Future<void> deleteClient(String id) async {
    final j = await _send('DELETE', '/api/clients', query: {'id': id});
    if (j['ok'] == false) throw ThermostatException(describeApiError(asStringOrNull(j['error'], 'error')));
  }

  /// `PATCH /api/clients {"id","access"}` - ręczna zmiana poziomu telefonu (przy chmurze nadpisuje go `access` domu).
  Future<void> setClientAccess(String id, AccessLevel access) async {
    final j = await _send('PATCH', '/api/clients', body: {'id': id, 'access': access.wire});
    if (j['ok'] == false) throw ThermostatException(describeApiError(asStringOrNull(j['error'], 'error')));
  }

  /// `POST /api/clients {"name","access"}` - nowy token bez parowania (hub, skrypt). Token widać tylko raz.
  Future<({String id, String token, AccessLevel access})> createClient(String name, AccessLevel access) async {
    final j = await _send('POST', '/api/clients', body: {'name': name, 'access': access.wire});
    if (j['ok'] == false) throw ThermostatException(describeApiError(asStringOrNull(j['error'], 'error')));
    return (
      id: asString(j['id'], 'id'),
      token: asString(j['token'], 'token'),
      access: AccessLevel.fromWire(j['access']),
    );
  }

  /// Dowolne żądanie (np. API huba, pkt 11): mapę z `ok` i listę zwraca bez oceny - ocenia wołający.
  Future<Object?> request(String method, String path, {Object? body, Map<String, String>? query, Duration? timeout}) =>
      _sendAny(method, path, body: body, query: query, timeout: timeout);

  Future<Json> stateJson() async => _data(await _send('GET', '/api/state'));

  Future<Json> configJson() async => _data(await _send('GET', '/api/config'));

  /// `POST /api/set` z dowolnym Set (każdy typ urządzenia).
  Future<SetResult> setJson(Json values) async => SetResult.fromJson(await _send('POST', '/api/set', body: values));

  /// `POST /api/wifi/reset` (pkt 3, 9.3): urządzenie zapomina sieć i wraca do trybu konfiguracji Bluetooth.
  Future<void> wifiReset() async {
    final j = await _send('POST', '/api/wifi/reset', body: const {});
    if (j['ok'] == false) throw ThermostatException(describeApiError(asStringOrNull(j['error'], 'error')));
  }

  Future<ThermostatState> state() async => ThermostatState.fromJson(_data(await _send('GET', '/api/state')));

  Future<ThermostatConfig> config() async => ThermostatConfig.fromJson(_data(await _send('GET', '/api/config')));

  /// State i Config nie mają pola `ok`; `{"ok":false,"error":...}` to błąd.
  static Json _data(Json j) {
    if (j['ok'] == false) throw ThermostatException(describeApiError(asStringOrNull(j['error'], 'error')));
    return j;
  }

  /// `POST /api/set`. Odpowiedź z błędami pól to nie wyjątek, tylko [SetResult.errors].
  Future<SetResult> set(SetValues values) async =>
      SetResult.fromJson(await _send('POST', '/api/set', body: values.toJson()));

  /// `POST /api/ota` (pkt 3a): cały plik `.bin` jako treść (`application/octet-stream`, z `Content-Length`).
  /// [onSent] dostaje liczbę wysłanych bajtów. Odpowiedź przychodzi po zapisaniu całego obrazu;
  /// zwraca, po ilu sekundach termostat się zrestartuje.
  Future<int> uploadFirmware(Uint8List image, {void Function(int sent, int total)? onSent}) async {
    final req = http.StreamedRequest('POST', endpoint.http('/api/ota'))
      ..contentLength = image.length
      ..headers['Content-Type'] = 'application/octet-stream';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';

    final response = _client.send(req);
    const chunk = 16 * 1024;
    for (var i = 0; i < image.length; i += chunk) {
      final end = i + chunk < image.length ? i + chunk : image.length;
      req.sink.add(image.sublist(i, end));
      onSent?.call(end, image.length);
      // Oddajemy pętlę zdarzeń, żeby UI i odpytywanie GET /api/ota mogły działać.
      await Future<void>.delayed(Duration.zero);
    }
    await req.sink.close();

    final http.Response res;
    try {
      res = await http.Response.fromStream(await response.timeout(const Duration(minutes: 3)));
    } on TimeoutException {
      throw UnreachableException('Urządzenie ${endpoint.display} nie odpowiedziało na wgrywanie.');
    } on http.ClientException catch (e) {
      throw UnreachableException('Przerwane wysyłanie do ${endpoint.display} (${e.message}).');
    }
    final d = _decode(res, '/api/ota');
    final j = d is Map<String, dynamic> ? d : const <String, dynamic>{};
    if (!asBool(j['ok'], 'ok')) throw ThermostatException(describeOtaError(asStringOrNull(j['error'], 'error')));
    return asInt(j['restartIn'], 'restartIn', 2);
  }

  /// `GET /api/ota` - postęp aktualizacji.
  Future<OtaStatus> otaStatus({Duration? timeout}) async =>
      OtaStatus.fromJson(await _send('GET', '/api/ota', timeout: timeout));

  /// Podłączenie urządzenia do Firebase (pkt 8.2): urządzenie zakłada sobie anonimowe konto
  /// (`POST /api/cloud` → `202 linking`), zgłasza je (`binding` + `deviceUid`), aplikacja przypisuje
  /// je do domu ([bind] - `homes/{h}/deviceAccounts`), a urządzenie potwierdza (`linked`).
  /// Odpytuje `GET /api/cloud` co [pollInterval]. Zwraca `deviceUid`.
  Future<String> cloud({
    required String apiKey,
    required String dbUrl,
    required String homeId,
    required Future<void> Function(String deviceUid) bind,
    Duration pollInterval = const Duration(seconds: 1),
    Duration maxWait = const Duration(seconds: 40),
    void Function(CloudLinkStatus status)? onStatus,
  }) async {
    final j = await _send('POST', '/api/cloud', body: {'apiKey': apiKey, 'dbUrl': dbUrl, 'homeId': homeId});
    if (!asBool(j['ok'], 'ok')) throw ThermostatException(_cloudError(asStringOrNull(j['error'], 'error')));

    final deadline = DateTime.now().add(maxWait);
    var status = CloudLinkStatus.fromJson(j);
    String? bound;
    while (status.status == 'linking' || status.status == 'binding') {
      onStatus?.call(status);
      final uid = status.deviceUid;
      if (status.status == 'binding' && uid != null && uid != bound) {
        await bind(uid);
        bound = uid;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw ThermostatException(
          bound == null
              ? 'Urządzenie długo zakłada konto w chmurze. Sprawdź jego połączenie z internetem.'
              : 'Urządzenie nie potwierdziło przypisania do domu. Sprawdź, czy w konsoli Firebase jest włączone '
                    'logowanie anonimowe i czy reguły bazy są aktualne.',
        );
      }
      await Future<void>.delayed(pollInterval);
      status = await cloudStatus();
    }
    onStatus?.call(status);
    return switch (status.status) {
      'linked' when status.deviceUid != null => status.deviceUid!,
      'error' => throw ThermostatException(_cloudError(status.error)),
      _ => throw const ThermostatException('Urządzenie nie zapisało danych chmury.'),
    };
  }

  /// `GET /api/cloud` - stan podłączenia do chmury.
  Future<CloudLinkStatus> cloudStatus() async => CloudLinkStatus.fromJson(await _send('GET', '/api/cloud'));

  /// `POST /api/cloud {"disconnect":true}` - termostat zapomina dane chmury.
  Future<void> cloudDisconnect() async {
    final j = await _send('POST', '/api/cloud', body: {'disconnect': true});
    if (!asBool(j['ok'], 'ok')) throw ThermostatException(_cloudError(asStringOrNull(j['error'], 'error')));
  }

  /// Błędy zakładania konta urządzenia (kody Firebase Auth) i odpowiedzi `/api/cloud`.
  static String _cloudError(String? code) => switch (code) {
    'ADMIN_ONLY_OPERATION' ||
    'OPERATION_NOT_ALLOWED' => 'Urządzenie nie założyło konta: w konsoli Firebase włącz logowanie anonimowe.',
    'API_KEY_INVALID' => 'Urządzenie nie założyło konta: zły klucz API Firebase.',
    'TOO_MANY_ATTEMPTS_TRY_LATER' => 'Urządzenie nie założyło konta: za dużo prób, spróbuj później.',
    'fields' => 'Urządzenie odrzuciło dane chmury (brak pól albo zły adres bazy).',
    'busy' || 'not_implemented' || 'json' || null => describeApiError(code),
    _ => 'Urządzenie nie zalogowało się do chmury ($code).',
  };

  Future<Json> _send(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    bool pairing = false,
    Map<String, String>? query,
  }) async {
    final v = await _sendAny(method, path, body: body, timeout: timeout, pairing: pairing, query: query);
    if (v is Map<String, dynamic>) return v;
    throw ThermostatException('Urządzenie zwróciło nieoczekiwaną odpowiedź na $path.');
  }

  Future<Object?> _sendAny(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    bool pairing = false,
    Map<String, String>? query,
  }) async {
    final req = http.Request(method, endpoint.http(path, query));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(req).timeout(timeout ?? this.timeout),
      ).timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw UnreachableException('Urządzenie ${endpoint.display} nie odpowiada.');
    } on http.ClientException catch (e) {
      throw UnreachableException('Brak połączenia z ${endpoint.display} (${e.message}).');
    }

    return _decode(res, path, pairing: pairing);
  }

  Object? _decode(http.Response res, String path, {bool pairing = false}) {
    if (res.statusCode == 401) throw const UnauthorizedException();

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    if (res.statusCode == 403 && !pairing && decoded is Map && decoded['error'] == 'forbidden') {
      throw const ForbiddenException();
    }
    if (decoded is List && res.statusCode < 300) return decoded;
    if (decoded is Map<String, dynamic>) {
      // Odpowiedzi z `ok` (także 400 z `errors`, 403/409 przy parowaniu, 503 `busy`) ocenia wołający.
      if (res.statusCode < 300 || pairing || decoded.containsKey('ok')) return decoded;
    }
    if (res.statusCode == 404) {
      throw ThermostatException('Urządzenie nie zna $path - może ma za starą wersję oprogramowania.');
    }
    throw ThermostatException('Urządzenie zwróciło błąd HTTP ${res.statusCode}.');
  }
}
