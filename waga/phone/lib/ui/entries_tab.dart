import 'package:flutter/material.dart';

import '../data/activity.dart';
import '../data/weights.dart';
import 'entry_dialog.dart';

/// Lista pomiarów od najnowszego; stuknięcie = poprawka albo usunięcie.
class EntriesTab extends StatelessWidget {
  const EntriesTab({super.key, required this.doc, required this.activity, required this.onEdit});

  final WeightDoc doc;
  final ActivityData activity;
  final Future<void> Function(EntryResult) onEdit;

  @override
  Widget build(BuildContext context) {
    if (doc.isEmpty) return const Center(child: Text('Brak pomiarów'));
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final rows = doc.entries.reversed.toList();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = rows[i];
        final prev = i + 1 < rows.length ? rows[i + 1] : null;
        final delta = prev == null ? null : e.w - prev.w;
        final kcal = activity.days[e.day]?.totalKcal;
        return ListTile(
          title: Text('${formatKg(e.w)} kg', style: theme.textTheme.titleMedium),
          subtitle: Text(
            '${shortDate(e.date)} ${e.date.year}${kcal == null ? '' : '  ·  ${formatThousands(kcal)} kcal'}',
          ),
          trailing: delta == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      delta < 0 ? Icons.arrow_downward : (delta > 0 ? Icons.arrow_upward : Icons.remove),
                      size: 16,
                      color: c.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(formatDelta(delta), style: theme.textTheme.bodyMedium),
                  ],
                ),
          onTap: () async {
            final r = await showEntryDialog(context, day: e.date, initial: e.w, existing: true, allowDateChange: false);
            if (r != null) await onEdit(r);
          },
        );
      },
    );
  }
}
