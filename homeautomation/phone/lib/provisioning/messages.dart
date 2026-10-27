// Wiadomości Espressif Unified Provisioning (ESP-IDF components/protocomm/proto i
// components/wifi_provisioning/proto). Numery pól jak w plikach .proto.

import 'dart:convert';
import 'dart:typed_data';

import 'protobuf.dart';

/// `constants.proto` Status.
enum ProvStatus {
  success,
  invalidSecScheme,
  invalidProto,
  tooManySessions,
  invalidArgument,
  internalError,
  cryptoError,
  invalidSession;

  static ProvStatus of(int v) => v >= 0 && v < values.length ? values[v] : internalError;
}

class ProvisioningException implements Exception {
  const ProvisioningException(this.message);

  final String message;

  @override
  String toString() => message;
}

void _checkStatus(int status, String what) {
  final s = ProvStatus.of(status);
  if (s == ProvStatus.success) return;
  throw ProvisioningException(switch (s) {
    ProvStatus.cryptoError ||
    ProvStatus.invalidSession => 'Urządzenie odrzuciło kod PoP albo sesję ($what). Sprawdź kod na ekranie urządzenia.',
    ProvStatus.tooManySessions => 'Urządzenie ma już otwartą sesję konfiguracji z innym telefonem.',
    _ => 'Urządzenie zgłosiło błąd: ${s.name} ($what).',
  });
}

// ------------------------------------------------------------------ session.proto + sec1.proto

const _secScheme1 = 1;

/// SessionData{sec_ver=1, sec1=Sec1Payload{msg, sc0|sc1}}.
Uint8List _session(int msgType, int payloadField, Uint8List payload) {
  final sec1 = ProtoWriter()
    ..uint(1, msgType)
    ..message(payloadField, payload);
  return (ProtoWriter()
        ..uint(2, _secScheme1)
        ..message(11, sec1.toBytes()))
      .toBytes();
}

/// Session_Command0: klucz publiczny klienta.
Uint8List encodeSessionCmd0(List<int> clientPubkey) =>
    _session(0, 20, (ProtoWriter()..bytes(1, clientPubkey)).toBytes());

/// Session_Command1: zaszyfrowany klucz publiczny urządzenia.
Uint8List encodeSessionCmd1(List<int> clientVerifyData) =>
    _session(2, 22, (ProtoWriter()..bytes(2, clientVerifyData)).toBytes());

ProtoMessage _sec1(List<int> data) {
  final session = ProtoMessage.parse(data);
  final sec1 = session.message(11);
  if (sec1 == null) throw const ProvisioningException('Urządzenie nie obsługuje security 1.');
  return sec1;
}

/// Session_Response0: (klucz publiczny urządzenia, losowe 16 B = licznik CTR).
({Uint8List devicePubkey, Uint8List deviceRandom}) decodeSessionResp0(List<int> data) {
  final sr0 = _sec1(data).message(21);
  if (sr0 == null) throw const ProvisioningException('Zła odpowiedź sesji (krok 0).');
  _checkStatus(sr0.uint(1), 'sesja 0');
  return (devicePubkey: sr0.bytes(2), deviceRandom: sr0.bytes(3));
}

/// Session_Response1: zaszyfrowany klucz publiczny klienta.
Uint8List decodeSessionResp1(List<int> data) {
  final sr1 = _sec1(data).message(23);
  if (sr1 == null) throw const ProvisioningException('Zła odpowiedź sesji (krok 1).');
  _checkStatus(sr1.uint(1), 'sesja 1');
  return sr1.bytes(3);
}

// ------------------------------------------------------------------ wifi_scan.proto

/// `wifi_constants.proto` WifiAuthMode.
enum WifiAuthMode { open, wep, wpaPsk, wpa2Psk, wpaWpa2Psk, wpa2Enterprise, wpa3Psk, wpa2Wpa3Psk }

class WifiNetwork {
  const WifiNetwork({required this.ssid, required this.rssi, required this.auth, this.channel = 0});

  final String ssid;
  final int rssi;
  final WifiAuthMode auth;
  final int channel;

  bool get secured => auth != WifiAuthMode.open;

  @override
  String toString() => '$ssid ($rssi dBm, ${auth.name})';
}

Uint8List _scanPayload(int msg, int field, Uint8List body) =>
    (ProtoWriter()
          ..uint(1, msg)
          ..message(field, body))
        .toBytes();

Uint8List encodeScanStart({bool blocking = true, int periodMs = 120}) => _scanPayload(
  0,
  10,
  (ProtoWriter()
        ..boolean(1, blocking)
        ..uint(4, periodMs))
      .toBytes(),
);

Uint8List encodeScanStatus() => _scanPayload(2, 12, Uint8List(0));

Uint8List encodeScanResult(int start, int count) => _scanPayload(
  4,
  14,
  (ProtoWriter()
        ..uint(1, start)
        ..uint(2, count))
      .toBytes(),
);

ProtoMessage _scan(List<int> data, int field, String what) {
  final p = ProtoMessage.parse(data);
  _checkStatus(p.uint(2), what);
  return p.message(field) ?? ProtoMessage.parse(const []);
}

void decodeScanStartResp(List<int> data) => _scan(data, 11, 'skan');

({bool finished, int count}) decodeScanStatusResp(List<int> data) {
  final m = _scan(data, 13, 'stan skanu');
  return (finished: m.boolean(1), count: m.uint(2));
}

List<WifiNetwork> decodeScanResultResp(List<int> data) => [
  for (final e in _scan(data, 15, 'wyniki skanu').messages(1))
    WifiNetwork(
      ssid: utf8.decode(e.bytes(1), allowMalformed: true),
      channel: e.uint(2),
      rssi: e.int32(3),
      auth: WifiAuthMode.values[e.uint(5).clamp(0, WifiAuthMode.values.length - 1)],
    ),
];

// ------------------------------------------------------------------ wifi_config.proto

enum WifiStationState { connected, connecting, disconnected, connectionFailed }

enum WifiFailReason { authError, networkNotFound }

class WifiStatus {
  const WifiStatus(this.state, {this.failReason, this.ip, this.attemptsRemaining});

  final WifiStationState state;
  final WifiFailReason? failReason;

  /// Adres IP urządzenia po połączeniu (`connected.ip4_addr`).
  final String? ip;

  /// Nowsze ESP-IDF: ile prób łączenia zostało.
  final int? attemptsRemaining;
}

Uint8List _configPayload(int msg, int field, Uint8List body) =>
    (ProtoWriter()
          ..uint(1, msg)
          ..message(field, body))
        .toBytes();

Uint8List encodeGetStatus() => _configPayload(0, 10, Uint8List(0));

Uint8List encodeSetConfig(String ssid, String passphrase) => _configPayload(
  2,
  12,
  (ProtoWriter()
        ..bytes(1, utf8.encode(ssid))
        ..bytes(2, utf8.encode(passphrase)))
      .toBytes(),
);

Uint8List encodeApplyConfig() => _configPayload(4, 14, Uint8List(0));

void decodeSetConfigResp(List<int> data) =>
    _checkStatus((ProtoMessage.parse(data).message(13) ?? ProtoMessage.parse(const [])).uint(1), 'zapis sieci');

void decodeApplyConfigResp(List<int> data) =>
    _checkStatus((ProtoMessage.parse(data).message(15) ?? ProtoMessage.parse(const [])).uint(1), 'łączenie');

WifiStatus decodeGetStatusResp(List<int> data) {
  final r = ProtoMessage.parse(data).message(11);
  if (r == null) throw const ProvisioningException('Zła odpowiedź stanu WiFi.');
  _checkStatus(r.uint(1), 'stan WiFi');
  final state = WifiStationState.values[r.uint(2).clamp(0, 3)];
  return WifiStatus(
    state,
    failReason: r.has(10) ? WifiFailReason.values[r.uint(10).clamp(0, 1)] : null,
    ip: r.message(11)?.string(1),
    attemptsRemaining: r.message(12)?.uint(1),
  );
}
