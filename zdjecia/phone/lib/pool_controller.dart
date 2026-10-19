// Sterowanie pulą: szuka zdjęć z aparatu, analizuje tylko nowe, punktuje, układa pulę 20 zdjęć,
// kadruje i podaje gotowe PNG serwerowi mostu (zegarek pobiera je pod 127.0.0.1).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'bridge/bridge_server.dart';
import 'media/analyzer.dart';
import 'media/gallery.dart';
import 'select/analysis.dart';
import 'select/candidates.dart';
import 'select/crop.dart';
import 'select/pool.dart';
import 'select/scoring.dart';
import 'select/store.dart';

enum PoolPhase { starting, scanning, analyzing, preparing, ready, noAccess, failed }

class PoolItem {
  const PoolItem({required this.scored, required this.crop, required this.manualCrop, required this.png});

  final ScoredPhoto scored;
  final CropBox crop;
  final bool manualCrop;
  final Uint8List png;

  String get id => scored.id;
  String get watchId => watchPhotoId(scored.id, crop);
  DateTime get taken => scored.taken;
}

class PoolController extends ChangeNotifier {
  PoolController(this.server);

  final BridgeServer server;
  late SelectStore _store;
  late Directory _tempDir;
  PoolPrefs prefs = PoolPrefs();
  Map<String, PhotoAnalysis> _analyses = {};
  Map<String, AssetEntity> _assets = {};

  PoolPhase phase = PoolPhase.starting;
  int done = 0;
  int total = 0;
  String? error;
  bool limited = false;

  /// Wszystkie zdjęcia z okresu z punktami
  List<ScoredPhoto> scored = const [];
  List<PoolItem> pool = const [];
  bool _busy = false;

  bool get busy => _busy;
  Set<String> get pinned => prefs.pinned;

  Map<String, int> get rejectedCounts {
    final out = <String, int>{};
    for (final s in scored) {
      if (s.rejected != null) out[s.rejected!] = (out[s.rejected!] ?? 0) + 1;
    }
    return out;
  }

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _store = SelectStore(Directory('${support.path}/wybor'));
    _tempDir = await getTemporaryDirectory();
    prefs = await _store.loadPrefs();
    _analyses = await _store.loadAnalyses();
    await refresh();
  }

  /// Pełne odświeżenie: nowe zdjęcia z galerii, analiza nowych, pula od nowa
  Future<void> refresh() => _run(() async {
        _set(PoolPhase.scanning);
        final access = await requestGalleryAccess();
        limited = access == PermissionState.limited;
        if (!access.hasAccess) {
          _set(PoolPhase.noAccess);
          return;
        }
        final assets = <String, AssetEntity>{for (final a in await cameraPhotos(prefs.days)) photoIdOf(a): a};
        // Przypięte zdjęcia spoza okresu (dodane ręcznie) też biorą udział
        for (final e in prefs.pinnedAssets.entries) {
          if (assets.containsKey(e.key)) continue;
          final a = await AssetEntity.fromId(e.value);
          if (a != null) assets[photoIdOf(a)] = a;
        }
        _assets = assets;
        await _analyzeMissing();
        _forgetOld();
        await _store.saveAnalyses(_analyses);
        _rescore();
        await _preparePool();
      });

  Future<void> _analyzeMissing() async {
    final todo = _assets.entries.where((e) => !_analyses.containsKey(e.key)).toList();
    if (todo.isEmpty) return;
    _set(PoolPhase.analyzing, total: todo.length);
    final analyzer = PhotoAnalyzer(_tempDir);
    try {
      for (final e in todo) {
        try {
          final a = await analyzer.analyze(e.value);
          if (a != null) _analyses[e.key] = a;
        } catch (err) {
          debugPrint('Analiza ${e.key}: $err');
        }
        done++;
        if (done % 10 == 0) {
          await _store.saveAnalyses(_analyses); // przerwanie nie gubi postępu
          notifyListeners();
        }
      }
    } finally {
      await analyzer.close();
    }
  }

  // Wyniki zdjęć, których już nie ma w okresie ani w przypiętych, nie są potrzebne
  void _forgetOld() {
    _analyses.removeWhere((id, _) => !_assets.containsKey(id));
  }

  void _rescore() {
    final present = [for (final id in _assets.keys) ?_analyses[id]];
    scored = scoreAll(present, now: DateTime.now(), days: prefs.days);
  }

  Future<void> _preparePool() async {
    final chosen = choosePool(
      scored,
      PoolRules(size: prefs.size, pinned: prefs.pinned, removed: prefs.removed),
    );
    _set(PoolPhase.preparing, total: chosen.length);
    final items = <PoolItem>[];
    for (final s in chosen) {
      final manual = prefs.crops[s.id];
      final crop = manual ?? autoCrop(s.analysis);
      try {
        items.add(PoolItem(scored: s, crop: crop, manualCrop: manual != null, png: await _png(s, crop)));
      } catch (err) {
        debugPrint('PNG ${s.id}: $err');
      }
      done++;
      notifyListeners();
    }
    pool = items;
    server.photos = [for (final i in items) BridgePhoto(id: i.watchId, png: i.png, taken: i.taken)];
    await _store.prunePngs({for (final i in items) _store.pngFile(i.id, i.crop).path});
    _set(PoolPhase.ready);
  }

  Future<Uint8List> _png(ScoredPhoto s, CropBox crop) async {
    final file = _store.pngFile(s.id, crop);
    if (await file.exists()) return file.readAsBytes();
    final asset = _assets[s.id] ?? await AssetEntity.fromId(s.analysis.assetId);
    if (asset == null) throw StateError('Zdjęcia nie ma już w galerii');
    final png = await watchPng(asset, crop);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png, flush: true);
    return png;
  }

  // --- zmiany użytkownika: bez ponownej analizy, tylko nowa pula ---

  Future<void> pin(String id) => _change(() {
        prefs.pinned.add(id);
        prefs.removed.remove(id);
      });

  Future<void> unpin(String id) => _change(() {
        prefs.pinned.remove(id);
        prefs.pinnedAssets.remove(id);
      });

  Future<void> remove(String id) => _change(() {
        prefs.removed.add(id);
        prefs.pinned.remove(id);
        prefs.pinnedAssets.remove(id);
      });

  Future<void> restoreRemoved() => _change(prefs.removed.clear);

  /// null = kadr automatyczny
  Future<void> setCrop(String id, CropBox? crop) => _change(() {
        if (crop == null) {
          prefs.crops.remove(id);
        } else {
          prefs.crops[id] = crop;
        }
      });

  Future<void> updateSettings({required int days, required int size}) async {
    final daysChanged = days != prefs.days;
    prefs.days = days;
    prefs.size = size;
    await _store.savePrefs(prefs);
    if (daysChanged) {
      await refresh();
    } else {
      await _run(_preparePool);
    }
  }

  /// Zdjęcie wybrane ręcznie z galerii: przypięte, analizowane, jeśli trzeba
  Future<void> addManual(AssetEntity asset) => _run(() async {
        final id = photoIdOf(asset);
        prefs.pinned.add(id);
        prefs.removed.remove(id);
        prefs.pinnedAssets[id] = asset.id;
        await _store.savePrefs(prefs);
        _assets[id] = asset;
        await _analyzeMissing();
        await _store.saveAnalyses(_analyses);
        _rescore();
        await _preparePool();
      });

  AssetEntity? assetOf(String id) => _assets[id];

  Future<void> _change(void Function() update) => _run(() async {
        update();
        await _store.savePrefs(prefs);
        _rescore();
        await _preparePool();
      });

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    _busy = true;
    error = null;
    try {
      await job();
    } catch (e) {
      error = '$e';
      phase = PoolPhase.failed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _set(PoolPhase p, {int total = 0}) {
    phase = p;
    done = 0;
    this.total = total;
    notifyListeners();
  }
}
