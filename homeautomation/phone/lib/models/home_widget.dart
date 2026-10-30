// Widżety na ekranie Androida: co pokazują. Dom jest zapisany razem z widżetem, żeby usługa w tle ruszyła
// bez internetu (poziomy dostępu i tak pilnuje urządzenie).

import 'json_utils.dart';

enum HomeWidgetKind {
  output('output'),
  thermostat('thermostat'),
  scene('scene');

  const HomeWidgetKind(this.wire);

  final String wire;

  static HomeWidgetKind? fromWire(Object? v) => values.where((k) => k.wire == v).firstOrNull;
}

/// Pozycja widżetu: wyjście (`point`: `on` albo `onN`), termostat albo scena.
class HomeWidgetItem {
  const HomeWidgetItem.output(String this.device, String this.point) : kind = HomeWidgetKind.output, sceneId = null;
  const HomeWidgetItem.thermostat(String this.device) : kind = HomeWidgetKind.thermostat, point = null, sceneId = null;
  const HomeWidgetItem.scene(String this.sceneId) : kind = HomeWidgetKind.scene, device = null, point = null;

  final HomeWidgetKind kind;
  final String? device;
  final String? point;
  final String? sceneId;

  static HomeWidgetItem? fromJson(Json j) {
    final device = j['device'], point = j['point'], scene = j['scene'];
    return switch (HomeWidgetKind.fromWire(j['kind'])) {
      HomeWidgetKind.output when device is String && point is String => HomeWidgetItem.output(device, point),
      HomeWidgetKind.thermostat when device is String => HomeWidgetItem.thermostat(device),
      HomeWidgetKind.scene when scene is String => HomeWidgetItem.scene(scene),
      _ => null,
    };
  }

  Json toJson() => {'kind': kind.wire, 'device': ?device, 'point': ?point, 'scene': ?sceneId};

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetItem &&
      other.kind == kind &&
      other.device == device &&
      other.point == point &&
      other.sceneId == sceneId;

  @override
  int get hashCode => Object.hash(kind, device, point, sceneId);
}

/// Widżet o identyfikatorze Androida [id]. [homeId] `local` = dom w telefonie, bez konta.
class HomeWidgetConfig {
  const HomeWidgetConfig({
    required this.id,
    required this.homeId,
    this.homeName = '',
    this.ownerUid = '',
    required this.items,
  });

  static const localHome = 'local';

  /// Najwięcej pozycji w jednym widżecie.
  static const maxItems = 6;

  final int id;
  final String homeId;
  final String homeName;
  final String ownerUid;
  final List<HomeWidgetItem> items;

  factory HomeWidgetConfig.fromJson(Json j) => HomeWidgetConfig(
    id: asInt(j['id'], 'id'),
    homeId: asString(j['homeId'], 'homeId', localHome),
    homeName: asString(j['homeName'], 'homeName', ''),
    ownerUid: asString(j['ownerUid'], 'ownerUid', ''),
    items: [
      for (final i in (j['items'] is List ? j['items'] as List : const []))
        if (i is Map) ?HomeWidgetItem.fromJson(i.cast<String, dynamic>()),
    ],
  );

  Json toJson() => {
    'id': id,
    'homeId': homeId,
    'homeName': homeName,
    'ownerUid': ownerUid,
    'items': [for (final i in items) i.toJson()],
  };
}

/// Jedna kratka widżetu do narysowania po stronie Androida.
/// [icon]: `bulb`, `thermostat`, `flame`, `scene`, `lock`. [open] - dotknięcie otwiera to urządzenie w aplikacji.
class WidgetCell {
  const WidgetCell({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.value,
    this.active = false,
    this.dimmed = false,
    this.open,
  });

  final String title;
  final String subtitle;
  final String icon;
  final String? value;
  final bool active;
  final bool dimmed;
  final String? open;

  WidgetCell copyWith({String? subtitle, bool? active}) => WidgetCell(
    title: title,
    subtitle: subtitle ?? this.subtitle,
    icon: icon,
    value: value,
    active: active ?? this.active,
    dimmed: dimmed,
    open: open,
  );

  Json toJson() => {
    'title': title,
    'subtitle': subtitle,
    'icon': icon,
    'value': ?value,
    'active': active,
    'dimmed': dimmed,
    'open': ?open,
  };
}
