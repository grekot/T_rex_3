import 'dart:convert';

import 'package:http/http.dart' as http;

/// Szukanie logo stacji radia (przycisk „Znajdź logo”, Config `radio.stations[].logo`) w otwartym katalogu
/// radio-browser.info: najpierw po adresie strumienia, potem po nazwie. Wysyła tylko adres strumienia albo nazwę
/// stacji. Zwraca adresy `favicon` bez powtórzeń - najpierw PNG / JPG (te zegar dekoduje), potem pozostałe.
/// Brak sieci albo katalogu = pusta lista.
Future<List<String>> findStationLogos({required String name, required String streamUrl, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final byUrl = await _query(c, '/json/stations/byurl', {'url': streamUrl});
    final found = byUrl.isNotEmpty
        ? byUrl
        : await _query(c, '/json/stations/search', {'name': name, 'limit': '20', 'hidebroken': 'true', 'order': 'votes', 'reverse': 'true'});
    final logos = <String>[];
    for (final s in found) {
      final f = s['favicon'];
      if (f is String && (f.startsWith('https://') || f.startsWith('http://')) && !logos.contains(f)) logos.add(f);
    }
    bool decodable(String u) => RegExp(r'\.(png|jpe?g)$').hasMatch(Uri.tryParse(u)?.path.toLowerCase() ?? '');
    return [...logos.where(decodable), ...logos.where((u) => !decodable(u))];
  } finally {
    if (client == null) c.close();
  }
}

// Serwery katalogu: nazwa zbiorcza (DNS na wszystkie), potem dwa stałe
const _hosts = ['all.api.radio-browser.info', 'de1.api.radio-browser.info', 'de2.api.radio-browser.info'];

Future<List<Map>> _query(http.Client c, String path, Map<String, String> q) async {
  for (final h in _hosts) {
    try {
      final res = await c
          .get(Uri.https(h, path, q), headers: {'User-Agent': 'HomeAutomation-app/1.0'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) continue;
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is List) return [for (final x in j) if (x is Map) x];
    } catch (_) {
      // następny serwer
    }
  }
  return const [];
}
