import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'aes_ctr_stream.dart';
import 'messages.dart';

/// Klucz sesji security 1 (ESP-IDF `security1.c`): X25519(klient, urządzenie) XOR SHA-256(PoP).
Future<Uint8List> deriveSecurity1Key(List<int> sharedSecret, String pop) async {
  final key = Uint8List.fromList(sharedSecret);
  if (pop.isNotEmpty) {
    final h = await Sha256().hash(utf8.encode(pop));
    for (var i = 0; i < key.length; i++) {
      key[i] ^= h.bytes[i];
    }
  }
  return key;
}

/// Strona klienta sesji security 1 Espressif Unified Provisioning:
/// 1. `SessionCmd0` z kluczem publicznym X25519 klienta,
/// 2. z `SessionResp0` (klucz urządzenia + 16 B losowych) wyliczamy klucz i licznik AES-256-CTR,
/// 3. `SessionCmd1` = zaszyfrowany klucz urządzenia, `SessionResp1` = zaszyfrowany klucz klienta.
/// Potem [encrypt]/[decrypt] na tym samym, ciągłym strumieniu CTR (jak w firmware).
class Security1Session {
  Security1Session(this.pop, {SimpleKeyPair? keyPair}) : _fixedKeyPair = keyPair;

  /// Kod PoP z ekranu/naklejki urządzenia.
  final String pop;
  final SimpleKeyPair? _fixedKeyPair;

  final _x25519 = X25519();
  late SimpleKeyPair _keyPair;
  late Uint8List _clientPubkey;
  late Uint8List _devicePubkey;
  AesCtrStream? _ctr;

  bool get established => _ctr != null;

  /// Krok 1: dane dla endpointu `prov-session`.
  Future<Uint8List> command0() async {
    _keyPair = _fixedKeyPair ?? await _x25519.newKeyPair();
    _clientPubkey = Uint8List.fromList((await _keyPair.extractPublicKey()).bytes);
    return encodeSessionCmd0(_clientPubkey);
  }

  /// Krok 2: odpowiedź na command0 → dane command1.
  Future<Uint8List> command1(List<int> response0) async {
    final r = decodeSessionResp0(response0);
    if (r.devicePubkey.length != 32 || r.deviceRandom.length != 16) {
      throw const ProvisioningException('Zła odpowiedź sesji: długość klucza albo licznika.');
    }
    _devicePubkey = r.devicePubkey;
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(_devicePubkey, type: KeyPairType.x25519),
    );
    final key = await deriveSecurity1Key(await shared.extractBytes(), pop);
    _ctr = AesCtrStream(key, r.deviceRandom);
    return encodeSessionCmd1(_ctr!.apply(_devicePubkey));
  }

  /// Krok 3: urządzenie odsyła nasz klucz zaszyfrowany - zgodność znaczy ten sam PoP.
  void verify(List<int> response1) {
    final data = decodeSessionResp1(response1);
    final plain = _ctr!.apply(data);
    if (!_equal(plain, _clientPubkey)) {
      throw const ProvisioningException('Nieprawidłowy kod PoP - urządzenie nie potwierdziło sesji.');
    }
  }

  Uint8List encrypt(List<int> data) => _require().apply(data);

  Uint8List decrypt(List<int> data) => _require().apply(data);

  AesCtrStream _require() {
    final c = _ctr;
    if (c == null) throw StateError('Sesja nie jest nawiązana');
    return c;
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
