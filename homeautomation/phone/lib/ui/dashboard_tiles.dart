import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../data/history.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import '../models/scene.dart';
import 'device_tiles.dart';
import 'generic_device_screen.dart' show canSet;
import 'point_controls.dart';

/// Historia pola urządzenia do wykresu; null = bez chmury (wykresy niedostępne).
typedef HistorySource = Future<List<HistoryPoint>> Function(String deviceId, String field);

/// Wysokość jednego wiersza siatki pulpitu.
const dashRowHeight = 128.0;
const dashGap = 8.0;

/// Siatka pulpitu: 2 kolumny, widżety 1×1 (pół wiersza), 2×1 (wiersz) i 2×2 (dwa wiersze).
class DashGrid extends StatelessWidget {
  const DashGrid({super.key, required this.widgets, required this.builder});

  final List<DashWidget> widgets;
  final Widget Function(DashWidget w) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final col = (box.maxWidth - dashGap) / 2;
        return Wrap(
          spacing: dashGap,
          runSpacing: dashGap,
          children: [
            for (final w in widgets)
              SizedBox(
                key: ValueKey(w.id),
                width: w.size.columns == 2 ? box.maxWidth : col,
                height: w.size.rows * dashRowHeight + (w.size.rows - 1) * dashGap,
                child: builder(w),
              ),
          ],
        );
      },
    );
  }
}

/// Punkt, gdy urządzenie (jeszcze) nie podało `describe` - znane pola z kontraktu.
DataPoint fallbackPoint(String key) => switch (key) {
  'temp' => const DataPoint(key: 'temp', name: 'Temperatura', kind: PointKind.sensor, unit: '°C', decimals: 1, history: 't'),
  'hum' => const DataPoint(key: 'hum', name: 'Wilgotność', kind: PointKind.sensor, unit: '%', decimals: 0),
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
  'heating' => const DataPoint(key: 'heating', name: 'Grzanie', kind: PointKind.status),
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

/// Jeden widżet pulpitu w trybie podglądu.
class DashTile extends StatefulWidget {
  const DashTile({super.key, required this.widget, required this.hub, this.history});

  final DashWidget widget;
  final DeviceHub hub;
  final HistorySource? history;

  @override
  State<DashTile> createState() => _DashTileState();
}

class _DashTileState extends State<DashTile> {
  DashWidget get w => widget.widget;
  DeviceDescription? _desc;

  /// Połączenie, o którego opis już pytano (raz na połączenie, także gdy opisu brak).
  Object? _askedConnection;

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.hub,
      builder: (context, _) {
        if (w.isScene) return _SceneTile(widget: w, hub: widget.hub);
        final c = _c;
        final level = w.device == null ? AccessLevel.none : widget.hub.accessFor(w.device!);
        if (c == null || level == AccessLevel.none) {
          return _Frame(
            title: w.label ?? 'Widżet',
            dimmed: true,
            child: Row(
              children: [
                const Icon(Icons.lock_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(c == null ? 'Urządzenie niedostępne' : 'Brak dostępu')),
              ],
            ),
          );
        }
        _ensureDescription();
        final state = c.stateJson;
        final p = _point;
        final title = w.label ?? p?.name ?? c.device.name;
        final subtitle = w.label == null ? c.device.name : null;
        final offline = state == null || !c.live;
        void open() => openDevice(context, c, hub: widget.hub);
        Future<void> set(DataPoint p, Object? v) async {
          final r = await c.sendJson(p.setFor(v));
          if (context.mounted) showSendErrors(context, r.errors);
        }

        return switch (w.view) {
          WidgetView.thermostat => _ThermostatWidget(controller: c, title: w.label ?? c.device.name, level: level),
          WidgetView.chart => _Frame(
            title: title,
            subtitle: subtitle,
            onTap: open,
            child: _ChartBody(
              deviceId: c.device.id,
              point: p ?? fallbackPoint('temp'),
              history: widget.history,
              big: w.size.rows > 1,
            ),
          ),
          _ when p == null => _Frame(title: title, onTap: open, child: const Text('Brak punktu danych')),
          WidgetView.toggle => _Frame(
            title: title,
            subtitle: subtitle,
            offline: offline,
            onTap: open,
            child: Align(
              alignment: Alignment.bottomRight,
              child: p.kind == PointKind.action
                  ? FilledButton.tonal(
                      onPressed: canSet(level, p) && !offline ? () => set(p, true) : null,
                      child: const Text('Wykonaj'),
                    )
                  : Switch(
                      key: Key('dash-switch-${w.id}'),
                      value: p.valueIn(state) == true,
                      onChanged: canSet(level, p) && !offline ? (v) => set(p, v) : null,
                    ),
            ),
          ),
          WidgetView.slider => _Frame(
            title: title,
            subtitle: subtitle,
            offline: offline,
            onTap: open,
            trailing: Text(p.format(p.valueIn(state))),
            child: p.min == null || p.max == null || p.valueIn(state) is! num
                ? Text(p.format(p.valueIn(state)))
                : SetpointSlider(
                    point: p,
                    value: (p.valueIn(state) as num).toDouble(),
                    enabled: canSet(level, p) && !offline,
                    onChanged: (v) => set(p, v),
                  ),
          ),
          WidgetView.stepper => _Frame(
            title: title,
            subtitle: subtitle,
            offline: offline,
            onTap: open,
            child: _StepperBody(point: p, value: p.valueIn(state), enabled: canSet(level, p) && !offline, onSet: (v) => set(p, v)),
          ),
          WidgetView.status => _Frame(
            title: title,
            subtitle: subtitle,
            offline: offline,
            onTap: open,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Icon(
                p.valueIn(state) == true ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 40,
                color: p.valueIn(state) == true ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
          WidgetView.value || WidgetView.scene => _Frame(
            title: title,
            subtitle: subtitle,
            offline: offline,
            onTap: open,
            child: _ValueBody(point: p, value: p.valueIn(state), enabled: canSet(level, p) && !offline, onSet: (v) => set(p, v)),
          ),
        };
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dimmed = false,
    this.offline = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onTap;
  final bool dimmed;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (offline) Icon(Icons.cloud_off, size: 16, color: cs.outline),
                    ?trailing,
                  ],
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: t.bodySmall?.copyWith(color: cs.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const Spacer(),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ValueBody extends StatelessWidget {
  const _ValueBody({required this.point, required this.value, required this.enabled, required this.onSet});

  final DataPoint point;
  final Object? value;
  final bool enabled;
  final ValueChanged<Object?> onSet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = point;
    if (p.kind == PointKind.select) {
      return DropdownButton<String>(
        isExpanded: true,
        value: p.options.contains(value) ? value as String : null,
        items: [for (final o in p.options) DropdownMenuItem(value: o, child: Text(optionLabel(o)))],
        onChanged: enabled ? onSet : null,
      );
    }
    if (p.kind == PointKind.action) {
      return Align(
        alignment: Alignment.bottomRight,
        child: FilledButton.tonal(onPressed: enabled ? () => onSet(true) : null, child: const Text('Wykonaj')),
      );
    }
    return FittedBox(
      alignment: Alignment.bottomLeft,
      fit: BoxFit.scaleDown,
      child: Text(p.format(value), style: t.headlineMedium),
    );
  }
}

class _StepperBody extends StatelessWidget {
  const _StepperBody({required this.point, required this.value, required this.enabled, required this.onSet});

  final DataPoint point;
  final Object? value;
  final bool enabled;
  final ValueChanged<Object?> onSet;

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
    return Row(
      children: [
        IconButton.filledTonal(onPressed: can ? () => onSet(next(-1)) : null, icon: const Icon(Icons.remove)),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(p.format(value), style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        IconButton.filledTonal(onPressed: can ? () => onSet(next(1)) : null, icon: const Icon(Icons.add)),
      ],
    );
  }
}

/// Widok „termostat”: temperatura, nastawa z − / + i grzanie.
class _ThermostatWidget extends StatelessWidget {
  const _ThermostatWidget({required this.controller, required this.title, required this.level});

  final DeviceController<Object?, Object?> controller;
  final String title;
  final AccessLevel level;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.stateJson;
    final t = Theme.of(context).textTheme;
    final temp = fallbackPoint('temp'), target = fallbackPoint('target');
    final heating = s?['heating'] == true;
    final offline = s == null || !c.live;
    return _Frame(
      title: title,
      offline: offline,
      onTap: () => openDevice(context, c),
      trailing: Icon(Icons.local_fire_department, color: heating ? const Color(0xFFE8590C) : null, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(temp.format(temp.valueIn(s)), style: t.headlineMedium),
          ),
          _StepperBody(
            point: target,
            value: target.valueIn(s),
            enabled: level.canControl && !offline && s['power'] != false,
            onSet: (v) async {
              final r = await c.sendJson({'target': v});
              if (context.mounted) showSendErrors(context, r.errors);
            },
          ),
        ],
      ),
    );
  }
}

/// Scena (`sceneId`): z hubem uruchamia ją hub, bez huba aplikacja wysyła akcje po kolei.
class _SceneTile extends StatefulWidget {
  const _SceneTile({required this.widget, required this.hub});

  final DashWidget widget;
  final DeviceHub hub;

  @override
  State<_SceneTile> createState() => _SceneTileState();
}

class _SceneTileState extends State<_SceneTile> {
  bool _running = false;

  Future<void> _run(Scene scene) async {
    setState(() => _running = true);
    final problems = await widget.hub.runScene(scene);
    if (!mounted) return;
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problems.isEmpty ? 'Wykonano „${widget.widget.label ?? scene.name}”.' : problems.join('\n'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.widget;
    final scene = w.sceneId == null ? null : widget.hub.scene(w.sceneId!);
    if (scene == null) {
      return _Frame(
        title: w.label ?? 'Scena',
        dimmed: true,
        child: const Text('Scena usunięta albo niedostępna'),
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
    return _Frame(
      title: w.label ?? scene.name,
      subtitle: blocked.isEmpty
          ? '$steps ${steps == 1 ? 'krok' : 'kroki'}'
          : all
          ? 'Brak dostępu'
          : 'Część kroków bez dostępu',
      dimmed: all,
      child: Align(
        alignment: Alignment.bottomRight,
        child: FilledButton.icon(
          key: Key('scene-${w.id}'),
          onPressed: _running || all || scene.actions.isEmpty ? null : () => _run(scene),
          icon: _running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: const Text('Uruchom'),
        ),
      ),
    );
  }
}

class _ChartBody extends StatefulWidget {
  const _ChartBody({required this.deviceId, required this.point, required this.history, required this.big});

  final String deviceId;
  final DataPoint point;
  final HistorySource? history;
  final bool big;

  @override
  State<_ChartBody> createState() => _ChartBodyState();
}

class _ChartBodyState extends State<_ChartBody> {
  Future<List<HistoryPoint>>? _data;

  @override
  void initState() {
    super.initState();
    final field = widget.point.history;
    if (widget.history != null && field != null) _data = widget.history!(widget.deviceId, field);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_data == null) {
      return Text(
        widget.history == null ? 'Wykres wymaga konta w chmurze' : 'Ten punkt nie ma historii',
        style: t.bodySmall,
      );
    }
    return FutureBuilder<List<HistoryPoint>>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Text('Nie udało się pobrać historii', style: t.bodySmall);
        final data = snap.data;
        if (data == null) return const LinearProgressIndicator();
        if (data.length < 2) return Text('Za mało danych (zapis co 15 min)', style: t.bodySmall);
        final lo = data.map((p) => p.value).reduce(math.min), hi = data.map((p) => p.value).reduce(math.max);
        return SizedBox(
          height: widget.big ? dashRowHeight + 40 : 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomPaint(painter: SparklinePainter(data, Theme.of(context).colorScheme.primary)),
              ),
              const SizedBox(width: 4),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(widget.point.format(hi), style: t.labelSmall),
                  Text(widget.point.format(lo), style: t.labelSmall),
                ],
              ),
            ],
          ),
        );
      },
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
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
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
