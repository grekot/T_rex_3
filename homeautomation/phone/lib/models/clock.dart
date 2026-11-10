// Zegar-termometr `clock` (kontrakt pkt 10.2, `nodes/deskclock/PLAN.md` pkt 1.5, 8.6, 9): ekrany, przejścia,
// strony z widżetami (siatka 4×3, tylko stan) - wyliczanie par `device`/`point`, limity, przenoszenie z pulpitu.

import 'dart:convert';

import 'dashboard.dart';
import 'describe.dart';
import 'json_utils.dart';

/// Ekrany wbudowane (`screens.list`), w kolejności proponowanej.
const clockScreens = {
  'main': 'Główny',
  'hours': 'Pogoda co godzinę',
  'days': 'Pogoda na 5 dni',
  'chart': 'Wykres pokoju',
  'calendar': 'Kalendarz',
  'air': 'Powietrze',
};

/// Opisy ekranów wbudowanych.
const clockScreenHints = {
  'main': 'godzina, pokój, pogoda teraz, komfort',
  'hours': 'temperatura i opady na najbliższe godziny',
  'days': 'kolejne dni z ikoną i min / max',
  'chart': 'temperatura i wilgotność pokoju z 24 h',
  'calendar': 'data, imieniny, święta, słońce i księżyc, kalendarz domu',
  'air': 'AQI, pyły, pyłki, UV (z huba)',
};

const clockTransitions = {
  'cards': 'Karty kaskadą',
  'slide': 'Przesunięcie',
  'cover': 'Nasunięcie',
  'fade': 'Przenikanie',
  'none': 'Bez animacji',
};

const clockNightModes = {
  'off': 'wyłączony',
  'schedule': 'w godzinach',
  'lux': 'według światła',
  'both': 'godziny albo światło',
};

const clockNightScreens = {'clock': 'sama godzina', 'clockTemp': 'godzina i temperatura', 'off': 'wygaszony'};

/// Motyw zegara (`theme.name`, nodes/deskclock/src/GuiTheme.cpp): nazwa i kolory do podglądu w aplikacji -
/// tło, karta, tekst na karcie, kafle pokój / wilgotność / ciśnienie / pogoda.
typedef ClockTheme = ({String label, int bg, int card, int ink, List<int> tiles});

const clockThemes = <String, ClockTheme>{
  'pastel': (
    label: 'Pastel',
    bg: 0xFFEEF1F6,
    card: 0xFFFFFFFF,
    ink: 0xFF1B1F2A,
    tiles: [0xFFFFD8C7, 0xFFD2E6FF, 0xFFE4DCFF, 0xFFFFE9A8],
  ),
  'contrast': (
    label: 'Kontrastowy',
    bg: 0xFFE4E6EA,
    card: 0xFFFFFFFF,
    ink: 0xFF000000,
    tiles: [0xFFFFB08A, 0xFF86BDFF, 0xFFC2B0FF, 0xFFFFD43B],
  ),
  'dark': (
    label: 'Ciemny',
    bg: 0xFF0B0D12,
    card: 0xFF171B24,
    ink: 0xFFF2F4F8,
    tiles: [0xFF3A2219, 0xFF172A45, 0xFF2A2145, 0xFF3A3015],
  ),
  'winter': (
    label: 'Zima',
    bg: 0xFFDCEBF7,
    card: 0xFFFFFFFF,
    ink: 0xFF163150,
    tiles: [0xFFE8F3FB, 0xFFD6EEF3, 0xFFE3E4F6, 0xFFFFFFFF],
  ),
  'winterNight': (
    label: 'Zima (noc)',
    bg: 0xFF0E1B2E,
    card: 0xFF16263D,
    ink: 0xFFEAF4FF,
    tiles: [0xFF1C3150, 0xFF183A44, 0xFF252B52, 0xFF1C3150],
  ),
  'xmas': (
    label: 'Boże Narodzenie',
    bg: 0xFF7E1622,
    card: 0xFFFFF8EC,
    ink: 0xFF3A0D12,
    tiles: [0xFFF7DFD2, 0xFFDDEBD7, 0xFFF6E8C4, 0xFFE6F0DA],
  ),
  'xmasNight': (
    label: 'Boże Narodzenie (wieczór)',
    bg: 0xFF0F2A1E,
    card: 0xFF173A2A,
    ink: 0xFFFFF6E2,
    tiles: [0xFF4A1A1F, 0xFF1F4A33, 0xFF4A3B14, 0xFF5E1A22],
  ),
  'spring': (
    label: 'Wiosna',
    bg: 0xFFEAF5E4,
    card: 0xFFFFFFFF,
    ink: 0xFF1F3320,
    tiles: [0xFFFCDDE6, 0xFFD5ECF7, 0xFFE9E0FA, 0xFFFFF2B3],
  ),
  'easter': (
    label: 'Wielkanoc',
    bg: 0xFFFFF8E1,
    card: 0xFFFFFFFF,
    ink: 0xFF3A3020,
    tiles: [0xFFFFE0CC, 0xFFDCEFD0, 0xFFEADFF7, 0xFFFFEFA8],
  ),
  'summer': (
    label: 'Lato',
    bg: 0xFFE3F6F7,
    card: 0xFFFFFFFF,
    ink: 0xFF0E3340,
    tiles: [0xFFFFE1C4, 0xFFC9F0F2, 0xFFE2E4FA, 0xFFFFE680],
  ),
  'autumn': (
    label: 'Jesień',
    bg: 0xFFF4E7D7,
    card: 0xFFFFFAF2,
    ink: 0xFF3B2414,
    tiles: [0xFFF8D3B5, 0xFFDCE3D0, 0xFFEAD9CF, 0xFFF7DC9C],
  ),
};

/// Format daty na ekranie (`clock.dateFormat`).
const clockDateFormats = {'long': 'środa, 4 listopada', 'short': 'śr 04.11'};

/// Polecenia `showScreen` poza ekranami.
const clockCommands = {
  'next': 'Następny ekran',
  'prev': 'Poprzedni ekran',
  'home': 'Ekran główny',
  'wake': 'Rozjaśnij (noc)',
  'info': 'Ekran informacyjny',
};

const clockMaxScreens = 6;
const clockMaxPages = 4;
const clockMaxWidgets = 10;
const clockMaxPairs = 24;
const clockMaxPagesBytes = 6144;
const clockCols = 4;
const clockRows = 3;

/// Widoki, które zegar rysuje (pkt 10.2) - sterujące jako stan, `scene` i `gate` bez czujnika pominięte.
const clockViews = {
  WidgetView.value,
  WidgetView.status,
  WidgetView.valueList,
  WidgetView.level,
  WidgetView.gauge,
  WidgetView.chart,
  WidgetView.thermostat,
  WidgetView.group,
  WidgetView.room,
  WidgetView.hub,
};

/// Widok na zegarze dla widoku z telefonu; null = pomijany.
WidgetView? clockViewFor(DashWidget w) => switch (w.view) {
  final v when clockViews.contains(v) => v,
  WidgetView.toggle => WidgetView.status,
  WidgetView.slider || WidgetView.stepper || WidgetView.dial => WidgetView.value,
  WidgetView.gate when w.sensor != null => WidgetView.status,
  WidgetView.weather => WidgetView.value,
  _ => null,
};

/// Nazwa ekranu: wbudowany albo strona `page:<id>`.
String clockScreenName(String key, List<ClockPage> pages) {
  if (key.startsWith('page:')) {
    final p = pages.where((p) => 'page:${p.id}' == key).firstOrNull;
    return p == null ? 'Strona (usunięta)' : 'Strona: ${p.title}';
  }
  return clockScreens[key] ?? clockCommands[key] ?? key;
}

/// Strona z widżetami (`pages[]`).
class ClockPage {
  const ClockPage({required this.id, required this.title, this.widgets = const []});

  final String id;
  final String title;
  final List<DashWidget> widgets;

  ClockPage copyWith({String? title, List<DashWidget>? widgets}) =>
      ClockPage(id: id, title: title ?? this.title, widgets: widgets ?? this.widgets);

  static List<ClockPage> listFrom(Object? config) {
    final pages = config is Map ? config['pages'] : null;
    return [
      for (final p in (pages is List ? pages : const []))
        if (p is Map && p['id'] is String)
          ClockPage(
            id: p['id'] as String,
            title: p['title'] is String ? p['title'] as String : 'Strona',
            widgets: [
              for (final w in (p['widgets'] is List ? p['widgets'] as List : const []))
                if (w is Map && w['id'] is String) DashWidget.fromJson(w.cast<String, dynamic>()),
            ],
          ),
    ];
  }

  Json toJson() => {
    'id': id,
    'title': title,
    'widgets': [for (final w in widgets) clockWidgetJson(w)],
  };
}

/// Pola widżetu, które zegar rozumie (reszta z pulpitu - np. `size`, `tap`, `features` - nie trafia do Config).
const _clockKeys = {
  'id', 'view', 'device', 'point', 'points', 'items', 'series', 'members', 'x', 'y', 'w', 'h', 'label', //
  'unit', 'decimals', 'labels', 'min', 'max', 'zones', 'color', 'icon', 'range',
};

Json clockWidgetJson(DashWidget w) => {
  for (final e in w.toJson().entries)
    if (_clockKeys.contains(e.key) && e.value != null) e.key: e.value,
};

/// Pary `device`/`point` widżetu (z `point`, `points`, `items`, `series`, `members`) - jak `Wants.cpp` zegara.
Iterable<(String, String)> clockWidgetPairs(DashWidget w) sync* {
  final d = w.device;
  if (d != null) {
    if (w.point != null) yield (d, w.point!);
    for (final p in w.points ?? const <String>[]) {
      yield (d, p);
    }
  }
  for (final i in w.items) {
    yield (i.device, i.point);
  }
  for (final s in w.series) {
    yield (s.device, s.point);
  }
  for (final m in w.members) {
    yield (m.device, m.point);
  }
}

/// Wszystkie różne pary ze stron.
Set<(String, String)> clockPairs(Iterable<ClockPage> pages) => {
  for (final p in pages)
    for (final w in p.widgets) ...clockWidgetPairs(w),
};

/// Rozmiar `pages` w Config (bajty JSON-a, limit 6 kB).
int clockPagesBytes(List<ClockPage> pages) => utf8.encode(jsonEncode([for (final p in pages) p.toJson()])).length;

/// Problemy przed zapisem stron (jak zegar: `pages: too_many|length`, `pages.<id>.<wid>: view|value`).
List<String> clockPagesProblems(List<ClockPage> pages) {
  final out = <String>[
    if (pages.length > clockMaxPages) 'Najwyżej $clockMaxPages strony.',
    for (final p in pages)
      if (p.widgets.length > clockMaxWidgets) 'Strona „${p.title}”: najwyżej $clockMaxWidgets widżetów.',
  ];
  final pairs = clockPairs(pages).length;
  if (pairs > clockMaxPairs) out.add('Za dużo odczytów: $pairs (najwyżej $clockMaxPairs różnych punktów).');
  final bytes = clockPagesBytes(pages);
  if (bytes > clockMaxPagesBytes) out.add('Strony zajmują ${(bytes / 1024).toStringAsFixed(1)} kB (najwyżej 6 kB).');
  for (final p in pages) {
    for (final w in p.widgets) {
      if (!clockViews.contains(w.view)) out.add('„${w.label ?? w.id}”: zegar nie pokazuje widoku ${w.view.label}.');
      final x = w.x ?? 0, y = w.y ?? 0;
      if (x < 0 || y < 0 || x + clockW(w) > clockCols || y + clockH(w) > clockRows) {
        out.add('„${w.label ?? w.id}”: poza siatką 4×3.');
      }
    }
  }
  return out;
}

/// Szerokość i wysokość widżetu na zegarze (bez `w` / `h` - 1).
int clockW(DashWidget w) => (w.w ?? 1).clamp(1, clockCols);
int clockH(DashWidget w) => (w.h ?? 1).clamp(1, clockRows);

/// Zajęte komórki siatki 4×3 przez widżety z pozycją.
List<List<bool>> _occupied(Iterable<DashWidget> widgets) {
  final grid = List.generate(clockRows, (_) => List.filled(clockCols, false));
  for (final w in widgets) {
    final x = w.x, y = w.y;
    if (x == null || y == null) continue;
    for (var r = y; r < y + clockH(w) && r < clockRows; r++) {
      for (var c = x; c < x + clockW(w) && c < clockCols; c++) {
        if (r >= 0 && c >= 0) grid[r][c] = true;
      }
    }
  }
  return grid;
}

/// Pierwsze wolne miejsce na widżet [w]×[h] (od lewej, z góry) albo null.
(int, int)? clockFreeSpot(Iterable<DashWidget> widgets, int w, int h) {
  final grid = _occupied(widgets);
  for (var y = 0; y + h <= clockRows; y++) {
    for (var x = 0; x + w <= clockCols; x++) {
      var free = true;
      for (var r = y; r < y + h && free; r++) {
        for (var c = x; c < x + w; c++) {
          if (grid[r][c]) {
            free = false;
            break;
          }
        }
      }
      if (free) return (x, y);
    }
  }
  return null;
}

/// Widżety z pulpitu telefonu na strony zegara: widoki wg [clockViewFor] (sceny i sterowanie bez stanu pomijane),
/// rozmiar przycięty do 4×3, po kolei na pierwsze wolne miejsce; nowa strona, gdy się nie mieści albo po 10.
/// Zwraca strony i nazwy pominiętych.
({List<ClockPage> pages, List<String> skipped}) clockPagesFromDashboard(
  List<DashWidget> widgets, {
  required String title,
  required String Function() newId,
}) {
  final pages = <ClockPage>[];
  final skipped = <String>[];
  var current = <DashWidget>[];
  void flush() {
    if (current.isEmpty) return;
    final n = pages.length + 1;
    pages.add(ClockPage(id: newId(), title: n == 1 ? title : '$title $n', widgets: current));
    current = [];
  }

  for (final w in widgets) {
    final view = clockViewFor(w);
    final noData = w.device == null && w.room == null && w.items.isEmpty && w.members.isEmpty && w.series.isEmpty;
    if (view == null || noData) {
      skipped.add(w.label ?? w.view.label);
      continue;
    }
    // Sterowanie bez stanu (brama z czujnikiem) - stan z czujnika.
    var cw = w.view == WidgetView.gate && w.sensor != null
        ? DashWidget(id: w.id, view: view, device: w.sensor!.device, point: w.sensor!.point, label: w.label)
        : w.copyWith(view: view);
    final gw = w.gridW.clamp(1, clockCols), gh = (w.gridH > clockRows ? clockRows : w.gridH).clamp(1, clockRows);
    cw = cw.patch({'x': null, 'y': null, 'section': null, 'w': gw, 'h': gh});
    var spot = current.length >= clockMaxWidgets ? null : clockFreeSpot(current, gw, gh);
    if (spot == null) {
      flush();
      spot = (0, 0);
    }
    current.add(cw.patch({'x': spot.$1, 'y': spot.$2}));
  }
  flush();
  return (pages: pages, skipped: skipped);
}

/// Punkty czujnika na zewnątrz (Config `outdoor`, pkt 10.2): temperatura (°C) i wilgotność (%) z `describe`.
List<DataPoint> clockOutdoorTempPoints(List<DataPoint> points) => [
  for (final p in points)
    if (p.kind == PointKind.sensor && p.unit == '°C') p,
];

List<DataPoint> clockOutdoorHumPoints(List<DataPoint> points) => [
  for (final p in points)
    if (p.kind == PointKind.sensor && p.unit == '%') p,
];

/// Config `outdoor` po wyborze urządzenia: punkt `temp` (gdy jest, inaczej pierwszy °C), `hum` (gdy jest, inaczej
/// pierwszy %, bez wilgotności - `""`).
Json clockOutdoorFor(String device, List<DataPoint> points) {
  String pick(List<DataPoint> list, String def, String none) =>
      list.any((p) => p.key == def) ? def : list.firstOrNull?.key ?? none;
  return {
    'device': device,
    'temp': pick(clockOutdoorTempPoints(points), 'temp', 'temp'),
    'hum': pick(clockOutdoorHumPoints(points), 'hum', ''),
  };
}

/// Domyślne punkty widżetów bez `point` (pkt 10.2): termostat i hub.
const clockThermostatPoints = ['temp', 'target', 'heating', 'mode'];
const clockHubPoints = ['online', 'devices', 'lastRun'];

/// Kolory kafli stylu C (makieta „C · Strona z widżetami”): tło, etykieta, wartość.
const clockTileColors = {
  'amber': (0xFFFFD8C7, 0xFF8A3A17, 0xFF5C2108),
  'blue': (0xFFD2E6FF, 0xFF1F5FAD, 0xFF0F3A70),
  'green': (0xFFCDEFD9, 0xFF1E6B3F, 0xFF0E3D22),
  'red': (0xFFFFD3DD, 0xFF9A2848, 0xFF5E1028),
  'purple': (0xFFE4DCFF, 0xFF5B3FB8, 0xFF33207A),
  'grey': (0xFFE3E6EC, 0xFF5A6275, 0xFF1B1F2A),
};
