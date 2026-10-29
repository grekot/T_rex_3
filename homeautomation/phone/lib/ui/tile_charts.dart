// Wykresy i półokrągłe kontrolki kafelków pulpitu (pkt 13.1): wykres liniowy z kilkoma seriami i zakresem,
// pokrętło (`dial`, półokrągły suwak) i wskaźnik (`gauge`, tylko odczyt). Rysowane CustomPainterem.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/history.dart';
import '../models/describe.dart';

/// Historia pola urządzenia ([hours] wstecz).
typedef HistoryLoader = Future<List<HistoryPoint>> Function(String deviceId, String field, {int hours});

/// Kolory nazwane z pkt 13.1 (`amber|blue|green|red|purple|grey`); inne / `auto` = akcent motywu.
Color namedColor(String? name, ColorScheme cs) => switch (name) {
  'amber' => const Color(0xFFE8A200),
  'blue' => const Color(0xFF1C6FB8),
  'green' => const Color(0xFF2B8A3E),
  'red' => const Color(0xFFC92A2A),
  'purple' => const Color(0xFF7048E8),
  'grey' => const Color(0xFF868E96),
  _ => cs.primary,
};

/// Zakres wykresu `6h|24h|7d|30d` w godzinach.
int rangeHours(String? range) => switch (range) {
  '6h' => 6,
  '7d' => 24 * 7,
  '30d' => 24 * 30,
  _ => 24,
};

const chartRanges = ['6h', '24h', '7d', '30d'];

String rangeLabel(String r) => switch (r) {
  '6h' => '6 h',
  '7d' => '7 dni',
  '30d' => '30 dni',
  _ => '24 h',
};

/// Jedna seria wykresu: urządzenie, punkt (z polem `history`), linia `smooth|step|band`.
typedef TileSeries = ({String deviceId, DataPoint point, String line});

/// Wykres liniowy: do 3 serii, linia gładka / schodkowa / pasy stanu, oś automatyczna albo stała, linia odniesienia,
/// przełącznik zakresu w kafelku ([rangeSwitch]).
class TileChart extends StatefulWidget {
  const TileChart({
    super.key,
    required this.series,
    required this.history,
    this.range,
    this.rangeSwitch = false,
    this.yMin,
    this.yMax,
    this.ref,
  });

  final List<TileSeries> series;
  final HistoryLoader? history;
  final String? range;
  final bool rangeSwitch;
  final double? yMin;
  final double? yMax;
  final double? ref;

  @override
  State<TileChart> createState() => _TileChartState();
}

class _TileChartState extends State<TileChart> {
  late String _range = widget.range ?? '24h';
  Future<List<List<HistoryPoint>>>? _data;

  List<TileSeries> get _withHistory => [
    for (final s in widget.series)
      if (s.point.history != null) s,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TileChart old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range) _range = widget.range ?? '24h';
    if (old.range != widget.range || old.series.length != widget.series.length) _load();
  }

  void _load() {
    final h = widget.history;
    final s = _withHistory;
    _data = h == null || s.isEmpty
        ? null
        : Future.wait([for (final x in s) h(x.deviceId, x.point.history!, hours: rangeHours(_range))]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (widget.history == null) return Text('Wykres wymaga konta w chmurze', style: t.bodySmall);
    if (_data == null) return Text('Ten punkt nie ma historii', style: t.bodySmall);
    final colors = [cs.primary, cs.onSurface.withValues(alpha: 0.6), const Color(0xFF1C6FB8)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.rangeSwitch)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 4,
              children: [
                for (final r in chartRanges)
                  ChoiceChip(
                    key: Key('chartRange-$r'),
                    showCheckmark: false,
                    label: Text(rangeLabel(r)),
                    labelStyle: t.labelSmall,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    selected: _range == r,
                    onSelected: (_) => setState(() {
                      _range = r;
                      _load();
                    }),
                  ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<List<List<HistoryPoint>>>(
            future: _data,
            builder: (context, snap) {
              if (snap.hasError) return Text('Nie udało się pobrać historii', style: t.bodySmall);
              final data = snap.data;
              if (data == null) return const Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator());
              final series = _withHistory;
              final lines = [
                for (final (i, d) in data.indexed)
                  if (d.length >= 2)
                    (data: d, line: series[i].line, color: colors[i % colors.length], point: series[i].point),
              ];
              if (lines.isEmpty) return Text('Za mało danych (zapis co 15 min)', style: t.bodySmall);
              final values = [
                for (final l in lines)
                  if (l.line != 'band') ...l.data.map((p) => p.value),
              ];
              var lo = widget.yMin ?? (values.isEmpty ? 0.0 : values.reduce(math.min));
              var hi = widget.yMax ?? (values.isEmpty ? 1.0 : values.reduce(math.max));
              if (widget.ref != null) {
                lo = math.min(lo, widget.ref!);
                hi = math.max(hi, widget.ref!);
              }
              if (hi - lo < 0.1) hi = lo + 1;
              final unitPoint = lines.firstWhere((l) => l.line != 'band', orElse: () => lines.first).point;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _ChartPainter(
                        lines: [for (final l in lines) (data: l.data, line: l.line, color: l.color)],
                        lo: lo,
                        hi: hi,
                        ref: widget.ref,
                        hours: rangeHours(_range),
                        grid: cs.outlineVariant,
                        band: const Color(0xFFE8590C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(unitPoint.format(hi), style: t.labelSmall),
                      Text(unitPoint.format(lo), style: t.labelSmall),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.lines,
    required this.lo,
    required this.hi,
    required this.ref,
    required this.hours,
    required this.grid,
    required this.band,
  });

  final List<({List<HistoryPoint> data, String line, Color color})> lines;
  final double lo;
  final double hi;
  final double? ref;
  final int hours;
  final Color grid;
  final Color band;

  @override
  void paint(Canvas canvas, Size size) {
    final end = lines.map((l) => l.data.last.at.millisecondsSinceEpoch).reduce(math.max).toDouble();
    final start = end - hours * 3600 * 1000;
    double x(DateTime t) => ((t.millisecondsSinceEpoch - start) / (end - start)).clamp(0.0, 1.0) * size.width;
    double y(double v) => size.height - 2 - ((v - lo) / (hi - lo)).clamp(0.0, 1.0) * (size.height - 4);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(0, y(hi)), Offset(size.width, y(hi)), gridPaint);
    canvas.drawLine(Offset(0, y(lo)), Offset(size.width, y(lo)), gridPaint);
    // Pasy stanu (np. grzanie) pod liniami.
    for (final l in lines.where((l) => l.line == 'band')) {
      final paint = Paint()..color = band.withValues(alpha: 0.16);
      for (var i = 0; i < l.data.length - 1; i++) {
        if (l.data[i].value > 0) {
          canvas.drawRect(Rect.fromLTRB(x(l.data[i].at), 0, x(l.data[i + 1].at), size.height), paint);
        }
      }
    }
    if (ref != null) {
      final p = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, y(ref!)), Offset(math.min(dx + 4, size.width), y(ref!)), p);
      }
    }
    var first = true;
    for (final l in lines.where((l) => l.line != 'band')) {
      final path = Path();
      for (final (i, p) in l.data.indexed) {
        final px = x(p.at), py = y(p.value);
        if (i == 0) {
          path.moveTo(px, py);
        } else if (l.line == 'step') {
          path
            ..lineTo(px, y(l.data[i - 1].value))
            ..lineTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      if (first) {
        final area = Path.from(path)
          ..lineTo(x(l.data.last.at), size.height)
          ..lineTo(x(l.data.first.at), size.height)
          ..close();
        canvas.drawPath(area, Paint()..color = l.color.withValues(alpha: 0.14));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = l.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = first ? 2 : 1.4
          ..strokeJoin = StrokeJoin.round,
      );
      if (first) canvas.drawCircle(Offset(x(l.data.last.at), y(l.data.last.value)), 3, Paint()..color = l.color);
      first = false;
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

/// Geometria łuku 180°: środek na dole, promień z miejsca.
({Offset c, double r}) _arc(Size size, double stroke) {
  final r = math.max(10.0, math.min(size.width / 2, size.height) - stroke);
  return (c: Offset(size.width / 2, math.min(size.height, r + stroke)), r: r);
}

double _frac(double v, double min, double max) => ((v - min) / (max - min)).clamp(0.0, 1.0);

/// Pokrętło: półokrągły suwak (pkt 13.1, `dial`). Przeciąganie po łuku zmienia wartość (krok z `describe`),
/// polecenie idzie po puszczeniu palca. [current] - wartość bieżąca (np. temperatura) jako kropka na łuku.
class DialControl extends StatefulWidget {
  const DialControl({
    super.key,
    required this.point,
    required this.value,
    required this.enabled,
    required this.onSet,
    this.current,
    this.currentLabel,
    this.color,
  });

  final DataPoint point;
  final double? value;
  final bool enabled;
  final ValueChanged<double> onSet;
  final double? current;
  final String? currentLabel;
  final Color? color;

  @override
  State<DialControl> createState() => _DialControlState();
}

class _DialControlState extends State<DialControl> {
  double? _drag;

  double get _min => widget.point.min ?? 0;
  double get _max => widget.point.max ?? 100;

  double _snap(double v) {
    final step = widget.point.step ?? 1;
    return ((v / step).round() * step).clamp(_min, _max).toDouble();
  }

  void _at(Offset local, Size size) {
    final g = _arc(size, 12);
    final d = local - g.c;
    var a = math.atan2(-d.dy, d.dx);
    if (a < 0) a = d.dx < 0 ? math.pi : 0;
    setState(() => _drag = _snap(_min + (1 - a / math.pi) * (_max - _min)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final v = _drag ?? widget.value;
    final color = widget.color ?? cs.primary;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final g = _arc(size, 12);
        return GestureDetector(
          key: const Key('dial'),
          behavior: HitTestBehavior.opaque,
          onPanStart: widget.enabled && v != null ? (d) => _at(d.localPosition, size) : null,
          onPanUpdate: widget.enabled && v != null ? (d) => _at(d.localPosition, size) : null,
          onPanEnd: widget.enabled
              ? (_) {
                  final x = _drag;
                  setState(() => _drag = null);
                  if (x != null && x != widget.value) widget.onSet(x);
                }
              : null,
          child: CustomPaint(
            painter: _DialPainter(
              f: v == null ? null : _frac(v, _min, _max),
              current: widget.current == null ? null : _frac(widget.current!, _min, _max),
              color: color,
              track: cs.onSurface.withValues(alpha: 0.14),
              knob: cs.surface,
              enabled: widget.enabled,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: math.max(0, g.c.dy - g.r * 0.62)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      child: Text(
                        widget.point.format(v),
                        style: (g.r > 60 ? t.headlineMedium : t.titleLarge)?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (widget.currentLabel != null && g.r > 50)
                      Text(widget.currentLabel!, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.f,
    required this.current,
    required this.color,
    required this.track,
    required this.knob,
    required this.enabled,
  });

  final double? f;
  final double? current;
  final Color color;
  final Color track;
  final Color knob;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final g = _arc(size, 12);
    final rect = Rect.fromCircle(center: g.c, radius: g.r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, base..color = track);
    if (f != null) {
      canvas.drawArc(rect, math.pi, math.pi * f!, false, base..color = enabled ? color : color.withValues(alpha: 0.5));
      final a = math.pi + math.pi * f!;
      final k = g.c + Offset(math.cos(a), math.sin(a)) * g.r;
      canvas.drawCircle(k, 9, Paint()..color = knob);
      canvas.drawCircle(
        k,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color,
      );
    }
    if (current != null) {
      final a = math.pi + math.pi * current!;
      canvas.drawCircle(
        g.c + Offset(math.cos(a), math.sin(a)) * (g.r - stroke - 2),
        3,
        Paint()..color = track.withValues(alpha: 1),
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.f != f || old.current != current || old.color != color;
}

/// Wskaźnik półokrągły (pkt 13.1, `gauge`, tylko odczyt): strefy kolorów, łuk do wartości, znacznik celu.
class GaugeView extends StatelessWidget {
  const GaugeView({
    super.key,
    required this.point,
    required this.value,
    required this.min,
    required this.max,
    this.zones = const [],
    this.target,
  });

  final DataPoint point;
  final double? value;
  final double min;
  final double max;
  final List<({double from, double to, String color})> zones;
  final double? target;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final v = value;
    final zone = v == null ? null : zones.where((z) => v >= z.from && v <= z.to).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final g = _arc(size, 12);
        return CustomPaint(
          painter: _GaugePainter(
            f: v == null ? null : _frac(v, min, max),
            zones: [
              for (final z in zones)
                (from: _frac(z.from, min, max), to: _frac(z.to, min, max), color: namedColor(z.color, cs)),
            ],
            target: target == null ? null : _frac(target!, min, max),
            color: zone == null ? cs.primary : namedColor(zone.color, cs),
            track: cs.onSurface.withValues(alpha: 0.12),
            mark: cs.onSurface,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: math.max(0, g.c.dy - g.r * 0.55),
                child: Center(
                  child: FittedBox(
                    child: Text(
                      point.format(v),
                      style: (g.r > 60 ? t.headlineMedium : t.titleLarge)?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              if (g.r > 40) ...[
                Positioned(
                  left: g.c.dx - g.r - 12,
                  top: g.c.dy + 2,
                  child: Text(point.format(min), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
                Positioned(
                  right: size.width - g.c.dx - g.r - 12,
                  top: g.c.dy + 2,
                  child: Text(point.format(max), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.f,
    required this.zones,
    required this.target,
    required this.color,
    required this.track,
    required this.mark,
  });

  final double? f;
  final List<({double from, double to, Color color})> zones;
  final double? target;
  final Color color;
  final Color track;
  final Color mark;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final g = _arc(size, 12);
    final rect = Rect.fromCircle(center: g.c, radius: g.r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, math.pi, math.pi, false, p..color = track);
    for (final z in zones) {
      canvas.drawArc(
        rect,
        math.pi + math.pi * z.from,
        math.pi * (z.to - z.from),
        false,
        p..color = z.color.withValues(alpha: 0.3),
      );
    }
    if (f != null) {
      canvas.drawArc(
        rect,
        math.pi,
        math.pi * f!,
        false,
        p
          ..color = color
          ..strokeCap = StrokeCap.round,
      );
    }
    if (target != null) {
      final a = math.pi + math.pi * target!;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        g.c + dir * (g.r - stroke),
        g.c + dir * (g.r + stroke),
        Paint()
          ..color = mark
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => true;
}
