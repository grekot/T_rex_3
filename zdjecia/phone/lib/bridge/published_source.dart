// Źródło zdjęć dla mostu: opublikowana pula z plików (published.json + PNG na dysku).
// JPEG-i dla zegarów HomeAutomation powstają na żądanie z tego samego zdjęcia w galerii (kadr z danych
// zapisanych przy publikowaniu) i zostają w pamięci podręcznej na dysku - kolejne pobranie jest od razu.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../select/crop.dart';
import '../select/store.dart';
import 'bridge_server.dart';
import 'photo_prep.dart';

/// Zdjęcie źródłowe (miniatura z galerii, już obrócona) po id w galerii; null = nie ma go już
typedef SourceLoader = Future<Uint8List?> Function(String assetId);

int _tmpCounter = 0;

class JpegMaker {
  JpegMaker(this.store, {required this.loadSource});

  final SelectStore store;
  final SourceLoader loadSource;

  /// Jedno przygotowanie naraz dla tego samego pliku (zegar może zapytać drugi raz, zanim skończymy)
  final Map<String, Future<Uint8List?>> _pending = {};

  Future<Uint8List?> jpeg(PublishedPhoto p, int width, int height) async {
    final file = store.jpegFile(p.id, width, height);
    if (await file.exists()) return file.readAsBytes();
    final key = file.path;
    final pending = _pending[key];
    if (pending != null) return pending;
    final job = _make(p, width, height, file);
    _pending[key] = job;
    try {
      return await job;
    } finally {
      _pending.remove(key);
    }
  }

  Future<Uint8List?> _make(PublishedPhoto p, int width, int height, File file) async {
    final input = await _cropInput(p);
    if (input == null) return null;
    final source = await loadSource(input.assetId);
    if (source == null) return null;
    final rect = rectCrop(input.frame, width / height);
    final jpg = await compute(prepareJpegJob, JpegJob(source, rect, width, height));
    // Zapis przez plik tymczasowy - przerwanie nie zostawi uciętego JPEG-a w pamięci podręcznej
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.${_tmpCounter++}.tmp');
    await tmp.writeAsBytes(jpg, flush: true);
    await tmp.rename(file.path);
    return jpg;
  }

  /// Dane kadru z published.json, a dla pul sprzed 0.10.0 - z analizy, ocen i ręcznych kadrów
  Future<({String assetId, CropFrame frame})?> _cropInput(PublishedPhoto p) async {
    final frame = p.frame;
    if (frame != null && p.assetId.isNotEmpty) return (assetId: p.assetId, frame: frame);
    final analysis = (await store.loadAnalyses())[p.photoId];
    if (analysis == null) return null;
    final rating = (await store.loadRatings())[p.photoId];
    final manual = (await store.loadPrefs()).crops[p.photoId];
    return (
      assetId: analysis.assetId,
      frame: CropFrame.of(analysis, subject: rating?.subject, focus: rating?.focus, manual: manual),
    );
  }
}

Future<List<BridgePhoto>> publishedPhotos(SelectStore store, {JpegMaker? jpeg}) async => [
      for (final p in await store.loadPublished())
        if (File(p.path).existsSync())
          BridgePhoto.file(
            id: p.id,
            file: File(p.path),
            size: p.size,
            taken: p.taken,
            caption: p.caption,
            memory: p.memory,
            jpeg: jpeg == null ? null : (w, h) => jpeg.jpeg(p, w, h),
          ),
    ];
