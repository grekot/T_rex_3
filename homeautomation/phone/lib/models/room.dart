import 'json_utils.dart';

/// Pokój z kolejnością kafelków (kontrakt pkt 8.3: `home/{uid}/rooms/{roomId}`).
class Room {
  const Room({required this.id, required this.name, required this.order, this.devices = const []});

  final String id;
  final String name;
  final int order;

  /// Identyfikatory urządzeń w kolejności kafelków.
  final List<String> devices;

  Room copyWith({String? name, int? order, List<String>? devices}) =>
      Room(id: id, name: name ?? this.name, order: order ?? this.order, devices: devices ?? this.devices);

  factory Room.fromJson(String id, Json j) => Room(
    id: id,
    name: asString(j['name'], 'name', 'Pokój'),
    order: asInt(j['order'], 'order'),
    // RTDB zwraca listę; pusta lista w ogóle nie istnieje (brak klucza).
    devices: [
      for (final d in (j['devices'] is List ? j['devices'] as List : const []))
        if (d is String) d,
    ],
  );

  Json toJson() => {'name': name, 'order': order, 'devices': devices};

  @override
  String toString() => '$name$devices';
}

/// Nowy identyfikator pokoju (klucz w bazie).
String newRoomId() => 'r${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// Pokoje posortowane wg `order`, potem nazwy.
List<Room> sortRooms(Iterable<Room> rooms) =>
    rooms.toList()..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.name.compareTo(b.name));

/// Sekcja ekranu „Dom”: pokój (null = „Bez pokoju”) i jego urządzenia w kolejności.
class RoomSection {
  const RoomSection(this.room, this.deviceIds);

  final Room? room;
  final List<String> deviceIds;
}

/// Układa znane urządzenia w pokoje. Urządzenia spoza pokoi trafiają na koniec do „Bez pokoju”,
/// a identyfikatory, których już nie ma, są pomijane (pokój zostaje).
List<RoomSection> layoutRooms(List<Room> rooms, List<String> knownDevices) {
  final known = knownDevices.toSet();
  final placed = <String>{};
  final sections = <RoomSection>[];
  for (final r in sortRooms(rooms)) {
    final ids = [
      for (final d in r.devices)
        if (known.contains(d) && placed.add(d)) d,
    ];
    sections.add(RoomSection(r, ids));
  }
  final rest = [
    for (final d in knownDevices)
      if (!placed.contains(d)) d,
  ];
  if (rest.isNotEmpty) sections.add(RoomSection(null, rest));
  return sections;
}

/// Przenosi urządzenie do pokoju [targetId] (na koniec); null = „Bez pokoju”.
/// Zwraca tylko pokoje, które się zmieniły.
List<Room> moveDevice(List<Room> rooms, String deviceId, String? targetId) {
  final changed = <Room>[];
  for (final r in rooms) {
    final has = r.devices.contains(deviceId);
    if (r.id == targetId) {
      if (!has) changed.add(r.copyWith(devices: [...r.devices, deviceId]));
    } else if (has) {
      changed.add(r.copyWith(devices: [...r.devices]..remove(deviceId)));
    }
  }
  return changed;
}

/// Przesuwa kafelek w pokoju o [delta] miejsc (−1 = wcześniej). Null, gdy nie da się.
Room? shiftDevice(Room room, String deviceId, int delta) {
  final list = [...room.devices];
  final i = list.indexOf(deviceId);
  final j = i + delta;
  if (i < 0 || j < 0 || j >= list.length) return null;
  list
    ..removeAt(i)
    ..insert(j, deviceId);
  return room.copyWith(devices: list);
}

/// Zamienia pokój z sąsiednim (−1 = wyżej). Zwraca pokoje z nowymi `order` (0, 1, 2…).
List<Room> shiftRoom(List<Room> rooms, String roomId, int delta) {
  final sorted = sortRooms(rooms);
  final i = sorted.indexWhere((r) => r.id == roomId);
  final j = i + delta;
  if (i < 0 || j < 0 || j >= sorted.length) return const [];
  final r = sorted.removeAt(i);
  sorted.insert(j, r);
  return [
    for (var k = 0; k < sorted.length; k++)
      if (sorted[k].order != k) sorted[k].copyWith(order: k),
  ];
}
