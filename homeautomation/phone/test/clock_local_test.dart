// Atrapa zegara `clock` przez HTTP (pkt 10.2): /api/info bez chmury, State z komfortem, błędy Set jak w kontrakcie.
// Osobny plik - testy widżetów podmieniają klienta HTTP.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/models/device_type.dart';

import '../tool/fake/fake_thermostat_server.dart';

void main() {
  group('atrapa zegara przez HTTP', () {
    late FakeClock fake;
    late LocalApi api;
    setUp(() async {
      fake = FakeClock();
      await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
      api = LocalApi(LocalEndpoint('127.0.0.1', fake.port), token: fake.token);
    });
    tearDown(() => fake.stop());

    test('info bez chmury, State z komfortem, błędy Set: noc bez czujnika światła, nieznana strona, limity', () async {
      final info = await api.info();
      expect(info.type, DeviceType.clock);
      final s = await api.stateJson();
      expect((s['temp'], s['comfort'], (s['outdoor'] as Map)['icon']), (21.4, 'komfort', 2));
      expect(
        (await api.setJson({
          'night': {'mode': 'lux'},
        })).errors,
        {'night.mode': 'value'},
      );
      expect(
        (await api.setJson({
          'screens': {
            'list': ['main', 'page:x'],
          },
        })).errors,
        {'screens.list': 'value'},
      );
      expect(
        (await api.setJson({
          'night': {'window': '23-6'},
        })).errors,
        {'night.window': 'format'},
      );
      final big = [
        for (var i = 0; i < 5; i++) {'id': 'p$i', 'title': 'S', 'widgets': []},
      ];
      expect((await api.setJson({'pages': big})).errors, {'pages': 'too_many'});
      final ok = await api.setJson({
        'pages': [
          {
            'id': 'p1',
            'title': 'Dom',
            'widgets': [
              {'id': 'w1', 'view': 'value', 'device': 'a', 'point': 'temp'},
            ],
          },
        ],
        'screens': {
          'list': ['main', 'page:p1'],
        },
        'showScreen': 'page:p1',
      });
      expect(ok.errors, isEmpty);
      expect((fake.screen, fake.wantsVer), ('page:p1', 2));
    });
  });
}
