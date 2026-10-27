import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import 'cloud_access.dart';
import 'cloud_store.dart';

/// Proste przechowywanie tekstu (kopia pulpitów na czas bez internetu, pulpity bez konta).
abstract class TextCache {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

class PrefsTextCache implements TextCache {
  PrefsTextCache({SharedPreferencesAsync? prefs}) : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> get(String key) async {
    try {
      return await _prefs.getString(key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> set(String key, String value) async {
    try {
      await _prefs.setString(key, value);
    } on Object {
      // Kopia jest tylko pomocą.
    }
  }
}

class MemoryTextCache implements TextCache {
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

/// Pulpity domu (prywatne + wspólne) i preferencje (kontrakt pkt 13).
abstract class DashboardStore {
  /// Wszystkie pulpity widoczne dla mnie w domu, posortowane: prywatne, potem wspólne, wg `order`.
  Stream<List<Dashboard>> watch(String homeId);

  Future<void> save(String homeId, Dashboard dashboard);

  Future<void> remove(String homeId, Dashboard dashboard);

  Future<HomePrefs> prefs(String homeId);

  Future<void> savePrefs(String homeId, HomePrefs prefs);

  /// Czy mogę zapisywać wspólne pulpity (właściciel domu).
  bool canEditShared = false;
}

List<Dashboard> sortDashboards(Iterable<Dashboard> list) => list.toList()
  ..sort(
    (a, b) => a.scope != b.scope
        ? a.scope.index.compareTo(b.scope.index)
        : (a.order != b.order ? a.order.compareTo(b.order) : a.name.compareTo(b.name)),
  );

List<Dashboard> _parse(Object? v, DashboardScope scope) {
  final j = toJsonObject(v) ?? const {};
  return [
    for (final e in j.entries)
      if (e.value is Map) Dashboard.fromJson(e.key, scope, (e.value as Map).cast<String, dynamic>()),
  ];
}

String _encode(List<Dashboard> list) => jsonEncode([
  for (final d in list) {'id': d.id, 'scope': d.scope.name, ...d.toJson()},
]);

List<Dashboard> _decode(String raw) {
  try {
    return [
      for (final e in jsonDecode(raw) as List)
        Dashboard.fromJson(
          (e as Map)['id'] as String,
          DashboardScope.values.byName(e['scope'] as String),
          e.cast<String, dynamic>(),
        ),
    ];
  } on Object {
    return const [];
  }
}

/// Chmura: `users/{uid}/dashboards/{h}/{id}` i `homes/{h}/dashboards/{id}`, preferencje
/// `users/{uid}/prefs/{h}`. Najpierw pokazuje ostatnią kopię lokalną.
class CloudDashboardStore extends DashboardStore {
  CloudDashboardStore(this.store, this.uid, {TextCache? cache}) : cache = cache ?? PrefsTextCache();

  final CloudStore store;
  final String uid;
  final TextCache cache;

  String _private(String h) => 'users/$uid/dashboards/$h';
  String _shared(String h) => 'homes/$h/dashboards';
  String _cacheKey(String h) => 'dashboards_$h';

  @override
  Stream<List<Dashboard>> watch(String homeId) {
    late StreamController<List<Dashboard>> c;
    final subs = <StreamSubscription<Object?>>[];
    var private = <Dashboard>[], shared = <Dashboard>[];
    var gotPrivate = false, gotShared = false;

    void emit() {
      if (!gotPrivate || !gotShared) return;
      final all = sortDashboards([...private, ...shared]);
      c.add(all);
      unawaited(cache.set(_cacheKey(homeId), _encode(all)));
    }

    c = StreamController<List<Dashboard>>(
      onListen: () async {
        final cached = await cache.get(_cacheKey(homeId));
        if (cached != null && !gotPrivate) c.add(sortDashboards(_decode(cached)));
        subs
          ..add(
            store.watch(_private(homeId)).listen((v) {
              private = _parse(v, DashboardScope.private);
              gotPrivate = true;
              emit();
            }, onError: (_) {}),
          )
          ..add(
            store
                .watch(_shared(homeId))
                .listen(
                  (v) {
                    shared = _parse(v, DashboardScope.shared);
                    gotShared = true;
                    emit();
                  },
                  onError: (_) {
                    gotShared = true;
                    emit();
                  },
                ),
          );
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return c.stream;
  }

  String _path(String homeId, Dashboard d) =>
      '${d.scope == DashboardScope.shared ? _shared(homeId) : _private(homeId)}/${d.id}';

  @override
  Future<void> save(String homeId, Dashboard dashboard) => store.write(_path(homeId, dashboard), dashboard.toJson());

  @override
  Future<void> remove(String homeId, Dashboard dashboard) => store.write(_path(homeId, dashboard), null);

  @override
  Future<HomePrefs> prefs(String homeId) async =>
      HomePrefs.fromJson(await store.read('users/$uid/prefs/$homeId').catchError((_) => null));

  @override
  Future<void> savePrefs(String homeId, HomePrefs prefs) => store.write('users/$uid/prefs/$homeId', prefs.toJson());
}

/// Bez konta: tylko prywatne pulpity w telefonie.
class LocalDashboardStore extends DashboardStore {
  LocalDashboardStore({TextCache? cache}) : cache = cache ?? PrefsTextCache();

  final TextCache cache;
  final _changes = StreamController<String>.broadcast();

  String _key(String h) => 'local_dashboards_$h';
  String _prefsKey(String h) => 'local_prefs_$h';

  Future<List<Dashboard>> _load(String h) async {
    final raw = await cache.get(_key(h));
    return raw == null ? [] : _decode(raw);
  }

  @override
  Stream<List<Dashboard>> watch(String homeId) {
    late StreamController<List<Dashboard>> c;
    StreamSubscription<String>? sub;
    c = StreamController<List<Dashboard>>(
      onListen: () async {
        sub = _changes.stream.where((h) => h == homeId).listen((_) async => c.add(sortDashboards(await _load(homeId))));
        c.add(sortDashboards(await _load(homeId)));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<void> save(String homeId, Dashboard dashboard) async {
    final list = (await _load(homeId))..removeWhere((d) => d.id == dashboard.id);
    await cache.set(_key(homeId), _encode([...list, dashboard.copyWith(scope: DashboardScope.private)]));
    _changes.add(homeId);
  }

  @override
  Future<void> remove(String homeId, Dashboard dashboard) async {
    final list = (await _load(homeId))..removeWhere((d) => d.id == dashboard.id);
    await cache.set(_key(homeId), _encode(list));
    _changes.add(homeId);
  }

  @override
  Future<HomePrefs> prefs(String homeId) async {
    final raw = await cache.get(_prefsKey(homeId));
    return raw == null ? const HomePrefs() : HomePrefs.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> savePrefs(String homeId, HomePrefs prefs) => cache.set(_prefsKey(homeId), jsonEncode(prefs.toJson()));
}

/// Wybór magazynu wg konta (jak pokoje): zalogowany z domem → chmura, inaczej telefon.
class AccountDashboardStore extends DashboardStore {
  AccountDashboardStore(this.cloud, {LocalDashboardStore? local, TextCache? cache})
    : _local = local ?? LocalDashboardStore(),
      _cache = cache ?? PrefsTextCache();

  final CloudAccess cloud;
  final LocalDashboardStore _local;
  final TextCache _cache;
  CloudDashboardStore? _cloudStore;

  DashboardStore get _current {
    if (!cloud.available || cloud.homeId == null) return _local;
    final uid = cloud.uid!;
    final s = _cloudStore;
    if (s != null && s.uid == uid) return s;
    return _cloudStore = CloudDashboardStore(cloud.store, uid, cache: _cache);
  }

  @override
  Stream<List<Dashboard>> watch(String homeId) => _current.watch(homeId);

  @override
  Future<void> save(String homeId, Dashboard dashboard) => _current.save(homeId, dashboard);

  @override
  Future<void> remove(String homeId, Dashboard dashboard) => _current.remove(homeId, dashboard);

  @override
  Future<HomePrefs> prefs(String homeId) => _current.prefs(homeId);

  @override
  Future<void> savePrefs(String homeId, HomePrefs prefs) => _current.savePrefs(homeId, prefs);
}
