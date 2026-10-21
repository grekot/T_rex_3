import 'package:flutter/material.dart';

import '../data/peaks_data.dart';
import '../data/stats.dart';
import 'format.dart';
import 'widgets.dart';

/// Zakładka „Historia”: liczby, zdobycia w latach i wszystkie zdobycia od najnowszego
class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key, required this.data});

  final PeaksData data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries;
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Brak zdobyć.\n\nOtwórz aplikację Na szczycie na zegarku na wierzchołku - zaliczy go po GPS - '
            'albo dodaj wcześniejsze wejścia z datą w szczegółach szczytu na zegarku.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final summary = summarize(entries);
    final years = climbsPerYear(entries);
    final rows = <Object>[];
    int? year;
    for (final e in entries) {
      if (e.date.year != year) {
        year = e.date.year;
        rows.add(year);
      }
      rows.add(e);
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          sliver: SliverToBoxAdapter(child: _SummaryGrid(summary: summary)),
        ),
        if (years.length > 1)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverToBoxAdapter(child: _YearsChart(years: years)),
          ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            if (row is int) {
              final n = entries.where((e) => e.date.year == row).length;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text('$row · ${peaksCount(n)}', style: Theme.of(context).textTheme.titleMedium),
              );
            }
            return _EntryTile(data: data, entry: row as TimelineEntry);
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final h = summary.highest;
    final tiles = [
      _Tile(value: '${summary.total}', label: 'zdobytych szczytów'
          '${summary.custom > 0 ? ' (w tym ${summary.custom} własnych)' : ''}'),
      _Tile(value: '${summary.thisYear}', label: 'w tym roku'),
      if (h != null) _Tile(value: formatHeight(h.h), label: 'najwyżej: ${h.name}'),
      _Tile(value: '${summary.gps}', label: 'zaliczonych po GPS na szczycie'),
      if (summary.first case final f?) _Tile(value: '${f.date.year}', label: 'pierwsze: ${f.name}'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Słupki: ile zdobyć w kolejnych latach
class _YearsChart extends StatelessWidget {
  const _YearsChart({required this.years});

  final List<(int, int)> years;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = years.map((y) => y.$2).reduce((a, b) => a > b ? a : b);
    const barArea = 110.0;
    const barWidth = 34.0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Zdobycia w latach', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (year, n) in years)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                        width: barWidth + 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(n > 0 ? '$n' : '', style: theme.textTheme.labelSmall),
                            const SizedBox(height: 2),
                            Container(
                              width: barWidth,
                              height: n == 0 ? 2 : 4 + (barArea - 4) * n / max,
                              decoration: BoxDecoration(
                                color: n == 0 ? unclimbedColor.withValues(alpha: 0.4) : climbedColor,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('$year', style: theme.textTheme.labelSmall),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.data, required this.entry});

  final PeaksData data;
  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final peak = entry.peak;
    final custom = entry.custom;
    final groups = peak == null
        ? ''
        : [for (final g in peak.groups) data.catalog.group(g)?.short ?? g].join(', ');
    final subtitle = [
      if (peak != null) formatHeight(peak.h),
      if (groups.isNotEmpty) groups,
      if (peak?.isVariant == true) 'wariant',
      if (custom != null) 'własny',
      if (peak == null && custom == null) 'spoza listy',
    ].join(' · ');
    return ListTile(
      leading: ClimbDot(climbed: true, custom: custom != null),
      title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(formatShortDay(entry.date)), const SizedBox(width: 4), GpsIcon(gps: entry.gps)],
      ),
      onTap: peak != null
          ? () => openPeak(context, data, peak)
          : (custom != null ? () => openCustom(context, data, custom) : null),
    );
  }
}
