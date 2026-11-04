import '../models/calendar.dart';
import 'cloud_store.dart';

/// Kalendarz domu w chmurze (`homes/{h}/calendar/{id}`, pkt 11): czyta i pisze każdy domownik, czyta też hub.
class CalendarStore {
  CalendarStore(this.store, this.homeId);

  final CloudStore store;
  final String homeId;

  String get _path => 'homes/$homeId/calendar';

  static List<CalendarEntry> _parse(Object? v) => [
    if (v is Map)
      for (final e in v.entries)
        if (e.value is Map) CalendarEntry.fromJson('${e.key}', (e.value as Map).cast<String, dynamic>()),
  ];

  Stream<List<CalendarEntry>> watch() => store.watch(_path).map(_parse);

  Future<List<CalendarEntry>> load() async => _parse(await store.read(_path));

  Future<void> save(CalendarEntry e) => store.write('$_path/${e.id}', e.toJson());

  Future<void> remove(String id) => store.write('$_path/$id', null);
}
