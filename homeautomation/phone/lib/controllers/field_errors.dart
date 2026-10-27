// Opisy błędów pól Set (kontrakt pkt 3) po polsku - wspólne dla wszystkich typów urządzeń.

/// Polskie nazwy pól Set do komunikatów o błędach.
const fieldLabels = <String, String>{
  'power': 'Zasilanie',
  'target': 'Nastawa',
  'mode': 'Tryb',
  'name': 'Nazwa',
  'comfort': 'Temperatura komfortu',
  'eco': 'Temperatura eko',
  'hystLow': 'Histereza dolna',
  'hystHigh': 'Histereza górna',
  'schedule': 'Harmonogram',
  'schedule.weekday': 'Plan Pn–Pt',
  'schedule.saturday': 'Plan sobota',
  'schedule.sunday': 'Plan niedziela',
  'screen.mode': 'Tryb ekranu',
  'screen.night': 'Pora nocna',
  'screen.timeoutMin': 'Czas wygaszania',
  'light.darkLux': 'Próg ciemności',
  'frost.temp': 'Ochrona przed zamarzaniem',
  'frost.faultDutyMin': 'Grzanie przy awarii czujnika',
  'weather.apiKey': 'Klucz OpenWeatherMap',
  'weather.lat': 'Szerokość geograficzna',
  'weather.lon': 'Długość geograficzna',
  'on': 'Włączenie',
  'level': 'Jasność',
  'toggle': 'Przełączenie',
  'defaultOn': 'Po zaniku zasilania',
  'firmwareUrl': 'Adres firmware',
};

/// Kod błędu pola z termostatu → tekst po polsku.
/// Kody z kontraktu (pkt 3): `type`, `range`, `format`, `value`, `length`, `json`.
String describeErrorCode(String code) => switch (code) {
  'type' => 'zły typ wartości',
  'range' => 'poza zakresem',
  'format' => 'zły format',
  'value' => 'niedozwolona wartość',
  'length' => 'zła długość',
  'json' => 'urządzenie nie zrozumiało danych',
  'forbidden' => 'brak uprawnień',
  '' => 'błąd',
  _ => code,
};

/// Pola kanałów przełącznika (pkt 10.1): `on2`, `toggle3`, `ch2.input`…
String? _channelLabel(String key) {
  final m = RegExp(r'^(on|toggle|in|ch|input)(\d+)(?:\.(\w+))?$').firstMatch(key);
  if (m == null) return null;
  final sub = switch (m.group(3)) {
    'name' => ' - nazwa',
    'defaultOn' => ' - po zaniku zasilania',
    'mode' => ' - tryb',
    'out' => ' - kanał',
    _ => '',
  };
  final what = m.group(1) == 'in' || m.group(1) == 'input' ? 'Wejście' : 'Kanał';
  return '$what ${m.group(2)}$sub';
}

/// Pod kluczem `_` jest kod termostatu (`json`) albo gotowy komunikat aplikacji.
String describeErrors(Map<String, String> errors) => errors.entries
    .map(
      (e) => e.key == '_'
          ? describeErrorCode(e.value)
          : '${fieldLabels[e.key] ?? _channelLabel(e.key) ?? e.key}: ${describeErrorCode(e.value)}',
    )
    .join('\n');
