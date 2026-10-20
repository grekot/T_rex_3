// Pamięć aplikacji w plikach JSON: wyniki analizy (żeby nie analizować zdjęć drugi raz),
// ustawienia, przypięte / usunięte zdjęcia i ręczne kadry.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
    this.autoEnabled = true,
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

  /// Usługa w tle: most dla zegarka i odświeżanie puli bez otwierania aplikacji
  bool autoEnabled;

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
        'auto': autoEnabled,
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
        autoEnabled: j['auto'] as bool? ?? true,
      );
}

/// Blokada odświeżania starsza niż to jest porzucona
const Duration staleLock = Duration(minutes: 45);

int _tmpCounter = 0;

/// Zdjęcie opublikowanej puli: identyfikator na zegarku i gotowy PNG na dysku
class PublishedPhoto {
  const PublishedPhoto({
    required this.id,
    required this.path,
    required this.size,
    required this.taken,
    this.caption = '',
  });

  final String id;
  final String path;
  final int size;
  final DateTime taken;
  final String caption;

  Map<String, Object> toJson() => {
        'id': id,
        'path': path,
        'size': size,
        'taken': taken.millisecondsSinceEpoch,
        if (caption.isNotEmpty) 'caption': caption,
      };

  factory PublishedPhoto.fromJson(Map<String, dynamic> j) => PublishedPhoto(
        id: j['id'] as String,
        path: j['path'] as String,
        size: j['size'] as int? ?? 0,
        taken: DateTime.fromMillisecondsSinceEpoch(j['taken'] as int? ?? 0),
        caption: j['caption'] as String? ?? '',
      );
}

/// Stan automatycznego odświeżania w tle
class AutoState {
  const AutoState({this.lastRun, this.ok = true, this.error, this.poolSize = 0, this.newPhotos = 0});

  final DateTime? lastRun;
  final bool ok;
  final String? error;
  final int poolSize;

  /// Ile zdjęć weszło do puli przy ostatnim odświeżeniu
  final int newPhotos;

  Map<String, Object?> toJson() => {
        'lastRun': lastRun?.millisecondsSinceEpoch,
        'ok': ok,
        'error': error,
        'poolSize': poolSize,
        'newPhotos': newPhotos,
      };

  factory AutoState.fromJson(Map<String, dynamic> j) => AutoState(
        lastRun: j['lastRun'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['lastRun'] as int),
        ok: j['ok'] as bool? ?? true,
        error: j['error'] as String?,
        poolSize: j['poolSize'] as int? ?? 0,
        newPhotos: j['newPhotos'] as int? ?? 0,
      );
}

/// Co ile automatyczne odświeżanie puli; po błędzie próba wcześniej
const Duration autoRefreshEvery = Duration(hours: 12);
const Duration autoRetryAfterError = Duration(hours: 1);

bool autoRefreshDue(AutoState s, DateTime now) {
  final last = s.lastRun;
  if (last == null) return true;
  return now.difference(last) >= (s.ok ? autoRefreshEvery : autoRetryAfterError);
}

/// Magazyn w katalogu danych aplikacji (ten sam dla aplikacji i usługi w tle)
Future<SelectStore> openSelectStore() async {
  final support = await getApplicationSupportDirectory();
  return SelectStore(Directory('${support.path}/wybor'));
}

class SelectStore {
  SelectStore(this.dir);

  final Directory dir;

  File get _prefsFile => File('${dir.path}/prefs.json');
  File get _analysisFile => File('${dir.path}/analysis.json');
  File get _ratingsFile => File('${dir.path}/ratings.json');
  File get _publishedFile => File('${dir.path}/published.json');
  File get _autoFile => File('${dir.path}/auto.json');
  File get _lockFile => File('${dir.path}/refresh.lock');
  Directory get pngDir => Directory('${dir.path}/png');

  /// Pula dla zegarka (most w usłudze w tle czyta ją przy każdym zapytaniu zegarka)
  Future<void> publish(List<PublishedPhoto> photos, {DateTime? at}) => _writeJson(_publishedFile, {
        'updatedAt': (at ?? DateTime.now()).millisecondsSinceEpoch,
        'photos': [for (final p in photos) p.toJson()],
      });

  Future<List<PublishedPhoto>> loadPublished() async {
    final j = await _readJson(_publishedFile);
    return [
      for (final p in (j?['photos'] as List? ?? const []))
        if (p is Map) PublishedPhoto.fromJson(p.cast<String, dynamic>()),
    ];
  }

  Future<AutoState> loadAuto() async {
    final j = await _readJson(_autoFile);
    return j == null ? const AutoState() : AutoState.fromJson(j);
  }

  Future<void> saveAuto(AutoState state) => _writeJson(_autoFile, state.toJson());

  /// Tylko jedno odświeżanie naraz (aplikacja albo usługa w tle). Blokada starsza niż [staleLock]
  /// zostaje uznana za porzuconą (np. telefon zabił proces w połowie).
  Future<bool> tryLock({DateTime? now}) async {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await dir.create(recursive: true);
    try {
      await _lockFile.create(exclusive: true);
      await _lockFile.writeAsString('$t', flush: true);
      return true;
    } on FileSystemException {
      String text;
      try {
        text = await _lockFile.readAsString();
      } catch (_) {
        return false;
      }
      final since = int.tryParse(text.trim());
      if (since == null || t - since < staleLock.inMilliseconds) return false;
      await _lockFile.writeAsString('$t', flush: true);
      return true;
    }
  }

  Future<void> unlock() async {
    try {
      await _lockFile.delete();
    } catch (_) {}
  }

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
  // (nazwa z numerem, bo aplikacja i usługa w tle mogą zapisywać naraz)
  Future<void> _writeJson(File f, Object data) async {
    await dir.create(recursive: true);
    final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.${_tmpCounter++}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }
}
