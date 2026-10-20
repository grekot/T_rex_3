import 'package:flutter/material.dart';

import '../data/korona_data.dart';
import '../data/stats.dart';
import 'format.dart';
import 'group_screen.dart';
import 'widgets.dart';

/// Zakładka „Postęp”: każda grupa z „12 / 28” i paskiem, własne szczyty, stan synchronizacji
class GroupsTab extends StatelessWidget {
  const GroupsTab({super.key, required this.data});

  final KoronaData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _SyncCard(data: data),
        for (final p in data.progress) _GroupCard(data: data, progress: p),
        Card(
          child: ListTile(
            leading: const ClimbDot(climbed: true, custom: true),
            title: const Text('Własne szczyty'),
            subtitle: Text(data.doc.custom.isEmpty
                ? 'Szczyty spoza listy dodane na zegarku przyciskiem „Dodaj szczyt tutaj”'
                : peaksCount(data.doc.custom.length)),
            trailing: data.doc.custom.isEmpty ? null : const Icon(Icons.chevron_right),
            onTap: data.doc.custom.isEmpty
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CustomScreen(data: data))),
          ),
        ),
        if (data.catalog.generated.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Lista szczytów z ${data.catalog.generated}: ${peaksCount(data.catalog.peaks.length)}. '
              '${data.catalog.sources.join('. ')}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.data});

  final KoronaData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.demo) {
      return Card(
        color: theme.colorScheme.tertiaryContainer,
        child: const ListTile(
          leading: Icon(Icons.science_outlined),
          title: Text('Przykładowe dane'),
          subtitle: Text('Zmyślone zdobycia do obejrzenia aplikacji - nie z Twojego zegarka.'),
        ),
      );
    }
    if (!data.doc.exists) {
      return Card(
        color: theme.colorScheme.secondaryContainer,
        child: const ListTile(
          leading: Icon(Icons.watch_outlined),
          title: Text('Zegarek jeszcze nic nie wysłał'),
          subtitle: Text(
            'Zaloguj się tym samym kontem w aplikacji Korona na zegarku '
            '(w aplikacji Zepp: Urządzenie → Korona → ustawienia). '
            'Zdobycia pojawią się tu po synchronizacji.',
          ),
        ),
      );
    }
    final u = data.doc.updatedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Icon(Icons.sync, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              u == null ? 'Dane z zegarka' : 'Z zegarka: ${formatDateTime(u)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.data, required this.progress});

  final KoronaData data;
  final GroupProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variants = progress.variants.where((p) => data.climbOf(p.id) != null).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupScreen(data: data, progress: progress)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(progress.group.name, style: theme.textTheme.titleLarge)),
                  if (progress.complete) const Icon(Icons.workspace_premium, color: Color(0xFFE5B100)),
                ],
              ),
              const SizedBox(height: 8),
              ProgressLine(climbed: progress.climbed, counted: progress.counted),
              if (progress.complete || variants > 0) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (progress.complete) 'Cała lista zdobyta!',
                    if (variants > 0) '+ ${plural(variants, 'wariant', 'warianty', 'wariantów')}',
                  ].join(' '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomScreen extends StatelessWidget {
  const _CustomScreen({required this.data});

  final KoronaData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Własne szczyty')),
      body: ListView(
        children: [
          for (final c in data.doc.custom)
            ListTile(
              leading: const ClimbDot(climbed: true, custom: true),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(formatLatLon(c.lat, c.lon)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text(formatShortDay(c.date)), const SizedBox(width: 4), GpsIcon(gps: c.gps)],
              ),
              onTap: () => openCustom(context, data, c),
            ),
        ],
      ),
    );
  }
}
