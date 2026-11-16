// Konto i Firestore przez REST (bez wtyczek Firebase - działa tak samo w aplikacji i w usłudze w tle):
// logowanie e-mailem i hasłem (to samo konto co w Zakupach / Wadze), w bezpiecznym magazynie zostaje
// tylko token odświeżania; Firestore - odczyt i zapis dokumentów (archiwum zdjęć, ARCHIWUM.md), zapis spisu
// z warunkiem wersji (narzędzie na PC może go w tym czasie nadpisać).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'firebase_config.dart';

class CloudException implements Exception {
  const CloudException(this.message, {this.status = 0, this.conflict = false});

  final String message;
  final int status;

  /// Dokument zmienił się od odczytu (zapis z warunkiem wersji) - trzeba odczytać i scalić jeszcze raz
  final bool conflict;

  bool get unauthorized => status == 401 || status == 403;

  @override
  String toString() => message;
}

class Account {
  const Account({required this.uid, required this.email, required this.refreshToken});

  final String uid;
  final String email;
  final String refreshToken;

  Map<String, String> toJson() => {'uid': uid, 'email': email, 'refresh': refreshToken};

  static Account? fromJson(Object? j) {
    if (j is! Map || j['uid'] is! String || j['refresh'] is! String) return null;
    return Account(uid: j['uid'] as String, email: j['email'] as String? ?? '', refreshToken: j['refresh'] as String);
  }
}

/// Gdzie leży konto (w aplikacji: bezpieczny magazyn Androida, w testach: pamięć)
abstract class AccountStore {
  Future<Account?> load();
  Future<void> save(Account? account);
}

class SecureAccountStore implements AccountStore {
  static const _key = 'archiwum_konto';
  final _storage = const FlutterSecureStorage();

  @override
  Future<Account?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : Account.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Account? account) => account == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(account.toJson()));
}

class MemoryAccountStore implements AccountStore {
  Account? account;

  @override
  Future<Account?> load() async => account;

  @override
  Future<void> save(Account? account) async => this.account = account;
}

/// Komunikaty Identity Toolkit po polsku
String authMessage(String code) {
  final c = code.split(' ').first.split(':').first;
  return switch (c) {
    'INVALID_LOGIN_CREDENTIALS' || 'INVALID_PASSWORD' || 'EMAIL_NOT_FOUND' => 'Zły e-mail albo hasło',
    'INVALID_EMAIL' => 'Nieprawidłowy e-mail',
    'USER_DISABLED' => 'Konto zablokowane',
    'TOO_MANY_ATTEMPTS_TRY_LATER' => 'Za dużo prób - spróbuj za chwilę',
    'TOKEN_EXPIRED' || 'INVALID_REFRESH_TOKEN' || 'USER_NOT_FOUND' => 'Sesja wygasła - zaloguj się ponownie',
    _ => 'Logowanie: $code',
  };
}

class FirebaseRest {
  FirebaseRest({
    AccountStore? store,
    http.Client? client,
    this.apiKey = firebaseApiKey,
    this.projectId = firebaseProjectId,
    DateTime Function()? now,
  })  : store = store ?? SecureAccountStore(),
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final AccountStore store;
  final http.Client _client;
  final String apiKey;
  final String projectId;
  final DateTime Function() _now;

  String? _idToken;
  DateTime _idTokenUntil = DateTime.fromMillisecondsSinceEpoch(0);

  bool get configured => apiKey.isNotEmpty && projectId.isNotEmpty;

  Future<Account?> account() => store.load();

  Future<Account> signIn(String email, String password) async {
    if (!configured) throw const CloudException('Ta wersja aplikacji nie ma konfiguracji Firebase');
    final res = await _post(
      Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey'),
      jsonEncode({'email': email.trim(), 'password': password, 'returnSecureToken': true}),
      json: true,
    );
    final a = Account(uid: res['localId'] as String, email: res['email'] as String? ?? email, refreshToken: res['refreshToken'] as String);
    await store.save(a);
    _remember(res['idToken'] as String, res['expiresIn']);
    return a;
  }

  Future<void> signOut() async {
    _idToken = null;
    await store.save(null);
  }

  /// Token do zapytań (odświeżany z zapasem 2 min). Wyjątek z [CloudException.unauthorized] = trzeba się zalogować.
  Future<String> idToken() async {
    final t = _idToken;
    if (t != null && _now().isBefore(_idTokenUntil)) return t;
    final a = await store.load();
    if (a == null) throw const CloudException('Nie zalogowano', status: 401);
    final res = await _post(
      Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey'),
      'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(a.refreshToken)}',
    );
    final refresh = res['refresh_token'] as String? ?? a.refreshToken;
    if (refresh != a.refreshToken) await store.save(Account(uid: a.uid, email: a.email, refreshToken: refresh));
    _remember(res['id_token'] as String, res['expires_in']);
    return _idToken!;
  }

  void _remember(String token, Object? expiresIn) {
    final seconds = int.tryParse('$expiresIn') ?? 3600;
    _idToken = token;
    _idTokenUntil = _now().add(Duration(seconds: seconds - 120));
  }

  Future<Map<String, dynamic>> _post(Uri url, String body, {bool json = false}) async {
    final http.Response res;
    try {
      res = await _client
          .post(url,
              headers: {'Content-Type': json ? 'application/json' : 'application/x-www-form-urlencoded'}, body: body)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw CloudException('Brak połączenia: $e');
    }
    final j = _decode(res);
    if (res.statusCode != 200) {
      final err = j['error'];
      final code = err is Map ? '${err['message']}' : '$err';
      // Zły token odświeżania = jak brak logowania
      throw CloudException(authMessage(code), status: res.statusCode == 400 && url.host.startsWith('securetoken') ? 401 : res.statusCode);
    }
    return j;
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  String _docUrl(String path) => 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path';

  /// Pola dokumentu ([mask] = tylko te pola); null = nie ma dokumentu
  Future<Map<String, Object?>?> getDocument(String path, {List<String> mask = const []}) async =>
      (await getDoc(path, mask: mask))?.fields;

  /// Dokument z wersją (`updateTime`, do zapisu z warunkiem); null = nie ma dokumentu
  Future<FirestoreDoc?> getDoc(String path, {List<String> mask = const []}) async {
    final token = await idToken();
    final query = mask.map((m) => 'mask.fieldPaths=${Uri.encodeQueryComponent(m)}').join('&');
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse(query.isEmpty ? _docUrl(path) : '${_docUrl(path)}?$query'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw CloudException('Brak połączenia: $e');
    }
    if (res.statusCode == 404) return null;
    final j = _decode(res);
    if (res.statusCode != 200) {
      final err = j['error'];
      throw CloudException('Firestore: HTTP ${res.statusCode} ${err is Map ? err['message'] : ''}'.trim(), status: res.statusCode);
    }
    return FirestoreDoc.fromJson(j);
  }

  /// Zapis dokumentu: [fields] (String, int, double, bool, Uint8List, DateTime = znacznik czasu).
  /// [updateMask] - zmieniane tylko te pola (inaczej cały dokument). Warunek: [ifUpdateTime] - dokument
  /// w tej wersji, [ifMissing] - dokumentu jeszcze nie ma; niespełniony = [CloudException.conflict].
  Future<FirestoreDoc> setDocument(
    String path,
    Map<String, Object> fields, {
    List<String>? updateMask,
    String? ifUpdateTime,
    bool ifMissing = false,
  }) async {
    final token = await idToken();
    final query = [
      for (final m in updateMask ?? const <String>[]) 'updateMask.fieldPaths=${Uri.encodeQueryComponent(m)}',
      if (ifUpdateTime != null)
        'currentDocument.updateTime=${Uri.encodeQueryComponent(ifUpdateTime)}'
      else if (ifMissing)
        'currentDocument.exists=false',
    ].join('&');
    final http.Response res;
    try {
      res = await _client
          .patch(Uri.parse(query.isEmpty ? _docUrl(path) : '${_docUrl(path)}?$query'),
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
              body: jsonEncode({'fields': firestoreFields(fields)}))
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw CloudException('Brak połączenia: $e');
    }
    final j = _decode(res);
    if (res.statusCode != 200) {
      final err = j['error'];
      final status = err is Map ? '${err['status']}' : '';
      throw CloudException(
        'Firestore: HTTP ${res.statusCode} ${err is Map ? err['message'] : ''}'.trim(),
        status: res.statusCode,
        conflict: res.statusCode == 409 || (res.statusCode == 400 && status == 'FAILED_PRECONDITION'),
      );
    }
    return FirestoreDoc.fromJson(j);
  }

  void close() => _client.close();
}

class FirestoreDoc {
  const FirestoreDoc(this.fields, this.updateTime);

  final Map<String, Object?> fields;

  /// Wersja dokumentu (RFC 3339) - do zapisu z warunkiem
  final String? updateTime;

  factory FirestoreDoc.fromJson(Map<String, dynamic> j) {
    final fields = j['fields'];
    return FirestoreDoc({
      if (fields is Map)
        for (final e in fields.entries) e.key as String: firestoreValue(e.value),
    }, j['updateTime'] as String?);
  }
}

/// Pola do zapisu w REST Firestore
Map<String, Object> firestoreFields(Map<String, Object> fields) => {
      for (final e in fields.entries) e.key: _toValue(e.value),
    };

Map<String, Object> _toValue(Object v) => switch (v) {
      final bool b => {'booleanValue': b},
      final int i => {'integerValue': '$i'},
      final double d => {'doubleValue': d},
      final Uint8List bytes => {'bytesValue': base64Encode(bytes)},
      final DateTime t => {'timestampValue': t.toUtc().toIso8601String()},
      final String s => {'stringValue': s},
      _ => throw ArgumentError('Typ pola: ${v.runtimeType}'),
    };

/// Wartość pola z REST Firestore (bez map i list - archiwum ich nie używa)
Object? firestoreValue(Object? v) {
  if (v is! Map) return null;
  if (v.containsKey('stringValue')) return v['stringValue'] as String;
  if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
  if (v.containsKey('bytesValue')) return Uint8List.fromList(base64Decode(v['bytesValue'] as String));
  if (v.containsKey('timestampValue')) return v['timestampValue'] as String;
  return null;
}
