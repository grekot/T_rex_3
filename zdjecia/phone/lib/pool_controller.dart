// Sterowanie pulą: szuka zdjęć z aparatu, analizuje tylko nowe, daje je do oceny Gemini (gdy jest klucz),
// układa pulę 20 zdjęć, kadruje i publikuje gotowe PNG w plikach (published.json), skąd most w usłudze
// w tle podaje je zegarkowi. Ten sam kod działa w aplikacji i bez ekranu w usłudze w tle (headless);
// blokada w plikach pilnuje, żeby nie odświeżały naraz.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'ai/ai_errors.dart';
import 'ai/gemini_client.dart';
import 'ai/key_store.dart';
import 'ai/photo_rating.dart';
import 'ai/rater.dart';
import 'media/analyzer.dart';
import 'media/gallery.dart';
import 'select/analysis.dart';
import 'select/candidates.dart';
import 'select/crop.dart';
import 'select/memories.dart';
import 'select/rotation.dart';
import 'select/pool.dart';
import 'select/scoring.dart';
import 'select/store.dart';

enum PoolPhase { starting, scanning, analyzing, rating, memories, preparing, ready, noAccess, failed }

/// Najwięcej zdjęć wysyłanych do oceny w jednym odświeżeniu (reszta przy następnym)
const int maxRatingsPerRefresh = 400;

/// Przerwa między zapytaniami do Gemini - darmowy klucz ma limit zapytań na minutę
const Duration ratingPause = Duration(seconds: 4);

class PoolItem {
  const PoolItem({
    required this.scored,
    required this.crop,
    required this.manualCrop,
    required this.png,
    this.isMemory = false,
    this.cropSource = CropSource.band,
  });

  final ScoredPhoto scored;
  final CropBox crop;
  final bool manualCrop;
  final Uint8List png;

  /// Starsze zdjęcie z losowego okresu (wspomnienie)
  final bool isMemory;

  /// Skąd kadr: ręczny, AI, twarze...
  final CropSource cropSource;

  /// Podpis dla zegarka; przy wspomnieniu z rokiem, np. „Nad jeziorem · 2019”
  String get watchCaption {
    final caption = rating?.caption ?? '';
    if (!isMemory) return caption;
    return caption.isEmpty ? '${taken.year}' : '$caption · ${taken.year}';
  }

  String get id => scored.id;
  String get watchId => watchPhotoId(scored.id, crop);
  DateTime get taken => scored.taken;
  PhotoRating? get rating => scored.rating;
}

class PoolController extends ChangeNotifier {
  PoolController({this.headless = false});

  /// Bez ekranu (usługa w tle): bez okien systemowych, dostęp do galerii nadany wcześniej w aplikacji
  final bool headless;
  late SelectStore _store;
  late Directory _tempDir;
  PoolPrefs prefs = PoolPrefs();
  Map<String, PhotoAnalysis> _analyses = {};
  Map<String, PhotoRating> _ratings = {};
  Map<String, AssetEntity> _assets = {};
  List<MemoryItem> _memories = [];
  final _random = math.Random();
  final _keys = KeyStore();
  String _apiKey = '';

  PoolPhase phase = PoolPhase.starting;
  int done = 0;
  int total = 0;
  String? error;
  bool limited = false;

  /// Ostatni problem z oceną AI (limit, zły klucz) - pula i tak powstaje
  String? aiError;

  /// Odświeżanie trwało już gdzie indziej (usługa w tle) - ta próba została pominięta
  bool lockedOut = false;

  /// Ile zdjęć weszło do puli przy ostatnim przygotowaniu (nowe dla zegarka)
  int lastNewPhotos = 0;

  bool get hasApiKey => _apiKey.isNotEmpty;
  bool get aiActive => prefs.aiEnabled && hasApiKey;
  int get ratedCount => scored.where((s) => s.rating != null).length;

  /// Wszystkie zdjęcia z okresu z punktami
  List<ScoredPhoto> scored = const [];
  List<PoolItem> pool = const [];
  bool _busy = false;

  bool get busy => _busy;
  Set<String> get pinned => prefs.pinned;

  /// Powody odrzucenia z liczbą zdjęć (powody AI zebrane razem)
  Map<String, int> get rejectedCounts {
    final out = <String, int>{};
    for (final s in scored) {
      final r = s.rejected;
      if (r == null) continue;
      final key = r.startsWith('AI:') ? 'nieciekawe wg AI' : r;
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  Future<void> init({bool refreshNow = true}) async {
    _store = await openSelectStore();
    _tempDir = await getTemporaryDirectory();
    await _reload();
    notifyListeners();
    if (refreshNow) await refresh();
  }

  // Stan z plików - druga strona (aplikacja / usługa w tle) mogła go zmienić
  Future<void> _reload() async {
    prefs = await _store.loadPrefs();
    _analyses = await _store.loadAnalyses();
    _ratings = await _store.loadRatings();
    _apiKey = await _keys.gemini();
  }

  /// Pełne odświeżenie: nowe zdjęcia z galerii, analiza nowych, pula od nowa.
  /// [swap] (przycisk „Odśwież”): od razu wymienia kilka świeżych zdjęć i wspomnień.
  Future<void> refresh({bool swap = false}) => _run(() => _fullRefresh(swap: swap));

  /// Ile wspomnień wymienia ręczne „Odśwież”
  static const int memorySwapOnRefresh = 2;

  // Cały przebieg na świeżym stanie z plików (usługa w tle mogła zmienić wspomnienia czy oceny);
  // gdy nie ma nic nowego, trwa krótko: analizy, oceny i PNG są zapamiętane.
  Future<void> _fullRefresh({bool swap = false}) async {
        _set(PoolPhase.scanning);
        if (headless) {
          // Bez aktywności nie da się pytać o zgodę - korzystamy z tej nadanej w aplikacji
          PhotoManager.setIgnorePermissionCheck(true);
        } else {
          final access = await requestGalleryAccess();
          limited = access == PermissionState.limited;
          if (!access.hasAccess) {
            _set(PoolPhase.noAccess);
            return;
          }
        }
        final assets = <String, AssetEntity>{for (final a in await cameraPhotos(prefs.days)) photoIdOf(a): a};
        // Przypięte zdjęcia spoza okresu (dodane ręcznie) też biorą udział
        for (final e in prefs.pinnedAssets.entries) {
          if (assets.containsKey(e.key)) continue;
          final a = await AssetEntity.fromId(e.value);
          if (a != null) assets[photoIdOf(a)] = a;
        }
        // Wspomnienia, które jeszcze nie wygasły, zostają w puli
        _memories = [];
        final active = activeMemories(await _store.loadMemories(), DateTime.now(),
            pinned: prefs.pinned, removed: prefs.removed);
        if (swap) {
          // Najdłużej obecne, nieprzypięte wspomnienia ustępują nowym
          final old = [for (final m in active) if (!prefs.pinned.contains(m.photoId)) m]
            ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
          active.removeWhere(old.take(memorySwapOnRefresh).contains);
        }
        for (final m in active) {
          final a = assets[m.photoId] ?? await AssetEntity.fromId(m.assetId);
          if (a == null) continue;
          assets[photoIdOf(a)] = a;
          _memories.add(m);
        }
        _assets = assets;
        await _analyzeMissing();
        _forgetOld();
        await _store.saveAnalyses(_analyses);
        await _rateMissing();
        await _refreshMemories();
        _rescore();
        await _preparePool(swap: swap ? freshSwapOnRefresh : 0);
  }

  /// Uzupełnia wspomnienia do udziału z ustawień: losuje okresy z historii galerii, z każdego
  /// najlepszych kandydatów (telefon odsiewa, AI wybiera), najwyżej [maxPeriodsPerRefresh] okresów naraz.
  Future<void> _refreshMemories() async {
    final target = memoryTarget(prefs.size, prefs.memoryShare);
    if (target == 0) {
      _memories = [for (final m in _memories) if (prefs.pinned.contains(m.photoId)) m];
      await _store.saveMemories(_memories);
      return;
    }
    final need = target - _memories.length;
    if (need <= 0) {
      await _store.saveMemories(_memories);
      return;
    }
    final oldest = await oldestCameraPhoto();
    if (oldest == null) return;

    _set(PoolPhase.memories, total: maxPeriodsPerRefresh);
    final now = DateTime.now();
    final hash = prefsHash(prefs.preferences);
    final rater = aiActive
        ? PhotoRater(client: GeminiClient(apiKey: _apiKey, model: prefs.aiModel), preferences: prefs.preferences)
        : null;
    const fatal = [AiErrorKind.rateLimited, AiErrorKind.unauthorized, AiErrorKind.noApiKey, AiErrorKind.badRequest];
    final analyzer = PhotoAnalyzer(_tempDir);
    final periodIds = <String>{};
    var found = 0;
    var periods = 0;
    try {
      // Puste okresy (np. lata z małą liczbą zdjęć) nie liczą się do limitu zapytań AI
      for (var attempt = 0; attempt < maxPeriodAttempts && periods < maxPeriodsPerRefresh && found < need; attempt++) {
        done = periods;
        notifyListeners();
        final years = {for (final m in _memories) m.taken.year};
        final period = randomPeriodSpread(oldest, now, prefs.days, _random, years);
        if (period == null) break;
        final taken = {for (final m in _memories) m.photoId};
        final inPeriod = [
          for (final a in await cameraPhotosBetween(period.start, period.end))
            if (!taken.contains(photoIdOf(a)) && !prefs.removed.contains(photoIdOf(a))) a,
        ];
        if (inPeriod.isEmpty) continue;
        periods++;

        // Kandydaci: rozłożeni w czasie (bez serii), przeanalizowani, odsiani przez telefon
        final analyses = <PhotoAnalysis>[];
        for (final a in spreadInTime(inPeriod, (a) => a.createDateTime, candidatesPerPeriod * 2)) {
          final id = photoIdOf(a);
          var an = _analyses[id];
          if (an == null) {
            try {
              an = await analyzer.analyze(a);
            } catch (err) {
              debugPrint('Wspomnienie $id: $err');
            }
          }
          if (an == null) continue;
          _analyses[id] = an;
          _assets[id] = a;
          periodIds.add(id);
          analyses.add(an);
        }
        final local = scoreAll(analyses, now: now, days: prefs.days);
        final candidates = bestOf(local.where((s) => s.accepted).toList(), (s) => s.score, candidatesPerPeriod);
        if (candidates.isEmpty) continue;

        var chosen = <ScoredPhoto>[];
        if (rater == null) {
          chosen = candidates.take(1).toList(); // bez AI: najlepsze według telefonu
        } else {
          final toRate = [for (final s in candidates) if (needsRating(_ratings[s.id], hash)) s];
          if (toRate.isNotEmpty) {
            final inputs = <RatingInput>[];
            final ids = <String>[];
            for (final s in toRate) {
              final jpeg = await imageBytes(_assets[s.id]!, 512, quality: 80);
              if (jpeg == null) continue;
              inputs.add(RatingInput(jpeg: jpeg, taken: s.taken));
              ids.add(s.id);
            }
            try {
              final ratings = await rater.rateBatch(inputs);
              for (var k = 0; k < ids.length; k++) {
                final r = ratings[k];
                if (r != null) _ratings[ids[k]] = r;
              }
            } on AiException catch (e) {
              aiError = e.userMessage;
              if (fatal.contains(e.kind)) break;
              continue;
            }
            await Future<void>.delayed(ratingPause);
          }
          chosen = bestOf(candidates, (s) {
            final r = _ratings[s.id];
            return r != null && r.keep && r.score >= minMemoryScore ? r.score + 0.01 * s.score : null;
          }, keepPerPeriod);
        }
        for (final s in chosen.take(need - found)) {
          // Ważność rozłożona losowo (3,5-7 dni), żeby wspomnienia wymieniały się po trochu,
          // a nie wszystkie naraz - zegarek dociąga tylko 1-2 zdjęcia przy każdym wyskoczeniu
          final age = Duration(minutes: _random.nextInt(memoryLifetime.inMinutes ~/ 2));
          _memories.add(MemoryItem(photoId: s.id, assetId: s.analysis.assetId, addedAt: now.subtract(age), taken: s.taken));
          found++;
        }
      }
    } finally {
      await analyzer.close();
    }
    // Kandydaci, którzy nie zostali wspomnieniami, nie są już potrzebni
    final memoryIds = {for (final m in _memories) m.photoId};
    for (final id in periodIds) {
      if (memoryIds.contains(id)) continue;
      _assets.remove(id);
      _analyses.remove(id);
    }
    await _store.saveAnalyses(_analyses);
    await _store.saveRatings(_ratings);
    await _store.saveMemories(_memories);
  }

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
    _ratings.removeWhere((id, _) => !_assets.containsKey(id));
  }

  void _rescore() {
    final present = [for (final id in _assets.keys) ?_analyses[id]];
    scored = scoreAll(present, now: DateTime.now(), days: prefs.days, ratings: _ratings);
  }

  /// Gemini ocenia zdjęcia bez aktualnej oceny: po odsianiu przez telefon (nieostre, dokumenty,
  /// serie) i najlepsze najpierw, żeby przy limicie klucza ocenione były te najbardziej obiecujące.
  Future<void> _rateMissing() async {
    aiError = null;
    if (!aiActive) return;
    final hash = prefsHash(prefs.preferences);
    final inPool = {for (final p in await _store.loadPublished()) p.photoId};
    final local = scoreAll([for (final id in _assets.keys) ?_analyses[id]], now: DateTime.now(), days: prefs.days);
    final winners = [
      for (final group in groupBursts(local.where((s) => s.accepted || prefs.pinned.contains(s.id)).toList()))
        group.first,
      ...local.where((s) => prefs.pinned.contains(s.id)),
    ]..sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    final todo = [
      for (final s in winners)
        if (seen.add(s.id) && needsRating(_ratings[s.id], hash, inPool: inPool.contains(s.id))) s,
    ].take(maxRatingsPerRefresh).toList();
    if (todo.isEmpty) return;

    _set(PoolPhase.rating, total: todo.length);
    final rater = PhotoRater(client: GeminiClient(apiKey: _apiKey, model: prefs.aiModel), preferences: prefs.preferences);
    const fatal = [AiErrorKind.rateLimited, AiErrorKind.unauthorized, AiErrorKind.noApiKey, AiErrorKind.badRequest];
    for (var start = 0; start < todo.length; start += ratingBatchSize) {
      final batch = todo.skip(start).take(ratingBatchSize).toList();
      final inputs = <RatingInput>[];
      final ids = <String>[];
      for (final s in batch) {
        final asset = _assets[s.id];
        final jpeg = asset == null ? null : await imageBytes(asset, 512, quality: 80);
        if (jpeg == null) continue;
        inputs.add(RatingInput(jpeg: jpeg, taken: s.taken));
        ids.add(s.id);
      }
      try {
        if (inputs.isNotEmpty) {
          final ratings = await rater.rateBatch(inputs);
          for (var i = 0; i < ids.length; i++) {
            final r = ratings[i];
            if (r != null) _ratings[ids[i]] = r;
          }
          await _store.saveRatings(_ratings);
        }
      } on AiException catch (e) {
        aiError = e.userMessage;
        if (fatal.contains(e.kind)) break;
      }
      done += batch.length;
      notifyListeners();
      if (start + ratingBatchSize < todo.length) await Future<void>.delayed(ratingPause);
    }
  }

  Future<void> _preparePool({int swap = 0}) async {
    // Pula = wspomnienia (najlepsze najpierw) + świeże zdjęcia na pozostałe miejsca, wg zasad puli
    final memoryIds = {for (final m in _memories) m.photoId};
    final memories = [
      for (final s in scored)
        if (memoryIds.contains(s.id) && !prefs.removed.contains(s.id)) s,
    ]..sort((a, b) => b.score.compareTo(a.score));
    // Przypięte wspomnienia najpierw; po zmniejszeniu udziału nadmiar odpada
    memories.sort((a, b) => (prefs.pinned.contains(b.id) ? 1 : 0) - (prefs.pinned.contains(a.id) ? 1 : 0));
    final pinnedMemories = memories.where((s) => prefs.pinned.contains(s.id)).length;
    final memorySlots = math.min(
      memories.length,
      math.min(prefs.size, math.max(memoryTarget(prefs.size, prefs.memoryShare), pinnedMemories)),
    );
    final rotation = await _store.loadRotation();
    final recent = rotateFresh(
      [for (final s in scored) if (!memoryIds.contains(s.id)) s],
      PoolRules(size: prefs.size - memorySlots, pinned: prefs.pinned, removed: prefs.removed),
      rotation,
      DateTime.now(),
      _random,
      swap: swap,
    );
    await _store.saveRotation(rotation);
    final chosen = [...recent, ...memories.take(memorySlots)];
    _set(PoolPhase.preparing, total: chosen.length);
    final items = <PoolItem>[];
    for (final s in chosen) {
      final manual = prefs.crops[s.id];
      final auto = autoCropWithSource(s.analysis, subject: s.rating?.subject, focus: s.rating?.focus);
      final crop = manual ?? auto.box;
      try {
        items.add(PoolItem(
          scored: s,
          crop: crop,
          manualCrop: manual != null,
          png: await _png(s, crop),
          isMemory: memoryIds.contains(s.id),
          cropSource: manual != null ? CropSource.manual : auto.source,
        ));
      } catch (err) {
        debugPrint('PNG ${s.id}: $err');
      }
      done++;
      notifyListeners();
    }
    pool = items;
    final before = {for (final p in await _store.loadPublished()) p.id};
    lastNewPhotos = items.where((i) => !before.contains(i.watchId)).length;
    await _store.publish([
      for (final i in items)
        PublishedPhoto(
          id: i.watchId,
          photoId: i.id,
          path: _store.pngFile(i.id, i.crop).path,
          size: i.png.length,
          taken: i.taken,
          caption: i.watchCaption,
        ),
    ]);
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
        // Zapamiętane, żeby zostało w puli także po wypadnięciu z okresu czy z wspomnień
        final asset = _assets[id];
        if (asset != null) prefs.pinnedAssets[id] = asset.id;
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

  Future<void> updateSettings({required int days, required int size, required int memoryShare}) async {
    prefs.days = days;
    prefs.size = size;
    prefs.memoryShare = memoryShare;
    await _store.savePrefs(prefs);
    await refresh();
  }

  /// Zdjęcie wybrane ręcznie z galerii: przypięte, analizowane, jeśli trzeba
  Future<void> addManual(AssetEntity asset) => _run(() async {
        final id = photoIdOf(asset);
        prefs.pinned.add(id);
        prefs.removed.remove(id);
        prefs.pinnedAssets[id] = asset.id;
        await _store.savePrefs(prefs);
        await _fullRefresh();
      });

  AssetEntity? assetOf(String id) => _assets[id];

  Future<AutoState> autoState() => _store.loadAuto();

  /// Zapamiętany wybór: czy usługa w tle ma działać (włączana też po restarcie aplikacji)
  Future<void> setAutoEnabled(bool enabled) async {
    final p = await _store.loadPrefs();
    p.autoEnabled = enabled;
    await _store.savePrefs(p);
    prefs.autoEnabled = enabled;
    notifyListeners();
  }

  // --- AI ---

  Future<String> apiKey() => _keys.gemini();

  /// null = klucz i model działają, inaczej komunikat do pokazania
  Future<String?> testAi(String key, String model) async {
    try {
      await GeminiClient(apiKey: key.trim(), model: model).ping();
      return null;
    } on AiException catch (e) {
      return e.userMessage;
    }
  }

  Future<List<String>> aiModels(String key) => GeminiClient(apiKey: key.trim()).listModels();

  /// Zapis ustawień AI; zmiana preferencji albo modelu = ponowna ocena przy odświeżeniu
  Future<void> setAi({required bool enabled, required String key, required String model, required String preferences}) async {
    await _keys.setGemini(key);
    _apiKey = key.trim();
    if (model != prefs.aiModel) await _store.saveRatings({});
    prefs.aiEnabled = enabled;
    prefs.aiModel = model;
    prefs.preferences = preferences.trim();
    await _store.savePrefs(prefs);
    await refresh();
  }

  Future<void> _change(void Function() update) => _run(() async {
        update();
        await _store.savePrefs(prefs);
        await _fullRefresh();
      });

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    _busy = true;
    error = null;
    lockedOut = false;
    try {
      if (!await _store.tryLock()) {
        lockedOut = true;
        return;
      }
      try {
        await _reload();
        await job();
      } finally {
        await _store.unlock();
      }
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
