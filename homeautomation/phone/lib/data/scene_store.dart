import 'dart:async';
import 'dart:convert';

import '../models/scene.dart';
import 'cloud_access.dart';
import 'cloud_store.dart';
import 'dashboard_store.dart';

/// Sceny domu (`homes/{h}/scenes`): czytają domownicy, pisze właściciel. Bez konta - w telefonie.
abstract class SceneStore {
  Stream<List<Scene>> watch(String homeId);

  Future<void> save(String homeId, Scene scene);

  Future<void> remove(String homeId, String sceneId);
}

List<Scene> _sorted(Iterable<Scene> l) => l.toList()..sort((a, b) => a.name.compareTo(b.name));

List<Scene> _parse(Object? v) {
  final j = toJsonObject(v) ?? const {};
  return _sorted([
    for (final e in j.entries)
      if (e.value is Map) Scene.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
  ]);
}

class CloudSceneStore implements SceneStore {
  CloudSceneStore(this.store, {TextCache? cache}) : cache = cache ?? PrefsTextCache();

  final CloudStore store;

  /// Kopia na czas bez internetu (kafelki scen na pulpicie).
  final TextCache cache;

  @override
  Stream<List<Scene>> watch(String homeId) {
    late StreamController<List<Scene>> c;
    StreamSubscription<Object?>? sub;
    var live = false;
    c = StreamController<List<Scene>>(
      onListen: () async {
        final cached = await cache.get('scenes_$homeId');
        if (cached != null && !live) c.add(_parse(jsonDecode(cached)));
        sub = store.watch('homes/$homeId/scenes').listen((v) {
          live = true;
          c.add(_parse(v));
          unawaited(cache.set('scenes_$homeId', jsonEncode(v ?? const {})));
        }, onError: (_) {});
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<void> save(String homeId, Scene scene) => store.write('homes/$homeId/scenes/${scene.id}', scene.toJson());

  @override
  Future<void> remove(String homeId, String sceneId) => store.write('homes/$homeId/scenes/$sceneId', null);
}

class LocalSceneStore implements SceneStore {
  LocalSceneStore({TextCache? cache}) : cache = cache ?? PrefsTextCache();

  final TextCache cache;
  final _changes = StreamController<String>.broadcast();

  Future<Map<String, dynamic>> _load(String h) async {
    final raw = await cache.get('local_scenes_$h');
    return raw == null ? <String, dynamic>{} : (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  @override
  Stream<List<Scene>> watch(String homeId) {
    late StreamController<List<Scene>> c;
    StreamSubscription<String>? sub;
    c = StreamController<List<Scene>>(
      onListen: () async {
        sub = _changes.stream.where((h) => h == homeId).listen((_) async => c.add(_parse(await _load(homeId))));
        c.add(_parse(await _load(homeId)));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<void> save(String homeId, Scene scene) async {
    final all = await _load(homeId)
      ..[scene.id] = scene.toJson();
    await cache.set('local_scenes_$homeId', jsonEncode(all));
    _changes.add(homeId);
  }

  @override
  Future<void> remove(String homeId, String sceneId) async {
    final all = await _load(homeId)
      ..remove(sceneId);
    await cache.set('local_scenes_$homeId', jsonEncode(all));
    _changes.add(homeId);
  }
}

/// Z kontem i domem - chmura, inaczej telefon.
class AccountSceneStore implements SceneStore {
  AccountSceneStore(this.cloud, {LocalSceneStore? local}) : _local = local ?? LocalSceneStore();

  final CloudAccess cloud;
  final LocalSceneStore _local;
  CloudSceneStore? _cloudStore;

  SceneStore get _current {
    if (!cloud.available || cloud.homeId == null) return _local;
    return _cloudStore ??= CloudSceneStore(cloud.store);
  }

  @override
  Stream<List<Scene>> watch(String homeId) => _current.watch(homeId);

  @override
  Future<void> save(String homeId, Scene scene) => _current.save(homeId, scene);

  @override
  Future<void> remove(String homeId, String sceneId) => _current.remove(homeId, sceneId);
}
