// Sceny (ARCHITEKTURA.md pkt 4.6, API.md pkt 11-13): `homes/{h}/scenes/{id}` `{"name","actions":[...]}`.
// Akcje jak w automatykach: `{"device","set"}`, `{"delay": s}`, `{"scene": id}`. Pisze właściciel domu.

import 'json_utils.dart';

/// Jedna akcja sceny.
class SceneAction {
  const SceneAction.set(String this.device, Json this.set) : delay = null, scene = null;
  const SceneAction.delay(int this.delay) : device = null, set = null, scene = null;
  const SceneAction.scene(String this.scene) : device = null, set = null, delay = null;

  final String? device;
  final Json? set;

  /// Sekundy.
  final int? delay;

  /// Inna scena.
  final String? scene;

  bool get isSet => device != null && set != null;

  static SceneAction? fromJson(Json j) {
    final device = j['device'], set = j['set'], delay = j['delay'], scene = j['scene'];
    if (device is String && set is Map) return SceneAction.set(device, set.cast<String, dynamic>());
    if (delay is num) return SceneAction.delay(delay.toInt());
    if (scene is String) return SceneAction.scene(scene);
    return null;
  }

  Json toJson() => {'device': ?device, 'set': ?set, 'delay': ?delay, 'scene': ?scene};
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
