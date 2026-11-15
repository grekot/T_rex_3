// Archiwum w Firestore widziane z telefonu: spis zapamiętany w pliku (sprawdzany w bazie najwyżej co
// [indexCheckEvery] jednym małym odczytem), zdjęcia ściągane dopiero, gdy są potrzebne, i trzymane w plikach
// tylko dopóki są w puli / strumieniu (plus kilkadziesiąt ostatnich na zapas).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../cloud/firebase_rest.dart';
import 'archive.dart';

const Duration indexCheckEvery = Duration(hours: 1);

/// Ile zdjęć spoza puli i strumienia zostaje w pamięci podręcznej
const int archiveSpareFiles = 40;

class ArchiveStatus {
  const ArchiveStatus({this.email, this.count = 0, this.updatedAt, this.error, this.configured = true});

  /// Zalogowane konto (null = brak)
  final String? email;
  final int count;
  final String? updatedAt;

  /// Ostatni problem (brak sieci, wygasła sesja) - spis z pamięci i tak działa
  final String? error;
  final bool configured;

  bool get signedIn => email != null;
}

int _tmp = 0;

class ArchiveSource {
  ArchiveSource(this.dir, {FirebaseRest? cloud, DateTime Function()? now})
      : cloud = cloud ?? FirebaseRest(),
        _now = now ?? DateTime.now;

  final Directory dir;
  final FirebaseRest cloud;
  final DateTime Function() _now;

  File get _indexFile => File('${dir.path}/spis.json');
  File get _shownFile => File('${dir.path}/pokazane.json');
  Directory get photoDir => Directory('${dir.path}/zdjecia');
  File photoFile(String id) => File('${photoDir.path}/$id.jpg');

  /// Spis zdjęć. [check] = sprawdź w bazie, czy się zmienił (najwyżej co [indexCheckEvery], [force] - teraz).
  Future<({List<ArchiveEntry> entries, ArchiveStatus status})> index({bool check = true, bool force = false}) async {
    final account = await cloud.account();
    final cached = await _readJson(_indexFile);
    if (!cloud.configured) return (entries: const <ArchiveEntry>[], status: const ArchiveStatus(configured: false));
    if (account == null) return (entries: const <ArchiveEntry>[], status: const ArchiveStatus());
    final sameUser = cached?['uid'] == account.uid;
    var items = sameUser ? cached!['items'] as String? ?? '[]' : '[]';
    var updatedAt = sameUser ? cached!['updatedAt'] as String? : null;
    final checked = sameUser && cached!['checked'] is int ? DateTime.fromMillisecondsSinceEpoch(cached['checked'] as int) : null;
    String? error;
    if (check && (force || checked == null || _now().difference(checked) >= indexCheckEvery)) {
      try {
        final head = await cloud.getDocument('archiwum/${account.uid}', mask: const ['updatedAt', 'count']);
        if (head == null) {
          items = '[]';
          updatedAt = null;
        } else if (head['updatedAt'] != updatedAt || !sameUser) {
          final full = await cloud.getDocument('archiwum/${account.uid}');
          items = full?['items'] as String? ?? '[]';
          updatedAt = full?['updatedAt'] as String?;
        }
        await _writeJson(_indexFile, {
          'uid': account.uid,
          'updatedAt': updatedAt,
          'items': items,
          'checked': _now().millisecondsSinceEpoch,
        });
      } on CloudException catch (e) {
        error = e.message;
      }
    }
    final entries = parseArchiveItems(items);
    return (
      entries: entries,
      status: ArchiveStatus(email: account.email, count: entries.length, updatedAt: updatedAt, error: error),
    );
  }

  /// JPEG zdjęcia z pamięci podręcznej albo z bazy; null = nie da się (brak sieci, usunięte z archiwum)
  Future<Uint8List?> photo(String id) async {
    final file = photoFile(id);
    if (await file.exists()) {
      try {
        await file.setLastModified(_now()); // ostatnio używane zostają przy porządkach
      } catch (_) {}
      return file.readAsBytes();
    }
    final account = await cloud.account();
    if (account == null) return null;
    final doc = await cloud.getDocument('archiwum/${account.uid}/zdjecia/$id');
    final jpeg = doc?['jpeg'];
    if (jpeg is! Uint8List || jpeg.isEmpty) return null;
    await photoDir.create(recursive: true);
    final tmp = File('${file.path}.${_tmp++}.tmp');
    await tmp.writeAsBytes(jpeg, flush: true);
    await tmp.rename(file.path);
    return jpeg;
  }

  /// Usuwa z pamięci podręcznej zdjęcia spoza [keep], zostawiając [spare] ostatnio używanych
  Future<void> prune(Set<String> keep, {int spare = archiveSpareFiles}) async {
    if (!await photoDir.exists()) return;
    final others = <(File, DateTime)>[];
    await for (final f in photoDir.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.jpg')) {
        if (name.endsWith('.tmp')) await _delete(f);
        continue;
      }
      if (keep.contains(name.substring(0, name.length - 4))) continue;
      others.add((f, await f.lastModified()));
    }
    others.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (f, _) in others.skip(spare)) {
      await _delete(f);
    }
  }

  /// Kiedy które zdjęcie z archiwum było wspomnieniem na zegarku
  Future<Map<String, DateTime>> loadShown() async {
    final j = await _readJson(_shownFile);
    return {
      for (final e in (j ?? const {}).entries)
        if (e.value is int) e.key: DateTime.fromMillisecondsSinceEpoch(e.value as int),
    };
  }

  Future<void> saveShown(Map<String, DateTime> shown) =>
      _writeJson(_shownFile, {for (final e in shown.entries) e.key: e.value.millisecondsSinceEpoch});

  Future<ArchiveStatus> signIn(String email, String password) async {
    await cloud.signIn(email, password);
    return (await index(force: true)).status;
  }

  /// Wylogowanie: konto, spis i zdjęcia z telefonu znikają (w bazie zostają)
  Future<void> signOut() async {
    await cloud.signOut();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _delete(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readJson(File f) async {
    try {
      if (!await f.exists()) return null;
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(File f, Object data) async {
    await dir.create(recursive: true);
    final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.${_tmp++}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }
}
