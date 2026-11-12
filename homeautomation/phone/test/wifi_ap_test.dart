// Punkt sieci mesh (kontrakt pkt 9.6): ekran „Punkt WiFi” (API: wifi_ap_api_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/models/wifi_ap.dart';
import 'package:homeautomation/ui/wifi_ap_screen.dart';

void main() {
  testWidgets('ekran: skan, przypięcie wybranego, automatycznie, podpowiedź Deco, odmowa skanu', (tester) async {
    var pinned = null as String?;
    var scanned = false;
    String? refuse;
    final pins = <String?>[];
    const aps = [
      WifiAp(bssid: 'A8:42:A1:33:3A:F1', rssi: -52, channel: 6),
      WifiAp(bssid: 'A8:42:A1:55:66:71', rssi: -74, channel: 1),
      WifiAp(bssid: 'A8:42:A1:11:22:31', rssi: -93, channel: 11),
    ];
    WifiApStatus status() => WifiApStatus(
      ssid: 'Dom',
      bssid: pinned ?? 'A8:42:A1:11:22:31',
      rssi: pinned == null ? -93 : -52,
      channel: pinned == null ? 11 : 6,
      pinned: pinned,
      mode: pinned == null ? 'auto' : 'pinned',
      scanState: scanned ? 'done' : 'none',
      aps: scanned ? aps : const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WifiApScreen(
          deviceName: 'Zegar',
          load: () async => status(),
          scan: () async {
            if (refuse != null) throw ThermostatException(wifiScanRefusal(refuse));
            scanned = true;
          },
          pin: (b) async {
            pins.add(b);
            pinned = b;
          },
          pollEvery: const Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Automatycznie: urządzenie łączy się z najsilniejszym'), findsOneWidget);
    expect(find.byKey(const Key('wifiAp-A8:42:A1:11:22:31')), findsOneWidget); // bieżący bez skanu
    expect(find.byKey(const Key('wifiApHint')), findsOneWidget);

    await tester.tap(find.byKey(const Key('wifiApScan')));
    await tester.pumpAndSettle();
    expect(find.textContaining('-52 dBm'), findsOneWidget);
    expect(find.textContaining('połączony teraz'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wifiAp-A8:42:A1:33:3A:F1')));
    await tester.pumpAndSettle();
    expect(pins, ['A8:42:A1:33:3A:F1']);
    expect(find.text('Przypięty punkt A8:42:A1:33:3A:F1.'), findsOneWidget);
    expect(find.textContaining('przypięty'), findsWidgets);

    await tester.tap(find.byKey(const Key('wifiApAuto')));
    await tester.pumpAndSettle();
    expect(pins, ['A8:42:A1:33:3A:F1', null]);

    refuse = 'radio';
    await tester.tap(find.byKey(const Key('wifiApScan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wifiApError')), findsOneWidget);
    expect(find.textContaining('gra radio'), findsOneWidget);
  });
}
