import 'package:flutter/material.dart';

import '../data/activity.dart';
import '../data/health_source.dart';
import '../data/weights.dart';

/// Kalorie, kroki i treningi z Health Connect (zapisuje je aplikacja Zepp) obok wagi.
class ActivityTab extends StatelessWidget {
  const ActivityTab({
    super.key,
    required this.state,
    required this.activity,
    required this.doc,
    required this.onConnect,
    required this.onRefresh,
  });

  final HealthState state;
  final ActivityData activity;
  final WeightDoc doc;
  final Future<void> Function() onConnect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case HealthState.checking:
        return const Center(child: CircularProgressIndicator());
      case HealthState.unavailable:
        return const _Info(
          icon: Icons.block,
          text: 'Health Connect nie jest dostępny na tym telefonie.',
        );
      case HealthState.needsInstall:
        return _Info(
          icon: Icons.download_outlined,
          text: 'Kalorie i treningi z zegarka trafiają do Health Connect. Zainstaluj albo zaktualizuj Health Connect.',
          action: FilledButton(onPressed: onConnect, child: const Text('Zainstaluj Health Connect')),
        );
      case HealthState.needsPermission:
        return _Info(
          icon: Icons.favorite_border,
          text: 'Pozwól Wadze czytać kalorie, kroki i treningi z Health Connect.\n\n'
              'W aplikacji Zepp włącz też wysyłanie danych: Profil → Połącz z innymi aplikacjami → Health Connect.',
          action: FilledButton(onPressed: onConnect, child: const Text('Połącz z Health Connect')),
        );
      case HealthState.ready:
        return RefreshIndicator(onRefresh: onRefresh, child: _ReadyView(activity: activity, doc: doc));
    }
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.activity, required this.doc});

  final ActivityData activity;
  final WeightDoc doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekFrom = today.subtract(const Duration(days: 6));
    // średnie z pełnych dni (dzisiaj dopiero trwa)
    final yesterday = today.subtract(const Duration(days: 1));
    final week7 = today.subtract(const Duration(days: 7));
    final total = activity.averageOf((d) => d.totalKcal, week7, yesterday);
    final active = activity.averageOf((d) => d.activeKcal, week7, yesterday);
    final steps = activity.averageOf((d) => d.steps, week7, yesterday);
    final recentWorkouts = activity.workouts.where((w) => !w.start.isBefore(weekFrom)).length;

    if (activity.days.isEmpty && activity.workouts.isEmpty) {
      return ListView(
        children: const [
          _Info(
            icon: Icons.hourglass_empty,
            text: 'Brak danych w Health Connect.\n\nSprawdź w aplikacji Zepp: Profil → Połącz z innymi '
                'aplikacjami → Health Connect (kalorie, kroki, treningi). Potem przeciągnij w dół, żeby odświeżyć.',
          ),
        ],
      );
    }

    final days = [for (var i = 0; i < 14; i++) today.subtract(Duration(days: i))];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ostatnie 7 dni – średnio dziennie', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Tile(label: 'spalone', value: total == null ? '–' : formatThousands(total), unit: 'kcal'),
                    _Tile(label: 'aktywne', value: active == null ? '–' : formatThousands(active), unit: 'kcal'),
                    _Tile(label: 'kroki', value: steps == null ? '–' : formatThousands(steps), unit: ''),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Treningi w tym tygodniu: $recentWorkouts', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Dzień po dniu', style: theme.textTheme.titleMedium),
        for (final d in days) _DayRow(day: d, activity: activity.days[dayKey(d)], weight: doc.entryFor(dayKey(d))),
        const SizedBox(height: 16),
        Text('Treningi', style: theme.textTheme.titleMedium),
        if (activity.workouts.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Brak treningów w Health Connect.')),
        for (final w in activity.workouts.take(50)) _WorkoutRow(w: w),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineSmall),
          Text(unit.isEmpty ? label : '$unit $label',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.activity, required this.weight});

  final DateTime day;
  final DayActivity? activity;
  final Entry? weight;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final parts = <String>[
      if (a?.totalKcal != null) '${formatThousands(a!.totalKcal!)} kcal',
      if (a?.activeKcal != null) 'akt. ${formatThousands(a!.activeKcal!)}',
      if (a?.steps != null) '${formatThousands(a!.steps!)} kroków',
    ];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(parts.isEmpty ? 'brak danych' : parts.join('  ·  ')),
      leading: SizedBox(width: 64, child: Text(shortDate(day))),
      trailing: weight == null ? null : Text('${formatKg(weight!.w)} kg'),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.w});

  final Workout w;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      formatDuration(w.duration),
      if (w.distanceM != null && w.distanceM! > 0) formatDistance(w.distanceM!),
      if (w.kcal != null && w.kcal! > 0) '${formatThousands(w.kcal!)} kcal',
    ];
    final hh = w.start.hour.toString().padLeft(2, '0');
    final mm = w.start.minute.toString().padLeft(2, '0');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.directions_run),
      title: Text(w.label),
      subtitle: Text('${shortDate(w.start)} $hh:$mm  ·  ${details.join('  ·  ')}'),
    );
  }
}
