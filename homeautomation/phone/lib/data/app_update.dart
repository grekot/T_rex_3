import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// Aktualizacja aplikacji na komputer: wersja z GitHub Release (tag `homeautomation-vX.Y.Z`, plik
// `homeautomation-windows.zip`). Telefon aktualizuje się przez Sklep rodzinny - tam tego nie sprawdzamy.

/// Wersja tej kompilacji (`--dart-define=APP_VERSION=X.Y.Z` w CI); pusta w kompilacji lokalnej - bez sprawdzania.
const appVersion = String.fromEnvironment('APP_VERSION');

const appReleaseTagPrefix = 'homeautomation-v';
const appWindowsAsset = 'homeautomation-windows.zip';
final appReleasesUrl = Uri.parse('https://api.github.com/repos/grekot/T_rex_3/releases?per_page=40');

class AppRelease {
  const AppRelease({required this.version, required this.page, required this.download});

  final String version;

  /// Strona wydania (opis).
  final Uri page;

  /// Plik zip do pobrania.
  final Uri download;
}

/// Porównanie wersji `X.Y.Z` (brakujące części = 0, nieliczbowe - 0).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Najnowsze wydanie z plikiem dla Windows z listy GitHuba (`GET /repos/.../releases`); null = brak.
AppRelease? latestWindowsRelease(Object? json) {
  if (json is! List) return null;
  AppRelease? best;
  for (final r in json) {
    if (r is! Map || r['draft'] == true || r['prerelease'] == true) continue;
    final tag = r['tag_name'];
    if (tag is! String || !tag.startsWith(appReleaseTagPrefix)) continue;
    final assets = r['assets'] is List ? r['assets'] as List : const [];
    final zip = assets.whereType<Map>().where((a) => a['name'] == appWindowsAsset).firstOrNull;
    final url = zip?['browser_download_url'], page = r['html_url'];
    if (url is! String || page is! String) continue;
    final version = tag.substring(appReleaseTagPrefix.length);
    if (best == null || compareVersions(version, best.version) > 0) {
      best = AppRelease(version: version, page: Uri.parse(page), download: Uri.parse(url));
    }
  }
  return best;
}

/// Nowsza wersja niż [current] albo null (także bez sieci - błąd nie przeszkadza w pracy).
Future<AppRelease?> checkAppUpdate({String current = appVersion, http.Client? client}) async {
  if (current.isEmpty) return null;
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(appReleasesUrl, headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final latest = latestWindowsRelease(jsonDecode(r.body));
    return latest != null && compareVersions(latest.version, current) > 0 ? latest : null;
  } on Object {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
