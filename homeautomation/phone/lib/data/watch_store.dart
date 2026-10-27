import '../models/watch.dart';
import 'cloud_store.dart';

/// Zegarki osoby i ich pulpity (kontrakt pkt 13a). Tylko z kontem - zegarek działa przez chmurę.
class WatchStore {
  WatchStore(this.store, this.uid);

  final CloudStore store;
  final String uid;

  /// `users/{uid}/watches` - zegarki, które się zgłosiły (ostatnio widziany pierwszy).
  Stream<List<WatchInfo>> watches() => store.watch('users/$uid/watches').map((v) {
    final j = toJsonObject(v) ?? const {};
    return [
      for (final e in j.entries)
        if (e.value is Map) WatchInfo.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
    ]..sort((a, b) => (b.lastSeen ?? 0).compareTo(a.lastSeen ?? 0));
  });

  String _path(String homeId, String watchId) => 'users/$uid/watchDashboards/$homeId/$watchId';

  Future<WatchDashboard?> load(String homeId, String watchId) async {
    final j = toJsonObject(await store.read(_path(homeId, watchId)));
    return j == null ? null : WatchDashboard.fromJson(j);
  }

  Future<void> save(String homeId, WatchInfo watch, WatchDashboard dashboard) =>
      store.write(_path(homeId, watch.id), dashboard.toJson(watch, serverTimestamp));

  /// Bez pulpitu zegarek pokazuje listę urządzeń, do których osoba ma dostęp.
  Future<void> remove(String homeId, String watchId) => store.write(_path(homeId, watchId), null);
}
