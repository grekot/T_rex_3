// Pulpity (kontrakt pkt 13): prywatne `users/{uid}/dashboards/{homeId}/{id}`,
// wspólne `homes/{homeId}/dashboards/{id}`. Widżet sceny wskazuje `homes/{h}/scenes/{id}` (`sceneId`).

import 'json_utils.dart';

/// Wygląd widżetu.
enum WidgetView {
  value('value', 'Wartość'),
  toggle('toggle', 'Przełącznik'),
  slider('slider', 'Suwak'),
  stepper('stepper', 'Plus / minus'),
  status('status', 'Stan'),
  chart('chart', 'Wykres'),
  thermostat('thermostat', 'Termostat'),
  scene('scene', 'Scena');

  const WidgetView(this.wire, this.label);

  final String wire;
  final String label;

  static WidgetView fromWire(Object? v) => values.firstWhere((w) => w.wire == v, orElse: () => value);
}

enum WidgetSize {
  s1x1('1x1', 1, 1),
  s2x1('2x1', 2, 1),
  s2x2('2x2', 2, 2);

  const WidgetSize(this.wire, this.columns, this.rows);

  final String wire;
  final int columns;
  final int rows;

  static WidgetSize fromWire(Object? v) => values.firstWhere((s) => s.wire == v, orElse: () => s1x1);
}

class DashWidget {
  const DashWidget({
    required this.id,
    required this.view,
    this.size = WidgetSize.s1x1,
    this.device,
    this.point,
    this.label,
    this.sceneId,
  });

  final String id;
  final WidgetView view;
  final WidgetSize size;
  final String? device;

  /// Klucz punktu danych z `describe`.
  final String? point;
  final String? label;

  /// Scena `homes/{h}/scenes/{id}` (widok `scene`).
  final String? sceneId;

  bool get isScene => view == WidgetView.scene;

  DashWidget copyWith({WidgetSize? size, String? label}) => DashWidget(
    id: id,
    view: view,
    size: size ?? this.size,
    device: device,
    point: point,
    label: label ?? this.label,
    sceneId: sceneId,
  );

  factory DashWidget.fromJson(Json j) => DashWidget(
    id: asString(j['id'], 'id'),
    view: WidgetView.fromWire(j['view']),
    size: WidgetSize.fromWire(j['size']),
    device: asStringOrNull(j['device'], 'device'),
    point: asStringOrNull(j['point'], 'point'),
    label: asStringOrNull(j['label'], 'label'),
    sceneId: asStringOrNull(j['sceneId'], 'sceneId'),
  );

  Json toJson() => {
    'id': id,
    'view': view.wire,
    'size': size.wire,
    'device': ?device,
    'point': ?point,
    'label': ?label,
    'sceneId': ?sceneId,
  };
}

/// Gdzie leży pulpit.
enum DashboardScope { private, shared }

class Dashboard {
  const Dashboard({
    required this.id,
    required this.name,
    required this.scope,
    this.order = 0,
    this.widgets = const [],
  });

  final String id;
  final String name;
  final DashboardScope scope;
  final int order;
  final List<DashWidget> widgets;

  Dashboard copyWith({
    String? id,
    String? name,
    DashboardScope? scope,
    int? order,
    List<DashWidget>? widgets,
  }) => Dashboard(
    id: id ?? this.id,
    name: name ?? this.name,
    scope: scope ?? this.scope,
    order: order ?? this.order,
    widgets: widgets ?? this.widgets,
  );

  factory Dashboard.fromJson(String id, DashboardScope scope, Json j) => Dashboard(
    id: id,
    scope: scope,
    name: asString(j['name'], 'name', 'Pulpit'),
    order: asInt(j['order'], 'order'),
    widgets: [
      for (final w in (j['widgets'] is List ? j['widgets'] as List : const []))
        if (w is Map) DashWidget.fromJson(w.cast<String, dynamic>()),
    ],
  );

  Json toJson() => {
    'name': name,
    'order': order,
    'widgets': [for (final w in widgets) w.toJson()],
  };
}

/// `users/{uid}/prefs/{homeId}` (pulpit zegarka jest osobno - pkt 13a).
class HomePrefs {
  const HomePrefs({this.defaultDashboard});

  final String? defaultDashboard;

  factory HomePrefs.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    return HomePrefs(
      defaultDashboard: j['defaultDashboard'] as String?,
    );
  }

  Json toJson() => {'defaultDashboard': ?defaultDashboard};
}

/// Nowy identyfikator widżetu / pulpitu.
String newLocalId(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// Przesuwa element listy z [from] na [to] (jak ReorderableListView).
List<T> reorder<T>(List<T> list, int from, int to) {
  final l = [...list];
  final item = l.removeAt(from);
  l.insert(to > from ? to - 1 : to, item);
  return l;
}
