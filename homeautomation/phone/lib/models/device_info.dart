import 'device_type.dart';
import 'json_utils.dart';

/// Wersje API, które obsługuje aplikacja (1 = termostat sprzed HomeAutomation).
const supportedApiVersions = {1, 2};

/// Jak urządzenie przechodzi konfigurację WiFi: Bluetooth (pkt 9.2) albo własna sieć WiFi (pkt 9.4).
enum ProvScheme {
  ble,
  softap;

  static ProvScheme fromWire(Object? v) => v == 'softap' ? softap : ble;
}

/// Kod parowania kolejnych telefonów: 6 cyfr na ekranie albo PoP z naklejki (pkt 2).
enum PairMethod {
  display,
  pop;

  static PairMethod fromWire(Object? v) => v == 'pop' ? pop : display;
}

/// Odpowiedź `GET /api/info` (bez autoryzacji).
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.fw,
    this.fwId,
    required this.api,
    required this.paired,
    this.type = DeviceType.thermostat,
    this.prov = ProvScheme.ble,
    this.pair = PairMethod.display,
    this.cloud = true,
    this.channels = 1,
    this.inputs = 0,
  });

  final String id;
  final DeviceType type;
  final String name;
  final String fw;

  /// Wariant firmware (`thermostat-n16r8`, `switch4-s2mini`…, pkt 3e); null = starszy firmware.
  final String? fwId;
  final int api;
  final bool paired;

  /// `prov` (brak = `ble`).
  final ProvScheme prov;

  /// `pair` (brak = `display`).
  final PairMethod pair;

  /// `cloud: false` = węzeł klasy B: bez `/api/cloud`, do chmury przez hub.
  final bool cloud;

  /// Liczba kanałów przełącznika (pkt 10.1; brak = 1).
  final int channels;

  /// Wejścia zwierane do masy (pkt 10.1; brak = 0).
  final int inputs;

  bool get apiSupported => supportedApiVersions.contains(api);

  factory DeviceInfo.fromJson(Json j) => DeviceInfo(
    id: asString(j['id'], 'id'),
    type: DeviceType.fromWire(asStringOrNull(j['type'], 'type')),
    name: asString(j['name'], 'name'),
    fw: asString(j['fw'], 'fw'),
    fwId: asStringOrNull(j['fwId'], 'fwId'),
    api: asInt(j['api'], 'api'),
    paired: asBool(j['paired'], 'paired'),
    prov: ProvScheme.fromWire(j['prov']),
    pair: PairMethod.fromWire(j['pair']),
    cloud: j['cloud'] != false,
    channels: asInt(j['channels'], 'channels', 1),
    inputs: asInt(j['inputs'], 'inputs'),
  );

  Json toJson() => {
    'id': id,
    'type': type.wire,
    'name': name,
    'fw': fw,
    'fwId': ?fwId,
    'api': api,
    'paired': paired,
    if (prov == ProvScheme.softap) 'prov': 'softap',
    if (pair == PairMethod.pop) 'pair': 'pop',
    if (!cloud) 'cloud': false,
    if (channels != 1) 'channels': channels,
    if (inputs != 0) 'inputs': inputs,
  };
}
