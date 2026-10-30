// Hub (kontrakt pkt 11, ARCHITEKTURA pkt 4.4-4.6): urządzenia podrzędne, wykrywanie, automatyki, dziennik.

import 'json_utils.dart';

/// Adaptery huba (`POST /api/devices`).
enum HubAdapter {
  ownNode('ownNode', 'Własny węzeł'),
  shelly('shelly', 'Shelly'),
  sonoffDiy('sonoffDiy', 'Sonoff DIY'),

  /// Sonoff z eWeLink i „Kontrolą LAN” - zostaje na koncie eWeLink, hub steruje lokalnie (pkt 11 „eWeLink LAN”).
  ewelink('ewelink', 'Sonoff (eWeLink)'),
  tasmota('tasmota', 'Tasmota'),
  tuya('tuya', 'Tuya');

  const HubAdapter(this.wire, this.label);

  final String wire;
  final String label;

  static HubAdapter fromWire(Object? v) => values.firstWhere((a) => a.wire == v, orElse: () => ownNode);

  /// Czy przy dodawaniu można podać hasło urządzenia.
  bool get hasPassword => this == shelly || this == tasmota;
}

/// `devicekey` urządzenia eWeLink (UUID, 36 znaków) - `localKey` przy dodawaniu do huba.
final ewelinkKeyPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Model eWeLink z kilkoma kanałami (jedno urządzenie huba na kanał).
bool ewelinkMultiChannel(String? model) => model == 'strip';

/// Urządzenie podrzędne (`GET /api/devices`).
class HubChild {
  const HubChild({
    required this.id,
    required this.adapter,
    required this.host,
    this.type,
    this.name,
    this.model,
    this.channel,
    this.mirror = true,
    this.linked = false,
    this.online = false,
    this.error,
    this.state = const {},
    this.deviceId,
  });

  final String id;
  final HubAdapter adapter;
  final String host;

  /// `switch` / `dimmer` / `sensor`; null = hub jeszcze wykrywa.
  final String? type;
  final String? name;
  final String? model;
  final int? channel;

  /// false = bez lustra w chmurze (np. termostat tylko do automatyk).
  final bool mirror;

  /// Zapis w chmurze działa (właściciel wpisał `deviceIndex/{id}/via`).
  final bool linked;
  final bool online;

  /// `offline`, `unauthorized`, `password`, `not_gen2`, `key` (eWeLink: zły klucz), `HTTP 404`…
  final String? error;
  final Json state;

  /// eWeLink: `deviceId` (z odpowiedzi huba albo z id `ewelink-<deviceId>[-N]`).
  final String? deviceId;

  String get label => name?.isNotEmpty == true ? name! : id;

  factory HubChild.fromJson(Json j) => HubChild(
    id: asString(j['id'], 'id'),
    adapter: HubAdapter.fromWire(j['adapter']),
    host: asString(j['host'], 'host'),
    type: asStringOrNull(j['type'], 'type'),
    name: asStringOrNull(j['name'], 'name'),
    model: asStringOrNull(j['model'], 'model'),
    channel: asIntOrNull(j['channel'], 'channel'),
    mirror: j['mirror'] != false,
    linked: asBool(j['linked'], 'linked'),
    online: asBool(j['online'], 'online'),
    error: asStringOrNull(j['error'], 'error'),
    state: asObjectOrNull(j['state'], 'state') ?? const {},
    deviceId:
        asStringOrNull(j['deviceId'], 'deviceId') ??
        RegExp(r'^ewelink-([0-9a-zA-Z]+)').firstMatch(asString(j['id'], 'id'))?.group(1),
  );
}

/// Znalezione w sieci, jeszcze niedodane (`GET /api/discover`).
class HubFound {
  const HubFound({required this.adapter, required this.host, this.id, this.model, this.type, this.deviceId});

  final HubAdapter adapter;
  final String host;
  final String? id;
  final String? model;
  final String? type;

  /// eWeLink: identyfikator urządzenia z TXT `id`.
  final String? deviceId;

  factory HubFound.fromJson(Json j) => HubFound(
    adapter: HubAdapter.fromWire(j['adapter']),
    host: asString(j['host'], 'host'),
    id: asStringOrNull(j['id'], 'id'),
    model: asStringOrNull(j['model'], 'model'),
    type: asStringOrNull(j['type'], 'type'),
    deviceId: asStringOrNull(j['deviceId'], 'deviceId'),
  );
}

/// Wynik wykrywania: skan trwa ~10 s w tle, aplikacja odpytuje, aż `scanning: false`.
class HubDiscovery {
  const HubDiscovery({required this.scanning, this.age, this.found = const []});

  final bool scanning;
  final int? age;
  final List<HubFound> found;

  factory HubDiscovery.fromJson(Json j) => HubDiscovery(
    scanning: asBool(j['scanning'], 'scanning'),
    age: asIntOrNull(j['age'], 'age'),
    found: [
      for (final f in (j['found'] is List ? j['found'] as List : const []))
        if (f is Map) HubFound.fromJson(f.cast<String, dynamic>()),
    ],
  );
}

/// Automatyka (`homes/{h}/automations/{id}`, ARCHITEKTURA pkt 4.5). Wyzwalacze, warunki i akcje zostają
/// mapami JSON - edytor buduje znane rodzaje, nieznane przenosi bez zmian.
class Automation {
  const Automation({
    required this.id,
    required this.name,
    this.enabled = true,
    this.when = const [],
    this.conditions = const [],
    this.then = const [],
    this.updatedAt,
  });

  final String id;
  final String name;
  final bool enabled;
  final List<Json> when;

  /// `if`.
  final List<Json> conditions;
  final List<Json> then;

  /// ms; przy uzgadnianiu z chmurą wygrywa nowszy.
  final int? updatedAt;

  Automation copyWith({String? name, bool? enabled, List<Json>? when, List<Json>? conditions, List<Json>? then}) =>
      Automation(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        when: when ?? this.when,
        conditions: conditions ?? this.conditions,
        then: then ?? this.then,
        updatedAt: updatedAt,
      );

  static List<Json> _list(Object? v) => [
    for (final x in (v is List ? v : const []))
      if (x is Map) x.cast<String, dynamic>(),
  ];

  factory Automation.fromJson(String id, Json j) => Automation(
    id: id,
    name: asString(j['name'], 'name', id),
    enabled: j['enabled'] != false,
    when: _list(j['when']),
    conditions: _list(j['if']),
    then: _list(j['then']),
    updatedAt: j['updatedAt'] is num ? (j['updatedAt'] as num).toInt() : null,
  );

  Json toJson({int? updatedAt}) => {
    'name': name,
    'enabled': enabled,
    'when': when,
    'if': conditions,
    'then': then,
    'updatedAt': ?(updatedAt ?? this.updatedAt),
  };
}

/// `GET /api/automations` - wpisy i diagnostyka huba.
class AutomationsInfo {
  const AutomationsInfo({
    this.items = const [],
    this.problems = const [],
    this.sunrise,
    this.sunset,
    this.timeKnown = true,
    this.pendingSync = 0,
  });

  final List<Automation> items;

  /// Np. `taras: when[0] time` - wpis z błędem hub pomija w całości.
  final List<String> problems;
  final String? sunrise;
  final String? sunset;
  final bool timeKnown;
  final int pendingSync;

  factory AutomationsInfo.fromJson(Json j) {
    final items = asObjectOrNull(j['items'], 'items') ?? const {};
    return AutomationsInfo(
      items: [
        for (final e in items.entries)
          if (e.value is Map) Automation.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
      ]..sort((a, b) => a.name.compareTo(b.name)),
      problems: [for (final p in (j['problems'] is List ? j['problems'] as List : const [])) '$p'],
      sunrise: asStringOrNull(j['sunrise'], 'sunrise'),
      sunset: asStringOrNull(j['sunset'], 'sunset'),
      timeKnown: j['timeKnown'] != false,
      pendingSync: asInt(j['pendingSync'], 'pendingSync'),
    );
  }
}

/// Wpis dziennika (`homes/{h}/automationLog`, `GET /api/automations/log`).
class HubLogEntry {
  const HubLogEntry({
    required this.ts,
    required this.kind,
    this.id,
    this.name,
    this.trigger,
    this.ok = true,
    this.error,
    this.text,
  });

  final int ts;

  /// `scene` | `automation` | `log`.
  final String kind;
  final String? id;
  final String? name;
  final String? trigger;
  final bool ok;
  final String? error;
  final String? text;

  factory HubLogEntry.fromJson(Json j) => HubLogEntry(
    ts: j['ts'] is num ? (j['ts'] as num).toInt() : 0,
    kind: asString(j['kind'], 'kind', 'log'),
    id: asStringOrNull(j['id'], 'id'),
    name: asStringOrNull(j['name'], 'name'),
    trigger: asStringOrNull(j['trigger'], 'trigger'),
    ok: j['ok'] != false,
    error: asStringOrNull(j['error'], 'error'),
    text: asStringOrNull(j['text'], 'text'),
  );
}

/// Powiadomienie z huba (`homes/{h}/notifications/{klucz}`, akcja `notify`).
class HubNotification {
  const HubNotification({required this.key, required this.ts, required this.text, this.level = 'info', this.id});

  final String key;
  final int ts;
  final String text;

  /// `info` | `warning` | `alarm`.
  final String level;

  /// Automatyka, która je wysłała.
  final String? id;

  factory HubNotification.fromJson(String key, Json j) => HubNotification(
    key: key,
    ts: j['ts'] is num ? (j['ts'] as num).toInt() : 0,
    text: asString(j['text'], 'text'),
    level: asString(j['level'], 'level', 'info'),
    id: asStringOrNull(j['id'], 'id'),
  );
}

/// Identyfikator automatyki / sceny w hubie: `[a-z0-9-]`, 3-40 znaków.
String hubDocId(String name) {
  const pl = {'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z'};
  final base = name
      .toLowerCase()
      .split('')
      .map((c) => pl[c] ?? c)
      .join()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(4);
  final id = base.isEmpty ? 'a-$suffix' : '${base.length > 30 ? base.substring(0, 30) : base}-$suffix';
  return id.length < 3 ? '$id-x' : id;
}
