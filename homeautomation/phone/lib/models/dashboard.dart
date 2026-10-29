// Pulpity (kontrakt pkt 13): prywatne `users/{uid}/dashboards/{homeId}/{id}`,
// wspólne `homes/{homeId}/dashboards/{id}`. Widżet sceny wskazuje `homes/{h}/scenes/{id}` (`sceneId`).
// Rozszerzony układ (pkt 13.1): siatka 4 kolumn, sekcje, pola wyglądu kafelka, pokrętło, wskaźnik, wykresy.

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
  scene('scene', 'Scena'),

  /// Półokrągły suwak do punktu `setpoint` (pkt 13.1).
  dial('dial', 'Pokrętło'),

  /// Półokrągły wskaźnik, tylko odczyt (pkt 13.1).
  gauge('gauge', 'Wskaźnik'),

  /// Kilka wyjść jednym kafelkiem (`members`, pkt 13.1).
  group('group', 'Grupa'),

  /// Pogoda z termostatu (`outdoor` w State, pkt 13.1).
  weather('weather', 'Pogoda'),

  /// Stan huba (pkt 13.1).
  hub('hub', 'Hub');

  const WidgetView(this.wire, this.label);

  final String wire;
  final String label;

  static WidgetView fromWire(Object? v) => values.firstWhere((w) => w.wire == v, orElse: () => value);

  static bool known(Object? v) => values.any((w) => w.wire == v);
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

/// Szybkie sterowanie w kafelku (`features`, pkt 13.1): `slider|stepper|modes|channels|trend`.
class TileFeature {
  const TileFeature(this.type, [this.point]);

  final String type;
  final String? point;

  Json toJson() => {'type': type, 'point': ?point};
}

/// Strefa wskaźnika: od, do, kolor (`amber|green|blue|red`).
typedef GaugeZone = ({double from, double to, String color});

/// Seria wykresu: urządzenie, punkt, linia (`smooth|step|band`).
typedef ChartSeries = ({String device, String point, String line});

/// Pola widżetu spoza pkt 13 - zostają w [DashWidget.extra].
const _coreKeys = {'id', 'view', 'size', 'device', 'point', 'label', 'sceneId', 'icon'};

double? _num(Object? v) => v is num ? v.toDouble() : null;
List<String>? _strings(Object? v) => v is List ? [for (final x in v) '$x'] : null;
List<Object?> _list(Object? v) => v is List ? v : (v is Map ? v.values.toList() : const []);

class DashWidget {
  const DashWidget({
    required this.id,
    required this.view,
    this.size = WidgetSize.s1x1,
    this.device,
    this.point,
    this.label,
    this.sceneId,
    this.icon,
    this.extra = const {},
    this.rawView,
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

  /// Wybrana ikona (klucz z katalogu aplikacji, np. `ceiling`); null = domyślna dla punktu / urządzenia.
  final String? icon;

  /// Pola z pkt 13.1 i nieznane (od nowszych wersji) - zapisywane bez zmian; czytane getterami niżej,
  /// zmieniane przez [patch].
  final Json extra;

  /// `view` nieznany tej wersji - kafelek jak `value`, zapis bez zmian.
  final String? rawView;

  bool get isScene => view == WidgetView.scene;

  // ---- pkt 13.1
  String? get section => extra['section'] as String?;
  int? get w => (extra['w'] as num?)?.toInt();
  int? get h => (extra['h'] as num?)?.toInt();

  /// `auto|amber|blue|green|red|purple|grey`; null = auto (akcent).
  String? get color => extra['color'] as String?;

  /// `state|lastChanged|point:<klucz>|none`; null = state.
  String? get secondary => extra['secondary'] as String?;

  /// `s|m|l|auto`; null = auto.
  String? get iconSize => extra['iconSize'] as String?;

  /// `toggle|scene|details|device|none`; null = domyślnie dla widoku.
  String? get iconTap => extra['iconTap'] as String?;
  String? get tap => extra['tap'] as String?;
  bool get confirm => extra['confirm'] == true;

  List<TileFeature> get features => [
    for (final f in _list(extra['features']))
      if (f is Map && f['type'] is String) TileFeature(f['type'] as String, f['point'] as String?),
  ];

  /// Kanały węzła (`toggle` na `on`) w wybranej kolejności; null = wszystkie.
  List<String>? get points => _strings(extra['points']);

  /// Napisy stanu `[fałsz, prawda]` (`status`).
  List<String>? get labels {
    final l = _strings(extra['labels']);
    return l != null && l.length == 2 ? l : null;
  }

  double? get min => _num(extra['min']);
  double? get max => _num(extra['max']);

  List<GaugeZone> get zones => [
    for (final z in _list(extra['zones']))
      if (z is List && z.length == 3 && z[0] is num && z[1] is num && z[2] is String)
        (from: (z[0] as num).toDouble(), to: (z[1] as num).toDouble(), color: z[2] as String),
  ];

  /// Członkowie grupy (`group`): urządzenie i wyjście (`on` / `onN`).
  List<({String device, String point})> get members => [
    for (final m in _list(extra['members']))
      if (m is Map && m['device'] is String && m['point'] is String)
        (device: m['device'] as String, point: m['point'] as String),
  ];

  /// Znacznik celu wskaźnika (`point:<klucz>`).
  String? get target => extra['target'] as String?;

  List<ChartSeries> get series => [
    for (final x in _list(extra['series']))
      if (x is Map && x['device'] is String && x['point'] is String)
        (device: x['device'] as String, point: x['point'] as String, line: x['line'] as String? ?? 'smooth'),
  ];

  /// `6h|24h|7d|30d`; null = 24h.
  String? get range => extra['range'] as String?;
  bool get rangeSwitch => extra['rangeSwitch'] == true;
  double? get yMin => _num(extra['yMin']);
  double? get yMax => _num(extra['yMax']);
  double? get ref => _num(extra['ref']);

  /// Szerokość / wysokość w siatce 4 kolumn: `w`/`h` albo z `size` (`1x1` → 2×2, `2x1` → 4×2, `2x2` → 4×4).
  int get gridW => (w ?? (size == WidgetSize.s1x1 ? 2 : 4)).clamp(1, 4);
  int get gridH => (h ?? (size == WidgetSize.s2x2 ? 4 : 2)).clamp(1, 4);

  DashWidget _with({Json? extra, WidgetSize? size}) => DashWidget(
    id: id,
    view: view,
    size: size ?? this.size,
    device: device,
    point: point,
    label: label,
    sceneId: sceneId,
    icon: icon,
    extra: extra ?? this.extra,
    rawView: rawView,
  );

  /// Zmiana pól z pkt 13.1; null usuwa pole.
  DashWidget patch(Json changes) {
    final e = {...extra};
    for (final c in changes.entries) {
      if (c.value == null) {
        e.remove(c.key);
      } else {
        e[c.key] = c.value;
      }
    }
    return _with(extra: e);
  }

  /// Rozmiar w siatce 4 (`w`, `h`) i najbliższy dawny `size` dla starszych wersji.
  DashWidget resized(int w, int h) => _with(
    extra: {...extra, 'w': w, 'h': h},
    size: w <= 2 ? WidgetSize.s1x1 : (h >= 4 ? WidgetSize.s2x2 : WidgetSize.s2x1),
  );

  DashWidget copyWith({
    String? id,
    WidgetView? view,
    WidgetSize? size,
    String? label,
    bool clearLabel = false,
    String? icon,
    bool clearIcon = false,
  }) => DashWidget(
    id: id ?? this.id,
    view: view ?? this.view,
    size: size ?? this.size,
    device: device,
    point: point,
    label: clearLabel ? null : label ?? this.label,
    sceneId: sceneId,
    icon: clearIcon ? null : icon ?? this.icon,
    extra: extra,
    rawView: view == null ? rawView : null,
  );

  factory DashWidget.fromJson(Json j) => DashWidget(
    id: asString(j['id'], 'id'),
    view: WidgetView.fromWire(j['view']),
    size: WidgetSize.fromWire(j['size']),
    device: asStringOrNull(j['device'], 'device'),
    point: asStringOrNull(j['point'], 'point'),
    label: asStringOrNull(j['label'], 'label'),
    sceneId: asStringOrNull(j['sceneId'], 'sceneId'),
    icon: asStringOrNull(j['icon'], 'icon'),
    extra: {
      for (final e in j.entries)
        if (!_coreKeys.contains(e.key)) e.key: e.value,
    },
    rawView: WidgetView.known(j['view']) || j['view'] is! String ? null : j['view'] as String,
  );

  Json toJson() => {
    ...extra,
    'id': id,
    'view': rawView ?? view.wire,
    'size': size.wire,
    'device': ?device,
    'point': ?point,
    'label': ?label,
    'sceneId': ?sceneId,
    'icon': ?icon,
  };
}

/// Gdzie leży pulpit.
enum DashboardScope { private, shared }

/// Sekcja pulpitu z nagłówkiem (pkt 13.1).
class DashSection {
  const DashSection({required this.id, required this.title, this.room});

  final String id;
  final String title;

  /// Pokój, z którego sekcję utworzono.
  final String? room;

  factory DashSection.fromJson(Json j) => DashSection(
    id: asString(j['id'], 'id'),
    title: asString(j['title'], 'title'),
    room: asStringOrNull(j['room'], 'room'),
  );

  Json toJson() => {'id': id, 'title': title, 'room': ?room};
}

class Dashboard {
  const Dashboard({
    required this.id,
    required this.name,
    required this.scope,
    this.order = 0,
    this.widgets = const [],
    this.grid = 2,
    this.sections = const [],
  });

  final String id;
  final String name;
  final DashboardScope scope;
  final int order;
  final List<DashWidget> widgets;

  /// Kolumny siatki: 2 (dawna, wiersz 128 px) albo 4 (pkt 13.1, wiersz 64 px).
  final int grid;
  final List<DashSection> sections;

  Dashboard copyWith({
    String? id,
    String? name,
    DashboardScope? scope,
    int? order,
    List<DashWidget>? widgets,
    int? grid,
    List<DashSection>? sections,
  }) => Dashboard(
    id: id ?? this.id,
    name: name ?? this.name,
    scope: scope ?? this.scope,
    order: order ?? this.order,
    widgets: widgets ?? this.widgets,
    grid: grid ?? this.grid,
    sections: sections ?? this.sections,
  );

  factory Dashboard.fromJson(String id, DashboardScope scope, Json j) => Dashboard(
    id: id,
    scope: scope,
    name: asString(j['name'], 'name', 'Pulpit'),
    order: asInt(j['order'], 'order'),
    widgets: [
      for (final w in _list(j['widgets']))
        if (w is Map) DashWidget.fromJson(w.cast<String, dynamic>()),
    ],
    grid: j['grid'] == 4 ? 4 : 2,
    sections: [
      for (final x in _list(j['sections']))
        if (x is Map && x['id'] is String) DashSection.fromJson(x.cast<String, dynamic>()),
    ],
  );

  Json toJson() => {
    'name': name,
    'order': order,
    if (grid == 4) 'grid': 4,
    if (sections.isNotEmpty) 'sections': [for (final x in sections) x.toJson()],
    'widgets': [for (final w in widgets) w.toJson()],
  };

  /// Przejście na siatkę 4 kolumn: każdy widżet dostaje `w`/`h` z dawnego `size` (wygląd prawie bez zmian).
  Dashboard toGrid4() =>
      grid == 4 ? this : copyWith(grid: 4, widgets: [for (final w in widgets) w.resized(w.gridW, w.gridH)]);
}

/// `users/{uid}/prefs/{homeId}` (pulpit zegarka jest osobno - pkt 13a).
class HomePrefs {
  const HomePrefs({this.defaultDashboard});

  final String? defaultDashboard;

  factory HomePrefs.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    return HomePrefs(defaultDashboard: j['defaultDashboard'] as String?);
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
