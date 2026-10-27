import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import '../models/json_utils.dart';

/// Znacznik czasu serwera Realtime Database (`{".sv":"timestamp"}`).
const serverTimestamp = {'.sv': 'timestamp'};

/// Realtime Database za interfejsem - CloudConnection i zadanie w tle testujemy bez Firebase.
abstract class CloudStore {
  /// Wartość pod ścieżką na żywo; null = brak węzła.
  Stream<Object?> watch(String path);

  Future<Object?> read(String path);

  /// Dopisuje dziecko z nowym kluczem (push) i zwraca ten klucz.
  Future<String> push(String path, Object value);

  /// Same klucze dzieci (bez pobierania całego poddrzewa, np. historii).
  Future<List<String>> childKeys(String path);

  /// Zapis wartości pod ścieżką; null usuwa węzeł.
  Future<void> write(String path, Object? value);

  /// Zapis kilku dzieci naraz (`update`) - reguły sprawdzają każde dziecko osobno.
  Future<void> update(String path, Map<String, Object?> values);
}

/// Implementacja na firebase_database. Klucze dzieci czyta REST-em z `shallow=true`,
/// bo SDK nie ma płytkiego odczytu, a urządzenia w `home/{uid}/devices` mają rosnącą historię.
class FirebaseCloudStore implements CloudStore {
  FirebaseCloudStore(this.db, {http.Client? client}) : _client = client ?? http.Client();

  final FirebaseDatabase db;
  final http.Client _client;

  @override
  Stream<Object?> watch(String path) => db.ref(path).onValue.map((e) => e.snapshot.value);

  @override
  Future<Object?> read(String path) async => (await db.ref(path).get()).value;

  @override
  Future<void> write(String path, Object? value) => value == null ? db.ref(path).remove() : db.ref(path).set(value);

  @override
  Future<void> update(String path, Map<String, Object?> values) =>
      (path.isEmpty ? db.ref() : db.ref(path)).update(values);

  @override
  Future<String> push(String path, Object value) async {
    final ref = db.ref(path).push();
    await ref.set(value);
    return ref.key!;
  }

  @override
  Future<List<String>> childKeys(String path) async {
    final user = FirebaseAuth.instance.currentUser;
    final base = db.databaseURL ?? db.app.options.databaseURL;
    if (user == null || base == null) return const [];
    final token = await user.getIdToken();
    final uri = Uri.parse('$base/$path.json').replace(queryParameters: {'shallow': 'true', 'auth': token});
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw http.ClientException('Realtime Database: HTTP ${res.statusCode}', uri);
    }
    final v = jsonDecode(res.body);
    return v is Map ? [for (final k in v.keys) k as String] : const [];
  }
}

/// Wartość z Realtime Database → JSON jak z HTTP (klucze String, zagnieżdżone mapy).
/// RTDB nie przechowuje `null`, więc brakujące pola są po prostu nieobecne.
Object? toJsonValue(Object? v) {
  if (v is Map) return <String, dynamic>{for (final e in v.entries) e.key.toString(): toJsonValue(e.value)};
  if (v is List) return [for (final e in v) toJsonValue(e)];
  return v;
}

Json? toJsonObject(Object? v) {
  final j = toJsonValue(v);
  return j is Map<String, dynamic> ? j : null;
}
