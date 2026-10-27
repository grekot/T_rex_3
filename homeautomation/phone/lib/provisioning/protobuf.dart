// Minimalny protobuf (proto3) dla wiadomości Espressif Unified Provisioning.
// Wiadomości są małe i stałe, więc ręczny koder zamiast generowania kodu z protoc.

import 'dart:convert';
import 'dart:typed_data';

const _wireVarint = 0;
const _wire64 = 1;
const _wireLen = 2;
const _wire32 = 5;

/// Koder wiadomości. Pola z wartością domyślną (0, pusty) pomija jak protobuf,
/// poza [message], gdzie pusta podwiadomość też jest zapisywana (ważne dla `oneof`).
class ProtoWriter {
  final _b = BytesBuilder();

  void _varint(int v) {
    assert(v >= 0, 'ujemne varinty nie są potrzebne w tym protokole');
    var x = v;
    while (x >= 0x80) {
      _b.addByte((x & 0x7f) | 0x80);
      x >>= 7;
    }
    _b.addByte(x);
  }

  void _key(int field, int wire) => _varint((field << 3) | wire);

  /// varint (uint32, int32 ≥ 0, enum, bool).
  void uint(int field, int value) {
    if (value == 0) return;
    _key(field, _wireVarint);
    _varint(value);
  }

  /// varint zapisany zawsze, także 0 - pole w `oneof` (np. `fail_reason = AuthError`).
  void uintAlways(int field, int value) {
    _key(field, _wireVarint);
    _varint(value);
  }

  /// int32: ujemne jako 10-bajtowy varint uzupełnienia do dwóch (jak protobuf).
  void int32(int field, int value) {
    if (value >= 0) return uint(field, value);
    _key(field, _wireVarint);
    var x = value; // 64-bitowe uzupełnienie do dwóch, przesuwamy logicznie (>>>)
    for (var i = 0; i < 9; i++) {
      _b.addByte((x & 0x7f) | 0x80);
      x = x >>> 7;
    }
    _b.addByte(x & 0x01);
  }

  void boolean(int field, bool value) => uint(field, value ? 1 : 0);

  void bytes(int field, List<int> value) {
    if (value.isEmpty) return;
    _key(field, _wireLen);
    _varint(value.length);
    _b.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  /// Podwiadomość - zawsze zapisana, nawet pusta.
  void message(int field, Uint8List value) {
    _key(field, _wireLen);
    _varint(value.length);
    _b.add(value);
  }

  Uint8List toBytes() => _b.toBytes();
}

/// Dekoder: pola numer → lista wartości (int dla varint, Uint8List dla danych/podwiadomości).
class ProtoMessage {
  ProtoMessage._(this._fields);

  final Map<int, List<Object>> _fields;

  factory ProtoMessage.parse(List<int> data) {
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final fields = <int, List<Object>>{};
    var i = 0;

    int varint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (i >= bytes.length) throw const FormatException('Ucięty varint');
        final b = bytes[i++];
        result |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) return result;
        shift += 7;
        if (shift > 63) throw const FormatException('Za długi varint');
      }
    }

    while (i < bytes.length) {
      final key = varint();
      final field = key >> 3;
      final Object value;
      switch (key & 7) {
        case _wireVarint:
          value = varint();
        case _wireLen:
          final len = varint();
          if (len < 0 || i + len > bytes.length) throw const FormatException('Ucięte pole');
          value = Uint8List.sublistView(bytes, i, i + len);
          i += len;
        case _wire64:
          i += 8;
          continue;
        case _wire32:
          i += 4;
          continue;
        default:
          throw FormatException('Nieznany typ pola ${key & 7}');
      }
      (fields[field] ??= []).add(value);
    }
    return ProtoMessage._(fields);
  }

  bool has(int field) => _fields.containsKey(field);

  int uint(int field) => (_fields[field]?.last as int?) ?? 0;

  /// int32 (np. rssi) zapisany jako 64-bitowy varint uzupełnienia do dwóch.
  int int32(int field) => uint(field).toSigned(32);

  bool boolean(int field) => uint(field) != 0;

  Uint8List bytes(int field) => (_fields[field]?.last as Uint8List?) ?? Uint8List(0);

  String string(int field) => utf8.decode(bytes(field), allowMalformed: true);

  ProtoMessage? message(int field) => has(field) ? ProtoMessage.parse(bytes(field)) : null;

  List<ProtoMessage> messages(int field) => [
    for (final v in _fields[field] ?? const <Object>[]) ProtoMessage.parse(v as Uint8List),
  ];
}
