import 'dart:convert';

import 'ble_transport.dart' show provNamePrefix;

/// Kod QR z naklejki urządzenia w formacie Espressif (kontrakt pkt 9.1):
/// `{"ver":"v1","name":"HA_hub-51e96c","pop":"9c86b317","transport":"ble","security":1}`.
/// `transport: softap` = urządzenie bez Bluetooth (pkt 9.4): `name` to SSID, `pop` hasło WPA2.
class ProvQr {
  const ProvQr({required this.name, required this.pop, this.softAp = false});

  /// Nazwa rozgłaszana (BLE) albo SSID (SoftAP), np. `HA_hub-51e96c`.
  final String name;
  final String pop;
  final bool softAp;

  /// `hub-51e96c`.
  String get id => name.startsWith(provNamePrefix) ? name.substring(provNamePrefix.length) : name;

  /// Rzuca [FormatException] z komunikatem po polsku. Nieznane pola ignoruje.
  static ProvQr parse(String raw) {
    final Object? j;
    try {
      j = jsonDecode(raw.trim());
    } on FormatException {
      throw const FormatException('To nie jest kod urządzenia HomeAutomation.');
    }
    if (j is! Map) throw const FormatException('To nie jest kod urządzenia HomeAutomation.');
    if (j['ver'] != 'v1') throw const FormatException('Nieobsługiwany kod QR (inna wersja formatu).');
    final name = j['name'], pop = j['pop'], transport = j['transport'] ?? 'ble';
    if (name is! String || name.isEmpty || pop is! String || pop.isEmpty) {
      throw const FormatException('Kod QR nie ma nazwy urządzenia albo kodu PoP.');
    }
    if (transport != 'ble' && transport != 'softap') {
      throw const FormatException('Nieobsługiwany kod QR (nieznany sposób połączenia).');
    }
    return ProvQr(name: name, pop: pop, softAp: transport == 'softap');
  }
}
