import 'dart:async';

import 'package:homeautomation/data/cloud_access.dart';
import 'package:homeautomation/data/cloud_store.dart';

/// Realtime Database w pamięci: drzewo map, nasłuch ścieżek, push z rosnącymi kluczami.
class MemoryCloudStore implements CloudStore {
  final Map<String, dynamic> root = {};
  final _changes = StreamController<void>.broadcast(sync: true);
  int _pushCounter = 0;
  int now = 1793000000000;

  /// Wywoływane po każdym push (np. symulacja termostatu odpowiadającego na polecenia).
  void Function(String path, String key, Object value)? onPush;

  List<String> _parts(String path) => path.split('/').where((p) => p.isNotEmpty).toList();

  Object? get(String path) {
    Object? node = root;
    for (final p in _parts(path)) {
      if (node is! Map) return null;
      node = node[p];
    }
    return node;
  }

  void set(String path, Object? value) {
    final parts = _parts(path);
    Map<String, dynamic> node = root;
    for (final p in parts.take(parts.length - 1)) {
      node = (node[p] ??= <String, dynamic>{}) as Map<String, dynamic>;
    }
    if (value == null) {
      node.remove(parts.last);
    } else {
      node[parts.last] = _resolve(value);
    }
    _changes.add(null);
  }

  /// `{".sv":"timestamp"}` → [now], jak robi serwer.
  Object? _resolve(Object? v) {
    if (v is Map) {
      if (v.length == 1 && v['.sv'] == 'timestamp') return now;
      return <String, dynamic>{for (final e in v.entries) e.key as String: _resolve(e.value)};
    }
    return v;
  }

  @override
  Stream<Object?> watch(String path) {
    late StreamController<Object?> c;
    StreamSubscription<void>? sub;
    c = StreamController<Object?>(
      onListen: () {
        c.add(get(path));
        sub = _changes.stream.listen((_) => c.add(get(path)));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<Object?> read(String path) async => get(path);

  @override
  Future<void> write(String path, Object? value) async => set(path, value);

  @override
  Future<void> update(String path, Map<String, Object?> values) async {
    for (final e in values.entries) {
      set('$path/${e.key}', e.value);
    }
  }

  @override
  Future<String> push(String path, Object value) async {
    final key = '-push${(_pushCounter++).toString().padLeft(4, '0')}';
    set('$path/$key', value);
    onPush?.call(path, key, value);
    return key;
  }

  @override
  Future<List<String>> childKeys(String path) async {
    final node = get(path);
    return node is Map ? [for (final k in node.keys) k as String] : const [];
  }
}

/// Zalogowany użytkownik bez Firebase.
class TestCloudAccess extends CloudAccess {
  TestCloudAccess(this.store, {this.uid = 'uid-1', this.email = 'ja@example.com', String? homeId = 'h1'}) {
    this.homeId = homeId;
  }

  @override
  final MemoryCloudStore store;
  @override
  final String? uid;
  @override
  final String? email;

  @override
  String? get unavailableReason => uid == null ? 'Zaloguj się.' : null;
  @override
  String get apiKey => 'test-api-key';
  @override
  String get dbUrl => 'https://test-rtdb.example';
}
