// Typy `switch` i `dimmer` (kontrakt pkt 10) i przełącznik wielokanałowy z wejściami (pkt 10.1, węzeł `switch4`):
// pola są płaskie (`on2`, `in3`, `ch1`, `input4`), żeby punkty z `describe` były zwykłymi kluczami State / Set.

import 'device_type.dart';
import 'json_utils.dart';

/// State włącznika / ściemniacza.
class LightState {
  const LightState({
    required this.id,
    required this.ts,
    required this.on,
    this.level,
    this.power,
    this.wifiRssi,
    this.cloud = false,
    this.uptime = 0,
    this.channels = 1,
    this.channelOn = const [],
    this.inputs = const [],
    this.inputFaults = const {},
  });

  final String id;
  final int ts;

  /// Wielokanałowy: dowolny kanał włączony.
  final bool on;

  /// 0-100, tylko ściemniacz.
  final int? level;

  /// W, gdy urządzenie mierzy pobór.
  final double? power;
  final int? wifiRssi;
  final bool cloud;
  final int uptime;

  /// Liczba kanałów (pkt 10.1; 1 = zwykły włącznik).
  final int channels;

  /// `on1`…`onN` (indeks 0 = kanał 1).
  final List<bool> channelOn;

  /// `in1`…`inM` - wejście zwarte do masy (przycisk wciśnięty / łącznik zamknięty).
  final List<bool> inputs;

  /// Numery wejść (od 1) z `inNFault: true`: usterka przewodu - wejście zablokowane, samo wraca po 60 s.
  final Set<int> inputFaults;

  bool get multi => channels > 1;

  /// Ile kanałów świeci.
  int get onCount => channelOn.where((x) => x).length;

  factory LightState.fromJson(Json j) {
    final channels = asInt(j['channels'], 'channels', 1);
    final inputs = asInt(j['inputs'], 'inputs', 0);
    return LightState(
      id: asString(j['id'], 'id'),
      ts: asInt(j['ts'], 'ts'),
      on: asBool(j['on'], 'on'),
      level: asIntOrNull(j['level'], 'level'),
      power: asDoubleOrNull(j['power'], 'power'),
      wifiRssi: asIntOrNull(j['wifiRssi'], 'wifiRssi'),
      cloud: asBool(j['cloud'], 'cloud'),
      uptime: asInt(j['uptime'], 'uptime'),
      channels: channels,
      channelOn: channels > 1 ? [for (var i = 1; i <= channels; i++) asBool(j['on$i'], 'on$i')] : const [],
      inputs: [for (var k = 1; k <= inputs; k++) asBool(j['in$k'], 'in$k')],
      inputFaults: {
        for (var k = 1; k <= inputs; k++)
          if (j['in${k}Fault'] == true) k,
      },
    );
  }

  Json toJson() => {
    'id': id,
    'ts': ts,
    'on': on,
    'level': level,
    'power': power,
    'wifiRssi': wifiRssi,
    'cloud': cloud,
    'uptime': uptime,
    if (multi) ...{
      'channels': channels,
      for (final (i, v) in channelOn.indexed) 'on${i + 1}': v,
    },
    if (inputs.isNotEmpty) ...{
      'inputs': inputs.length,
      for (final (i, v) in inputs.indexed) 'in${i + 1}': v,
      for (final k in inputFaults) 'in${k}Fault': true,
    },
  };
}

/// Zachowanie po zaniku zasilania.
enum DefaultOn {
  last('last', 'Jak przed zanikiem'),
  on('on', 'Włączone'),
  off('off', 'Wyłączone');

  const DefaultOn(this.wire, this.label);

  final String wire;
  final String label;

  static DefaultOn fromWire(String? v) => values.firstWhere((d) => d.wire == v, orElse: () => last);
}

/// Tryb wejścia (pkt 10.1) - działa lokalnie w węźle, bez sieci i bez telefonu.
enum InputMode {
  momentary('momentary', 'Przycisk', 'przycisk dzwonkowy - każde naciśnięcie przełącza'),
  edge('edge', 'Łącznik - każda zmiana', 'każda zmiana położenia łącznika przełącza'),
  follow('follow', 'Łącznik - położenie', 'światło = położenie łącznika');

  const InputMode(this.wire, this.label, this.help);

  final String wire;
  final String label;
  final String help;

  static InputMode fromWire(String? v) => values.firstWhere((m) => m.wire == v, orElse: () => momentary);
}

/// `chN` w Config.
class ChannelConfig {
  const ChannelConfig({required this.name, this.defaultOn = DefaultOn.last});

  final String name;
  final DefaultOn defaultOn;

  factory ChannelConfig.fromJson(Json j, int n) => ChannelConfig(
    name: asString(j['name'], 'ch$n.name', 'Kanał $n'),
    defaultOn: DefaultOn.fromWire(asStringOrNull(j['defaultOn'], 'ch$n.defaultOn')),
  );

  Json toJson() => {'name': name, 'defaultOn': defaultOn.wire};
}

/// `inputK` w Config: wejście przełącza kanał [out] (0 = żaden, tylko `inK` dla huba).
class InputConfig {
  const InputConfig({required this.name, this.mode = InputMode.momentary, this.out = 0});

  final String name;
  final InputMode mode;
  final int out;

  factory InputConfig.fromJson(Json j, int k) => InputConfig(
    name: asString(j['name'], 'input$k.name', 'Wejście $k'),
    mode: InputMode.fromWire(asStringOrNull(j['mode'], 'input$k.mode')),
    out: asInt(j['out'], 'input$k.out'),
  );

  Json toJson() => {'name': name, 'mode': mode.wire, 'out': out};
}

/// Config włącznika / ściemniacza.
class LightConfig {
  const LightConfig({
    required this.name,
    this.defaultOn = DefaultOn.last,
    this.channels = const [],
    this.inputs = const [],
  });

  final String name;
  final DefaultOn defaultOn;

  /// `ch1`…`chN` (pusta lista = jeden kanał).
  final List<ChannelConfig> channels;

  /// `input1`…`inputM`.
  final List<InputConfig> inputs;

  factory LightConfig.fromJson(Json j) {
    final n = asInt(j['channels'], 'channels', 1);
    final m = asInt(j['inputs'], 'inputs', 0);
    return LightConfig(
      name: asString(j['name'], 'name'),
      defaultOn: DefaultOn.fromWire(asStringOrNull(j['defaultOn'], 'defaultOn')),
      channels: n > 1
          ? [for (var i = 1; i <= n; i++) ChannelConfig.fromJson(asObjectOrNull(j['ch$i'], 'ch$i') ?? const {}, i)]
          : const [],
      inputs: [
        for (var k = 1; k <= m; k++) InputConfig.fromJson(asObjectOrNull(j['input$k'], 'input$k') ?? const {}, k),
      ],
    );
  }

  Json toJson() => {
    'name': name,
    if (channels.isEmpty) 'defaultOn': defaultOn.wire,
    if (channels.isNotEmpty) ...{
      'channels': channels.length,
      for (final (i, c) in channels.indexed) 'ch${i + 1}': c.toJson(),
    },
    if (inputs.isNotEmpty) ...{
      'inputs': inputs.length,
      for (final (i, x) in inputs.indexed) 'input${i + 1}': x.toJson(),
    },
  };
}

/// Zmiana ustawień jednego kanału (`chN` w Set).
class ChannelPatch {
  const ChannelPatch({this.name, this.defaultOn});

  final String? name;
  final DefaultOn? defaultOn;

  Json toJson() => {'name': ?name, 'defaultOn': ?defaultOn?.wire};
}

/// Zmiana wejścia (`inputK` w Set).
class InputPatch {
  const InputPatch({this.name, this.mode, this.out});

  final String? name;
  final InputMode? mode;
  final int? out;

  Json toJson() => {'name': ?name, 'mode': ?mode?.wire, 'out': ?out};
}

/// Set włącznika / ściemniacza: tylko ustawione pola. `on` / `toggle` = wszystkie kanały.
class LightSet {
  const LightSet({
    this.on,
    this.level,
    this.toggle,
    this.name,
    this.defaultOn,
    this.channelOn = const {},
    this.channelToggle = const {},
    this.channel = const {},
    this.input = const {},
  });

  final bool? on;
  final int? level;
  final bool? toggle;
  final String? name;
  final DefaultOn? defaultOn;

  /// `onN` (klucz = numer kanału od 1).
  final Map<int, bool> channelOn;

  /// `toggleN`.
  final Set<int> channelToggle;

  /// `chN`.
  final Map<int, ChannelPatch> channel;

  /// `inputK`.
  final Map<int, InputPatch> input;

  Json toJson() {
    final j = <String, dynamic>{};
    putIfNotNull(j, 'on', on);
    putIfNotNull(j, 'level', level);
    if (toggle == true) j['toggle'] = true;
    putIfNotNull(j, 'name', name);
    putIfNotNull(j, 'defaultOn', defaultOn?.wire);
    for (final e in channelOn.entries) {
      j['on${e.key}'] = e.value;
    }
    for (final n in channelToggle) {
      j['toggle$n'] = true;
    }
    for (final e in channel.entries) {
      final p = e.value.toJson();
      if (p.isNotEmpty) j['ch${e.key}'] = p;
    }
    for (final e in input.entries) {
      final p = e.value.toJson();
      if (p.isNotEmpty) j['input${e.key}'] = p;
    }
    return j;
  }
}

final lightCodec = DeviceCodec<LightState, LightConfig>(
  state: LightState.fromJson,
  config: LightConfig.fromJson,
  nameOf: (c) => c.name,
  stateToJson: (s) => s.toJson(),
);
