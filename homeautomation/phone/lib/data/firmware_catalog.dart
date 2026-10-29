import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/firmware.dart';
import '../models/json_utils.dart';
import 'dashboard_store.dart';
import 'errors.dart';

/// Manifest wydań (pkt 3e) z `https://ha-firmware.web.app/manifest.json`; ostatni pobrany zostaje w telefonie
/// (pokazywany bez internetu, z datą pobrania).
class FirmwareCatalog {
  FirmwareCatalog({http.Client? client, TextCache? cache, Uri? url, DateTime Function()? clock})
    : _client = client ?? http.Client(),
      _cacheOverride = cache,
      url = url ?? Uri.parse(firmwareManifestUrl),
      _clock = clock ?? DateTime.now;

  final http.Client _client;
  final TextCache? _cacheOverride;
  late final TextCache _cache = _cacheOverride ?? PrefsTextCache();
  final Uri url;
  final DateTime Function() _clock;

  static const _key = 'fw_manifest';

  /// Kiedy pobrano [load] z sieci (null = z kopii albo jeszcze nie).
  DateTime? fetchedAt;

  /// Manifest z sieci; bez sieci - ostatnia kopia, a bez kopii wyjątek.
  Future<FirmwareManifest> load() async {
    try {
      final res = await _client.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', url);
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map) throw const FormatException('Manifest nie jest obiektem');
      final m = FirmwareManifest.fromJson(j.cast<String, dynamic>());
      fetchedAt = _clock();
      try {
        await _cache.set(_key, jsonEncode({'at': fetchedAt!.millisecondsSinceEpoch, 'manifest': j}));
      } on Object {
        // kopia tylko na czas bez internetu
      }
      return m;
    } on Object catch (e) {
      final cached = await _cached();
      if (cached != null) return cached;
      throw ThermostatException('Nie udało się pobrać listy wydań firmware ($e).');
    }
  }

  Future<FirmwareManifest?> _cached() async {
    try {
      final raw = await _cache.get(_key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      fetchedAt = DateTime.fromMillisecondsSinceEpoch(asInt(j['at'], 'at'));
      return FirmwareManifest.fromJson((j['manifest'] as Map).cast<String, dynamic>());
    } on Object {
      return null;
    }
  }
}
