import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/clock.dart';

/// Indeks paczek motywów zegara (pkt 10.2 „Paczki motywów”) z `https://ha-firmware.web.app/themes/index.json`.
/// Brak indeksu (jeszcze nie opublikowany), brak sieci albo zły plik = wyjątek; ekran pokazuje wtedy tylko
/// zainstalowane paczki.
Future<List<ClockThemePack>> loadThemePackIndex({http.Client? client, Uri? url}) async {
  final c = client ?? http.Client();
  try {
    final u = url ?? Uri.parse(clockThemeIndexUrl);
    final res = await c.get(u).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', u);
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map || j['packs'] is! List) throw const FormatException('Indeks bez listy packs');
    return [
      for (final p in ClockThemePack.listFrom(j['packs']))
        if (p.url != null && p.sha256 != null) p,
    ];
  } finally {
    if (client == null) c.close();
  }
}
