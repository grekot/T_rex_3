import 'json_utils.dart';

/// Typ urządzenia (kontrakt pkt 0) - mówi aplikacji, jaki kafelek i ekran pokazać.
enum DeviceType {
  thermostat('thermostat', 'Termostat'),
  onOff('switch', 'Włącznik'),
  dimmer('dimmer', 'Ściemniacz'),
  hub('hub', 'Hub'),

  /// Czujnik (np. Bluetooth przez hub, pkt 11): tylko odczyt, punkty z `describe`.
  sensor('sensor', 'Czujnik'),

  /// Bramka Bluetooth (`nodes/btnode`): przekazuje hubowi czujniki Bluetooth i zegarki (pkt 11, 15).
  btnode('btnode', 'Bramka Bluetooth'),

  /// Zegar-termometr biurkowy z ekranem (`nodes/deskclock`, pkt 10.2): pokój, pogoda, strony z widżetami.
  clock('clock', 'Zegar'),
  unknown('', 'Urządzenie');

  const DeviceType(this.wire, this.label);

  /// Wartość `type` w JSON-ie, TXT mDNS i `info/type` w chmurze.
  final String wire;
  final String label;

  /// Brak typu (null) = urządzenie z API 1, czyli termostat. Pusty tekst to zapisany typ nieznany (do 1.6.0 tak
  /// zapisywał się każdy typ spoza listy, np. `btnode`) - nie termostat.
  static DeviceType fromWire(String? v) => switch (v) {
    null || 'thermostat' => thermostat,
    'switch' => onOff,
    'dimmer' => dimmer,
    'hub' => hub,
    'sensor' => sensor,
    'btnode' => btnode,
    'clock' => clock,
    _ => unknown,
  };

  bool get isLight => this == onOff || this == dimmer;
}

/// Jak z JSON-a State/Config zrobić modele danego typu urządzenia.
class DeviceCodec<S, C> {
  const DeviceCodec({required this.state, required this.config, required this.nameOf, required this.stateToJson});

  final S Function(Json json) state;
  final C Function(Json json) config;

  /// Nazwa urządzenia z Config (do listy i kafelków).
  final String Function(C config) nameOf;

  /// State z powrotem jako JSON - widżety pulpitów czytają z niego punkty danych (pkt 14).
  final Json Function(S state) stateToJson;
}

/// Typy bez własnego modelu (hub, przyszłe): State i Config jako surowy JSON.
final rawCodec = DeviceCodec<Json, Json>(
  state: (j) => j,
  config: (j) => j,
  nameOf: (c) => c['name'] is String ? c['name'] as String : '',
  stateToJson: (s) => s,
);
