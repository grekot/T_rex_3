// Powiadomienia ntfy (pkt 3d) na atrapie urządzenia - prawdziwe gniazda, więc bez testWidgets
// (ekran: notify_test.dart).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/models/notify.dart';

import '../tool/fake/fake_thermostat_server.dart';

void main() {
  group('atrapa urządzenia (prawdziwe gniazda)', () {
    late FakeLight fake;
    late LocalEndpoint endpoint;

    setUp(() async {
      fake = FakeLight(id: 'swiatlo-1', name: 'Lampa');
      await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
      endpoint = LocalEndpoint('127.0.0.1', fake.port);
    });

    tearDown(() => fake.stop());

    test('Config notify, włączenie, próbne, nowy temat, błędy pól, poziom config', () async {
      final api = LocalApi(endpoint, token: fake.token);
      var c = NotifyConfig.fromConfig(await api.configJson())!;
      expect((c.enabled, c.server, c.topic.startsWith('ha-'), c.topic.length), (false, 'https://ntfy.sh', true, 19));

      var r = await api.setJson(const NotifySet(enabled: true, test: true).toJson());
      expect(r.errors, isEmpty);
      expect((fake.notifyEnabled, fake.notifyTests), (true, 1));

      final old = c.topic;
      r = await api.setJson(const NotifySet(topic: '', token: 'tk_abc').toJson());
      c = NotifyConfig.fromConfig(await api.configJson())!;
      expect((c.topic == old, c.tokenSet), (false, true));
      expect((await api.configJson())['notify'].containsKey('ntfyToken'), isFalse, reason: 'token nie wraca');

      r = await api.setJson({
        'notify': {'ntfyTopic': 'zły temat', 'ntfyServer': 'http://x', 'ntfyToken': 'x' * 129},
      });
      expect(r.errors, {'notify.ntfyTopic': 'format', 'notify.ntfyServer': 'format', 'notify.ntfyToken': 'length'});

      final guest = LocalApi(endpoint, token: fake.addPhone('Gość', access: 'control'));
      r = await guest.setJson(const NotifySet(enabled: false).toJson());
      expect(r.errors, {'notify': 'forbidden'});
      expect(fake.notifyEnabled, isTrue);
    });
  });
}
