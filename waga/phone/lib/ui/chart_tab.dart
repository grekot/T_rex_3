import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/activity.dart';
import '../data/weights.dart';

enum ChartRange {
  month('30 dni', 30),
  quarter('90 dni', 90),
  year('Rok', 365),
  all('Wszystko', null);

  const ChartRange(this.label, this.days);

  final String label;
  final int? days;
}

class ChartTab extends StatefulWidget {
  const ChartTab({
    super.key,
    required this.doc,
    required this.activity,
    required this.healthReady,
    required this.onSetGoal,
  });

  final WeightDoc doc;
  final ActivityData activity;
  final bool healthReady;
  final VoidCallback onSetGoal;

  @override
  State<ChartTab> createState() => _ChartTabState();
}

class _ChartTabState extends State<ChartTab> {
  ChartRange _range = ChartRange.month;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    if (doc.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Brak pomiarów.\n\nZważ się rano i zapisz wagę na zegarku (aplikacja Waga) '
            'albo dodaj pomiar przyciskiem poniżej.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final trendByDay = trend(doc.entries, today);
    final current = trendByDay[dayKey(today)]!;
    final rate = weeklyRate(trendByDay, today);

    final from = _range.days == null ? doc.entries.first.date : today.subtract(Duration(days: _range.days! - 1));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _Summary(doc: doc, current: current, rate: rate, today: today, onSetGoal: widget.onSetGoal),
        const SizedBox(height: 16),
        SegmentedButton<ChartRange>(
          segments: [for (final r in ChartRange.values) ButtonSegment(value: r, label: Text(r.label))],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _range = s.first),
        ),
        const SizedBox(height: 16),
        Text('Waga', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const _Legend(),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: _WeightChart(doc: doc, trendByDay: trendByDay, from: from, to: today),
        ),
        if (widget.healthReady && (_range.days ?? 9999) <= 120) ...[
          const SizedBox(height: 24),
          Text('Spalone kalorie (dziennie)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(height: 160, child: _CaloriesChart(activity: widget.activity, from: from, to: today)),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.doc, required this.current, required this.rate, required this.today, required this.onSetGoal});

  final WeightDoc doc;
  final double current;
  final double? rate;
  final DateTime today;
  final VoidCallback onSetGoal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = doc.last!;
    final prev = doc.lastBefore(last.day);
    final week = averageBetween(doc.entries, today.subtract(const Duration(days: 6)), today);
    final prevWeek =
        averageBetween(doc.entries, today.subtract(const Duration(days: 13)), today.subtract(const Duration(days: 7)));
    final goal = doc.goal;
    final forecast = goal == null ? null : forecastGoal(current: current, goal: goal, ratePerWeek: rate, today: today);

    String goalText() {
      if (goal == null) return 'Ustaw cel';
      final left = goal - current;
      if (left.abs() < 1) return 'Cel osiągnięty';
      final f = forecast == null ? 'przy obecnym tempie – brak prognozy' : 'ok. ${longDate(forecast)}';
      return '${formatKg(goal)} kg (${formatDelta(left)}), $f';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatKg(last.w), style: theme.textTheme.displayMedium),
                const SizedBox(width: 6),
                Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('kg', style: theme.textTheme.titleMedium)),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(shortDate(last.date), style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            if (prev != null)
              Text('${formatDelta(last.w - prev.w)} kg od ${shortDate(prev.date)}', style: theme.textTheme.bodyMedium),
            const Divider(height: 24),
            _Stat(label: 'Trend', value: '${formatKg(current)} kg'),
            _Stat(label: 'Tempo (4 tyg.)', value: rate == null ? '–' : '${formatDelta(rate!)} kg / tydz.'),
            _Stat(
              label: 'Średnia 7 dni',
              value: week == null
                  ? '–'
                  : '${formatKg(week)} kg${prevWeek == null ? '' : ' (${formatDelta(week - prevWeek)} do poprz.)'}',
            ),
            InkWell(onTap: onSetGoal, child: _Stat(label: 'Cel', value: goalText())),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    Widget item(Widget mark, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [mark, const SizedBox(width: 6), Text(label, style: style)]);
    return Wrap(
      spacing: 16,
      children: [
        item(Container(width: 8, height: 8, decoration: BoxDecoration(color: c.onSurfaceVariant, shape: BoxShape.circle)), 'pomiar'),
        item(Container(width: 18, height: 2, color: c.primary), 'trend'),
        item(Container(width: 18, height: 2, color: c.tertiary), 'cel'),
      ],
    );
  }
}

double _x(DateTime from, DateTime d) => d.difference(from).inHours / 24;

String _axisDate(DateTime d, int spanDays) {
  if (spanDays > 400) return '${d.month.toString().padLeft(2, '0')}.${d.year % 100}';
  return '${d.day}.${d.month.toString().padLeft(2, '0')}';
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.doc, required this.trendByDay, required this.from, required this.to});

  final WeightDoc doc;
  final Map<String, double> trendByDay;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fromKey = dayKey(from);
    final points = [for (final e in doc.entries) if (e.day.compareTo(fromKey) >= 0) FlSpot(_x(from, e.date), e.kg)];
    final trendSpots = [
      for (final d in daysBetween(from, to))
        if (trendByDay[dayKey(d)] != null) FlSpot(_x(from, d), trendByDay[dayKey(d)]! / 10),
    ];
    final values = [...points.map((p) => p.y), ...trendSpots.map((p) => p.y)];
    if (doc.goal != null) values.add(doc.goal! / 10);
    var minY = values.reduce(math.min), maxY = values.reduce(math.max);
    if (maxY - minY < 2) {
      final mid = (maxY + minY) / 2;
      minY = mid - 1;
      maxY = mid + 1;
    }
    minY = (minY - 0.5).floorToDouble();
    maxY = (maxY + 0.5).ceilToDouble();
    final span = math.max(1, to.difference(from).inDays);
    final maxX = _x(from, to);
    final yStep = math.max(1.0, ((maxY - minY) / 5).ceilToDouble());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(maxX, 1),
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: yStep,
          getDrawingHorizontalLine: (_) => FlLine(color: c.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: yStep,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(v.toStringAsFixed(0), style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: math.max(1, (span / 4).roundToDouble()),
              getTitlesWidget: (v, meta) {
                if (v == meta.max && v != meta.min) return const SizedBox.shrink();
                final d = from.add(Duration(days: v.round()));
                return SideTitleWidget(
                  meta: meta,
                  child: Text(_axisDate(d, span), style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (doc.goal != null)
              HorizontalLine(y: doc.goal! / 10, color: c.tertiary, strokeWidth: 2, dashArray: [6, 4]),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.inverseSurface,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.barIndex == 0 ? 'pomiar' : 'trend'} ${shortDate(from.add(Duration(days: s.x.round())))}\n'
                  '${formatKg(s.y * 10)} kg',
                  TextStyle(color: c.onInverseSurface, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            barWidth: 0,
            color: Colors.transparent,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: points.length > 120 ? 2 : 4,
                color: c.onSurfaceVariant,
                strokeWidth: 1,
                strokeColor: c.surface,
              ),
            ),
          ),
          LineChartBarData(
            spots: trendSpots,
            isCurved: false,
            barWidth: 2,
            color: c.primary,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _CaloriesChart extends StatelessWidget {
  const _CaloriesChart({required this.activity, required this.from, required this.to});

  final ActivityData activity;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final days = daysBetween(from, to).toList();
    final values = [for (final d in days) activity.days[dayKey(d)]?.totalKcal ?? activity.days[dayKey(d)]?.activeKcal ?? 0.0];
    if (values.every((v) => v == 0)) {
      return const Center(child: Text('Brak danych o kaloriach z Health Connect w tym okresie.'));
    }
    final maxY = values.reduce(math.max) * 1.1;
    final barWidth = math.max(2.0, math.min(10.0, 300 / days.length));
    final span = days.length;
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: c.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(formatThousands(v), style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                final step = math.max(1, (span / 4).round());
                if (i % step != 0 || i >= days.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(_axisDate(days[i], span), style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => c.inverseSurface,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${shortDate(days[group.x])}\n${formatThousands(rod.toY)} kcal',
              TextStyle(color: c.onInverseSurface, fontSize: 12),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: barWidth,
                  color: c.secondary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(4, barWidth / 2))),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
