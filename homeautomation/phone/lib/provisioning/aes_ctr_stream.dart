import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-CTR jako jeden ciągły strumień - tak jak `mbedtls_aes_crypt_ctr` w security1 ESP-IDF:
/// licznik to cały 16-bajtowy blok (big-endian, przeniesienie przez wszystkie 128 bitów),
/// a pozycja w strumieniu (`nc_off`) przechodzi między kolejnymi wiadomościami sesji.
class AesCtrStream {
  AesCtrStream(Uint8List key, Uint8List initialCounter)
    : assert(initialCounter.length == 16),
      _counter = Uint8List.fromList(initialCounter) {
    _aes.init(true, KeyParameter(key));
  }

  final _aes = AESEngine();
  final Uint8List _counter;
  final _block = Uint8List(16);
  int _offset = 16; // 16 = trzeba wyliczyć nowy blok strumienia

  /// Szyfruje albo deszyfruje (CTR jest symetryczny) i przesuwa strumień.
  Uint8List apply(List<int> data) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      if (_offset == 16) {
        _aes.processBlock(_counter, 0, _block, 0);
        _increment();
        _offset = 0;
      }
      out[i] = data[i] ^ _block[_offset++];
    }
    return out;
  }

  void _increment() {
    for (var i = 15; i >= 0; i--) {
      _counter[i] = (_counter[i] + 1) & 0xff;
      if (_counter[i] != 0) return;
    }
  }
}
