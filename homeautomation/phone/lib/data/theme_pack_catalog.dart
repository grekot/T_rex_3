import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/clock.dart';

/// Indeks paczek motywów zegara (pkt 10.2 „Paczki motywów”) z `https://ha-firmware.web.app/themes/index.json`.
/// Brak indeksu (jeszcze nie opublikowany), brak sieci albo zły plik = wyjątek; ekran pokazuje wtedy tylko
/// zainstalowane paczki.
Future<List<ClockPack>> loadThemePackIndex({http.Client? client}) => _loadIndex(Uri.parse(clockThemeIndexUrl), client);

/// Indeks paczek treści (ciekawostki, pkt 10.2 „Dymki i ciekawostki”) z `.../content/index.json`.
Future<List<ClockPack>> loadContentPackIndex({http.Client? client}) =>
    _loadIndex(Uri.parse(clockContentIndexUrl), client);

Future<List<ClockPack>> _loadIndex(Uri u, http.Client? client) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(u).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', u);
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map || j['packs'] is! List) throw const FormatException('Indeks bez listy packs');
    return [
      for (final p in ClockPack.listFrom(j['packs']))
        if (p.url != null && p.sha256 != null) p,
    ];
  } finally {
    if (client == null) c.close();
  }
}
