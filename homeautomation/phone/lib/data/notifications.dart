import '../models/hub.dart';
import 'cloud_store.dart';

/// Powiadomienia z huba (`homes/{h}/notifications/{klucz}`, akcja `notify` automatyk, pkt 11) - najnowsze pierwsze.
List<HubNotification> parseNotifications(Object? v, {int limit = 50}) {
  final j = toJsonObject(v) ?? const {};
  final list = [
    for (final e in j.entries)
      if (e.value is Map) HubNotification.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
  ]..sort((a, b) => b.ts != a.ts ? b.ts.compareTo(a.ts) : b.key.compareTo(a.key));
  return list.length > limit ? list.sublist(0, limit) : list;
}

Stream<List<HubNotification>> watchNotifications(CloudStore store, String homeId) =>
    store.watch('homes/$homeId/notifications').map(parseNotifications);

/// Nowe od ostatnio pokazanego (`ts` w ms); null = pierwsze sprawdzenie - tylko z ostatniej godziny.
List<HubNotification> newNotifications(List<HubNotification> all, int? lastShownTs, int nowMs) {
  final since = lastShownTs ?? nowMs - const Duration(hours: 1).inMilliseconds;
  return [for (final n in all.reversed) if (n.ts > since) n];
}
