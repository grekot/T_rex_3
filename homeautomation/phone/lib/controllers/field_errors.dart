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
  'outdoor': 'Źródło temperatury na zewnątrz',
  'outdoor.device': 'Źródło temperatury na zewnątrz',
  'outdoor.temp': 'Źródło temperatury na zewnątrz - punkt temperatury',
  'outdoor.hum': 'Źródło temperatury na zewnątrz - punkt wilgotności',
  'news': 'Wiadomości',
  'news.feeds': 'Kanały wiadomości',
  'news.keywords': 'Słowa kluczowe',
  'news.refreshMin': 'Pobieranie wiadomości',
  'news.jumpS': 'Ekran wiadomości',
  'newsRead': 'Wiadomości przeczytane',
  'theme.name': 'Motyw',
  'themePack': 'Paczka motywów',
  'radio': 'Radio',
  'radio.stations': 'Stacje radia',
  'radio.muteOffMin': 'Wyłączenie po wyciszeniu',
  'radio.maxW': 'Moc głośnika',
  'radio.resume': 'Radio po restarcie',
  'radio.showS': 'Ekran radia po włączeniu',
  'radio.eq': 'Korekcja głośnika',
  'screens.holdS': 'Po ręcznej zmianie ekranu',
  'alarms': 'Budziki',
  'alarmStop': 'Wyłączenie budzika',
  'alarmSnooze': 'Drzemka',
  'sleepTimer': 'Wyłącz radio za',
  'radioOn': 'Radio',
  'radioStation': 'Stacja radia',
  'radioVol': 'Głośność radia',
  'radioMute': 'Wyciszenie radia',
  'bubble': 'Dymek',
  'bubble.text': 'Dymek - treść',
  'bubble.title': 'Dymek - tytuł',
  'bubble.icon': 'Dymek - ikona',
  'bubble.sound': 'Dymek - dźwięk',
  'bubble.ttlS': 'Dymek - czas na ekranie',
  'bubble.waitMin': 'Dymek - czekanie',
  'bubble.reply': 'Dymek - odpowiedź',
  'bubble.prio': 'Dymek - priorytet',
  'bubble.id': 'Dymek - id',
  'bubbleCancel': 'Zamknięcie dymku',
  'meeting': 'Spotkanie',
  'bubbles.vol': 'Głośność dymków',
  'bubbles.maxPerDay': 'Dymki na dobę',
  'fun': 'Ciekawostki',
  'fun.perDay': 'Ciekawostki dziennie',
  'fun.window': 'Ciekawostki - godziny',
  'fun.days': 'Ciekawostki - dni',
  'fun.categories': 'Ciekawostki - kategorie',
  'fun.ttlS': 'Ciekawostki - czas na ekranie',
  'fun.sound': 'Ciekawostki - dźwięk',
  'contentPack': 'Paczka ciekawostek',
  'on': 'Włączenie',
  'level': 'Jasność',
  'toggle': 'Przełączenie',
  'defaultOn': 'Po zaniku zasilania',
  'firmwareUrl': 'Adres firmware',
  'firmwareSha256': 'Suma firmware',
  'applyUpdates': 'Aktualizacja węzłów',
  'notify': 'Powiadomienia',
  'notify.enabled': 'Powiadomienia',
  'notify.ntfyTopic': 'Temat ntfy',
  'notify.ntfyServer': 'Serwer ntfy',
  'notify.ntfyToken': 'Token ntfy',
  'notify.test': 'Próbne powiadomienie',
  'identify': 'Pokaż, który to',
  'indicator': 'Diody przycisków',
  'indicator.on': 'Diody przycisków - kanał włączony',
  'indicator.off': 'Diody przycisków - kanał wyłączony',
  'tempWarn': 'Ostrzeżenie o temperaturze',
  'tempOff': 'Wyłączenie przy przegrzaniu',
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
  'sha256' => 'suma pliku się nie zgadza (plik uszkodzony albo podmieniony)',
  'host' => 'niedozwolony adres',
  'busy' => 'trwa inna aktualizacja',
  'overheat' => 'urządzenie przegrzane - włączanie zablokowane do ostygnięcia',
  'too_many' => 'za dużo pozycji',
  'limit' => 'wyczerpany dzienny limit dymków',
  'full' => 'kolejka dymków pełna ważnych wiadomości',
  'space' => 'za mało miejsca w urządzeniu',
  'invalid' => 'plik uszkodzony albo w złym formacie',
  'http' => 'nie udało się pobrać pliku',
  'no_stations' => 'brak stacji radia',
  'state' => 'nie w tej chwili',
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
    'out' => ' - kanały',
    'autoOff' => ' - wyłączanie po czasie',
    'autoOffPress' => ' - ponowne naciśnięcie',
    'pulse' => ' - impuls',
    'minOff' => ' - minimalna przerwa',
    'kind' => ' - rodzaj',
    'longOut' => ' - długie naciśnięcie',
    'invert' => ' - styk NC',
    _ => '',
  };
  final what = m.group(1) == 'in' || m.group(1) == 'input' ? 'Wejście' : 'Kanał';
  return '$what ${m.group(2)}$sub';
}

/// Pola budzików zegara (pkt 10.2): `alarms.0.time` → „Budzik 1 - godzina”.
String? _alarmLabel(String key) {
  final m = RegExp(r'^alarms\.(\d)(?:\.(\w+))?$').firstMatch(key);
  if (m == null) return null;
  final sub = switch (m.group(2)) {
    'on' => ' - włączony',
    'time' => ' - godzina',
    'days' => ' - dni',
    'source' => ' - dźwięk',
    'station' => ' - stacja',
    'vol' => ' - głośność',
    'rampS' => ' - narastanie',
    'snoozeMin' => ' - drzemka',
    _ => '',
  };
  return 'Budzik ${int.parse(m.group(1)!) + 1}$sub';
}

/// Pod kluczem `_` jest kod termostatu (`json`) albo gotowy komunikat aplikacji.
String describeErrors(Map<String, String> errors) => errors.entries
    .map(
      (e) => e.key == '_'
          ? describeErrorCode(e.value)
          : '${fieldLabels[e.key] ?? _channelLabel(e.key) ?? _alarmLabel(e.key) ?? e.key}: ${describeErrorCode(e.value)}',
    )
    .join('\n');
