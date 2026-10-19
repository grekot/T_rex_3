// Karta zdjęcia z puli: duży okrągły podgląd jak na zegarku, powody wyboru i akcje.
import 'package:flutter/material.dart';

import '../bridge/format.dart';
import '../pool_controller.dart';
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
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(child: Image.memory(item.png, width: size, height: size, fit: BoxFit.cover)),
              const SizedBox(height: 12),
              Text(formatDateTime(item.taken), style: Theme.of(sheetContext).textTheme.titleMedium),
              if (s.tags.isNotEmpty) Text(s.tags.join(' · ')),
              Text(
                'Punkty: ${s.score.toStringAsFixed(2)}${item.manualCrop ? ' · kadr poprawiony ręcznie' : ''}',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              if (s.rejected != null)
                Text('Punktacja by je pominęła (${s.rejected}), ale jest przypięte.',
                    style: Theme.of(sheetContext).textTheme.bodySmall),
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
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CropScreen(pool: pool, item: item)));
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
      );
    },
  );
}
