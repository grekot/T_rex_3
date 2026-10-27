// Konfiguracja WiFi przez Bluetooth (kontrakt pkt 9): AES-CTR, X25519 + PoP, sesja security 1
// na wektorach z OpenSSL (Node), protobuf i pełny przebieg z atrapą urządzenia.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/provisioning/aes_ctr_stream.dart';
import 'package:homeautomation/provisioning/messages.dart';
import 'package:homeautomation/provisioning/protobuf.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/provisioning/security1.dart';

import 'support/fake_prov_device.dart';

Uint8List h(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

String hx(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Transport odtwarzający przygotowane odpowiedzi i zapisujący żądania.
class _Scripted implements ProvTransport {
  _Scripted(this.responses);

  final List<Uint8List> responses;
  final sent = <Uint8List>[];

  @override
  Future<Uint8List> exchange(String endpoint, Uint8List data) async {
    sent.add(data);
    return responses.removeAt(0);
  }

  @override
  Future<void> close() async {}
}

Uint8List _sec1Resp(int msg, int field, Uint8List body) =>
    (ProtoWriter()
          ..uint(2, 1)
          ..message(
            11,
            (ProtoWriter()
                  ..uint(1, msg)
                  ..message(field, body))
                .toBytes(),
          ))
        .toBytes();

void main() {
  group('AES-256-CTR', () {
    test('NIST SP 800-38A F.5.5', () {
      final ctr = AesCtrStream(
        h('603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4'),
        h('f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff'),
      );
      final out = ctr.apply(
        h(
          '6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51'
          '30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710',
        ),
      );
      expect(
        hx(out),
        '601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c5'
        '2b0930daa23de94ce87017ba2d84988ddfc9c58db67aada613c2dd08457941a6',
      );
    });

    test('ciągły strumień: kawałki = całość; licznik przenosi się przez 128 bitów', () {
      final key = h('a3937a411dfcd00911bdb6fc3e78e6fa03e08180fa7e2d71b89505f95b1d7eec');
      final whole = AesCtrStream(key, Uint8List(16)..fillRange(0, 16, 0xff)).apply(Uint8List(48));
      expect(
        hx(whole),
        'ab0c3073c4ba5744f55d7517bc12e4d6e64fef0f927e54d7f2c4d115d035e426'
        'fce326dd8d6984e01ea0b6a3d1f34d69',
      );
      final parts = AesCtrStream(key, Uint8List(16)..fillRange(0, 16, 0xff));
      expect(
        hx([...parts.apply(Uint8List(5)), ...parts.apply(Uint8List(30)), ...parts.apply(Uint8List(13))]),
        hx(whole),
      );
    });
  });

  test('sesja security 1 zgodna z referencją OpenSSL (RFC 7748, PoP abcd1234)', () async {
    final clientKeys = await X25519().newKeyPairFromSeed(
      h('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'),
    );
    final devicePub = h('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f');
    final random = h('000102030405060708090a0b0c0d0e0f');
    final t = _Scripted([
      _sec1Resp(
        1,
        21,
        (ProtoWriter()
              ..bytes(2, devicePub)
              ..bytes(3, random))
            .toBytes(),
      ),
      _sec1Resp(
        3,
        23,
        (ProtoWriter()..bytes(3, h('1a9fc468be5458d825515286b44ebbaf011f97a43c07f40c6d64f729c6b35efd'))).toBytes(),
      ),
    ]);
    final p = Provisioner(t, 'abcd1234', session: Security1Session('abcd1234', keyPair: clientKeys));
    await p.start();

    // cmd0: SessionData{sec_ver=1, sec1{sc0{client_pubkey}}}
    expect(hx(t.sent[0]), '10015a25a201220a20${'8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a'}');
    // cmd1: msg=2, sc1{client_verify_data} = AES-CTR(klucz urządzenia)
    expect(hx(t.sent[1]), contains('83bf9c458ee640df428e0d2de2717eeddeaf3867023007ec09bc853fa1db0ccf'));
    // Dalsze wiadomości ciągną ten sam strumień CTR.
    expect(hx(p.session.encrypt('{"client":"Test"}'.codeUnits)), 'c77960008ac4c1fb21e5d01f064fd57b59');
  });

  test('zły PoP: urządzenie odrzuca sesję', () async {
    final dev = FakeProvDevice(pop: 'dobry123');
    await expectLater(Provisioner(dev, 'zly12345').start(), throwsA(isA<ProvisioningException>()));
    expect(dev.sessionOk, isFalse);
  });

  test('pełny przebieg: ha-pair, skan, zapis sieci, połączenie z IP', () async {
    final dev = FakeProvDevice(
      pop: 'abcd1234',
      networks: const [
        FakeNetwork('Dom', -48, password: 'tajne123'),
        FakeNetwork('Sasiad', -80),
        FakeNetwork('Dom', -70, password: 'tajne123'),
        FakeNetwork('', -40),
        FakeNetwork('Gosc', -60, auth: 0),
      ],
    );
    final p = Provisioner(dev, 'abcd1234');
    await p.start();
    final pair = await p.haPair('Pixel 8');
    expect((pair.id, pair.type, pair.token, pair.api), ('termostat-ab12cd', 'thermostat', 'a1b2c3', 2));
    expect(dev.pairedClient, 'Pixel 8');

    final nets = await p.scanWifi();
    expect(nets.map((n) => (n.ssid, n.rssi)), [('Dom', -48), ('Gosc', -60), ('Sasiad', -80)]);
    expect(nets[1].secured, isFalse);

    await p.setWifi('Dom', 'tajne123');
    expect((dev.ssid, dev.passphrase, dev.applied), ('Dom', 'tajne123', true));
    final s = await p.waitForConnection(interval: Duration.zero);
    expect(s.state, WifiStationState.connected);
    expect(s.ip, '192.168.1.77');
  });

  test('złe hasło i brak sieci → czytelny błąd', () async {
    for (final (ssid, pass, msg) in [('Dom', 'zle', 'Złe hasło'), ('Brak', 'x', 'nie widzi')]) {
      final dev = FakeProvDevice(
        pop: 'p',
        networks: const [FakeNetwork('Dom', -50, password: 'ok')],
        connectPolls: 0,
      );
      final p = Provisioner(dev, 'p');
      await p.start();
      await p.setWifi(ssid, pass);
      await expectLater(
        p.waitForConnection(interval: Duration.zero),
        throwsA(isA<ProvisioningException>().having((e) => e.message, 'message', contains(msg))),
      );
    }
  });

  test('protobuf: ujemny int32 i pola oneof z zerem', () {
    final w = ProtoWriter()
      ..int32(3, -60)
      ..uintAlways(10, 0);
    final m = ProtoMessage.parse(w.toBytes());
    expect(m.int32(3), -60);
    expect(m.has(10), isTrue);
    expect(m.uint(10), 0);
  });
}
