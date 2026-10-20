// Ustawienia puli: z ilu dni brać świeże zdjęcia, ile zdjęć dla zegarka, jaka część to wspomnienia
// (starsze zdjęcia z losowych okresów), przywracanie usuniętych.
import 'package:flutter/material.dart';

import '../pool_controller.dart';

const _dayOptions = [7, 14, 30, 60, 90];
const _sizeOptions = [10, 20, 30, 50];
const _memoryOptions = [0, 25, 50, 75];

Future<void> showSettingsSheet(BuildContext context, PoolController pool) {
  var days = pool.prefs.days;
  var size = pool.prefs.size;
  var memoryShare = pool.prefs.memoryShare;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Świeże zdjęcia z ostatnich dni'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [for (final d in _dayOptions) ButtonSegment(value: d, label: Text('$d'))],
                selected: {days},
                onSelectionChanged: (s) => setState(() => days = s.first),
              ),
              const SizedBox(height: 16),
              const Text('Zdjęć w puli dla zegarka'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [for (final n in _sizeOptions) ButtonSegment(value: n, label: Text('$n'))],
                selected: {size},
                onSelectionChanged: (s) => setState(() => size = s.first),
              ),
              const SizedBox(height: 16),
              const Text('Wspomnienia (starsze zdjęcia z losowych okresów) – część puli w %'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [for (final m in _memoryOptions) ButtonSegment(value: m, label: Text('$m'))],
                selected: {memoryShare},
                onSelectionChanged: (s) => setState(() => memoryShare = s.first),
              ),
              if (pool.prefs.removed.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: Text('Przywróć usunięte zdjęcia (${pool.prefs.removed.length})'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    pool.restoreRemoved();
                  },
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    pool.updateSettings(days: days, size: size, memoryShare: memoryShare);
                  },
                  child: const Text('Zastosuj'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
