// Karta zdjęcia z puli: duży okrągły podgląd jak na zegarku, powody wyboru i akcje.
import 'package:flutter/material.dart';

import '../bridge/format.dart';
import '../pool_controller.dart';
import '../select/crop.dart';
import 'crop_screen.dart';

Future<void> showPhotoSheet(BuildContext context, PoolController pool, PoolItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final size = (MediaQuery.of(sheetContext).size.width * 0.7).clamp(160.0, 320.0);
      final pinned = pool.pinned.contains(item.id);
      final s = item.scored;
      final canArchive = pool.archiveStatus.signedIn && !item.fromArchive;
      final archived = pool.archivedPhotoIds.contains(item.id);
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: Image.memory(item.png, width: size, height: size, fit: BoxFit.cover),
                ),
                const SizedBox(height: 12),
                Text(formatDateTime(item.taken), style: Theme.of(sheetContext).textTheme.titleMedium),
                if (item.isMemory)
                  Text(
                    'Wspomnienie – zostanie w puli kilka dni, potem ustąpi innemu (przypięte zostaje)',
                    textAlign: TextAlign.center,
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                if (s.tags.isNotEmpty) Text(s.tags.join(' · '), textAlign: TextAlign.center),
                if (item.rating != null)
                  Text(
                    'AI: ${item.rating!.score}/10 – ${item.rating!.reason}',
                    textAlign: TextAlign.center,
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                Text(
                  'Punkty: ${s.score.toStringAsFixed(2)} · kadr: ${cropSourceNames[item.cropSource]}',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                if (s.rejected != null)
                  Text(
                    'Punktacja by je pominęła (${s.rejected}), ale jest przypięte.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      icon: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
                      label: Text(pinned ? 'Odepnij' : 'Przypnij'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        pinned ? pool.unpin(item.id) : pool.pin(item.id);
                      },
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.crop),
                      label: const Text('Popraw kadr'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CropScreen(pool: pool, item: item),
                          ),
                        );
                      },
                    ),
                    if (canArchive)
                      FilledButton.tonalIcon(
                        icon: Icon(archived ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined),
                        label: Text(archived ? 'W archiwum' : 'Dodaj do archiwum'),
                        onPressed: archived
                            ? null
                            : () async {
                                Navigator.pop(sheetContext);
                                final messenger = ScaffoldMessenger.of(context);
                                final error = await pool.addToArchive(item.id);
                                messenger.showSnackBar(SnackBar(
                                  content: Text(error ?? 'Dodane do archiwum - wróci jako wspomnienie za kilka tygodni'),
                                ));
                              },
                      ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Usuń z puli'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        pool.remove(item.id);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
