import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'messages.dart';
import 'provisioner.dart';

/// Adres urządzenia w jego sieci konfiguracyjnej (kontrakt pkt 9.4).
final softApBase = Uri.parse('http://192.168.4.1');

/// Łączenie telefonu z siecią WiFi urządzenia `HA_<id>` (WPA2, hasło = PoP).
abstract class ApJoiner {
  bool get supported;

  /// [ssid] znany (zmiana sieci znanego urządzenia) albo `null` - telefon proponuje sieci `HA_*`.
  /// Rzuca [ProvisioningException], gdy się nie uda (złe PoP = telefon nie połączy się z siecią).
  Future<void> join({String? ssid, required String passphrase});

  /// Zwalnia sieć urządzenia - telefon wraca do sieci domowej.
  Future<void> release();
}

/// Android 10+: `WifiNetworkSpecifier` + `requestNetwork` + `bindProcessToNetwork`;
/// iOS: `NEHotspotConfiguration` (kod natywny w `MainActivity.kt` / `AppDelegate.swift`).
class PlatformApJoiner implements ApJoiner {
  static const _channel = MethodChannel('pl.grekot.homeautomation/wifi');

  @override
  bool get supported => true;

  @override
  Future<void> join({String? ssid, required String passphrase}) async {
    try {
      await _channel.invokeMethod<void>('joinAp', {'ssid': ssid, 'prefix': 'HA_', 'passphrase': passphrase});
    } on PlatformException catch (e) {
      throw ProvisioningException(switch (e.code) {
        'unavailable' => 'Telefon nie połączył się z siecią urządzenia. Sprawdź kod z naklejki i czy urządzenie '
            'jest w trybie konfiguracji (przycisk 3 s).',
        'unsupported' => 'Ten telefon nie łączy się sam z siecią urządzenia (Android 10+ albo iOS 13+). '
            'Połącz się ręcznie z siecią HA_… w ustawieniach WiFi i wybierz „Jestem już połączony”.',
        'cancelled' => 'Anulowano wybór sieci.',
        _ => 'Nie udało się połączyć z siecią urządzenia: ${e.message ?? e.code}',
      });
    } on MissingPluginException {
      throw const ProvisioningException('Łączenie z siecią urządzenia działa tylko w aplikacji na telefonie.');
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('releaseAp');
    } on Object {
      // Telefon i tak wróci do sieci domowej po wyłączeniu sieci urządzenia.
    }
  }
}

/// Telefon jest już ręcznie połączony z siecią urządzenia - nic do zrobienia.
class ManualApJoiner implements ApJoiner {
  const ManualApJoiner();

  @override
  bool get supported => true;

  @override
  Future<void> join({String? ssid, required String passphrase}) async {}

  @override
  Future<void> release() async {}
}

/// Transport provisioningu przez HTTP w sieci urządzenia (`wifi_prov_scheme_softap`, pkt 9.4):
/// `POST http://192.168.4.1/<endpoint>` z tymi samymi bajtami protobuf co przy BLE. Sesję security 1
/// urządzenie trzyma po ciasteczku `session=` z pierwszej odpowiedzi.
class SoftApTransport implements ProvTransport {
  SoftApTransport({Uri? base, http.Client? client, this.joiner, this.timeout = const Duration(seconds: 8)})
    : base = base ?? softApBase,
      _client = client ?? http.Client();

  final Uri base;
  final http.Client _client;
  final ApJoiner? joiner;
  final Duration timeout;
  String? _cookie;

  @override
  Future<Uint8List> exchange(String endpoint, Uint8List data) async {
    final req = http.Request('POST', base.resolve('/$endpoint'))
      ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
      ..headers['Accept'] = 'text/plain'
      ..bodyBytes = data;
    final cookie = _cookie;
    if (cookie != null) req.headers['Cookie'] = cookie;
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw const ProvisioningException('Urządzenie nie odpowiada w swojej sieci WiFi.');
    } on http.ClientException catch (e) {
      throw ProvisioningException('Brak połączenia z urządzeniem w jego sieci WiFi (${e.message}).');
    }
    final setCookie = res.headers['set-cookie'];
    if (setCookie != null) {
      final m = RegExp(r'session=([^;,\s]+)').firstMatch(setCookie);
      if (m != null) _cookie = 'session=${m.group(1)}';
    }
    if (res.statusCode != 200) {
      throw ProvisioningException('Urządzenie odrzuciło żądanie $endpoint (HTTP ${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  @override
  Future<void> close() async {
    _client.close();
    await joiner?.release();
  }
}

/// Konfiguracja urządzeń bez Bluetooth: łączy telefon z `HA_*` i zwraca transport HTTP.
class SoftApProvisioning {
  SoftApProvisioning({ApJoiner? joiner, this.base, this.clientFactory}) : joiner = joiner ?? PlatformApJoiner();

  final ApJoiner joiner;
  final Uri? base;

  /// Do testów.
  final http.Client Function()? clientFactory;

  /// [manual] - użytkownik połączył się z siecią sam (w ustawieniach WiFi).
  Future<ProvTransport> connect({required String pop, String? deviceId, bool manual = false}) async {
    final j = manual ? const ManualApJoiner() : joiner;
    await j.join(ssid: deviceId == null ? null : 'HA_$deviceId', passphrase: pop);
    return SoftApTransport(base: base, client: clientFactory?.call(), joiner: j);
  }
}
