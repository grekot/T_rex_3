import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'messages.dart';
import 'security1.dart';

/// Kanał do urządzenia w trybie konfiguracji: zapis do endpointu i odczyt odpowiedzi.
abstract class ProvTransport {
  Future<Uint8List> exchange(String endpoint, Uint8List data);

  Future<void> close();
}

/// Wynik `ha-pair` (kontrakt pkt 9.2, krok 3): urządzenie od razu sparowane.
class HaPairResult {
  const HaPairResult({
    required this.id,
    required this.type,
    required this.token,
    required this.api,
    this.access = 'config',
  });

  final String id;
  final String type;
  final String token;
  final int api;

  /// Poziom tokenu - telefon, który konfiguruje urządzenie, ma `config` (pkt 9.2).
  final String access;

  factory HaPairResult.fromJson(Map<String, dynamic> j) {
    final id = j['id'], token = j['token'];
    if (id is! String || token is! String || token.isEmpty) {
      throw const ProvisioningException('Urządzenie nie zwróciło identyfikatora albo tokenu.');
    }
    return HaPairResult(
      id: id,
      type: j['type'] is String ? j['type'] as String : 'thermostat',
      token: token,
      api: j['api'] is num ? (j['api'] as num).toInt() : 2,
      access: j['access'] is String ? j['access'] as String : 'config',
    );
  }
}

/// Konfiguracja urządzenia przez Bluetooth (kontrakt pkt 9): sesja security 1, `ha-pair`,
/// skan sieci, zapis SSID/hasła, oczekiwanie na połączenie.
class Provisioner {
  Provisioner(this.transport, String pop, {Security1Session? session}) : session = session ?? Security1Session(pop);

  final ProvTransport transport;
  final Security1Session session;

  /// Nawiązuje szyfrowaną sesję; zły PoP kończy się [ProvisioningException].
  Future<void> start() async {
    final r0 = await transport.exchange('prov-session', await session.command0());
    final r1 = await transport.exchange('prov-session', await session.command1(r0));
    session.verify(r1);
  }

  Future<Uint8List> _secure(String endpoint, Uint8List plain) async =>
      session.decrypt(await transport.exchange(endpoint, session.encrypt(plain)));

  /// Własny kanał `ha-pair`: `{"client":…}` → `{"id","type","token","api"}`.
  /// [uid] - konto Firebase właściciela tokenu (pkt 9.2), null bez konta.
  Future<HaPairResult> haPair(String clientName, {String? uid}) async {
    final res = await _secure(
      'ha-pair',
      Uint8List.fromList(utf8.encode(jsonEncode({'client': clientName, 'uid': ?uid}))),
    );
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(res));
    } on FormatException {
      throw const ProvisioningException('Urządzenie zwróciło nieczytelną odpowiedź parowania.');
    }
    if (j is! Map<String, dynamic>) throw const ProvisioningException('Zła odpowiedź parowania.');
    return HaPairResult.fromJson(j);
  }

  /// Sieci widoczne dla urządzenia: bez pustych nazw, każda nazwa raz (najsilniejszy sygnał), od najsilniejszej.
  Future<List<WifiNetwork>> scanWifi({int pageSize = 4}) async {
    decodeScanStartResp(await _secure('prov-scan', encodeScanStart()));
    var status = decodeScanStatusResp(await _secure('prov-scan', encodeScanStatus()));
    for (var i = 0; !status.finished && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = decodeScanStatusResp(await _secure('prov-scan', encodeScanStatus()));
    }
    final all = <WifiNetwork>[];
    for (var start = 0; start < status.count; start += pageSize) {
      final n = status.count - start < pageSize ? status.count - start : pageSize;
      all.addAll(decodeScanResultResp(await _secure('prov-scan', encodeScanResult(start, n))));
    }
    final best = <String, WifiNetwork>{};
    for (final n in all) {
      if (n.ssid.isEmpty) continue;
      final prev = best[n.ssid];
      if (prev == null || n.rssi > prev.rssi) best[n.ssid] = n;
    }
    return best.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  /// Zapisuje sieć i każe urządzeniu się z nią połączyć (`prov-config`: set + apply).
  Future<void> setWifi(String ssid, String passphrase) async {
    decodeSetConfigResp(await _secure('prov-config', encodeSetConfig(ssid, passphrase)));
    decodeApplyConfigResp(await _secure('prov-config', encodeApplyConfig()));
  }

  Future<WifiStatus> wifiStatus() async => decodeGetStatusResp(await _secure('prov-config', encodeGetStatus()));

  /// Czeka, aż urządzenie połączy się z siecią albo zgłosi błąd.
  /// [retries] - ile kolejnych nieudanych odczytów statusu przeczekać (SoftAP: radio urządzenia przechodzi
  /// na kanał sieci domowej i telefon może na chwilę stracić z nim łączność, pkt 9.4).
  Future<WifiStatus> waitForConnection({
    Duration timeout = const Duration(seconds: 45),
    Duration interval = const Duration(milliseconds: 1500),
    int retries = 0,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var failures = 0;
    while (true) {
      final WifiStatus s;
      try {
        s = await wifiStatus();
        failures = 0;
      } on ProvisioningException {
        if (++failures > retries || DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(interval);
        continue;
      }
      if (s.state == WifiStationState.connected) return s;
      if (s.state == WifiStationState.connectionFailed) {
        throw ProvisioningException(switch (s.failReason) {
          WifiFailReason.authError => 'Złe hasło do sieci WiFi.',
          WifiFailReason.networkNotFound => 'Urządzenie nie widzi tej sieci WiFi.',
          null => 'Urządzenie nie połączyło się z siecią WiFi.',
        });
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const ProvisioningException('Urządzenie zbyt długo łączy się z siecią WiFi.');
      }
      await Future<void>.delayed(interval);
    }
  }
}
