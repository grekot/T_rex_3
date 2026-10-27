// Pulpit zegarka (kontrakt pkt 13a): zegarki osoby `users/{uid}/watches/{watchId}` (zapisuje je zegarek)
// i pulpit `users/{uid}/watchDashboards/{homeId}/{watchId}` (układa aplikacja na telefonie).
// Układ kafelków jest przeniesiony 1:1 z aplikacji zegarka (`homeautomation/watch/utils/layout.js`),
// żeby podgląd na telefonie wyglądał jak na zegarku.

import 'dart:math' as math;

import 'json_utils.dart';

enum WatchShape {
  round('round', 'okrągły'),
  square('square', 'prostokątny');

  const WatchShape(this.wire, this.label);

  final String wire;
  final String label;

  static WatchShape fromWire(Object? v) => v == 'square' ? square : round;
}

/// Zegarek (zgłoszony sam albo wybrany z listy modeli).
class WatchInfo {
  const WatchInfo({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.shape,
    this.app,
    this.lastSeen,
    this.registered = false,
  });

  /// `deviceSource` (zgłoszony) albo `model:<nazwa>` (z listy).
  final String id;
  final String name;
  final int width;
  final int height;
  final WatchShape shape;

  /// Wersja aplikacji „Dom” na zegarku.
  final String? app;

  /// ms.
  final int? lastSeen;

  /// Zgłosił się sam (`users/{uid}/watches`).
  final bool registered;

  String get resolution => '$width×$height, ${shape.label}';

  factory WatchInfo.fromJson(String id, Json j) => WatchInfo(
    id: id,
    name: asString(j['name'], 'name', 'Zegarek $id'),
    width: asInt(j['width'], 'width', 480),
    height: asInt(j['height'], 'height', 480),
    shape: WatchShape.fromWire(j['shape']),
    app: asStringOrNull(j['app'], 'app'),
    lastSeen: j['lastSeen'] is num ? (j['lastSeen'] as num).toInt() : null,
    registered: true,
  );

  /// Pole `watch` pulpitu: dla jakiego ekranu układano.
  Json screenJson() => {'width': width, 'height': height, 'shape': shape.wire};
}

/// Popularne zegarki Amazfit z Zepp OS, gdy żaden jeszcze się nie zgłosił.
/// Rozdzielczości i kształty z kart technicznych producenta (amazfit.com, specyfikacja ekranu)
/// i listy urządzeń Zepp OS dla deweloperów (docs.zepp.com, „Device list”) - przy nowym modelu sprawdź tam.
const builtInWatches = [
  WatchInfo(id: 'model:t-rex-3', name: 'Amazfit T-Rex 3', width: 480, height: 480, shape: WatchShape.round),
  WatchInfo(id: 'model:balance', name: 'Amazfit Balance', width: 480, height: 480, shape: WatchShape.round),
  WatchInfo(id: 'model:cheetah-pro', name: 'Amazfit Cheetah Pro', width: 480, height: 480, shape: WatchShape.round),
  WatchInfo(id: 'model:gtr-4', name: 'Amazfit GTR 4', width: 466, height: 466, shape: WatchShape.round),
  WatchInfo(id: 'model:active-2', name: 'Amazfit Active 2', width: 466, height: 466, shape: WatchShape.round),
  WatchInfo(id: 'model:t-rex-ultra', name: 'Amazfit T-Rex Ultra', width: 454, height: 454, shape: WatchShape.round),
  WatchInfo(id: 'model:gts-4', name: 'Amazfit GTS 4', width: 390, height: 450, shape: WatchShape.square),
  WatchInfo(id: 'model:active', name: 'Amazfit Active', width: 390, height: 450, shape: WatchShape.square),
  WatchInfo(id: 'model:gts-4-mini', name: 'Amazfit GTS 4 Mini', width: 336, height: 384, shape: WatchShape.square),
  WatchInfo(id: 'model:bip-5', name: 'Amazfit Bip 5', width: 320, height: 380, shape: WatchShape.square),
];

/// Widoki dostępne na zegarku (bez wykresów i suwaków).
enum WatchView {
  value('value', 'Wartość'),
  toggle('toggle', 'Przełącznik'),
  stepper('stepper', 'Plus / minus'),
  status('status', 'Stan'),
  thermostat('thermostat', 'Termostat'),
  scene('scene', 'Scena');

  const WatchView(this.wire, this.label);

  final String wire;
  final String label;

  static WatchView fromWire(Object? v) => values.firstWhere((w) => w.wire == v, orElse: () => value);
}

enum WatchTileSize {
  half('half', 'pół wiersza'),
  full('full', 'cały wiersz'),
  big('big', 'duży');

  const WatchTileSize(this.wire, this.label);

  final String wire;
  final String label;

  static WatchTileSize fromWire(Object? v) => values.firstWhere((s) => s.wire == v, orElse: () => full);

  /// Domyślny rozmiar dla widoku.
  static WatchTileSize defaultFor(WatchView v) => switch (v) {
    WatchView.thermostat => big,
    WatchView.scene || WatchView.stepper => full,
    _ => half,
  };
}

class WatchTile {
  const WatchTile({
    required this.id,
    required this.view,
    this.size = WatchTileSize.half,
    this.device,
    this.point,
    this.label,
    this.sceneId,
  });

  final String id;
  final WatchView view;
  final WatchTileSize size;
  final String? device;
  final String? point;
  final String? label;
  final String? sceneId;

  WatchTile copyWith({WatchTileSize? size, String? label, bool clearLabel = false}) => WatchTile(
    id: id,
    view: view,
    size: size ?? this.size,
    device: device,
    point: point,
    label: clearLabel ? null : label ?? this.label,
    sceneId: sceneId,
  );

  factory WatchTile.fromJson(Json j) => WatchTile(
    id: asString(j['id'], 'id'),
    view: WatchView.fromWire(j['view']),
    size: WatchTileSize.fromWire(j['size']),
    device: asStringOrNull(j['device'], 'device'),
    point: asStringOrNull(j['point'], 'point'),
    label: asStringOrNull(j['label'], 'label'),
    sceneId: asStringOrNull(j['sceneId'], 'sceneId'),
  );

  Json toJson() => {
    'id': id,
    'device': ?device,
    'point': ?point,
    'sceneId': ?sceneId,
    'view': view.wire,
    'size': size.wire,
    'label': ?label,
  };
}

class WatchPage {
  const WatchPage({this.title = '', this.tiles = const []});

  final String title;
  final List<WatchTile> tiles;

  WatchPage copyWith({String? title, List<WatchTile>? tiles}) =>
      WatchPage(title: title ?? this.title, tiles: tiles ?? this.tiles);

  factory WatchPage.fromJson(Json j) => WatchPage(
    title: asString(j['title'], 'title'),
    tiles: [
      for (final t in (j['tiles'] is List ? j['tiles'] as List : const []))
        if (t is Map) WatchTile.fromJson(t.cast<String, dynamic>()),
    ],
  );

  Json toJson() => {
    'title': title,
    'tiles': [for (final t in tiles) t.toJson()],
  };
}

/// `users/{uid}/watchDashboards/{homeId}/{watchId}`.
class WatchDashboard {
  const WatchDashboard({required this.pages, this.screen});

  final List<WatchPage> pages;

  /// Dla jakiego ekranu układano (`watch`); zegarek i tak układa pod własny ekran.
  final Json? screen;

  factory WatchDashboard.fromJson(Json j) => WatchDashboard(
    screen: asObjectOrNull(j['watch'], 'watch'),
    pages: [
      for (final p in (j['pages'] is List ? j['pages'] as List : const []))
        if (p is Map) WatchPage.fromJson(p.cast<String, dynamic>()),
    ],
  );

  Json toJson(WatchInfo watch, Object updatedAt) => {
    'watch': watch.screenJson(),
    'pages': [for (final p in pages) p.toJson()],
    'updatedAt': updatedAt,
  };
}

// ---- Układ (jak `watch/utils/layout.js`) ----

/// Stałe układu zegarka (px ekranu zegarka).
abstract final class WatchGeometry {
  static const top = 92; // pod tytułem i linią stanu
  static const header = 40; // nagłówek strony
  static const row = 88; // wiersz half / full
  static const big = 186; // wiersz big (dwa wiersze + odstęp)
  static const gap = 10;
  static const margin = 14; // od krawędzi koła
  static const maxWidth = 400;
  static const minWidth = 220;
  static const bottom = 70; // pod ostatnim wierszem
}

/// Prostokąt nagłówka (`tile == null`) albo kafelka.
class WatchBlock {
  const WatchBlock({this.header, this.tile, this.size, required this.x, required this.y, required this.w, required this.h});

  final String? header;
  final WatchTile? tile;
  final WatchTileSize? size;
  final int x, y, w, h;
}

/// Kafelki → wiersze: dwa `half` obok siebie, `half` bez pary zostaje sam (na środku).
List<(WatchTileSize, List<WatchTile>)> watchRows(List<WatchTile> tiles) {
  final rows = <(WatchTileSize, List<WatchTile>)>[];
  List<WatchTile>? pending;
  for (final t in tiles) {
    if (t.size == WatchTileSize.half) {
      if (pending != null) {
        pending.add(t);
        pending = null;
      } else {
        pending = [t];
        rows.add((WatchTileSize.half, pending));
      }
      continue;
    }
    pending = null;
    rows.add((t.size, [t]));
  }
  return rows;
}

/// Układ stron na ekranie zegarka: bloki (współrzędne w px treści) i wysokość treści.
({List<WatchBlock> blocks, int height}) layoutWatchPages(List<WatchPage> pages, int width, int height, WatchShape shape) {
  final round = shape == WatchShape.round;
  final rows = <({String? header, (WatchTileSize, List<WatchTile>)? row, int y, int h})>[];
  var y = WatchGeometry.top;
  for (final page in pages) {
    if (page.tiles.isEmpty) continue;
    if (page.title.isNotEmpty) {
      rows.add((header: page.title, row: null, y: y, h: WatchGeometry.header));
      y += WatchGeometry.header;
    }
    for (final row in watchRows(page.tiles)) {
      final h = row.$1 == WatchTileSize.big ? WatchGeometry.big : WatchGeometry.row;
      rows.add((header: null, row: row, y: y, h: h));
      y += h + WatchGeometry.gap;
    }
  }
  final total = y + WatchGeometry.bottom;
  final maxScroll = math.max(0, total - height);

  int widthAt(int top, int h) {
    if (!round) return math.min(WatchGeometry.maxWidth, width - 2 * WatchGeometry.margin);
    // przewinięcie, które stawia wiersz najbliżej środka ekranu
    final s = math.min(maxScroll.toDouble(), math.max(0.0, top + h / 2 - height / 2));
    final cy = height / 2;
    final d = math.max((top - s - cy).abs(), (top + h - s - cy).abs());
    final r = math.min(width, height) / 2;
    final half = d >= r ? 0.0 : math.sqrt(r * r - d * d);
    final w = 2 * half - 2 * WatchGeometry.margin;
    return _jsRound(math.max(WatchGeometry.minWidth.toDouble(), math.min(WatchGeometry.maxWidth.toDouble(), w)));
  }

  final blocks = <WatchBlock>[];
  for (final r in rows) {
    final w = widthAt(r.y, r.h);
    final x = _jsRound((width - w) / 2);
    final row = r.row;
    if (row == null) {
      blocks.add(WatchBlock(header: r.header, x: x, y: r.y, w: w, h: r.h));
      continue;
    }
    final two = row.$1 == WatchTileSize.half;
    final tw = two ? ((w - WatchGeometry.gap) / 2).floor() : w;
    final startX = two && row.$2.length == 1 ? _jsRound((width - tw) / 2) : x;
    for (final (i, t) in row.$2.indexed) {
      blocks.add(WatchBlock(tile: t, size: row.$1, x: startX + i * (tw + WatchGeometry.gap), y: r.y, w: tw, h: r.h));
    }
  }
  return (blocks: blocks, height: total);
}

/// `Math.round` z JS (połówki w górę).
int _jsRound(double v) => (v + 0.5).floor();
