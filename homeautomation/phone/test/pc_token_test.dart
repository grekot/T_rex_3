// „Wyślij token do komputera” (pkt 2a): kod QR komputera, token `config` od każdego urządzenia, jedno POST
// na komputer (atrapa pair_pc.py). Prawdziwe gniazda - bez testWidgets.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/pc_token.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../tool/fake/fake_thermostat_server.dart';

void main() {
  test('kod QR komputera: kind pc-token, adres w sieci domowej', () {
    final qr = PcTokenQr.parse(
      '{"ver":"v1","kind":"pc-token","url":"http://192.168.68.116:52017/token","secret":"0123456789abcdef","name":"LAPTOP"}',
    );
    expect((qr.url.port, qr.secret, qr.name), (52017, '0123456789abcdef', 'LAPTOP'));
    expect(
      () => PcTokenQr.parse('{"ver":"v1","name":"HA_hub-51e96c","pop":"9c86b317"}'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('nie ten kod'))),
    );
    expect(
      () => PcTokenQr.parse('{"ver":"v1","kind":"pc-token","url":"http://8.8.8.8:1/token","secret":"x"}'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('sieci domowej'))),
    );
  });

  test('wysyłka: token „komputer <nazwa>” od każdego urządzenia, jedno POST z sekretem; 403 i 410', () async {
    final hub = FakeHub();
    final light = FakeLight(channels: 4);
    await hub.start(port: 0, address: InternetAddress.loopbackIPv4);
    await light.start(port: 0, address: InternetAddress.loopbackIPv4);
    addTearDown(hub.stop);
    addTearDown(light.stop);

    var status = 200;
    Map<String, dynamic>? received;
    final pc = await shelf_io.serve((Request req) async {
      received = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      if (status != 200) return Response(status);
      final ids = [for (final d in received!['devices'] as List) (d as Map)['id']];
      return Response.ok(jsonEncode({'ok': true, 'saved': ids}), headers: {'Content-Type': 'application/json'});
    }, InternetAddress.loopbackIPv4, 0);
    addTearDown(() => pc.close(force: true));

    final qr = PcTokenQr.parse(
      jsonEncode({'ver': 'v1', 'kind': 'pc-token', 'url': 'http://127.0.0.1:${pc.port}/token', 'secret': 'abc123', 'name': 'LAPTOP'}),
    );
    final devices = [
      PairedDevice(
        id: hub.id,
        name: 'Hub',
        type: DeviceType.hub,
        lastEndpoint: LocalEndpoint('127.0.0.1', hub.port),
        access: AccessLevel.config,
      ),
      PairedDevice(
        id: light.id,
        name: 'Parter',
        type: DeviceType.onOff,
        lastEndpoint: LocalEndpoint('127.0.0.1', light.port),
        access: AccessLevel.config,
      ),
      const PairedDevice(id: 'bez-adresu', name: 'X', access: AccessLevel.config),
    ];
    final tokens = {hub.id: hub.token, light.id: light.token};
    final r = await sendTokensToPc(qr, devices, (id) async => tokens[id]);

    expect(r.saved, [hub.id, light.id]);
    expect(r.failed.keys, ['bez-adresu']);
    expect(received!['secret'], 'abc123');
    final sent = (received!['devices'] as List).cast<Map<String, dynamic>>();
    expect(sent.map((d) => (d['id'], d['type'], d['host'])).toList(), [
      (hub.id, 'hub', '127.0.0.1'),
      (light.id, 'switch', '127.0.0.1'),
    ]);
    // Token komputera jest u urządzenia nowym klientem „komputer LAPTOP” z poziomem config.
    final pcPhone = hub.phones.last;
    expect((pcPhone.name, pcPhone.access, pcPhone.token), ('komputer LAPTOP', 'config', sent.first['token']));

    status = 403;
    await expectLater(
      sendTokensToPc(qr, [devices.first], (id) async => tokens[id]),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('odrzucił'))),
    );
    status = 410;
    await expectLater(
      sendTokensToPc(qr, [devices.first], (id) async => tokens[id]),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('wygasł'))),
    );
  });
}
