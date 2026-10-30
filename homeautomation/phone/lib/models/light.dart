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
    this.overheat = false,
    this.overheatOff = false,
    this.offIn = const {},
    this.waitIn = const {},
    this.cycles = const {},
    this.hours = const {},
    this.temp,
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

  /// `in1`…`inM` - wejście aktywne (zwarte; przy `invert` - rozwarte).
  final List<bool> inputs;

  /// Numery wejść (od 1) z `inNFault: true`: usterka przewodu - wejście zablokowane, samo wraca po 60 s.
  final Set<int> inputFaults;

  /// Temperatura w obudowie ponad `tempWarn` (czujnik DS18B20).
  final bool overheat;

  /// Ponad `tempOff`: wszystkie kanały wyłączone, włączanie zablokowane do ostygnięcia.
  final bool overheatOff;

  /// `chNOffIn` (numer kanału → s do wyłączenia: wyłączanie po czasie albo impuls).
  final Map<int, int> offIn;

  /// `chNWait` (s do włączenia - kanał czeka na minimalny czas wyłączenia).
  final Map<int, int> waitIn;

  /// `chNCycles` / `chNHours`: liczniki łączeń i czasu pracy.
  final Map<int, int> cycles;
  final Map<int, double> hours;

  /// °C w obudowie, gdy jest czujnik.
  final double? temp;

  bool get multi => channels > 1;

  /// Ile kanałów świeci.
  int get onCount => channelOn.where((x) => x).length;

  factory LightState.fromJson(Json j) {
    final channels = asInt(j['channels'], 'channels', 1);
    final inputs = asInt(j['inputs'], 'inputs', 0);
    Map<int, T> perChannel<T>(String suffix, T Function(num) read) => {
      for (var i = 1; i <= channels; i++)
        if (j['ch$i$suffix'] case final num v) i: read(v),
    };
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
      overheat: j['overheat'] == true,
      overheatOff: j['overheatOff'] == true,
      offIn: perChannel('OffIn', (v) => v.toInt()),
      waitIn: perChannel('Wait', (v) => v.toInt()),
      cycles: perChannel('Cycles', (v) => v.toInt()),
      hours: perChannel('Hours', (v) => v.toDouble()),
      temp: asDoubleOrNull(j['temp'], 'temp'),
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
    if (multi) ...{'channels': channels, for (final (i, v) in channelOn.indexed) 'on${i + 1}': v},
    if (inputs.isNotEmpty) ...{
      'inputs': inputs.length,
      for (final (i, v) in inputs.indexed) 'in${i + 1}': v,
      for (final k in inputFaults) 'in${k}Fault': true,
    },
    if (overheat) 'overheat': true,
    if (overheatOff) 'overheatOff': true,
    for (final e in offIn.entries) 'ch${e.key}OffIn': e.value,
    for (final e in waitIn.entries) 'ch${e.key}Wait': e.value,
    for (final e in cycles.entries) 'ch${e.key}Cycles': e.value,
    for (final e in hours.entries) 'ch${e.key}Hours': e.value,
    'temp': ?temp,
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
  follow('follow', 'Łącznik - położenie', 'światło = położenie łącznika'),
  motion('motion', 'Czujka ruchu', 'ruch włącza kanał i odlicza jego wyłączanie po czasie od nowa');

  const InputMode(this.wire, this.label, this.help);

  final String wire;
  final String label;
  final String help;

  static InputMode fromWire(String? v) => values.firstWhere((m) => m.wire == v, orElse: () => momentary);
}

/// Co jest podłączone do wejścia (`kind`, pkt 10.1): ikona i opis stanu w aplikacji, powiadomienia huba.
enum InputKind {
  button('button', 'Przycisk', 'puszczony', 'wciśnięty'),
  switch_('switch', 'Łącznik', 'rozwarty', 'zwarty'),
  contact('contact', 'Kontaktron (drzwi, okno)', 'zamknięte', 'otwarte'),
  motion('motion', 'Czujka ruchu', 'spokój', 'ruch'),
  leak('leak', 'Czujnik zalania', 'sucho', 'zalanie!'),
  other('other', 'Inne', 'nieaktywne', 'aktywne');

  const InputKind(this.wire, this.label, this.offText, this.onText);

  final String wire;
  final String label;

  /// Opis stanu `inN`: nieaktywne / aktywne.
  final String offText;
  final String onText;

  String stateText(bool active) => active ? onText : offText;

  static InputKind fromWire(Object? v) => values.firstWhere((k) => k.wire == v, orElse: () => button);
}

/// `out` / `longOut`: liczba (jeden kanał, 0 = żaden) albo lista kanałów.
List<int> _channelList(Object? v, String field) => switch (v) {
  null => const [],
  final num n => n.toInt() > 0 ? [n.toInt()] : const [],
  final List<Object?> l => [
    for (final x in l)
      if (x is num && x > 0) x.toInt(),
  ],
  _ => throw FormatException('Pole "$field": oczekiwano liczby albo listy'),
};

/// Jeden kanał zawsze jako liczba, kilka jako lista, żaden jako 0 (pkt 10.1).
Object encodeChannels(List<int> outs) => switch (outs) {
  [] => 0,
  [final one] => one,
  _ => outs,
};

/// `chN` w Config.
class ChannelConfig {
  const ChannelConfig({
    required this.name,
    this.defaultOn = DefaultOn.last,
    this.autoOff = 0,
    this.autoOffPress = 'off',
    this.pulse = 0,
    this.minOff = 0,
  });

  final String name;
  final DefaultOn defaultOn;

  /// s (0 = bez): kanał gaśnie sam po tym czasie od włączenia.
  final int autoOff;

  /// `off` - ponowne krótkie naciśnięcie wyłącza; `extend` - odlicza od nowa, długie przytrzymanie wyłącza.
  final String autoOffPress;

  /// ms (0 = zwykły kanał): kanał impulsowy - brama, furtka, elektrozaczep.
  final int pulse;

  /// s: minimalny czas wyłączenia (pompa, sprężarka).
  final int minOff;

  bool get isPulse => pulse > 0;

  factory ChannelConfig.fromJson(Json j, int n) => ChannelConfig(
    name: asString(j['name'], 'ch$n.name', 'Kanał $n'),
    defaultOn: DefaultOn.fromWire(asStringOrNull(j['defaultOn'], 'ch$n.defaultOn')),
    autoOff: asInt(j['autoOff'], 'ch$n.autoOff'),
    autoOffPress: asString(j['autoOffPress'], 'ch$n.autoOffPress', 'off'),
    pulse: asInt(j['pulse'], 'ch$n.pulse'),
    minOff: asInt(j['minOff'], 'ch$n.minOff'),
  );

  Json toJson() => {
    'name': name,
    'defaultOn': defaultOn.wire,
    'autoOff': autoOff,
    'autoOffPress': autoOffPress,
    'pulse': pulse,
    'minOff': minOff,
  };
}

/// `inputK` w Config: wejście przełącza kanały [outs] (pusta = żaden, tylko `inK` dla huba).
class InputConfig {
  const InputConfig({
    required this.name,
    this.mode = InputMode.momentary,
    this.outs = const [],
    this.longOuts = const [],
    this.kind = InputKind.button,
    this.invert = false,
  });

  final String name;
  final InputMode mode;
  final List<int> outs;

  /// Druga funkcja przycisku: długie naciśnięcie (≥ 0,8 s) przełącza te kanały.
  final List<int> longOuts;
  final InputKind kind;

  /// Styk normalnie zamknięty (NC): aktywne = rozwarte.
  final bool invert;

  /// Pierwszy kanał (0 = żaden).
  int get out => outs.isEmpty ? 0 : outs.first;

  factory InputConfig.fromJson(Json j, int k) => InputConfig(
    name: asString(j['name'], 'input$k.name', 'Wejście $k'),
    mode: InputMode.fromWire(asStringOrNull(j['mode'], 'input$k.mode')),
    outs: _channelList(j['out'], 'input$k.out'),
    longOuts: _channelList(j['longOut'], 'input$k.longOut'),
    kind: InputKind.fromWire(j['kind']),
    invert: asBool(j['invert'], 'input$k.invert'),
  );

  Json toJson() => {
    'name': name,
    'mode': mode.wire,
    'kind': kind.wire,
    'out': encodeChannels(outs),
    'longOut': encodeChannels(longOuts),
    'invert': invert,
  };
}

/// Config włącznika / ściemniacza.
class LightConfig {
  const LightConfig({
    required this.name,
    this.defaultOn = DefaultOn.last,
    this.channels = const [],
    this.inputs = const [],
    this.indicatorOn,
    this.indicatorOff,
    this.tempWarn,
    this.tempOff,
  });

  final String name;
  final DefaultOn defaultOn;

  /// `ch1`…`chN` (pusta lista = jeden kanał).
  final List<ChannelConfig> channels;

  /// `input1`…`inputM`.
  final List<InputConfig> inputs;

  /// `indicator`: jasność diod przycisków, % (kanał włączony / wyłączony); null - urządzenie bez diod.
  final int? indicatorOn;
  final int? indicatorOff;

  /// °C: ostrzeżenie / wyłączenie kanałów (0 = wyłączone); null - urządzenie bez tych ustawień.
  final int? tempWarn;
  final int? tempOff;

  bool get hasIndicator => indicatorOn != null || indicatorOff != null;
  bool get hasTempLimits => tempWarn != null || tempOff != null;

  factory LightConfig.fromJson(Json j) {
    final n = asInt(j['channels'], 'channels', 1);
    final m = asInt(j['inputs'], 'inputs', 0);
    final indicator = asObjectOrNull(j['indicator'], 'indicator');
    return LightConfig(
      name: asString(j['name'], 'name'),
      defaultOn: DefaultOn.fromWire(asStringOrNull(j['defaultOn'], 'defaultOn')),
      channels: n > 1
          ? [for (var i = 1; i <= n; i++) ChannelConfig.fromJson(asObjectOrNull(j['ch$i'], 'ch$i') ?? const {}, i)]
          : const [],
      inputs: [
        for (var k = 1; k <= m; k++) InputConfig.fromJson(asObjectOrNull(j['input$k'], 'input$k') ?? const {}, k),
      ],
      indicatorOn: asIntOrNull(indicator?['on'], 'indicator.on'),
      indicatorOff: asIntOrNull(indicator?['off'], 'indicator.off'),
      tempWarn: asIntOrNull(j['tempWarn'], 'tempWarn'),
      tempOff: asIntOrNull(j['tempOff'], 'tempOff'),
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
    if (hasIndicator) 'indicator': {'on': ?indicatorOn, 'off': ?indicatorOff},
    'tempWarn': ?tempWarn,
    'tempOff': ?tempOff,
  };
}

/// Zmiana ustawień jednego kanału (`chN` w Set).
class ChannelPatch {
  const ChannelPatch({
    this.name,
    this.defaultOn,
    this.autoOff,
    this.autoOffPress,
    this.pulse,
    this.minOff,
    this.resetCounters = false,
  });

  final String? name;
  final DefaultOn? defaultOn;
  final int? autoOff;
  final String? autoOffPress;
  final int? pulse;
  final int? minOff;

  /// Zeruje `chNCycles` / `chNHours`.
  final bool resetCounters;

  Json toJson() => {
    'name': ?name,
    'defaultOn': ?defaultOn?.wire,
    'autoOff': ?autoOff,
    'autoOffPress': ?autoOffPress,
    'pulse': ?pulse,
    'minOff': ?minOff,
    if (resetCounters) 'resetCounters': true,
  };
}

/// Zmiana wejścia (`inputK` w Set). Kanały: [out] (jeden, 0 = żaden) albo [outs] (lista).
class InputPatch {
  const InputPatch({this.name, this.mode, int? out, List<int>? outs, this.longOuts, this.kind, this.invert})
    : _out = out,
      _outs = outs;

  final String? name;
  final InputMode? mode;
  final int? _out;
  final List<int>? _outs;
  final List<int>? longOuts;
  final InputKind? kind;
  final bool? invert;

  List<int>? get outs => _outs ?? (_out == null ? null : [if (_out > 0) _out]);

  Json toJson() => {
    'name': ?name,
    'mode': ?mode?.wire,
    if (outs case final o?) 'out': encodeChannels(o),
    if (longOuts case final o?) 'longOut': encodeChannels(o),
    'kind': ?kind?.wire,
    'invert': ?invert,
  };
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
    this.identify = false,
    this.indicatorOn,
    this.indicatorOff,
    this.tempWarn,
    this.tempOff,
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

  /// Dioda na płytce miga 10 s („który to moduł”).
  final bool identify;
  final int? indicatorOn;
  final int? indicatorOff;
  final int? tempWarn;
  final int? tempOff;

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
    if (identify) j['identify'] = true;
    if (indicatorOn != null || indicatorOff != null) j['indicator'] = {'on': ?indicatorOn, 'off': ?indicatorOff};
    putIfNotNull(j, 'tempWarn', tempWarn);
    putIfNotNull(j, 'tempOff', tempOff);
    return j;
  }
}

final lightCodec = DeviceCodec<LightState, LightConfig>(
  state: LightState.fromJson,
  config: LightConfig.fromJson,
  nameOf: (c) => c.name,
  stateToJson: (s) => s.toJson(),
);
