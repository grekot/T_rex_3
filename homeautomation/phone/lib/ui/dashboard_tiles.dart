import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../data/history.dart';
import '../data/hub_api.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/home.dart';
import '../models/hub.dart';
import '../models/json_utils.dart';
import '../models/scene.dart';
import '../data/device_icons.dart';
import 'app_icons.dart';
import 'device_tiles.dart';
import 'generic_device_screen.dart' show canSet;
import 'point_controls.dart';
import 'tile_charts.dart';

/// Historia pola urządzenia do wykresu ([hours] wstecz); null = bez chmury (wykresy niedostępne).
typedef HistorySource = Future<List<HistoryPoint>> Function(String deviceId, String field, {int hours});

/// Wysokość jednego wiersza dawnej siatki 2 kolumn.
const dashRowHeight = 128.0;
const dashGap = 8.0;

/// Wysokość wiersza siatki 4 kolumn (pkt 13.1).
const dashRow4 = 64.0;

/// Wymiary kafelka w pikselach przy szerokości siatki [width].
Size dashTileSize(DashWidget w, int grid, double width) {
  if (grid == 4) {
    final col = (width - 3 * dashGap) / 4;
    return Size(w.gridW * col + (w.gridW - 1) * dashGap, w.gridH * dashRow4 + (w.gridH - 1) * dashGap);
  }
  final col = (width - dashGap) / 2;
  return Size(w.size.columns == 2 ? width : col, w.size.rows * dashRowHeight + (w.size.rows - 1) * dashGap);
}

/// Siatka pulpitu. [grid] 2: dawna (2 kolumny, `1x1`/`2x1`/`2x2`); 4: kolumny 1-4 × wiersze 64 px (`w`, `h`),
/// kafelki układane po kolei w pierwszym wolnym miejscu, w którym się mieszczą (mniejsze wypełniają luki).
class DashGrid extends StatelessWidget {
  const DashGrid({super.key, required this.widgets, required this.builder, this.grid = 2});

  final List<DashWidget> widgets;
  final Widget Function(DashWidget w) builder;
  final int grid;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (grid != 4) {
          return Wrap(
            spacing: dashGap,
            runSpacing: dashGap,
            children: [
              for (final w in widgets)
                SizedBox.fromSize(key: ValueKey(w.id), size: dashTileSize(w, 2, box.maxWidth), child: builder(w)),
            ],
          );
        }
        final col = (box.maxWidth - 3 * dashGap) / 4;
        final placed = packGrid4(widgets);
        final rows = placed.isEmpty ? 0 : placed.map((p) => p.row + p.widget.gridH).reduce(math.max);
        return SizedBox(
          height: rows == 0 ? 0 : rows * dashRow4 + (rows - 1) * dashGap,
          child: Stack(
            children: [
              for (final p in placed)
                Positioned(
                  key: ValueKey(p.widget.id),
                  left: p.col * (col + dashGap),
                  top: p.row * (dashRow4 + dashGap),
                  child: SizedBox.fromSize(size: dashTileSize(p.widget, 4, box.maxWidth), child: builder(p.widget)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Miejsca kafelków w siatce 4 kolumn: każdy w pierwszym wolnym polu (od góry, od lewej), w którym się mieści.
List<({DashWidget widget, int row, int col})> packGrid4(List<DashWidget> widgets) {
  final taken = <List<bool>>[];
  bool free(int r, int c, int w, int h) {
    for (var y = r; y < r + h; y++) {
      for (var x = c; x < c + w; x++) {
        if (y < taken.length && taken[y][x]) return false;
      }
    }
    return true;
  }

  final out = <({DashWidget widget, int row, int col})>[];
  for (final w in widgets) {
    final gw = w.gridW, gh = w.gridH;
    for (var r = 0; ; r++) {
      final c = [for (var x = 0; x + gw <= 4; x++) x].where((x) => free(r, x, gw, gh)).firstOrNull;
      if (c == null) continue;
      while (taken.length < r + gh) {
        taken.add(List.filled(4, false));
      }
      for (var y = r; y < r + gh; y++) {
        for (var x = c; x < c + gw; x++) {
          taken[y][x] = true;
        }
      }
      out.add((widget: w, row: r, col: c));
      break;
    }
  }
  return out;
}

/// Punkt, gdy urządzenie (jeszcze) nie podało `describe` - znane pola z kontraktu.
DataPoint fallbackPoint(String key) => switch (key) {
  'temp' => const DataPoint(
    key: 'temp',
    name: 'Temperatura',
    kind: PointKind.sensor,
    unit: '°C',
    decimals: 1,
    history: 't',
  ),
  'hum' => const DataPoint(key: 'hum', name: 'Wilgotność', kind: PointKind.sensor, unit: '%', decimals: 0),
  'outdoor.temp' => const DataPoint(
    key: 'outdoor.temp',
    name: 'Na zewnątrz',
    kind: PointKind.sensor,
    unit: '°C',
    decimals: 1,
    history: 'out',
  ),
  'target' => const DataPoint(
    key: 'target',
    name: 'Nastawa',
    kind: PointKind.setpoint,
    unit: '°C',
    min: 15,
    max: 30,
    step: 0.5,
    access: AccessLevel.control,
    history: 'target',
  ),
  'heating' => const DataPoint(key: 'heating', name: 'Grzanie', kind: PointKind.status, history: 'heat'),
  'mode' => const DataPoint(
    key: 'mode',
    name: 'Tryb',
    kind: PointKind.select,
    options: ['manual', 'auto'],
    access: AccessLevel.control,
  ),
  'on' => const DataPoint(key: 'on', name: 'Włączone', kind: PointKind.switchKind, access: AccessLevel.control),
  'level' => const DataPoint(
    key: 'level',
    name: 'Jasność',
    kind: PointKind.setpoint,
    unit: '%',
    min: 0,
    max: 100,
    step: 5,
    access: AccessLevel.control,
  ),
  _ => switch (RegExp(r'^(on|in)(\d+)$').firstMatch(key)) {
    // Kanały przełącznika wielokanałowego (pkt 10.1).
    final m? when m.group(1) == 'on' => DataPoint(
      key: key,
      name: 'Kanał ${m.group(2)}',
      kind: PointKind.switchKind,
      access: AccessLevel.control,
    ),
    final m? => DataPoint(key: key, name: 'Wejście ${m.group(2)}', kind: PointKind.status),
    _ => DataPoint(key: key, name: key, kind: PointKind.sensor),
  },
};

/// Pokazuje błędy polecenia (w tym `forbidden`) jako pasek na dole.
void showSendErrors(BuildContext context, Map<String, String> errors) {
  if (errors.isEmpty || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeErrors(errors))));
}

/// Jeden widżet pulpitu w trybie podglądu. Dwie strefy dotyku: ikona wykonuje akcję główną (przełącz, scena),
/// reszta kafelka otwiera szczegóły (arkusz z pełnym sterowaniem i wykresem albo ekran urządzenia).
/// Ustawienia z pkt 13.1: kolor, druga linia, rozmiar ikony, działanie dotyku, potwierdzenie, szybkie sterowanie,
/// wybrane kanały, napisy stanu, pokrętło, wskaźnik, wykres z seriami.
class DashTile extends StatefulWidget {
  const DashTile({super.key, required this.widget, required this.hub, this.history});

  final DashWidget widget;
  final DeviceHub hub;
  final HistorySource? history;

  @override
  State<DashTile> createState() => _DashTileState();
}

/// Co robi dotyk (`iconTap` / `tap`, pkt 13.1).
VoidCallback? _tapAction(String kind, {VoidCallback? toggle, VoidCallback? details, VoidCallback? device}) =>
    switch (kind) {
      'toggle' || 'scene' => toggle,
      'details' => details,
      'device' => device,
      _ => null,
    };

class _DashTileState extends State<DashTile> {
  DashWidget get w => widget.widget;
  DeviceDescription? _desc;

  /// Połączenie, o którego opis już pytano (raz na połączenie, także gdy opisu brak).
  Object? _askedConnection;

  /// Wysłane, jeszcze niepotwierdzone wartości (kafelek zmienia się od razu): klucz pola Set → wartość.
  final _pending = <String, Object?>{};

  /// Ostatnia zmiana wartości głównego punktu widziana w aplikacji (`secondary: lastChanged`).
  Object? _lastValue;
  DateTime? _changedAt;

  DeviceController<Object?, Object?>? get _c => w.device == null ? null : widget.hub.controller(w.device!);

  void _ensureDescription() {
    final c = _c;
    final conn = c?.connection;
    if (_desc != null || c == null || conn == null || identical(conn, _askedConnection)) return;
    _askedConnection = conn;
    c.description().then((d) {
      if (mounted && d != null) setState(() => _desc = d);
    });
  }

  DataPoint? get _point {
    final key = w.point;
    if (key == null) return null;
    return _desc?.point(key) ?? fallbackPoint(key);
  }

  DataPoint _pointFor(String key) => _desc?.point(key) ?? fallbackPoint(key);

  Object? _value(String key, Json? state) => _pending.containsKey(key) ? _pending[key] : _pointFor(key).valueIn(state);

  /// Set z wartościami pokazanymi od razu ([optimistic]); po odpowiedzi stan wraca do tego, co podało urządzenie.
  Future<void> _send(
    DeviceController<Object?, Object?> c,
    Json values, [
    Map<String, Object?> optimistic = const {},
  ]) async {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _pending.addAll(optimistic));
    final r = await c.sendJson(values);
    if (!mounted) return;
    setState(() => optimistic.keys.forEach(_pending.remove));
    showSendErrors(context, r.errors);
  }

  /// `confirm: true` - pytanie przed akcją.
  VoidCallback? _confirmed(String title, VoidCallback? action) {
    if (action == null || !w.confirm) return action;
    return () async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: const Text('Na pewno wykonać?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            FilledButton(
              key: const Key('tileConfirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Wykonaj'),
            ),
          ],
        ),
      );
      if (ok == true) action();
    };
  }

  /// Druga linia wg `secondary`: stan (domyślnie), ostatnia zmiana, inny punkt, nic.
  String? _secondary(Json? state, String? byState) {
    final s = w.secondary;
    if (s == 'none') return null;
    if (s == 'lastChanged') {
      final t = _changedAt;
      if (t == null) return byState;
      String two(int x) => x.toString().padLeft(2, '0');
      return 'od ${two(t.hour)}:${two(t.minute)}';
    }
    if (s != null && s.startsWith('point:')) {
      final p = _pointFor(s.substring(6));
      return '${p.name} ${p.format(_value(p.key, state))}';
    }
    return byState;
  }

  void _track(Object? v) {
    if (_lastValue != null && v != _lastValue) _changedAt = DateTime.now();
    _lastValue = v;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.hub, builder: (context, _) => _tile(context));
  }

  Widget _tile(BuildContext context) {
    final icon = dashWidgetIcon(w, widget.hub);
    final large = w.size.rows > 1;
    if (w.isScene) return _SceneTile(widget: w, hub: widget.hub, icon: icon);
    final c = _c;
    final level = w.device == null ? AccessLevel.none : widget.hub.accessFor(w.device!);
    if (w.view == WidgetView.group) return _group(context, icon, large);
    if (c == null || level == AccessLevel.none) {
      return TileShell(
        icon: Icons.lock_outline,
        title: w.label ?? 'Widżet',
        secondary: c == null ? 'Urządzenie niedostępne' : 'Brak dostępu',
        dimmed: true,
      );
    }
    _ensureDescription();
    final state = c.stateJson;
    final p = _point;
    final title = w.label ?? p?.name ?? c.device.name;
    final offline = state == null || !c.live;
    void open() => openDevice(context, c, hub: widget.hub);
    void details() => p == null ? open() : _showDetails(context, c, p, level);
    final can = p != null && canSet(level, p) && !offline;
    if (p != null) _track(_value(p.key, state));

    /// Kafelek z ustawieniami z pkt 13.1. [primary] - akcja główna (przełącz); domyślnie ikona = [primary],
    /// kafelek = szczegóły ([defaultTap]).
    TileShell shell({
      String? secondary,
      bool active = false,
      VoidCallback? primary,
      Key? iconKey,
      String defaultTap = 'details',
      TileBadge? badge,
      Widget? body,
      bool fillBody = false,
      String? titleOverride,
    }) {
      final act = _confirmed(titleOverride ?? title, primary);
      final features = _features(c, state, level, offline);
      return TileShell(
        icon: icon,
        title: titleOverride ?? title,
        secondary: _secondary(state, secondary),
        active: active,
        iconKey: iconKey,
        onIcon: _tapAction(
          w.iconTap ?? (primary != null ? 'toggle' : defaultTap),
          toggle: act,
          details: details,
          device: open,
        ),
        onTap: _tapAction(w.tap ?? defaultTap, toggle: act, details: details, device: open),
        badge: badge,
        // Szybkie sterowanie pod treścią; na małym kafelku widać tyle, ile się zmieści (dół), bez przepełnienia.
        body: features == null
            ? body
            : SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (body != null) ...[body, const SizedBox(height: 4)],
                    features,
                  ],
                ),
              ),
        fillBody: fillBody,
        large: large,
        offline: offline,
        color: w.color,
        iconSize: w.iconSize,
      );
    }

    if (w.view == WidgetView.thermostat) return _thermostat(context, c, level, offline, icon, large);
    if (w.view == WidgetView.weather) return _weather(context, c, offline, icon, large);
    if (w.view == WidgetView.hub) return _hub(context, c, offline, icon, large);
    if (w.view == WidgetView.chart) {
      final series = w.series.isEmpty
          ? [(deviceId: c.device.id, point: p ?? fallbackPoint('temp'), line: 'smooth')]
          : [
              for (final s in w.series.take(3))
                (
                  deviceId: s.device,
                  point: s.device == c.device.id ? _pointFor(s.point) : fallbackPoint(s.point),
                  line: s.line,
                ),
            ];
      return shell(
        secondary: w.label == null ? c.device.name : null,
        fillBody: true,
        body: TileChart(
          series: series,
          history: widget.history,
          range: w.range,
          rangeSwitch: w.rangeSwitch,
          yMin: w.yMin,
          yMax: w.yMax,
          ref: w.ref,
        ),
      );
    }
    if (p == null) return shell(secondary: 'Brak punktu danych', defaultTap: 'device');
    final channels = state?['channels'] is int ? state!['channels'] as int : 1;
    switch (w.view) {
      case WidgetView.toggle when p.key == 'on' && channels > 1:
        return _outputs(context, c, level, offline, icon, large, channels);
      case WidgetView.toggle || WidgetView.value when p.kind == PointKind.action:
        return shell(
          secondary: 'Dotknij ikony, aby wykonać',
          iconKey: Key('dash-toggle-${w.id}'),
          primary: can ? () => _send(c, p.setFor(true)) : null,
        );
      case WidgetView.toggle:
        final on = _value(p.key, state) == true;
        final level0 = p.key == 'on' && state?['level'] is num ? ' · ${state!['level']}%' : '';
        return shell(
          secondary: '${on ? 'Włączone$level0' : 'Wyłączone'}${w.label == null ? ' · ${c.device.name}' : ''}',
          active: on,
          iconKey: Key('dash-toggle-${w.id}'),
          primary: can && p.kind == PointKind.switchKind ? () => _send(c, p.setFor(!on), {p.key: !on}) : null,
        );
      case WidgetView.status:
        final v = _value(p.key, state);
        final fault = RegExp(r'^in\d+$').hasMatch(p.key) && state?['${p.key}Fault'] == true;
        final labels = w.labels;
        return shell(
          secondary: fault
              ? 'Usterka - wejście zablokowane'
              : labels != null && v is bool
              ? labels[v ? 1 : 0]
              : _statusLabel(p, v),
          active: v == true,
          badge: fault ? const TileBadge('USTERKA', TileBadgeKind.error) : null,
        );
      case WidgetView.slider:
        final v = _value(p.key, state);
        final devOn = p.key == 'level' && state?['on'] is bool;
        final on = devOn ? _value('on', state) == true : v is num && v > 0;
        return shell(
          secondary: p.format(v),
          active: on,
          iconKey: Key('dash-toggle-${w.id}'),
          primary: devOn && canSet(level, _pointFor('on')) && !offline
              ? () => _send(c, {'on': !on}, {'on': !on})
              : null,
          body: p.min == null || p.max == null || v is! num
              ? null
              : SetpointSlider(
                  point: p,
                  value: v.toDouble(),
                  enabled: can,
                  onChanged: (x) => _send(c, p.setFor(x), {p.key: x}),
                ),
        );
      case WidgetView.stepper:
        return shell(
          secondary: w.label == null ? c.device.name : null,
          body: _StepperBody(
            point: p,
            value: _value(p.key, state),
            enabled: can,
            onSet: (x) => _send(c, p.setFor(x), {p.key: x}),
          ),
        );
      case WidgetView.dial:
        final v = _value(p.key, state);
        // Bieżąca wartość obok nastawy: `secondary: point:<klucz>`, a dla `target` - temperatura.
        final curKey = w.secondary != null && w.secondary!.startsWith('point:')
            ? w.secondary!.substring(6)
            : (p.key == 'target' ? 'temp' : null);
        final cur = curKey == null ? null : _value(curKey, state);
        final heating = p.key == 'target' && state?['heating'] == true;
        return shell(
          secondary: w.label == null ? c.device.name : null,
          badge: heating ? const TileBadge('GRZEJE', TileBadgeKind.heat) : null,
          fillBody: true,
          body: DialControl(
            key: Key('dial-${w.id}'),
            point: p,
            value: v is num ? v.toDouble() : null,
            enabled: can,
            current: cur is num ? cur.toDouble() : null,
            currentLabel: cur == null ? null : 'teraz ${_pointFor(curKey!).format(cur)}',
            color: w.color == null ? null : namedColor(w.color, Theme.of(context).colorScheme),
            onSet: (x) {
              final out = (p.step ?? 1) % 1 == 0 ? x.round() : x;
              _send(c, p.setFor(out), {p.key: out});
            },
          ),
        );
      case WidgetView.gauge:
        final v = _value(p.key, state);
        final t = w.target;
        final tv = t != null && t.startsWith('point:') ? _value(t.substring(6), state) : null;
        return shell(
          secondary: w.label == null ? c.device.name : null,
          fillBody: true,
          body: GaugeView(
            key: Key('gauge-${w.id}'),
            point: p,
            value: v is num ? v.toDouble() : null,
            min: w.min ?? p.min ?? 0,
            max: w.max ?? p.max ?? 100,
            zones: w.zones,
            target: tv is num ? tv.toDouble() : null,
          ),
        );
      case WidgetView.value ||
          WidgetView.scene ||
          WidgetView.thermostat ||
          WidgetView.chart ||
          WidgetView.group ||
          WidgetView.weather ||
          WidgetView.hub:
        final v = _value(p.key, state);
        return shell(
          secondary: w.label == null ? c.device.name : null,
          active: p.kind == PointKind.switchKind && v == true,
          body: p.kind == PointKind.select
              ? DropdownButton<String>(
                  isExpanded: true,
                  value: p.options.contains(v) ? v as String : null,
                  items: [for (final o in p.options) DropdownMenuItem(value: o, child: Text(optionLabel(o)))],
                  onChanged: can ? (o) => _send(c, p.setFor(o), {p.key: o}) : null,
                )
              : _BigValue(text: p.format(v), large: large),
        );
    }
  }

  /// Szybkie sterowanie w kafelku (`features`): suwak, plus / minus, tryby, kanały, trend. Null - brak.
  Widget? _features(DeviceController<Object?, Object?> c, Json? state, AccessLevel level, bool offline) {
    final list = w.features;
    if (list.isEmpty) return null;
    final items = <Widget>[];
    for (final f in list) {
      final p = f.point == null ? _point : _pointFor(f.point!);
      if (p == null) continue;
      final can = canSet(level, p) && !offline;
      final v = _value(p.key, state);
      switch (f.type) {
        case 'slider' when v is num && p.min != null && p.max != null:
          items.add(
            SetpointSlider(
              point: p,
              value: v.toDouble(),
              enabled: can,
              onChanged: (x) => _send(c, p.setFor(x), {p.key: x}),
            ),
          );
        case 'stepper':
          items.add(_StepperBody(point: p, value: v, enabled: can, onSet: (x) => _send(c, p.setFor(x), {p.key: x})));
        case 'modes' when p.options.isNotEmpty:
          items.add(
            Wrap(
              spacing: 4,
              children: [
                for (final o in p.options)
                  ChoiceChip(
                    key: Key('feat-${w.id}-${p.key}-$o'),
                    label: Text(optionLabel(o)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selected: v == o,
                    onSelected: can ? (_) => _send(c, p.setFor(o), {p.key: o}) : null,
                  ),
              ],
            ),
          );
        case 'channels':
          final n = state?['channels'] is int ? state!['channels'] as int : 1;
          if (n < 2) continue;
          final ons = [for (var i = 1; i <= n; i++) _value('on$i', state) == true];
          items.add(
            _Channels(
              widgetId: '${w.id}-f',
              names: [for (var i = 1; i <= n; i++) _desc?.point('on$i')?.name ?? 'Kanał $i'],
              on: ons,
              compact: false,
              rows: 1,
              onToggle: canSet(level, _pointFor('on1')) && !offline
                  ? (i) => _send(c, {'on$i': !ons[i - 1]}, {'on$i': !ons[i - 1]})
                  : null,
            ),
          );
        case 'trend' when p.history != null:
          items.add(
            SizedBox(
              height: 40,
              child: TileChart(series: [(deviceId: c.device.id, point: p, line: 'smooth')], history: widget.history),
            ),
          );
      }
    }
    if (items.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, x) in items.indexed) ...[if (i > 0) const SizedBox(height: 4), x],
      ],
    );
  }

  /// Grupa wyjść (`group`): ikona - gdy coś świeci, wyłącza wszystko, inaczej włącza; członkowie bez `control`
  /// albo bez połączenia są pomijani. Dotyk - lista członków z przełącznikami.
  Widget _group(BuildContext context, IconData icon, bool large) {
    final hub = widget.hub;
    final rows = [
      for (final m in w.members)
        (
          m: m,
          c: hub.controller(m.device),
          on: _pending.containsKey('${m.device}/${m.point}')
              ? _pending['${m.device}/${m.point}'] == true
              : hub.controller(m.device)?.stateJson?[m.point] == true,
        ),
    ];
    final count = rows.where((r) => r.on).length;
    final usable = [
      for (final r in rows)
        if (r.c != null && r.c!.live && hub.accessFor(r.m.device).canControl) r,
    ];
    Future<void> set(Iterable<({String device, String point})> ms, bool on) async {
      unawaited(HapticFeedback.selectionClick());
      setState(() {
        for (final m in ms) {
          _pending['${m.device}/${m.point}'] = on;
        }
      });
      final errors = <String>[];
      await Future.wait([
        for (final m in ms)
          hub.controller(m.device)!.sendJson({m.point: on}).then((r) {
            if (r.errors.isNotEmpty) {
              errors.add('${hub.device(m.device)?.name ?? m.device}: ${describeErrors(r.errors)}');
            }
          }),
      ]);
      if (!mounted || !context.mounted) return;
      setState(() {
        for (final m in ms) {
          _pending.remove('${m.device}/${m.point}');
        }
      });
      if (errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
      }
    }

    final title = w.label ?? 'Grupa';
    final toggle = usable.isEmpty ? null : () => set([for (final r in usable) r.m], count == 0);
    void list() => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: hub,
        builder: (ctx, _) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
              for (final m in w.members)
                SwitchListTile(
                  key: Key('groupMember-${m.device}-${m.point}'),
                  title: Text(hub.device(m.device)?.name ?? m.device),
                  subtitle: Text(m.point == 'on' ? 'wyjście' : 'kanał ${m.point.substring(2)}'),
                  value: hub.controller(m.device)?.stateJson?[m.point] == true,
                  onChanged: usable.any((r) => r.m == m) ? (v) => set([m], v) : null,
                ),
            ],
          ),
        ),
      ),
    );
    return TileShell(
      icon: icon,
      title: title,
      secondary: _secondary(null, rows.isEmpty ? 'Brak wyjść w grupie' : '$count z ${rows.length} włączone'),
      active: count > 0,
      large: large,
      color: w.color,
      iconSize: w.iconSize,
      dimmed: rows.isNotEmpty && usable.isEmpty,
      iconKey: Key('dash-toggle-${w.id}'),
      onIcon: _tapAction(w.iconTap ?? 'toggle', toggle: _confirmed(title, toggle), details: list, device: list),
      onTap: _tapAction(w.tap ?? 'details', toggle: _confirmed(title, toggle), details: list, device: list),
    );
  }

  /// Pogoda z termostatu (`weather`): `outdoor` `{temp, icon, age}`; przy wysokim kafelku trend z historii (`out`).
  Widget _weather(BuildContext context, DeviceController<Object?, Object?> c, bool offline, IconData icon, bool large) {
    final o = c.stateJson?['outdoor'];
    final temp = o is Map ? o['temp'] : null;
    final code = o is Map ? o['icon'] : null;
    final age = o is Map ? o['age'] : null;
    final tall = w.h != null && w.h! >= 3;
    final t = fallbackPoint('outdoor.temp');
    void open() => openDevice(context, c);
    return TileShell(
      icon: weatherIcon(code),
      title: w.label ?? 'Na zewnątrz',
      secondary: _secondary(
        c.stateJson,
        o is! Map
            ? 'Brak pogody - ustaw klucz w termostacie'
            : age is num && age > 1800
            ? 'sprzed ${age ~/ 60} min'
            : weatherLabel(code),
      ),
      large: large,
      offline: offline,
      color: w.color,
      iconSize: w.iconSize,
      onIcon: _tapAction(w.iconTap ?? 'device', details: open, device: open),
      onTap: _tapAction(w.tap ?? 'device', details: open, device: open),
      fillBody: tall,
      body: temp is! num
          ? null
          : tall
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BigValue(text: t.format(temp), large: false),
                const SizedBox(height: 4),
                Expanded(
                  child: TileChart(
                    series: [
                      (
                        deviceId: c.device.id,
                        point: const DataPoint(
                          key: 'outdoor.temp',
                          name: 'Na zewnątrz',
                          kind: PointKind.sensor,
                          unit: '°C',
                          decimals: 1,
                          history: 'out',
                        ),
                        line: 'smooth',
                      ),
                    ],
                    history: widget.history,
                  ),
                ),
              ],
            )
          : _BigValue(text: t.format(temp), large: large),
    );
  }

  /// Nazwy automatyk huba (`lastRun` podaje tylko id): z `homes/{h}/automations` albo lokalnie z API huba.
  final _automationNames = <String, String>{};
  final _askedAutomations = <String>{};

  String? _automationName(DeviceController<Object?, Object?> c, String id) {
    if (_automationNames.containsKey(id) || !_askedAutomations.add(id)) return _automationNames[id];
    Future<String?> load() async {
      final cloud = widget.hub.cloud, home = widget.hub.home;
      if (cloud.available && home != null) {
        final v = await cloud.store.read('homes/${home.id}/automations/$id/name').catchError((_) => null);
        if (v is String) return v;
      }
      final api = c.localApi;
      if (api != null) {
        final info = await HubApi(api).automations().catchError((_) => const AutomationsInfo());
        return info.items.where((a) => a.id == id).firstOrNull?.name;
      }
      return null;
    }

    load().then((name) {
      if (name != null && mounted) setState(() => _automationNames[id] = name);
    });
    return null;
  }

  /// Stan huba (`hub`): dostępne urządzenia, automatyki, trwające sceny, ostatnie wykonanie, chmura.
  Widget _hub(BuildContext context, DeviceController<Object?, Object?> c, bool offline, IconData icon, bool large) {
    final s = c.stateJson ?? const {};
    final last = s['lastRun'];
    String? lastText;
    if (last is Map && last['id'] is String) {
      final id = last['id'] as String;
      final name = last['kind'] == 'scene' ? widget.hub.scene(id)?.name ?? id : _automationName(c, id) ?? id;
      final at = last['at'];
      final when = at is num ? DateTime.fromMillisecondsSinceEpoch((at < 1e12 ? at * 1000 : at).toInt()) : null;
      String two(int x) => x.toString().padLeft(2, '0');
      lastText = [
        '${last['ok'] == false ? 'Nieudane' : 'Ostatnio'}: $name',
        if (when != null) '${two(when.hour)}:${two(when.minute)}',
      ].join(' · ');
    }
    final running = s['running'] is num ? (s['running'] as num).toInt() : 0;
    void open() => openDevice(context, c, hub: widget.hub);
    final t = Theme.of(context).textTheme;
    return TileShell(
      icon: icon,
      title: w.label ?? c.device.name,
      secondary: _secondary(
        s,
        '${s['online'] ?? '—'} z ${s['devices'] ?? '—'} urządzeń · ${s['automations'] ?? 0} automatyk',
      ),
      active: running > 0,
      large: large,
      offline: offline,
      color: w.color,
      iconSize: w.iconSize,
      badge: s['cloud'] == false && !offline ? const TileBadge('BEZ CHMURY', TileBadgeKind.error) : null,
      onIcon: _tapAction(w.iconTap ?? 'device', details: open, device: open),
      onTap: _tapAction(w.tap ?? 'device', details: open, device: open),
      body: lastText == null && running == 0
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (running > 0) Text('Trwa: $running', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (lastText != null) Text(lastText, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
    );
  }

  /// Termostat: temperatura dużą cyfrą, nastawa − / +, plakietka GRZEJE / MRÓZ / AWARIA; dotyk - ekran termostatu.
  Widget _thermostat(
    BuildContext context,
    DeviceController<Object?, Object?> c,
    AccessLevel level,
    bool offline,
    IconData icon,
    bool large,
  ) {
    final s = c.stateJson;
    final temp = fallbackPoint('temp'), target = fallbackPoint('target');
    final heating = s?['heating'] == true;
    final power = s?['power'] != false;
    final fault = s?['sensorFault'] == true || s?['protect'] == 'faultDuty';
    final mode = s?['mode'] == 'auto' ? 'AUTO' : 'Ręcznie';
    void open() => openDevice(context, c);
    return TileShell(
      icon: icon,
      title: w.label ?? c.device.name,
      secondary: _secondary(s, power ? '$mode · nastawa ${target.format(_value('target', s))}' : 'Wyłączony'),
      active: heating,
      large: large,
      offline: offline,
      color: w.color,
      iconSize: w.iconSize,
      badge: fault
          ? const TileBadge('AWARIA', TileBadgeKind.error)
          : s?['protect'] == 'frost'
          ? const TileBadge('MRÓZ', TileBadgeKind.cool)
          : heating
          ? const TileBadge('GRZEJE', TileBadgeKind.heat)
          : null,
      onIcon: _tapAction(w.iconTap ?? 'device', details: open, device: open),
      onTap: _tapAction(w.tap ?? 'device', details: open, device: open),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _BigValue(text: temp.format(temp.valueIn(s)), large: large),
          ),
          _StepperBody(
            point: target,
            value: _value('target', s),
            enabled: level.canControl && !offline && power,
            compact: true,
            onSet: (v) => _send(c, {'target': v}, {'target': v}),
          ),
        ],
      ),
    );
  }

  /// Wszystkie wyjścia węzła (`on` na urządzeniu wielokanałowym, pkt 10.1): przycisk na kanał, ikona - wszystkie;
  /// `points` - wybrane kanały i kolejność.
  Widget _outputs(
    BuildContext context,
    DeviceController<Object?, Object?> c,
    AccessLevel level,
    bool offline,
    IconData icon,
    bool large,
    int n,
  ) {
    final s = c.stateJson;
    final chosen = [
      for (final k in w.points ?? [for (var i = 1; i <= n; i++) 'on$i'])
        if (RegExp(r'^on(\d+)$').firstMatch(k) case final m? when int.parse(m.group(1)!) <= n) int.parse(m.group(1)!),
    ];
    final ons = [for (final i in chosen) _value('on$i', s) == true];
    final count = ons.where((x) => x).length;
    final can = level.canControl && !offline;
    final faults = (s ?? const {}).entries
        .where((e) => RegExp(r'^in\d+Fault$').hasMatch(e.key) && e.value == true)
        .length;
    void open() => openDevice(context, c, hub: widget.hub);
    // Ikona: wszystkie wybrane kanały razem (gdy wybrano wszystkie - jednym `on`).
    final VoidCallback? all = can
        ? () => _send(c, chosen.length == n ? {'on': count == 0} : {for (final i in chosen) 'on$i': count == 0}, {
            for (final i in chosen) 'on$i': count == 0,
          })
        : null;
    return TileShell(
      icon: icon,
      title: w.label ?? c.device.name,
      secondary: _secondary(s, '$count z ${chosen.length} włączone'),
      active: count > 0,
      large: large,
      offline: offline,
      color: w.color,
      iconSize: w.iconSize,
      badge: faults > 0 ? const TileBadge('USTERKA WEJŚCIA', TileBadgeKind.error) : null,
      iconKey: Key('dash-toggle-${w.id}'),
      onIcon: _tapAction(
        w.iconTap ?? 'toggle',
        toggle: _confirmed(w.label ?? c.device.name, all),
        details: open,
        device: open,
      ),
      onTap: _tapAction(
        w.tap ?? 'device',
        toggle: _confirmed(w.label ?? c.device.name, all),
        details: open,
        device: open,
      ),
      body: _Channels(
        widgetId: w.id,
        channels: chosen,
        names: [for (final i in chosen) _desc?.point('on$i')?.name ?? 'Kanał $i'],
        on: ons,
        compact: w.size == WidgetSize.s1x1 && w.w == null,
        rows: large ? 2 : 1,
        onToggle: can ? (i) => _send(c, {'on$i': !ons[chosen.indexOf(i)]}, {'on$i': !ons[chosen.indexOf(i)]}) : null,
      ),
    );
  }

  /// Szczegóły punktu: pełna kontrolka, wykres 24 h (gdy punkt ma historię) i przejście do urządzenia.
  void _showDetails(BuildContext context, DeviceController<Object?, Object?> c, DataPoint p, AccessLevel level) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final s = c.stateJson;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: Icon(dashWidgetIcon(w, widget.hub)),
                    title: Text(w.label ?? p.name, style: Theme.of(ctx).textTheme.titleMedium),
                    subtitle: Text(c.device.name),
                  ),
                  PointTile(
                    point: p,
                    value: p.valueIn(s),
                    enabled: canSet(level, p) && s != null && c.live,
                    onSet: (v) async {
                      final r = await c.sendJson(p.setFor(v));
                      if (ctx.mounted) showSendErrors(ctx, r.errors);
                    },
                  ),
                  if (p.history != null && widget.history != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SizedBox(
                        height: 160,
                        child: TileChart(
                          series: [(deviceId: c.device.id, point: p, line: 'smooth')],
                          history: widget.history,
                          rangeSwitch: true,
                        ),
                      ),
                    ),
                  ListTile(
                    key: const Key('tileOpenDevice'),
                    leading: const Icon(Icons.tune),
                    title: const Text('Urządzenie i ustawienia'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      openDevice(context, c, hub: widget.hub);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Napis stanu dwustanowego punktu: wejścia (pkt 10.1), grzanie, reszta tak / nie.
String _statusLabel(DataPoint p, Object? v) {
  if (v is! bool) return p.format(v);
  if (RegExp(r'^in\d+$').hasMatch(p.key)) return v ? 'Zwarte' : 'Rozwarte';
  return switch (p.key) {
    'heating' => v ? 'Grzeje' : 'Nie grzeje',
    'cloud' => v ? 'Połączone' : 'Brak połączenia',
    _ => v ? 'Tak' : 'Nie',
  };
}

/// Ikona widżetu: wybrana (`icon`), dla całego urządzenia - ikona urządzenia, inaczej domyślna dla punktu.
IconData dashWidgetIcon(DashWidget w, DeviceHub hub) {
  final chosen = appIcon(w.icon);
  if (chosen != null) return chosen.icon;
  if (w.device != null && (w.view == WidgetView.thermostat || w.point == 'on')) {
    final own = appIcon(DeviceIcons.instance.of(w.device!));
    if (own != null) return own.icon;
  }
  final type = w.device == null ? null : hub.device(w.device!)?.type;
  return appIcon(widgetIconKey(view: w.view, point: w.point, type: type))!.icon;
}

enum TileBadgeKind { heat, cool, error }

/// Plakietka w rogu kafelka (GRZEJE, MRÓZ, USTERKA…).
class TileBadge {
  const TileBadge(this.text, this.kind);

  final String text;
  final TileBadgeKind kind;
}

/// Kolor plakietki grzania - ten sam pomarańcz co akcent aplikacji.
const tileHeatColor = Color(0xFFE8590C);

/// Wspólny wygląd kafelka: ikona-przycisk (akcja główna), nazwa, druga linia, plakietka, treść na dole.
/// Włączony kafelek ([active]) ma tło w kolorze akcentu (pomarańcz z motywu) albo w kolorze [color] (pkt 13.1).
/// Niski kafelek (jeden wiersz siatki 4, 64 px): wszystko w jednej linii, treść (np. suwak) obok nazwy.
class TileShell extends StatelessWidget {
  const TileShell({
    super.key,
    required this.icon,
    required this.title,
    this.secondary,
    this.active = false,
    this.onIcon,
    this.iconKey,
    this.onTap,
    this.badge,
    this.body,
    this.fillBody = false,
    this.large = false,
    this.dimmed = false,
    this.offline = false,
    this.busy = false,
    this.color,
    this.iconSize,
  });

  final IconData icon;
  final String title;
  final String? secondary;
  final bool active;

  /// Akcja ikony; null = ikona tylko pokazuje stan (dotyk jak w reszcie kafelka).
  final VoidCallback? onIcon;
  final Key? iconKey;
  final VoidCallback? onTap;
  final TileBadge? badge;
  final Widget? body;

  /// Treść wypełnia resztę kafelka (wykres, pokrętło); inaczej przylega do dołu.
  final bool fillBody;

  /// Kafelek na dwa wiersze dawnej siatki - większa ikona (w siatce 4 decyduje wysokość).
  final bool large;
  final bool dimmed;
  final bool offline;

  /// Akcja w toku (kółko w ikonie).
  final bool busy;

  /// `amber|blue|green|red|purple|grey`; null / `auto` - akcent motywu.
  final String? color;

  /// `s|m|l|auto`.
  final String? iconSize;

  static final _schemes = <(String, Brightness), ColorScheme>{};

  /// Kolory aktywnego kafelka dla nazwanego koloru (z tego samego wzoru co motyw aplikacji).
  static ColorScheme schemeFor(String? color, ThemeData theme) {
    if (color == null || color == 'auto') return theme.colorScheme;
    return _schemes.putIfAbsent((
      color,
      theme.brightness,
    ), () => ColorScheme.fromSeed(seedColor: namedColor(color, theme.colorScheme), brightness: theme.brightness));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) => _build(context, box));
  }

  Widget _build(BuildContext context, BoxConstraints box) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = theme.textTheme;
    final acc = schemeFor(color, theme);
    final bg = active ? acc.primaryContainer : cs.surfaceContainerHigh;
    final fg = active ? acc.onPrimaryContainer : cs.onSurface;
    final muted = fg.withValues(alpha: 0.72);
    final tiny = box.maxHeight < 90;
    final size = switch (iconSize) {
      's' => 30.0,
      'm' => 40.0,
      'l' => 56.0,
      _ => tiny ? 36.0 : (large || box.maxHeight >= 200 ? 52.0 : 40.0),
    };
    final iconBox = tiny ? math.min(size, box.maxHeight - 16) : size;
    final iconButton = Material(
      key: iconKey,
      shape: const CircleBorder(),
      color: active ? acc.primary : cs.surface,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onIcon ?? onTap,
        child: SizedBox.square(
          dimension: iconBox,
          child: busy
              ? Padding(
                  padding: EdgeInsets.all(iconBox / 4),
                  child: CircularProgressIndicator(strokeWidth: 2, color: active ? acc.onPrimary : cs.primary),
                )
              : Icon(icon, size: iconBox * 0.55, color: active ? acc.onPrimary : cs.onSurfaceVariant),
        ),
      ),
    );
    final b = badge;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: t.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (secondary != null)
          Text(
            secondary!,
            style: t.bodySmall?.copyWith(color: muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    final extras = [
      if (offline) Icon(Icons.cloud_off, size: 16, color: muted),
      if (b != null)
        // Najwyżej 40% szerokości kafelka - na wąskim kafelku napis się skraca, nazwa zostaje.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
          child: Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: switch (b.kind) {
                TileBadgeKind.heat => tileHeatColor,
                TileBadgeKind.cool => const Color(0xFF1C6FB8),
                TileBadgeKind.error => cs.error,
              },
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              b.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelSmall?.copyWith(
                color: b.kind == TileBadgeKind.error ? cs.onError : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ),
    ];
    final Widget content;
    if (tiny) {
      // Jeden wiersz: ikona, nazwa, treść obok (gdy jest miejsce), plakietka.
      final inline = body != null && box.maxWidth >= 240;
      content = Row(
        children: [
          iconButton,
          const SizedBox(width: 8),
          if (inline) ...[
            Flexible(child: texts),
            const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: fg),
                child: body!,
              ),
            ),
          ] else
            Expanded(child: texts),
          ...extras,
        ],
      );
    } else if (body == null) {
      // Bez treści na dole: ikona u góry, nazwa i stan na dole (jak kafelki Apple Home) - bez pustego środka.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [iconButton, const Spacer(), ...extras]),
          const Spacer(),
          texts,
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              iconButton,
              const SizedBox(width: 10),
              Expanded(child: texts),
              ...extras,
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: fillBody
                ? body!
                : Align(
                    alignment: Alignment.bottomLeft,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: fg),
                      child: body!,
                    ),
                  ),
          ),
        ],
      );
    }
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(tiny ? 16 : 20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: tiny
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                : const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Wartość dużą cyfrą, dopasowana do miejsca.
class _BigValue extends StatelessWidget {
  const _BigValue({required this.text, required this.large});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FittedBox(
      alignment: Alignment.bottomLeft,
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        style: (large ? t.displaySmall : t.headlineMedium)?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Przyciski kanałów węzła; [compact] - same numery (kafelek 1×1).
class _Channels extends StatelessWidget {
  const _Channels({
    required this.widgetId,
    this.channels,
    required this.names,
    required this.on,
    required this.compact,
    required this.rows,
    required this.onToggle,
  });

  final String widgetId;

  /// Numery kanałów (od 1) w kolejności przycisków; null = 1..n.
  final List<int>? channels;
  final List<String> names;
  final List<bool> on;
  final bool compact;
  final int rows;
  final void Function(int channel)? onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final nums = channels ?? [for (var i = 1; i <= names.length; i++) i];
    Widget button(int i) => Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        key: Key('dash-ch-$widgetId-${nums[i - 1]}'),
        color: on[i - 1] ? cs.primary : cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle == null ? null : () => onToggle!(nums[i - 1]),
          child: SizedBox(
            height: compact ? 28 : 34,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  compact ? '${nums[i - 1]}' : names[i - 1],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(
                    color: on[i - 1] ? cs.onPrimary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final n = names.length;
    final perRow = rows > 1 && !compact ? (n / 2).ceil() : n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r * perRow < n; r++)
          Row(
            children: [
              for (var i = r * perRow + 1; i <= math.min(n, (r + 1) * perRow); i++) Expanded(child: button(i)),
            ],
          ),
      ],
    );
  }
}

class _StepperBody extends StatelessWidget {
  const _StepperBody({
    required this.point,
    required this.value,
    required this.enabled,
    required this.onSet,
    this.compact = false,
  });

  final DataPoint point;
  final Object? value;
  final bool enabled;
  final ValueChanged<Object?> onSet;

  /// Same przyciski − / + (wartość jest gdzie indziej, np. w drugiej linii termostatu).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final v = value is num ? (value as num).toDouble() : null;
    final step = p.step ?? 1;
    Object? next(int dir) {
      final x = ((v! + dir * step) / step).round() * step;
      final c = x.clamp(p.min ?? double.negativeInfinity, p.max ?? double.infinity);
      return step % 1 == 0 ? c.round() : c;
    }

    final can = enabled && v != null;
    final style = compact
        ? IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          )
        : null;
    final minus = IconButton.filledTonal(
      style: style,
      onPressed: can ? () => onSet(next(-1)) : null,
      icon: const Icon(Icons.remove),
    );
    final plus = IconButton.filledTonal(
      style: style,
      onPressed: can ? () => onSet(next(1)) : null,
      icon: const Icon(Icons.add),
    );
    if (compact) return Row(mainAxisSize: MainAxisSize.min, children: [minus, plus]);
    return Row(
      children: [
        minus,
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(p.format(value), style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        plus,
      ],
    );
  }
}

/// Scena (`sceneId`): ikona uruchamia; z hubem wykonuje ją hub, bez huba aplikacja wysyła akcje po kolei.
class _SceneTile extends StatefulWidget {
  const _SceneTile({required this.widget, required this.hub, required this.icon});

  final DashWidget widget;
  final DeviceHub hub;
  final IconData icon;

  @override
  State<_SceneTile> createState() => _SceneTileState();
}

class _SceneTileState extends State<_SceneTile> {
  bool _running = false;

  Future<void> _run(Scene scene) async {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _running = true);
    final problems = await widget.hub.runScene(scene);
    if (!mounted) return;
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(problems.isEmpty ? 'Wykonano „${widget.widget.label ?? scene.name}”.' : problems.join('\n')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.widget;
    final large = w.size.rows > 1;
    final scene = w.sceneId == null ? null : widget.hub.scene(w.sceneId!);
    if (scene == null) {
      return TileShell(
        icon: widget.icon,
        title: w.label ?? 'Scena',
        secondary: 'Scena usunięta albo niedostępna',
        dimmed: true,
        large: large,
      );
    }
    // Bez huba: kroki, których nie mogę wykonać (brak urządzenia albo poziomu).
    final blocked = [
      for (final a in scene.actions)
        if (a.isSet &&
            (widget.hub.controller(a.device!) == null ||
                !widget.hub.accessFor(a.device!).atLeast(requiredLevelFor(a.set!))))
          a,
    ];
    final steps = scene.actions.where((a) => a.isSet).length;
    final all = steps > 0 && blocked.length == steps;
    final can = !_running && !all && scene.actions.isNotEmpty;
    return TileShell(
      icon: widget.icon,
      title: w.label ?? scene.name,
      secondary: _running
          ? 'Wykonuję…'
          : blocked.isEmpty
          ? 'Scena · $steps ${steps == 1 ? 'krok' : 'kroki'}'
          : all
          ? 'Brak dostępu'
          : 'Część kroków bez dostępu',
      active: _running,
      busy: _running,
      dimmed: all,
      large: large,
      iconKey: Key('scene-${w.id}'),
      onIcon: can ? () => _run(scene) : null,
      onTap: can ? () => _run(scene) : null,
    );
  }
}

/// Linia wykresu (ostatnie 24 h).
class SparklinePainter extends CustomPainter {
  SparklinePainter(this.data, this.color);

  final List<HistoryPoint> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t0 = data.first.at.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, data.last.at.millisecondsSinceEpoch - t0);
    final lo = data.map((p) => p.value).reduce(math.min), hi = data.map((p) => p.value).reduce(math.max);
    final range = hi - lo < 0.1 ? 1.0 : hi - lo;
    final path = Path();
    for (final (i, p) in data.indexed) {
      final x = (p.at.millisecondsSinceEpoch - t0) / span * size.width;
      final y = size.height - (p.value - lo) / range * (size.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    // Pole pod linią, potem linia i kropka na ostatnim odczycie.
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    final last = data.last;
    canvas.drawCircle(
      Offset(size.width, size.height - (last.value - lo) / range * (size.height - 4) - 2),
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) => old.data != data || old.color != color;
}

/// Krótki opis Set do list (np. „mode = auto, on = nie”).
String describeSet(Json set, [String prefix = '']) => [
  for (final e in set.entries)
    if (e.value is Map)
      describeSet((e.value as Map).cast<String, dynamic>(), '$prefix${e.key}.')
    else
      '${fallbackPoint('$prefix${e.key}').name} = ${switch (e.value) {
        true => 'tak',
        false => 'nie',
        final String s => optionLabel(s),
        final v => '$v',
      }}',
].join(', ');

/// Ikona pogody z `outdoor.icon`: numer ikony termostatu (1-9, `WeatherManager`) albo kod OpenWeatherMap (200-804).
IconData weatherIcon(Object? code) => switch (_weatherKind(code)) {
  1 => Icons.wb_sunny_outlined,
  2 => Icons.wb_cloudy_outlined,
  3 => Icons.cloud_outlined,
  4 || 5 => Icons.water_drop_outlined,
  6 => Icons.thunderstorm_outlined,
  7 => Icons.ac_unit,
  8 => Icons.foggy,
  9 => Icons.air,
  _ => Icons.wb_sunny_outlined,
};

String weatherLabel(Object? code) => switch (_weatherKind(code)) {
  1 => 'Bezchmurnie',
  2 => 'Małe zachmurzenie',
  3 => 'Pochmurno',
  4 => 'Deszcz',
  5 => 'Mżawka',
  6 => 'Burza',
  7 => 'Śnieg',
  8 => 'Mgła',
  9 => 'Wiatr',
  _ => 'Pogoda',
};

int _weatherKind(Object? code) {
  if (code is! num) return 0;
  final id = code.toInt();
  if (id >= 1 && id <= 9) return id;
  if (id >= 200 && id < 300) return 6;
  if (id >= 300 && id < 400) return 5;
  if (id >= 500 && id < 600) return 4;
  if (id >= 600 && id < 700) return 7;
  if (id == 771 || id == 781) return 9;
  if (id >= 700 && id < 800) return 8;
  if (id == 800) return 1;
  if (id == 801 || id == 802) return 2;
  if (id >= 803) return 3;
  return 0;
}
