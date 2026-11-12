// Punkt sieci mesh urządzenia (kontrakt pkt 9.6): bieżący punkt, przypięty, wynik skanu.

import 'json_utils.dart';

/// Punkt sieci z tą samą nazwą (np. Deco): adres radia, siła sygnału, kanał.
class WifiAp {
  const WifiAp({required this.bssid, required this.rssi, required this.channel});

  final String bssid;
  final int rssi;
  final int channel;

  static List<WifiAp> listFrom(Object? v) => [
    for (final x in (v is List ? v : const []))
      if (x is Map && x['bssid'] is String)
        WifiAp(bssid: (x['bssid'] as String).toUpperCase(), rssi: (x['rssi'] as num?)?.toInt() ?? 0, channel: (x['channel'] as num?)?.toInt() ?? 0),
  ];
}

/// `GET /api/wifi`.
class WifiApStatus {
  const WifiApStatus({
    this.ssid = '',
    this.bssid,
    this.rssi,
    this.channel,
    this.pinned,
    this.mode = 'auto',
    this.scanState = 'none',
    this.scanAgeS = 0,
    this.aps = const [],
  });

  factory WifiApStatus.fromJson(Json j) {
    final scan = j['scan'] is Map ? (j['scan'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    String? mac(Object? v) => v is String && v.isNotEmpty ? v.toUpperCase() : null;
    return WifiApStatus(
      ssid: j['ssid'] is String ? j['ssid'] as String : '',
      bssid: mac(j['bssid']),
      rssi: (j['rssi'] as num?)?.toInt(),
      channel: (j['channel'] as num?)?.toInt(),
      pinned: mac(j['pinned']),
      mode: j['mode'] is String ? j['mode'] as String : 'auto',
      scanState: scan['state'] is String ? scan['state'] as String : 'none',
      scanAgeS: (scan['ageS'] as num?)?.toInt() ?? 0,
      aps: WifiAp.listFrom(scan['aps']),
    );
  }

  final String ssid;
  final String? bssid;
  final int? rssi;
  final int? channel;

  /// Przypięty punkt; null = automatycznie (najsilniejszy).
  final String? pinned;

  /// `auto` | `pinned` | `connecting` | `fallback` (przypięty niedostępny - urządzenie na najsilniejszym).
  final String mode;
  final String scanState;
  final int scanAgeS;
  final List<WifiAp> aps;

  bool get scanning => scanState == 'scanning';
}

/// Siła sygnału słownie (do listy punktów).
String wifiSignalText(int rssi) => switch (rssi) {
  >= -60 => 'bardzo dobry',
  >= -70 => 'dobry',
  >= -80 => 'słaby',
  _ => 'bardzo słaby',
};

/// Odmowa skanu (`409 busy`, pole `reason`) po polsku.
String wifiScanRefusal(String? reason) => switch (reason) {
  'radio' => 'Teraz gra radio - skan przerwałby je na 2-3 s. Wyłącz radio i spróbuj ponownie.',
  'ota' => 'Trwa aktualizacja firmware - spróbuj po jej zakończeniu.',
  'provisioning' => 'Urządzenie jest w trybie konfiguracji sieci.',
  'ethernet' => 'Urządzenie jest podłączone kablem - punkt WiFi nie ma znaczenia.',
  'offline' => 'Urządzenie nie jest teraz połączone z WiFi.',
  _ => 'Urządzenie nie może teraz skanować (${reason ?? 'zajęte'}).',
};
