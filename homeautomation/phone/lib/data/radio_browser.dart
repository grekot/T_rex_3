// Katalog stacji radio-browser.info (otwarty, bez klucza) dla radia zegara: szukanie stacji po nazwie i logo
// stacji (Config `radio.stations[].logo`, kontrakt pkt 10.2). Wysyłamy tylko nazwę stacji / adres strumienia /
// stronę stacji; User-Agent aplikacji bez danych użytkownika. Bez zewnętrznych usług faviconów.
//
// Logo: kandydaci z kilku źródeł (favicony z katalogu - bywają martwe, strona stacji: <link rel=icon|apple-touch-icon>,
// og:image, /apple-touch-icon.png i /favicon.ico domeny), każdy sprawdzony GET-em: 200, image/png albo image/jpeg,
// do 64 KB, nagłówek PNG albo JPEG baseline do 1024 px - tylko takie zegar zdekoduje (src/RadioLogo.cpp).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const radioBrowserUserAgent = 'HomeAutomation-app/1.26 (radio-browser client)';
const radioLogoMaxBytes = 64 * 1024;
const _radioLogoMaxPx = 1024;

/// Serwery katalogu: nazwa zbiorcza (DNS na wszystkie), potem stałe zapasowe.
const radioBrowserHosts = ['all.api.radio-browser.info', 'de1.api.radio-browser.info', 'de2.api.radio-browser.info'];

/// Stacja z katalogu.
class RbStation {
  const RbStation({
    required this.name,
    required this.url,
    this.country = '',
    this.countryCode = '',
    this.codec = '',
    this.bitrate = 0,
    this.homepage = '',
    this.favicon = '',
  });

  factory RbStation.fromJson(Map j) {
    String str(String k) => j[k] is String ? (j[k] as String).trim() : '';
    final resolved = str('url_resolved');
    return RbStation(
      name: str('name'),
      url: resolved.isNotEmpty ? resolved : str('url'),
      country: str('country'),
      countryCode: str('countrycode'),
      codec: str('codec'),
      bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
      homepage: str('homepage'),
      favicon: str('favicon'),
    );
  }

  final String name, url, country, countryCode, codec, homepage, favicon;
  final int bitrate;

  /// Zegar gra tylko MP3 (minimp3; AAC bez dekodera z licencją zgodną z repo).
  bool get mp3 => codec.toUpperCase() == 'MP3';
}

enum LogoFormat { png, jpeg }

/// Sprawdzony obraz, który zegar zdekoduje.
class LogoCandidate {
  const LogoCandidate({
    required this.url,
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
  });

  final String url;
  final Uint8List bytes;
  final LogoFormat format;
  final int width, height;

  /// „PNG 114×114 · 12 KB · rmf.fm”.
  String get label =>
      '${format == LogoFormat.png ? 'PNG' : 'JPG'} $width×$height · ${(bytes.length / 1024).ceil()} KB · '
      '${Uri.tryParse(url)?.host ?? url}';

  // Kolejność na liście: kwadratowe, potem większe (do 512 px - zegar i tak zmniejsza do 76 px)
  int get _score {
    final side = width < height ? width : height;
    final square = (width - height).abs() <= side ~/ 10 ? 1000 : 0;
    return square + (side > 512 ? 512 : side);
  }
}

/// Wynik sprawdzenia adresu obrazka: [logo] albo przyczyna po polsku.
class LogoCheck {
  const LogoCheck.ok(LogoCandidate this.logo) : error = null;
  const LogoCheck.failed(String this.error) : logo = null;

  final LogoCandidate? logo;
  final String? error;
}

class RadioBrowser {
  RadioBrowser({http.Client? client, this.timeout = const Duration(seconds: 8)})
    : _client = client ?? http.Client(),
      _own = client == null;

  final http.Client _client;
  final bool _own;
  final Duration timeout;

  void close() {
    if (_own) _client.close();
  }

  Map<String, String> get _headers => const {'User-Agent': radioBrowserUserAgent};

  /// Stacje po nazwie (do [limit], działające, od najpopularniejszych). Brak sieci / katalogu = pusta lista.
  Future<List<RbStation>> search(String name, {int limit = 30}) async {
    final q = name.trim();
    if (q.isEmpty) return const [];
    final j = await _api('/json/stations/search', {
      'name': q,
      'limit': '$limit',
      'hidebroken': 'true',
      'order': 'votes',
      'reverse': 'true',
    });
    return [
      for (final x in j)
        if (RbStation.fromJson(x) case final s when s.name.isNotEmpty && s.url.startsWith('http')) s,
    ];
  }

  /// Działające logo stacji (sprawdzone, najlepsze pierwsze); pusta lista = nic, co zegar pokaże.
  Future<List<LogoCandidate>> findLogos({
    required String name,
    required String streamUrl,
    String homepage = '',
    String favicon = '',
  }) async {
    final favicons = <String>[if (favicon.isNotEmpty) favicon];
    final homepages = <String>[if (homepage.isNotEmpty) homepage];
    // Wpisy tej stacji w katalogu: po adresie strumienia i po nazwie (bywa kilka, z różnymi faviconami)
    final byUrl = streamUrl.isEmpty ? const <Map>[] : await _api('/json/stations/byurl', {'url': streamUrl});
    final byName = name.trim().isEmpty
        ? const <Map>[]
        : await _api('/json/stations/search', {'name': name.trim(), 'limit': '10', 'order': 'votes', 'reverse': 'true'});
    for (final s in [...byUrl, ...byName].map(RbStation.fromJson)) {
      if (s.favicon.isNotEmpty) favicons.add(s.favicon);
      if (s.homepage.isNotEmpty) homepages.add(s.homepage);
    }
    final urls = <String>[...favicons];
    // Strony stacji: ikony z <head> i og:image, potem stałe adresy domeny
    for (final page in _unique(homepages).take(3)) {
      urls.addAll(await _iconsFromPage(page));
    }
    for (final base in _unique([...homepages, ...favicons])) {
      final u = Uri.tryParse(base);
      if (u == null || !u.hasScheme || u.host.isEmpty) continue;
      final origin = '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
      urls.addAll(['$origin/apple-touch-icon.png', '$origin/apple-touch-icon-precomposed.png', '$origin/favicon.ico']);
    }
    final candidates = _unique(urls.where((u) => u.startsWith('http://') || u.startsWith('https://'))).take(20).toList();
    final checks = await Future.wait(candidates.map(check));
    final ok = <LogoCandidate>[];
    final seen = <String>{};
    for (final c in checks) {
      final l = c.logo;
      if (l == null) continue;
      final key = '${l.bytes.length}:${base64Encode(l.bytes.sublist(0, l.bytes.length < 256 ? l.bytes.length : 256))}';
      if (seen.add(key)) ok.add(l); // ten sam obraz pod kilkoma adresami - raz
    }
    ok.sort((a, b) => b._score.compareTo(a._score));
    return ok;
  }

  /// Sprawdzenie adresu obrazka tak, jak zrobi to zegar (także adresu wpisanego ręcznie).
  Future<LogoCheck> check(String url) async {
    final Uri u;
    try {
      u = Uri.parse(url);
    } on FormatException {
      return const LogoCheck.failed('zły adres');
    }
    final http.Response r;
    try {
      r = await _client.get(u, headers: _headers).timeout(timeout);
    } catch (_) {
      return const LogoCheck.failed('serwer nie odpowiada');
    }
    if (r.statusCode != 200) return LogoCheck.failed('HTTP ${r.statusCode}');
    final type = (r.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
    final b = r.bodyBytes;
    if (b.isEmpty) return const LogoCheck.failed('pusty plik');
    if (type.contains('svg') || type.contains('icon') || type.contains('webp') || type.contains('gif')) {
      return LogoCheck.failed('format ${type.replaceFirst('image/', '').toUpperCase()} - zegar czyta tylko PNG i JPG');
    }
    if (type != 'image/png' && type != 'image/jpeg' && type != 'image/jpg') {
      return LogoCheck.failed(type.startsWith('text/') ? 'to nie obrazek (strona $type)' : 'typ ${type.isEmpty ? 'nieznany' : type}');
    }
    if (b.length > radioLogoMaxBytes) return LogoCheck.failed('za duży plik (${(b.length / 1024).ceil()} KB, zegar: do 64 KB)');
    final h = probeImage(b);
    if (h == null) return const LogoCheck.failed('plik nie jest PNG ani JPG baseline (np. JPG progresywny)');
    final (fmt, w, hh) = h;
    if (w <= 0 || hh <= 0 || w > _radioLogoMaxPx || hh > _radioLogoMaxPx) {
      return LogoCheck.failed('wymiary $w×$hh (zegar: do 1024 px)');
    }
    return LogoCheck.ok(LogoCandidate(url: url, bytes: b, format: fmt, width: w, height: hh));
  }

  Future<List<String>> _iconsFromPage(String page) async {
    final Uri base;
    try {
      base = Uri.parse(page);
    } on FormatException {
      return const [];
    }
    if (!base.hasScheme || base.host.isEmpty) return const [];
    try {
      final r = await _client.get(base, headers: _headers).timeout(timeout);
      if (r.statusCode != 200) return const [];
      final html = utf8.decode(r.bodyBytes.length > 512 * 1024 ? r.bodyBytes.sublist(0, 512 * 1024) : r.bodyBytes, allowMalformed: true);
      return [for (final href in pageIconLinks(html)) base.resolve(href).toString()];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map>> _api(String path, Map<String, String> q) async {
    for (final h in radioBrowserHosts) {
      try {
        final r = await _client.get(Uri.https(h, path, q), headers: _headers).timeout(timeout);
        if (r.statusCode != 200) continue;
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is List) return [for (final x in j) if (x is Map) x];
      } catch (_) {
        // następny serwer
      }
    }
    return const [];
  }
}

Iterable<String> _unique(Iterable<String> v) {
  final seen = <String>{};
  return v.where((x) => x.isNotEmpty && seen.add(x));
}

/// Adresy ikon z HTML strony: <link rel="apple-touch-icon|icon|shortcut icon" href> (najpierw apple-touch-icon -
/// zwykle większe i PNG) i <meta property="og:image" content>.
List<String> pageIconLinks(String html) {
  String? attr(String tag, String name) {
    final m = RegExp('$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false).firstMatch(tag);
    return m == null ? null : (m.group(2) ?? m.group(3) ?? m.group(4));
  }

  final apple = <String>[], icons = <String>[], og = <String>[];
  for (final m in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(html)) {
    final tag = m.group(0)!;
    final rel = attr(tag, 'rel')?.toLowerCase() ?? '';
    final href = attr(tag, 'href');
    if (href == null || href.isEmpty) continue;
    if (rel.contains('apple-touch-icon')) {
      apple.add(href);
    } else if (rel.split(RegExp(r'\s+')).contains('icon')) {
      icons.add(href);
    }
  }
  for (final m in RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(html)) {
    final tag = m.group(0)!;
    final p = (attr(tag, 'property') ?? attr(tag, 'name') ?? '').toLowerCase();
    final c = attr(tag, 'content');
    if (p == 'og:image' && c != null && c.isNotEmpty) og.add(c);
  }
  return [...apple, ...icons, ...og].map((h) => h.replaceAll('&amp;', '&')).toList();
}

/// Nagłówek obrazu: PNG (IHDR) albo JPEG baseline (SOF0/SOF1) jak w zegarze; null = inny format.
(LogoFormat, int, int)? probeImage(Uint8List d) {
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (d.length > 24 && List.generate(8, (i) => d[i]).join(',') == png.join(',')) {
    int be32(int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
    return (LogoFormat.png, be32(16), be32(20));
  }
  if (d.length > 4 && d[0] == 0xFF && d[1] == 0xD8) {
    var i = 2;
    while (i + 9 < d.length) {
      if (d[i] != 0xFF) return null;
      final m = d[i + 1];
      if (m == 0xD8 || (m >= 0xD0 && m <= 0xD7) || m == 0x01 || m == 0xFF) {
        i += m == 0xFF ? 1 : 2;
        continue;
      }
      final len = (d[i + 2] << 8) | d[i + 3];
      if (m == 0xC0 || m == 0xC1) return (LogoFormat.jpeg, (d[i + 7] << 8) | d[i + 8], (d[i + 5] << 8) | d[i + 6]);
      if (m >= 0xC2 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) return null; // progresywny, arytmetyczny
      i += 2 + len;
    }
  }
  return null;
}
