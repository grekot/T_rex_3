// Widżety na ekranie Androida: co pokazują. Dom jest zapisany razem z widżetem, żeby usługa w tle ruszyła
// bez internetu (poziomy dostępu i tak pilnuje urządzenie).

import 'json_utils.dart';

enum HomeWidgetKind {
  output('output'),
  thermostat('thermostat'),
  scene('scene'),

  /// Czujnik: nazwa i do 3 wartości (punkty `sensor` z `describe`).
  sensor('sensor');

  const HomeWidgetKind(this.wire);

  final String wire;

  static HomeWidgetKind? fromWire(Object? v) => values.where((k) => k.wire == v).firstOrNull;
}

/// Wygląd pozycji widżetu (wszystko opcjonalne, brak = jak dotąd).
class WidgetItemLook {
  const WidgetItemLook({this.label, this.icon, this.color, this.main, this.more, this.tap});

  /// Własny podpis zamiast nazwy urządzenia / kanału / sceny.
  final String? label;

  /// Klucz ikony z katalogu aplikacji (`app_icons.dart`).
  final String? icon;

  /// `amber|blue|green|red|purple|grey` - tło włączonej pozycji i kolor ikony; null = pomarańczowy akcent.
  final String? color;

  /// Czujnik: główna (duża) wartość - klucz punktu; null = temperatura, potem inne wg kolejności.
  final String? main;

  /// Czujnik: wartości pod główną (do 2), termostat: `target` / `hum` pod temperaturą; null = domyślne,
  /// pusta lista = nic.
  final List<String>? more;

  /// Wyjście: `open` = dotknięcie otwiera urządzenie zamiast przełączać; null = przełącza.
  final String? tap;

  bool get isEmpty => label == null && icon == null && color == null && main == null && more == null && tap == null;

  static WidgetItemLook fromJson(Json j) => WidgetItemLook(
    label: j['label'] is String && (j['label'] as String).isNotEmpty ? j['label'] as String : null,
    icon: j['icon'] is String ? j['icon'] as String : null,
    color: j['color'] is String ? j['color'] as String : null,
    main: j['main'] is String ? j['main'] as String : null,
    more: j['more'] is List
        ? [
            for (final x in j['more'] as List)
              if (x is String) x,
          ]
        : null,
    tap: j['tap'] is String ? j['tap'] as String : null,
  );

  Json toJson() => {'label': ?label, 'icon': ?icon, 'color': ?color, 'main': ?main, 'more': ?more, 'tap': ?tap};

  @override
  bool operator ==(Object other) =>
      other is WidgetItemLook &&
      other.label == label &&
      other.icon == icon &&
      other.color == color &&
      other.main == main &&
      other.tap == tap &&
      (other.more == null) == (more == null) &&
      (more == null || other.more!.join('|') == more!.join('|'));

  @override
  int get hashCode => Object.hash(label, icon, color, main, more?.join('|'), tap);
}

/// Pozycja widżetu: wyjście (`point`: `on` albo `onN`), termostat, scena albo czujnik, z wyglądem [look].
/// Równość (wybór na liście) - tylko po tym, co pokazuje, bez wyglądu.
class HomeWidgetItem {
  const HomeWidgetItem.output(String this.device, String this.point, {this.look = const WidgetItemLook()})
    : kind = HomeWidgetKind.output,
      sceneId = null;
  const HomeWidgetItem.thermostat(String this.device, {this.look = const WidgetItemLook()})
    : kind = HomeWidgetKind.thermostat,
      point = null,
      sceneId = null;
  const HomeWidgetItem.scene(String this.sceneId, {this.look = const WidgetItemLook()})
    : kind = HomeWidgetKind.scene,
      device = null,
      point = null;
  const HomeWidgetItem.sensor(String this.device, {this.look = const WidgetItemLook()})
    : kind = HomeWidgetKind.sensor,
      point = null,
      sceneId = null;

  const HomeWidgetItem._(this.kind, this.device, this.point, this.sceneId, this.look);

  final HomeWidgetKind kind;
  final String? device;
  final String? point;
  final String? sceneId;
  final WidgetItemLook look;

  HomeWidgetItem withLook(WidgetItemLook look) => HomeWidgetItem._(kind, device, point, sceneId, look);

  static HomeWidgetItem? fromJson(Json j) {
    final device = j['device'], point = j['point'], scene = j['scene'];
    final look = WidgetItemLook.fromJson(j);
    return switch (HomeWidgetKind.fromWire(j['kind'])) {
      HomeWidgetKind.output when device is String && point is String => HomeWidgetItem.output(
        device,
        point,
        look: look,
      ),
      HomeWidgetKind.thermostat when device is String => HomeWidgetItem.thermostat(device, look: look),
      HomeWidgetKind.scene when scene is String => HomeWidgetItem.scene(scene, look: look),
      HomeWidgetKind.sensor when device is String => HomeWidgetItem.sensor(device, look: look),
      _ => null,
    };
  }

  Json toJson() => {'kind': kind.wire, 'device': ?device, 'point': ?point, 'scene': ?sceneId, ...look.toJson()};

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
/// [icon]: `bulb`, `thermostat`, `flame`, `scene`, `sensor`, `lock` (ikona zapasowa Androida); [iconKey] - ikona
/// z katalogu aplikacji (usługa rysuje ją do obrazka, `iconPng`). [color] - nazwany kolor (`amber|blue|…`): tło
/// włączonej kratki i kolor ikony. [open] - dotknięcie otwiera to urządzenie w aplikacji.
class WidgetCell {
  const WidgetCell({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.value,
    this.active = false,
    this.dimmed = false,
    this.open,
    this.iconKey,
    this.color,
  });

  final String title;
  final String subtitle;
  final String icon;
  final String? value;
  final bool active;
  final bool dimmed;
  final String? open;
  final String? iconKey;
  final String? color;

  WidgetCell copyWith({String? subtitle, bool? active}) => WidgetCell(
    title: title,
    subtitle: subtitle ?? this.subtitle,
    icon: icon,
    value: value,
    active: active ?? this.active,
    dimmed: dimmed,
    open: open,
    iconKey: iconKey,
    color: color,
  );

  Json toJson() => {
    'title': title,
    'subtitle': subtitle,
    'icon': icon,
    'value': ?value,
    'active': active,
    'dimmed': dimmed,
    'open': ?open,
    'iconKey': ?iconKey,
    'color': ?color,
  };
}
