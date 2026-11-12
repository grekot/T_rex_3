// Punkt sieci mesh (kontrakt pkt 9.6): API lokalne na atrapie zegara (prawdziwe HTTP, bez testów widżetów -
// te podmieniają klienta HTTP).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';

import '../tool/fake/fake_thermostat_server.dart';

void main() {
  test('API: stan, skan, przypięcie, odmowa przy radiu, urządzenie bez funkcji', () async {
    final clock = FakeClock();
    await clock.start(port: 0, address: InternetAddress.loopbackIPv4);
    final api = LocalApi(LocalEndpoint('127.0.0.1', clock.port), token: clock.token);
    try {
      var st = (await api.wifiAp())!;
      expect((st.ssid, st.bssid, st.rssi, st.channel, st.pinned, st.mode), ('Dom', 'A8:42:A1:11:22:31', -93, 11, null, 'auto'));
      expect(st.aps, isEmpty);

      await api.wifiScan();
      st = (await api.wifiAp())!;
      expect(st.scanState, 'done');
      expect([for (final a in st.aps) a.rssi], [-52, -74, -93]);

      await api.wifiPin('a8-42-a1-33-3a-f1');
      st = (await api.wifiAp())!;
      expect((st.pinned, st.bssid, st.mode), ('A8:42:A1:33:3A:F1', 'A8:42:A1:33:3A:F1', 'pinned'));
      await expectLater(
        api.wifiPin('A8:42:A1'),
        throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('Nieprawidłowy adres'))),
      );
      await api.wifiPin(null);
      expect((await api.wifiAp())!.mode, 'auto');

      clock.wifiBusyReason = 'radio';
      await expectLater(
        api.wifiScan(),
        throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('gra radio'))),
      );
    } finally {
      api.close();
      await clock.stop();
    }

    final old = FakeThermostat(simulate: false);
    await old.start(port: 0, address: InternetAddress.loopbackIPv4);
    final api2 = LocalApi(LocalEndpoint('127.0.0.1', old.port), token: old.token);
    try {
      expect(await api2.wifiAp(), isNull);
    } finally {
      api2.close();
      await old.stop();
    }
  });
}
