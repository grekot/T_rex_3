// Źródło zdjęć dla mostu: opublikowana pula z plików (published.json + PNG na dysku).
import 'dart:io';

import '../select/store.dart';
import 'bridge_server.dart';

Future<List<BridgePhoto>> publishedPhotos(SelectStore store) async => [
      for (final p in await store.loadPublished())
        if (File(p.path).existsSync())
          BridgePhoto.file(id: p.id, file: File(p.path), size: p.size, taken: p.taken, caption: p.caption),
    ];
