// Pamięć aplikacji w plikach JSON: wyniki analizy (żeby nie analizować zdjęć drugi raz),
// ustawienia, przypięte / usunięte zdjęcia i ręczne kadry.
import 'dart:convert';
import 'dart:io';

import '../ai/gemini_client.dart';
import '../ai/photo_rating.dart';
import 'analysis.dart';
import 'crop.dart';

class PoolPrefs {
  PoolPrefs({
    this.days = 30,
    this.size = 20,
    Set<String>? pinned,
    Set<String>? removed,
    Map<String, CropBox>? crops,
    Map<String, String>? pinnedAssets,
    this.aiEnabled = true,
    this.aiModel = defaultGeminiModel,
    this.preferences = '',
  })  : pinned = pinned ?? {},
        removed = removed ?? {},
        crops = crops ?? {},
        pinnedAssets = pinnedAssets ?? {};

  /// Z ilu ostatnich dni brać zdjęcia
  int days;

  /// Ile zdjęć w puli dla zegarka
  int size;
  final Set<String> pinned;
  final Set<String> removed;

  /// Ręcznie poprawione kadry (id zdjęcia -> kadr)
  final Map<String, CropBox> crops;

  /// Przypięte zdjęcia spoza okresu (np. dodane ręcznie): id zdjęcia -> id w galerii
  final Map<String, String> pinnedAssets;

  /// Ocena przez Gemini (gdy jest klucz); bez niej - sama punktacja na telefonie
  bool aiEnabled;
  String aiModel;

  /// Co właściciel lubi / czego nie chce - dopisywane do polecenia dla AI
  String preferences;

  Map<String, Object> toJson() => {
        'days': days,
        'size': size,
        'pinned': pinned.toList(),
        'removed': removed.toList(),
        'crops': {for (final e in crops.entries) e.key: e.value.toJson()},
        'pinnedAssets': pinnedAssets,
        'ai': aiEnabled,
        'aiModel': aiModel,
        'preferences': preferences,
      };

  factory PoolPrefs.fromJson(Map<String, dynamic> j) => PoolPrefs(
        days: j['days'] as int? ?? 30,
        size: j['size'] as int? ?? 20,
        pinned: {...(j['pinned'] as List? ?? const []).cast<String>()},
        removed: {...(j['removed'] as List? ?? const []).cast<String>()},
        crops: {
          for (final e in ((j['crops'] as Map?) ?? const {}).entries)
            e.key as String: CropBox.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        pinnedAssets: ((j['pinnedAssets'] as Map?) ?? const {}).cast<String, String>(),
        aiEnabled: j['ai'] as bool? ?? true,
        aiModel: j['aiModel'] as String? ?? defaultGeminiModel,
        preferences: j['preferences'] as String? ?? '',
      );
}

class SelectStore {
  SelectStore(this.dir);

  final Directory dir;

  File get _prefsFile => File('${dir.path}/prefs.json');
  File get _analysisFile => File('${dir.path}/analysis.json');
  File get _ratingsFile => File('${dir.path}/ratings.json');
  Directory get pngDir => Directory('${dir.path}/png');

  Future<PoolPrefs> loadPrefs() async {
    final j = await _readJson(_prefsFile);
    return j == null ? PoolPrefs() : PoolPrefs.fromJson(j);
  }

  Future<void> savePrefs(PoolPrefs prefs) => _writeJson(_prefsFile, prefs.toJson());

  Future<Map<String, PhotoAnalysis>> loadAnalyses() async {
    final j = await _readJson(_analysisFile);
    final items = (j?['items'] as Map?) ?? const {};
    final out = <String, PhotoAnalysis>{};
    for (final e in items.entries) {
      final a = PhotoAnalysis.fromJson((e.value as Map).cast<String, dynamic>());
      if (a != null) out[e.key as String] = a;
    }
    return out;
  }

  Future<void> saveAnalyses(Map<String, PhotoAnalysis> items) =>
      _writeJson(_analysisFile, {'items': {for (final e in items.entries) e.key: e.value.toJson()}});

  Future<Map<String, PhotoRating>> loadRatings() async {
    final j = await _readJson(_ratingsFile);
    final out = <String, PhotoRating>{};
    for (final e in ((j?['items'] as Map?) ?? const {}).entries) {
      final r = PhotoRating.fromJson((e.value as Map).cast<String, dynamic>());
      if (r != null) out[e.key as String] = r;
    }
    return out;
  }

  Future<void> saveRatings(Map<String, PhotoRating> items) =>
      _writeJson(_ratingsFile, {'items': {for (final e in items.entries) e.key: e.value.toJson()}});

  /// Gotowy PNG dla zegarka (zależy od kadru, więc kadr jest w nazwie)
  File pngFile(String id, CropBox crop) => File('${pngDir.path}/${id}_${crop.key}.png');

  /// Usuwa PNG zdjęć, których nie ma już w puli
  Future<void> prunePngs(Set<String> keepPaths) async {
    if (!await pngDir.exists()) return;
    await for (final f in pngDir.list()) {
      if (f is File && !keepPaths.contains(f.path)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>?> _readJson(File f) async {
    try {
      if (!await f.exists()) return null;
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return null; // uszkodzony plik = zaczynamy od zera
    }
  }

  // Zapis przez plik tymczasowy, żeby przerwanie w połowie nie zostawiło uciętego JSON-a
  Future<void> _writeJson(File f, Object data) async {
    await dir.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }
}
