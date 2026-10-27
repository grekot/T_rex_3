import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/room.dart';
import 'cloud_access.dart';
import 'cloud_store.dart';

/// Pokoje i kolejność kafelków. Z kontem: w chmurze (`homes/{homeId}/rooms`, wspólne dla domowników),
/// bez Firebase: lokalnie w telefonie.
abstract class RoomStore {
  Stream<List<Room>> watch();

  Future<void> save(Room room);

  Future<void> saveAll(Iterable<Room> rooms) async {
    for (final r in rooms) {
      await save(r);
    }
  }

  Future<void> remove(String roomId);
}

class CloudRoomStore extends RoomStore {
  CloudRoomStore(this.store, this.homeId);

  final CloudStore store;
  final String homeId;

  String get _path => 'homes/$homeId/rooms';

  @override
  Stream<List<Room>> watch() => store.watch(_path).map((v) {
    final j = toJsonObject(v) ?? const {};
    return [
      for (final e in j.entries)
        if (e.value is Map) Room.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
    ];
  });

  @override
  Future<void> save(Room room) => store.write('$_path/${room.id}', room.toJson());

  @override
  Future<void> remove(String roomId) => store.write('$_path/$roomId', null);
}

class LocalRoomStore extends RoomStore {
  LocalRoomStore({SharedPreferencesAsync? prefs}) : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'rooms';
  final SharedPreferencesAsync _prefs;
  final _changes = StreamController<List<Room>>.broadcast();

  Future<Map<String, Room>> _load() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return {};
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in j.entries) e.key: Room.fromJson(e.key, (e.value as Map).cast<String, dynamic>())};
    } on Object {
      return {};
    }
  }

  Future<void> _store(Map<String, Room> rooms) async {
    await _prefs.setString(_key, jsonEncode({for (final r in rooms.values) r.id: r.toJson()}));
    _changes.add(rooms.values.toList());
  }

  @override
  Stream<List<Room>> watch() {
    late StreamController<List<Room>> c;
    StreamSubscription<List<Room>>? sub;
    c = StreamController<List<Room>>(
      onListen: () async {
        sub = _changes.stream.listen(c.add);
        c.add((await _load()).values.toList());
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<void> save(Room room) async => _store((await _load())..[room.id] = room);

  @override
  Future<void> remove(String roomId) async => _store((await _load())..remove(roomId));
}

/// Wybiera magazyn przy każdym użyciu: zalogowany → chmura, inaczej lokalnie.
class AccountRoomStore extends RoomStore {
  AccountRoomStore(this.cloud, {LocalRoomStore? local}) : _local = local ?? LocalRoomStore();

  final CloudAccess cloud;
  final LocalRoomStore _local;

  RoomStore get _current =>
      cloud.available && cloud.homeId != null ? CloudRoomStore(cloud.store, cloud.homeId!) : _local;

  @override
  Stream<List<Room>> watch() => _current.watch();

  @override
  Future<void> save(Room room) => _current.save(room);

  @override
  Future<void> remove(String roomId) => _current.remove(roomId);
}
