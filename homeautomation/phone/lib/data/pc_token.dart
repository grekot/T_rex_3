import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/home.dart';
import 'device_store.dart';
import 'errors.dart';
import 'local_api.dart';
import 'local_endpoint.dart';

/// Kod QR komputera (kontrakt pkt 2a): `{"ver":"v1","kind":"pc-token","url","secret","name"}`.
class PcTokenQr {
  const PcTokenQr({required this.url, required this.secret, required this.name});

  final Uri url;
  final String secret;

  /// Nazwa komputera - token u urządzenia dostaje nazwę „komputer `name`”.
  final String name;

  /// Rzuca [FormatException] z komunikatem po polsku. Adres musi być w sieci lokalnej - tokeny nie wychodzą z domu.
  static PcTokenQr parse(String raw) {
    final Object? j;
    try {
      j = jsonDecode(raw.trim());
    } on FormatException {
      throw const FormatException('To nie jest kod komputera (pair_pc.py).');
    }
    if (j is! Map || j['kind'] != 'pc-token') throw const FormatException('To nie ten kod - zeskanuj kod z komputera.');
    if (j['ver'] != 'v1') throw const FormatException('Nieobsługiwany kod QR (inna wersja formatu).');
    final url = Uri.tryParse(j['url'] is String ? j['url'] as String : '');
    final secret = j['secret'], name = j['name'];
    if (url == null || url.scheme != 'http' || secret is! String || secret.isEmpty) {
      throw const FormatException('Kod komputera nie ma adresu albo sekretu.');
    }
    if (!isLocalNetworkHost(url.host)) {
      throw const FormatException('Adres komputera nie jest w sieci domowej - tokenów tam nie wysyłam.');
    }
    return PcTokenQr(url: url, secret: secret, name: name is String && name.isNotEmpty ? name : 'PC');
  }
}

/// Wynik: id zapisane przez komputer i błędy urządzeń, dla których nie udało się wystawić tokenu.
typedef PcTokenResult = ({List<String> saved, Map<String, String> failed});

/// Dla każdego urządzenia nowy token `config` (`POST /api/clients {"name":"komputer <name>"}`), potem jedno
/// `POST <url>` z sekretem i listą `{"id","type","name","host","token"}` (pkt 2a).
Future<PcTokenResult> sendTokensToPc(
  PcTokenQr qr,
  List<PairedDevice> devices,
  Future<String?> Function(String deviceId) phoneToken, {
  http.Client? client,
}) async {
  final entries = <Map<String, Object?>>[];
  final failed = <String, String>{};
  for (final d in devices) {
    final endpoint = d.lastEndpoint;
    final token = await phoneToken(d.id);
    if (endpoint == null || token == null) {
      failed[d.id] = 'brak adresu albo parowania';
      continue;
    }
    try {
      final t = await LocalApi(endpoint, token: token, client: client).createClient('komputer ${qr.name}', AccessLevel.config);
      entries.add({'id': d.id, 'type': d.type.wire, 'name': d.name, 'host': endpoint.host, 'token': t.token});
    } on ThermostatException catch (e) {
      failed[d.id] = e.message;
    }
  }
  if (entries.isEmpty) return (saved: const <String>[], failed: failed);

  final c = client ?? http.Client();
  final http.Response res;
  try {
    res = await c
        .post(
          qr.url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'secret': qr.secret, 'devices': entries}),
        )
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    throw const ThermostatException('Komputer nie odpowiada - czy pair_pc.py dalej działa i jest w tej samej sieci?');
  } on http.ClientException catch (e) {
    throw ThermostatException('Brak połączenia z komputerem (${e.message}).');
  } finally {
    if (client == null) c.close();
  }
  switch (res.statusCode) {
    case 200:
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final saved = j is Map && j['saved'] is List ? [for (final x in j['saved'] as List) '$x'] : <String>[];
      return (saved: saved, failed: failed);
    case 403:
      throw const ThermostatException('Komputer odrzucił kod - zeskanuj go jeszcze raz.');
    case 410:
      throw const ThermostatException('Kod na komputerze wygasł (5 min) - uruchom pair_pc.py jeszcze raz.');
    default:
      throw ThermostatException('Komputer zwrócił błąd HTTP ${res.statusCode}.');
  }
}
