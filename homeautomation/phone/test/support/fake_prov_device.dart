// Urządzenie w trybie konfiguracji Bluetooth - strona urządzenia protokołu (jak ESP-IDF
// protocomm + wifi_provisioning + endpoint ha-pair z firmware), bez BLE.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:homeautomation/provisioning/aes_ctr_stream.dart';
import 'package:homeautomation/provisioning/protobuf.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/provisioning/security1.dart';

class FakeNetwork {
  const FakeNetwork(this.ssid, this.rssi, {this.password = '', this.auth = 3});

  final String ssid;
  final int rssi;
  final String password;
  final int auth;
}

class FakeProvDevice implements ProvTransport {
  FakeProvDevice({
    required this.pop,
    this.id = 'termostat-ab12cd',
    this.type = 'thermostat',
    this.token = 'a1b2c3',
    this.networks = const [],
    this.ip = '192.168.1.77',
    this.connectPolls = 2,
  });

  final String pop;
  final String id;
  final String type;
  final String token;
  final List<FakeNetwork> networks;
  final String ip;

  /// Ile zapytań o stan zwraca „connecting” przed wynikiem.
  final int connectPolls;

  final _x25519 = X25519();
  SimpleKeyPair? _keyPair;
  Uint8List? _devicePub;
  Uint8List? _clientPub;
  AesCtrStream? _ctr;
  bool sessionOk = false;

  String? pairedClient;
  String? pairedUid;
  String? ssid;
  String? passphrase;
  bool applied = false;
  int _statusPolls = 0;
  final log = <String>[];

  @override
  Future<Uint8List> exchange(String endpoint, Uint8List data) async {
    log.add(endpoint);
    if (endpoint == 'prov-session') return _session(data);
    if (!sessionOk) throw StateError('Brak sesji');
    final plain = _ctr!.apply(data);
    final Uint8List response = switch (endpoint) {
      'ha-pair' => _haPair(plain),
      'prov-scan' => _scan(plain),
      'prov-config' => _config(plain),
      _ => throw StateError('Nieznany endpoint $endpoint'),
    };
    return _ctr!.apply(response);
  }

  Future<Uint8List> _session(Uint8List data) async {
    final sec1 = ProtoMessage.parse(data).message(11)!;
    final msg = sec1.uint(1);
    if (msg == 0) {
      _clientPub = sec1.message(20)!.bytes(1);
      _keyPair = await _x25519.newKeyPair();
      _devicePub = Uint8List.fromList((await _keyPair!.extractPublicKey()).bytes);
      final random = Uint8List.fromList(List.generate(16, (_) => Random.secure().nextInt(256)));
      final shared = await _x25519.sharedSecretKey(
        keyPair: _keyPair!,
        remotePublicKey: SimplePublicKey(_clientPub!, type: KeyPairType.x25519),
      );
      _ctr = AesCtrStream(await deriveSecurity1Key(await shared.extractBytes(), pop), random);
      final sr0 = ProtoWriter()
        ..bytes(2, _devicePub!)
        ..bytes(3, random);
      return _sec1(1, 21, sr0.toBytes());
    }
    // Command1: klient musi umieć zaszyfrować nasz klucz - inaczej PoP się nie zgadza.
    final check = _ctr!.apply(sec1.message(22)!.bytes(2));
    final ok = _eq(check, _devicePub!);
    final sr1 = ProtoWriter()..uint(1, ok ? 0 : 6); // 6 = CryptoError
    if (ok) sr1.bytes(3, _ctr!.apply(_clientPub!));
    sessionOk = ok;
    return _sec1(3, 23, sr1.toBytes());
  }

  Uint8List _sec1(int msg, int field, Uint8List payload) {
    final sec1 = ProtoWriter()
      ..uint(1, msg)
      ..message(field, payload);
    return (ProtoWriter()
          ..uint(2, 1)
          ..message(11, sec1.toBytes()))
        .toBytes();
  }

  Uint8List _haPair(Uint8List plain) {
    final req = jsonDecode(utf8.decode(plain)) as Map;
    pairedClient = req['client'] as String?;
    pairedUid = req['uid'] as String?;
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'id': id, 'type': type, 'token': token, 'api': 2, 'access': 'config'})),
    );
  }

  Uint8List _scan(Uint8List plain) {
    final p = ProtoMessage.parse(plain);
    final w = ProtoWriter();
    switch (p.uint(1)) {
      case 0:
        w
          ..uint(1, 1)
          ..message(11, Uint8List(0));
      case 2:
        w
          ..uint(1, 3)
          ..message(
            13,
            (ProtoWriter()
                  ..boolean(1, true)
                  ..uint(2, networks.length))
                .toBytes(),
          );
      case 4:
        final req = p.message(14)!;
        final start = req.uint(1), count = req.uint(2);
        final resp = ProtoWriter();
        for (final n in networks.skip(start).take(count)) {
          final e = ProtoWriter()
            ..string(1, n.ssid)
            ..uint(2, 6)
            ..uint(5, n.auth);
          e.int32(3, n.rssi);
          resp.message(1, e.toBytes());
        }
        w
          ..uint(1, 5)
          ..message(15, resp.toBytes());
    }
    return w.toBytes();
  }

  Uint8List _config(Uint8List plain) {
    final p = ProtoMessage.parse(plain);
    final w = ProtoWriter();
    switch (p.uint(1)) {
      case 2:
        final c = p.message(12)!;
        ssid = c.string(1);
        passphrase = c.string(2);
        w
          ..uint(1, 3)
          ..message(13, Uint8List(0));
      case 4:
        applied = true;
        w
          ..uint(1, 5)
          ..message(15, Uint8List(0));
      case 0:
        final r = ProtoWriter();
        if (!applied || _statusPolls++ < connectPolls) {
          r.uint(2, 1); // Connecting
        } else {
          final net = networks.where((n) => n.ssid == ssid).firstOrNull;
          if (net == null) {
            r
              ..uint(2, 3)
              ..uintAlways(10, 1); // NetworkNotFound
          } else if (net.password != passphrase) {
            r
              ..uint(2, 3)
              ..uintAlways(10, 0); // AuthError = 0, w oneof zapisany mimo zera
          } else {
            r.message(11, (ProtoWriter()..string(1, ip)).toBytes()); // Connected = 0
          }
        }
        w
          ..uint(1, 1)
          ..message(11, r.toBytes());
    }
    return w.toBytes();
  }

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<void> close() async {}
}
