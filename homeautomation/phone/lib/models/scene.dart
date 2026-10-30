// Sceny (ARCHITEKTURA.md pkt 4.6, API.md pkt 11-13): `homes/{h}/scenes/{id}` `{"name","actions":[...]}`.
// Akcje jak w automatykach: `{"device","set"}`, `{"delay": s}`, `{"scene": id}`, `{"notify","level"}`, `{"log"}`,
// krok warunkowy `{"if":[warunki],"then":[akcje],"else":[akcje]}` (ARCHITEKTURA pkt 4.5, wykonuje hub).
// Pisze właściciel domu; `updatedAt` (ms) - przy uzgadnianiu z hubem wygrywa nowszy (pkt 11).

import 'json_utils.dart';

/// Jedna akcja sceny.
class SceneAction {
  const SceneAction.set(String this.device, Json this.set)
    : delay = null,
      scene = null,
      notify = null,
      level = null,
      log = null,
      raw = null;
  const SceneAction.delay(int this.delay)
    : device = null,
      set = null,
      scene = null,
      notify = null,
      level = null,
      log = null,
      raw = null;
  const SceneAction.scene(String this.scene)
    : device = null,
      set = null,
      delay = null,
      notify = null,
      level = null,
      log = null,
      raw = null;
  const SceneAction.notify(String this.notify, {this.level = 'info'})
    : device = null,
      set = null,
      delay = null,
      scene = null,
      log = null,
      raw = null;
  const SceneAction.log(String this.log)
    : device = null,
      set = null,
      delay = null,
      scene = null,
      notify = null,
      level = null,
      raw = null;

  /// Krok warunkowy (`if` / `then` / `else`) albo akcja nieznana tej wersji - zapisywana bez zmian.
  const SceneAction.raw(Json this.raw)
    : device = null,
      set = null,
      delay = null,
      scene = null,
      notify = null,
      level = null,
      log = null;

  final String? device;
  final Json? set;

  /// Sekundy.
  final int? delay;

  /// Inna scena.
  final String? scene;

  /// Powiadomienie domowników (`homes/{h}/notifications`, wysyła hub) i jego waga `info|warning|alarm`.
  final String? notify;
  final String? level;

  /// Wpis w dzienniku huba.
  final String? log;

  /// Akcja w postaci JSON-a ([SceneAction.raw]).
  final Json? raw;

  bool get isSet => device != null && set != null;

  /// Krok warunkowy „Jeśli…”.
  bool get isBranch => raw?['if'] is List;

  static SceneAction? fromJson(Json j) {
    final device = j['device'], set = j['set'], delay = j['delay'], scene = j['scene'];
    if (device is String && set is Map) return SceneAction.set(device, set.cast<String, dynamic>());
    if (delay is num) return SceneAction.delay(delay.toInt());
    if (scene is String) return SceneAction.scene(scene);
    if (j['notify'] is String) {
      return SceneAction.notify(j['notify'] as String, level: j['level'] is String ? j['level'] as String : 'info');
    }
    if (j['log'] is String) return SceneAction.log(j['log'] as String);
    return j.isEmpty ? null : SceneAction.raw(j);
  }

  Json toJson() => raw ?? {
    'device': ?device,
    'set': ?set,
    'delay': ?delay,
    'scene': ?scene,
    'notify': ?notify,
    if (notify != null) 'level': level ?? 'info',
    'log': ?log,
  };
}

class Scene {
  const Scene({required this.id, required this.name, this.actions = const []});

  final String id;
  final String name;
  final List<SceneAction> actions;

  /// Urządzenia, którymi steruje scena (bez zagnieżdżonych scen).
  Set<String> get devices => {for (final a in actions) ?a.device};

  Scene copyWith({String? name, List<SceneAction>? actions}) =>
      Scene(id: id, name: name ?? this.name, actions: actions ?? this.actions);

  factory Scene.fromJson(String id, Json j) => Scene(
    id: id,
    name: asString(j['name'], 'name', 'Scena'),
    actions: [
      for (final a in (j['actions'] is List ? j['actions'] as List : const []))
        if (a is Map) ?SceneAction.fromJson(a.cast<String, dynamic>()),
    ],
  );

  Json toJson() => {
    'name': name,
    'actions': [for (final a in actions) a.toJson()],
  };
}
