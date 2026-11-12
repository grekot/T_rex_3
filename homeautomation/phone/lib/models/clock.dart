// Zegar-termometr `clock` (kontrakt pkt 10.2, `nodes/deskclock/PLAN.md` pkt 1.5, 8.6, 9): ekrany, przejścia,
// strony z widżetami (siatka 4×3, tylko stan) - wyliczanie par `device`/`point`, limity, przenoszenie z pulpitu.

import 'dart:convert';

import 'dashboard.dart';
import 'describe.dart';
import 'json_utils.dart';

/// Ekrany wbudowane (`screens.list`), w kolejności proponowanej.
const clockScreens = {
  'main': 'Główny',
  'hours': 'Pogoda co godzinę',
  'days': 'Pogoda na 5 dni',
  'chart': 'Wykres pokoju',
  'calendar': 'Kalendarz',
  'air': 'Powietrze',
  'news': 'Wiadomości',
  'radio': 'Radio',
};

/// Opisy ekranów wbudowanych.
const clockScreenHints = {
  'main': 'godzina, pokój, pogoda teraz, komfort',
  'hours': 'temperatura i opady na najbliższe godziny',
  'days': 'kolejne dni z ikoną i min / max',
  'chart': 'temperatura i wilgotność pokoju z 24 h',
  'calendar': 'data, imieniny, święta, słońce i księżyc, kalendarz domu',
  'air': 'AQI, pyły, pyłki, UV (z huba)',
  'news': 'kanały RSS i ostrzeżenia IMGW',
  'radio': 'stacja, logo, tytuł utworu, głośność (gdy radio gra)',
};

/// Po ręcznej zmianie ekranu pokaz stoi (`screens.holdS`, fw 0.7.3): 0 = do środkowego przycisku.
const clockHoldOptions = {0: 'Do środkowego przycisku', 60: '1 min', 300: '5 min', 900: '15 min', 3600: '1 h'};

const clockTransitions = {
  'cards': 'Karty kaskadą',
  'slide': 'Przesunięcie',
  'cover': 'Nasunięcie',
  'fade': 'Przenikanie',
  'none': 'Bez animacji',
};

const clockNightModes = {
  'off': 'wyłączony',
  'schedule': 'w godzinach',
  'lux': 'według światła',
  'both': 'godziny albo światło',
};

const clockNightScreens = {'clock': 'sama godzina', 'clockTemp': 'godzina i temperatura', 'off': 'wygaszony'};

/// Motyw zegara (`theme.name`, nodes/deskclock/src/GuiTheme.cpp): nazwa i kolory do podglądu w aplikacji -
/// tło, karta, tekst na karcie, kafle pokój / wilgotność / ciśnienie / pogoda. Kolejność jak w kalendarzu `theme.seasonal`;
/// motywy od fw 0.4.0 (`thaw`, `holidays`, `indianSummer`, `gloom`, `advent`, `nicholas`) w kolorach makiet (`LOOKS`).
typedef ClockTheme = ({String label, int bg, int card, int ink, List<int> tiles});

const clockThemes = <String, ClockTheme>{
  'pastel': (
    label: 'Pastel',
    bg: 0xFFEEF1F6,
    card: 0xFFFFFFFF,
    ink: 0xFF1B1F2A,
    tiles: [0xFFFFD8C7, 0xFFD2E6FF, 0xFFE4DCFF, 0xFFFFE9A8],
  ),
  'contrast': (
    label: 'Kontrastowy',
    bg: 0xFFE4E6EA,
    card: 0xFFFFFFFF,
    ink: 0xFF000000,
    tiles: [0xFFFFB08A, 0xFF86BDFF, 0xFFC2B0FF, 0xFFFFD43B],
  ),
  'dark': (
    label: 'Ciemny',
    bg: 0xFF0B0D12,
    card: 0xFF171B24,
    ink: 0xFFF2F4F8,
    tiles: [0xFF3A2219, 0xFF172A45, 0xFF2A2145, 0xFF3A3015],
  ),
  'winter': (
    label: 'Zima',
    bg: 0xFFDCEBF7,
    card: 0xFFFFFFFF,
    ink: 0xFF163150,
    tiles: [0xFFE8F3FB, 0xFFD6EEF3, 0xFFE3E4F6, 0xFFFFFFFF],
  ),
  'winterNight': (
    label: 'Zima (noc)',
    bg: 0xFF0E1B2E,
    card: 0xFF16263D,
    ink: 0xFFEAF4FF,
    tiles: [0xFF1C3150, 0xFF183A44, 0xFF252B52, 0xFF1C3150],
  ),
  'thaw': (
    label: 'Roztopy',
    bg: 0xFFCCCCD2,
    card: 0xFFF0F6F6,
    ink: 0xFF242A30,
    tiles: [0xFFDEC6C0, 0xFFA2B4C0, 0xFFC0BACC, 0xFFD8DEC6],
  ),
  'spring': (
    label: 'Wiosna',
    bg: 0xFFEAF5E4,
    card: 0xFFFFFFFF,
    ink: 0xFF1F3320,
    tiles: [0xFFFCDDE6, 0xFFD5ECF7, 0xFFE9E0FA, 0xFFFFF2B3],
  ),
  'easter': (
    label: 'Wielkanoc',
    bg: 0xFFFFF8E1,
    card: 0xFFFFFFFF,
    ink: 0xFF3A3020,
    tiles: [0xFFFFE0CC, 0xFFDCEFD0, 0xFFEADFF7, 0xFFFFEFA8],
  ),
  'summer': (
    label: 'Lato',
    bg: 0xFFE3F6F7,
    card: 0xFFFFFFFF,
    ink: 0xFF0E3340,
    tiles: [0xFFFFE1C4, 0xFFC9F0F2, 0xFFE2E4FA, 0xFFFFE680],
  ),
  'holidays': (
    label: 'Wakacje',
    bg: 0xFFF0E4D8,
    card: 0xFFDEF0FC,
    ink: 0xFF06243C,
    tiles: [0xFFFCD8B4, 0xFFBADEDE, 0xFFDED2F0, 0xFFFCEAC6],
  ),
  'indianSummer': (
    label: 'Babie lato',
    bg: 0xFFEAE4D8,
    card: 0xFFF6F6F0,
    ink: 0xFF241E1E,
    tiles: [0xFFE4A884, 0xFFA2B4AE, 0xFFC0AEA2, 0xFFEABA6C],
  ),
  'autumn': (
    label: 'Jesień',
    bg: 0xFFF4E7D7,
    card: 0xFFFFFAF2,
    ink: 0xFF3B2414,
    tiles: [0xFFF8D3B5, 0xFFDCE3D0, 0xFFEAD9CF, 0xFFF7DC9C],
  ),
  'gloom': (
    label: 'Szaruga',
    bg: 0xFFCCD2D8,
    card: 0xFFF0F0F6,
    ink: 0xFF242A36,
    tiles: [0xFFDED2CC, 0xFF90A2B4, 0xFFA2A2AE, 0xFFC0CCD8],
  ),
  'advent': (
    label: 'Adwent',
    bg: 0xFF1E243C,
    card: 0xFF2A3654,
    ink: 0xFFFCB466,
    tiles: [0xFF3C2A24, 0xFF1E363C, 0xFF2A1E30, 0xFF242A48],
  ),
  'nicholas': (
    label: 'Mikołajki',
    bg: 0xFFEAEAE4,
    card: 0xFFFCFCFC,
    ink: 0xFF1E2430,
    tiles: [0xFFFCD8BA, 0xFFCCDEF6, 0xFFDED8F6, 0xFFFCE4A8],
  ),
  'xmas': (
    label: 'Boże Narodzenie',
    bg: 0xFF7E1622,
    card: 0xFFFFF8EC,
    ink: 0xFF3A0D12,
    tiles: [0xFFF7DFD2, 0xFFDDEBD7, 0xFFF6E8C4, 0xFFE6F0DA],
  ),
  'xmasNight': (
    label: 'Boże Narodzenie (wieczór)',
    bg: 0xFF0F2A1E,
    card: 0xFF173A2A,
    ink: 0xFFFFF6E2,
    tiles: [0xFF4A1A1F, 0xFF1F4A33, 0xFF4A3B14, 0xFF5E1A22],
  ),
};

/// Format daty na ekranie (`clock.dateFormat`).
const clockDateFormats = {'long': 'środa, 4 listopada', 'short': 'śr 04.11'};

/// Polecenia `showScreen` poza ekranami.
const clockCommands = {
  'next': 'Następny ekran',
  'prev': 'Poprzedni ekran',
  'home': 'Ekran główny',
  'wake': 'Rozjaśnij (noc)',
  'info': 'Ekran informacyjny',
};

// ---------------------------------------------------------------- Wiadomości (Config `news`, pkt 10.2)

const clockMaxFeeds = 6;
const clockMaxKeywords = 16;

/// Zegar z wiadomościami (fw z Config `news`); starszy nie ma pola i ekranu `news`.
bool clockHasNews(Map<String, dynamic>? cfg) => cfg?['news'] is Map;

/// Kanał wiadomości (`news.feeds[]`): RSS / Atom spod [url] albo ostrzeżenia meteo IMGW dla powiatu [imgw]
/// (kod TERYT, 4 cyfry). [alert] - każda nowa pozycja kanału jest ważna.
class ClockFeed {
  const ClockFeed({required this.name, this.url, this.imgw, this.alert = false});

  final String name;
  final String? url;
  final String? imgw;
  final bool alert;

  bool get isImgw => imgw != null;

  ClockFeed copyWith({bool? alert}) => ClockFeed(name: name, url: url, imgw: imgw, alert: alert ?? this.alert);

  Json toJson() => {'name': name, if (imgw != null) 'imgw': imgw else 'url': url, 'alert': alert};

  static List<ClockFeed> listFrom(Object? news) {
    final feeds = news is Map ? news['feeds'] : null;
    return [
      for (final f in (feeds is List ? feeds : const []))
        if (f is Map && f['name'] is String)
          ClockFeed(
            name: f['name'] as String,
            url: f['url'] as String?,
            imgw: f['imgw'] as String?,
            alert: f['alert'] == true,
          ),
    ];
  }
}

int _bytes(String s) => utf8.encode(s).length;

/// Sprawdzenie pól kanału jak `validFeed` w firmware (DeskConfig.cpp); null = dobre.
/// Nazwa skrócona do limitu Config (24 B UTF-8; polska litera to 2 B), bez ucięcia znaku w połowie.
String clockTrimName(String name) {
  var n = name.trim();
  while (_bytes(n) > 24) {
    n = n.substring(0, n.length - 1);
  }
  return n.trimRight();
}

String? clockFeedNameError(String name) =>
    name.trim().isEmpty ? 'Podaj nazwę' : (_bytes(name) > 24 ? 'Najwyżej 24 bajty (polska litera to 2)' : null);

String? clockFeedUrlError(String url) {
  if (!url.startsWith('https://') && !url.startsWith('http://')) return 'Adres zaczyna się od https:// albo http://';
  if (url.length <= 10) return 'Za krótki adres';
  if (RegExp(r'[\x00-\x20]').hasMatch(url)) return 'Adres bez spacji';
  if (_bytes(url) > 256) return 'Najwyżej 256 znaków';
  return null;
}

String? clockTerytError(String code) => RegExp(r'^\d{4}$').hasMatch(code) ? null : 'Kod TERYT powiatu: 4 cyfry';

String? clockKeywordError(String word) =>
    _bytes(word) < 2 ? 'Co najmniej 2 znaki' : (_bytes(word) > 32 ? 'Najwyżej 32 bajty' : null);

/// Kanały sprawdzone na zegarze 2026-11-10 (sesja firmware wiadomości).
const clockNewsSuggestions = <({String name, String url})>[
  (name: 'RMF24', url: 'https://www.rmf24.pl/feed'),
  (name: 'Polsat News', url: 'https://www.polsatnews.pl/rss/wszystkie.xml'),
  (name: 'TVN24', url: 'https://tvn24.pl/najnowsze.xml'),
  (name: 'Onet', url: 'https://wiadomosci.onet.pl/.feed'),
  (name: 'Gazeta Krakowska', url: 'https://gazetakrakowska.pl/rss/gazetakrakowska.xml'),
  (name: 'Wyborcza Kraków', url: 'https://krakow.wyborcza.pl/pub/rss/krakow.xml'),
  (name: 'Bochnianin', url: 'https://bochnianin.pl/feed/'),
  (name: 'Bochnia z bliska', url: 'https://bochniazbliska.pl/feed/'),
];

/// Powiaty małopolskie (TERYT) - nazwy przy kodzie IMGW; inne kody można wpisać.
const clockPowiaty = {
  '1201': 'bocheński',
  '1202': 'brzeski',
  '1203': 'chrzanowski',
  '1204': 'dąbrowski',
  '1205': 'gorlicki',
  '1206': 'krakowski',
  '1207': 'limanowski',
  '1208': 'miechowski',
  '1209': 'myślenicki',
  '1210': 'nowosądecki',
  '1211': 'nowotarski',
  '1212': 'olkuski',
  '1213': 'oświęcimski',
  '1214': 'proszowicki',
  '1215': 'suski',
  '1216': 'tarnowski',
  '1217': 'tatrzański',
  '1218': 'wadowicki',
  '1219': 'wielicki',
  '1261': 'Kraków',
  '1262': 'Nowy Sącz',
  '1263': 'Tarnów',
};

// ---------------------------------------------------------------- Paczki motywów (pkt 10.2 „Paczki motywów”)

const clockThemeIndexUrl = 'https://ha-firmware.web.app/themes/index.json';
const clockContentIndexUrl = 'https://ha-firmware.web.app/content/index.json';

/// Zegar z paczkami motywów: State `themePacks` albo Config `theme.packs`.
bool clockHasThemePacks(Map<String, dynamic>? cfg, Map<String, dynamic>? state) =>
    state?['themePacks'] is List || (cfg?['theme'] is Map && (cfg!['theme'] as Map)['packs'] is List);

/// Paczka motywów (`.dctp`) albo treści (`.dccp`): z indeksu (`url`, `sha256`, `thumb`, `author`) albo zainstalowana
/// (State `themePacks` / `contentPacks`). [items] - motywy (`themes`) albo kategorie (`categories`, z liczbą pozycji).
class ClockPack {
  const ClockPack({
    required this.id,
    required this.name,
    required this.version,
    this.items = const [],
    this.size = 0,
    this.url,
    this.sha256,
    this.author,
    this.thumb,
  });

  final String id;
  final String name;
  final String version;
  final List<({String id, String name, int count})> items;
  final int size;
  final String? url;
  final String? sha256;
  final String? author;
  final String? thumb;

  static ClockPack? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return ClockPack(
      id: j['id'] as String,
      name: j['name'] as String? ?? j['id'] as String,
      version: '${j['version'] ?? ''}',
      items: [
        for (final t in (j['themes'] as List? ?? j['categories'] as List? ?? const []))
          if (t is Map && t['id'] is String)
            (
              id: t['id'] as String,
              name: t['name'] as String? ?? t['id'] as String,
              count: (t['count'] as num?)?.toInt() ?? 0,
            )
          else if (t is String)
            (id: t, name: t, count: 0),
      ],
      size: (j['size'] as num?)?.toInt() ?? 0,
      url: j['url'] as String?,
      sha256: j['sha256'] as String?,
      author: j['author'] as String?,
      thumb: j['thumb'] as String?,
    );
  }

  static List<ClockPack> listFrom(Object? list) => [for (final p in (list is List ? list : const [])) ?fromJson(p)];
}

/// Wersja `a` nowsza od `b` (liczby po kropkach).
bool clockVersionNewer(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// Nazwa motywu do pokazania: wbudowany albo `<paczka>/<motyw>` z zainstalowanych paczek.
String clockThemeLabel(String name, List<ClockPack> packs) {
  final i = name.indexOf('/');
  if (i < 0) return clockThemes[name]?.label ?? clockThemes['pastel']!.label;
  final pack = packs.where((p) => p.id == name.substring(0, i)).firstOrNull;
  final theme = pack?.items.where((t) => t.id == name.substring(i + 1)).firstOrNull;
  return theme == null ? name : '${theme.name} (${pack!.name})';
}

/// „1,4 MB”, „320 KB”.
String clockBytesText(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB'
    : '${(bytes / 1024).round()} KB';

// ---------------------------------------------------------------- Radio (Config `radio`, pkt 10.2 „Radio”)

const clockMaxStations = 12;

/// Zegar z radiem (fw z Config `radio`).
bool clockHasRadio(Map<String, dynamic>? cfg) => cfg?['radio'] is Map;

/// Zegar z ekranem `radio` (fw 0.6.0: Config `radio.showS`, `stations[].logo`).
bool clockHasRadioScreen(Map<String, dynamic>? cfg) =>
    cfg?['radio'] is Map && (cfg!['radio'] as Map).containsKey('showS');

/// Stacja radia (`radio.stations[]`): nazwa 1-24 B, strumień MP3 http/https, logo (adres PNG/JPG, '' = bez logo).
typedef ClockStation = ({String name, String url, String logo});

List<ClockStation> clockStationsFrom(Object? radio) {
  final s = radio is Map ? radio['stations'] : null;
  return [
    for (final x in (s is List ? s : const []))
      if (x is Map && x['name'] is String && x['url'] is String)
        (name: x['name'] as String, url: x['url'] as String, logo: x['logo'] is String ? x['logo'] as String : ''),
  ];
}

/// Stacja do Config: `logo` tylko, gdy jest (starszy firmware zna tylko `name` i `url`).
Map<String, dynamic> clockStationJson(ClockStation s) => {
  'name': s.name,
  'url': s.url,
  if (s.logo.isNotEmpty) 'logo': s.logo,
};

/// Adres logo: pusty (bez logo) albo jak adres strumienia.
String? clockLogoUrlError(String url) => url.isEmpty ? null : clockFeedUrlError(url);

/// Ostrzeżenie dla formatów, których zegar nie zdekoduje (pokaże inicjały): SVG, WebP, ICO, GIF.
String? clockLogoWarning(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  for (final ext in ['.svg', '.webp', '.ico', '.gif']) {
    if (path.endsWith(ext)) return 'Zegar czyta tylko PNG i JPG (do 64 KB) - ten plik pokaże jako inicjały';
  }
  return null;
}

/// Korekcja głośnika (`radio.eq`, fw 0.7.1): nazwa i opis.
const clockRadioEq = {'off': 'Wyłączona', 'music': 'Muzyka', 'voice': 'Mowa'};
const clockRadioEqHints = {
  'off': 'Pełne pasmo - mały głośnik i tak nie odda basu, a bas zabiera moc',
  'music': 'Bez najniższego basu (poniżej ok. 120 Hz) i pełniejsze brzmienie (podbicie ok. 300 Hz)',
  'voice': 'Mocniej odcięty bas (poniżej 300 Hz) i wyraźniejsza mowa (+4 dB przy 3 kHz) - wiadomości, audycje',
};

const clockRadioPressWarning = 'Dwuklik / przytrzymanie na zegarze steruje radiem - zadziała jedno i drugie';

/// Wyzwalacz `double`/`long` na przycisku `in1`-`in3` zegara z radiem - zegar zrobi też swoje (stacja, głośność).
bool clockPressCollides(Map<String, dynamic>? clockCfg, Map<String, dynamic> trigger) =>
    clockHasRadio(clockCfg) &&
    RegExp(r'^in[1-3]$').hasMatch('${trigger['input']}') &&
    (trigger['press'] == 'double' || trigger['press'] == 'long');

// ---------------------------------------------------------------- Dymki i ciekawostki (pkt 10.2)

/// Zegar z dymkami: Config `bubbles` (firmware z dymkami, spotkaniem i ciekawostkami).
bool clockHasBubbles(Map<String, dynamic>? cfg) => cfg?['bubbles'] is Map;

/// Ikony dymków - klucze z firmware zegara (`tools/gen_state_icons.py`), w aplikacji z katalogu `appIcons`.
const clockBubbleIcons = [
  'chat',
  'food',
  'bell',
  'door',
  'laundry',
  'rain',
  'meeting',
  'phone',
  'info',
  'warning',
  'heart',
  'smile',
  'calendar',
  'quote',
  'puzzle',
  'book',
];

const clockBubbleSounds = {
  'chime': 'Dzwonek',
  'pop': 'Pyknięcie',
  'gong': 'Gong',
  'alarm': 'Alarm',
  'none': 'Bez dźwięku',
};

/// `id` dymku: `[a-z0-9-]{1,24}`, bez zarezerwowanego `fun`.
String? clockBubbleIdError(String id) => !RegExp(r'^[a-z0-9-]{1,24}$').hasMatch(id)
    ? 'Małe litery bez polskich znaków, cyfry i „-”, do 24 znaków'
    : (id == 'fun' ? '„fun” jest zarezerwowane dla ciekawostek' : null);

String? clockBubbleTextError(String text) =>
    text.trim().isEmpty ? 'Wpisz treść' : (_bytes(text) > 200 ? 'Najwyżej 200 bajtów (polska litera to 2)' : null);

String? clockBubbleTitleError(String title) => _bytes(title) > 32 ? 'Najwyżej 32 bajty' : null;

String? clockBubbleReplyError(String reply) => _bytes(reply) > 24 ? 'Najwyżej 24 bajty' : null;

/// Opis dymku do listy akcji: „Obiad gotowy!” (odpowiedź „Idę!”).
String clockBubbleText(Map bubble) {
  final title = bubble['title'] is String && (bubble['title'] as String).isNotEmpty ? '${bubble['title']}: ' : '';
  final reply = bubble['reply'] is String ? ' (odpowiedź „${bubble['reply']}”)' : '';
  return '„$title${bubble['text'] ?? ''}”$reply${bubble['prio'] == 'high' ? ', ważny' : ''}';
}

/// Id dymków z akcji `{"device": clockId, "set": {"bubble": {"id"}}}` (także w blokach „Jeśli…”) - podpowiedzi
/// do wyzwalacza `bubbleReply`.
Set<String> clockBubbleIds(Iterable<Map> actions, String clockId) => {
  for (final a in actions) ...[
    if (a['device'] == clockId && a['set'] is Map && (a['set'] as Map)['bubble'] is Map)
      '${((a['set'] as Map)['bubble'] as Map)['id'] ?? 'msg'}',
    for (final key in ['then', 'else'])
      if (a[key] is List) ...clockBubbleIds((a[key] as List).whereType<Map>(), clockId),
  ],
};

const clockFunTtl = [10, 20, 30, 60, 120, 300, 600];

const clockMeetingMinutes = [15, 30, 45, 60, 90, 120, 180, 240];

const clockMaxScreens = 12; // fw zegara od 0.6.3 (wcześniej 6)
const clockMaxPages = 4;
const clockMaxWidgets = 10;
const clockMaxPairs = 24;
const clockMaxPagesBytes = 6144;
const clockCols = 4;
const clockRows = 3;

/// Widoki, które zegar rysuje (pkt 10.2) - sterujące jako stan, `scene` i `gate` bez czujnika pominięte.
const clockViews = {
  WidgetView.value,
  WidgetView.status,
  WidgetView.valueList,
  WidgetView.level,
  WidgetView.gauge,
  WidgetView.chart,
  WidgetView.thermostat,
  WidgetView.group,
  WidgetView.room,
  WidgetView.hub,
};

/// Widok na zegarze dla widoku z telefonu; null = pomijany.
WidgetView? clockViewFor(DashWidget w) => switch (w.view) {
  final v when clockViews.contains(v) => v,
  WidgetView.toggle => WidgetView.status,
  WidgetView.slider || WidgetView.stepper || WidgetView.dial => WidgetView.value,
  WidgetView.gate when w.sensor != null => WidgetView.status,
  WidgetView.weather => WidgetView.value,
  _ => null,
};

/// Nazwa ekranu: wbudowany albo strona `page:<id>`.
String clockScreenName(String key, List<ClockPage> pages) {
  if (key.startsWith('page:')) {
    final p = pages.where((p) => 'page:${p.id}' == key).firstOrNull;
    return p == null ? 'Strona (usunięta)' : 'Strona: ${p.title}';
  }
  return clockScreens[key] ?? clockCommands[key] ?? key;
}

/// Strona z widżetami (`pages[]`).
class ClockPage {
  const ClockPage({required this.id, required this.title, this.widgets = const []});

  final String id;
  final String title;
  final List<DashWidget> widgets;

  ClockPage copyWith({String? title, List<DashWidget>? widgets}) =>
      ClockPage(id: id, title: title ?? this.title, widgets: widgets ?? this.widgets);

  static List<ClockPage> listFrom(Object? config) {
    final pages = config is Map ? config['pages'] : null;
    return [
      for (final p in (pages is List ? pages : const []))
        if (p is Map && p['id'] is String)
          ClockPage(
            id: p['id'] as String,
            title: p['title'] is String ? p['title'] as String : 'Strona',
            widgets: [
              for (final w in (p['widgets'] is List ? p['widgets'] as List : const []))
                if (w is Map && w['id'] is String) DashWidget.fromJson(w.cast<String, dynamic>()),
            ],
          ),
    ];
  }

  Json toJson() => {
    'id': id,
    'title': title,
    'widgets': [for (final w in widgets) clockWidgetJson(w)],
  };
}

/// Pola widżetu, które zegar rozumie (reszta z pulpitu - np. `size`, `tap`, `features` - nie trafia do Config).
const _clockKeys = {
  'id', 'view', 'device', 'point', 'points', 'items', 'series', 'members', 'x', 'y', 'w', 'h', 'label', //
  'unit', 'decimals', 'labels', 'min', 'max', 'zones', 'color', 'icon', 'range',
};

Json clockWidgetJson(DashWidget w) => {
  for (final e in w.toJson().entries)
    if (_clockKeys.contains(e.key) && e.value != null) e.key: e.value,
};

/// Pary `device`/`point` widżetu (z `point`, `points`, `items`, `series`, `members`) - jak `Wants.cpp` zegara.
Iterable<(String, String)> clockWidgetPairs(DashWidget w) sync* {
  final d = w.device;
  if (d != null) {
    if (w.point != null) yield (d, w.point!);
    for (final p in w.points ?? const <String>[]) {
      yield (d, p);
    }
  }
  for (final i in w.items) {
    yield (i.device, i.point);
  }
  for (final s in w.series) {
    yield (s.device, s.point);
  }
  for (final m in w.members) {
    yield (m.device, m.point);
  }
}

/// Wszystkie różne pary ze stron.
Set<(String, String)> clockPairs(Iterable<ClockPage> pages) => {
  for (final p in pages)
    for (final w in p.widgets) ...clockWidgetPairs(w),
};

/// Rozmiar `pages` w Config (bajty JSON-a, limit 6 kB).
int clockPagesBytes(List<ClockPage> pages) => utf8.encode(jsonEncode([for (final p in pages) p.toJson()])).length;

/// Problemy przed zapisem stron (jak zegar: `pages: too_many|length`, `pages.<id>.<wid>: view|value`).
List<String> clockPagesProblems(List<ClockPage> pages) {
  final out = <String>[
    if (pages.length > clockMaxPages) 'Najwyżej $clockMaxPages strony.',
    for (final p in pages)
      if (p.widgets.length > clockMaxWidgets) 'Strona „${p.title}”: najwyżej $clockMaxWidgets widżetów.',
  ];
  final pairs = clockPairs(pages).length;
  if (pairs > clockMaxPairs) out.add('Za dużo odczytów: $pairs (najwyżej $clockMaxPairs różnych punktów).');
  final bytes = clockPagesBytes(pages);
  if (bytes > clockMaxPagesBytes) out.add('Strony zajmują ${(bytes / 1024).toStringAsFixed(1)} kB (najwyżej 6 kB).');
  for (final p in pages) {
    for (final w in p.widgets) {
      if (!clockViews.contains(w.view)) out.add('„${w.label ?? w.id}”: zegar nie pokazuje widoku ${w.view.label}.');
      final x = w.x ?? 0, y = w.y ?? 0;
      if (x < 0 || y < 0 || x + clockW(w) > clockCols || y + clockH(w) > clockRows) {
        out.add('„${w.label ?? w.id}”: poza siatką 4×3.');
      }
    }
  }
  return out;
}

/// Szerokość i wysokość widżetu na zegarze (bez `w` / `h` - 1).
int clockW(DashWidget w) => (w.w ?? 1).clamp(1, clockCols);
int clockH(DashWidget w) => (w.h ?? 1).clamp(1, clockRows);

/// Zajęte komórki siatki 4×3 przez widżety z pozycją.
List<List<bool>> _occupied(Iterable<DashWidget> widgets) {
  final grid = List.generate(clockRows, (_) => List.filled(clockCols, false));
  for (final w in widgets) {
    final x = w.x, y = w.y;
    if (x == null || y == null) continue;
    for (var r = y; r < y + clockH(w) && r < clockRows; r++) {
      for (var c = x; c < x + clockW(w) && c < clockCols; c++) {
        if (r >= 0 && c >= 0) grid[r][c] = true;
      }
    }
  }
  return grid;
}

/// Pierwsze wolne miejsce na widżet [w]×[h] (od lewej, z góry) albo null.
(int, int)? clockFreeSpot(Iterable<DashWidget> widgets, int w, int h) {
  final grid = _occupied(widgets);
  for (var y = 0; y + h <= clockRows; y++) {
    for (var x = 0; x + w <= clockCols; x++) {
      var free = true;
      for (var r = y; r < y + h && free; r++) {
        for (var c = x; c < x + w; c++) {
          if (grid[r][c]) {
            free = false;
            break;
          }
        }
      }
      if (free) return (x, y);
    }
  }
  return null;
}

/// Widżety z pulpitu telefonu na strony zegara: widoki wg [clockViewFor] (sceny i sterowanie bez stanu pomijane),
/// rozmiar przycięty do 4×3, po kolei na pierwsze wolne miejsce; nowa strona, gdy się nie mieści albo po 10.
/// Zwraca strony i nazwy pominiętych.
({List<ClockPage> pages, List<String> skipped}) clockPagesFromDashboard(
  List<DashWidget> widgets, {
  required String title,
  required String Function() newId,
}) {
  final pages = <ClockPage>[];
  final skipped = <String>[];
  var current = <DashWidget>[];
  void flush() {
    if (current.isEmpty) return;
    final n = pages.length + 1;
    pages.add(ClockPage(id: newId(), title: n == 1 ? title : '$title $n', widgets: current));
    current = [];
  }

  for (final w in widgets) {
    final view = clockViewFor(w);
    final noData = w.device == null && w.room == null && w.items.isEmpty && w.members.isEmpty && w.series.isEmpty;
    if (view == null || noData) {
      skipped.add(w.label ?? w.view.label);
      continue;
    }
    // Sterowanie bez stanu (brama z czujnikiem) - stan z czujnika.
    var cw = w.view == WidgetView.gate && w.sensor != null
        ? DashWidget(id: w.id, view: view, device: w.sensor!.device, point: w.sensor!.point, label: w.label)
        : w.copyWith(view: view);
    final gw = w.gridW.clamp(1, clockCols), gh = (w.gridH > clockRows ? clockRows : w.gridH).clamp(1, clockRows);
    cw = cw.patch({'x': null, 'y': null, 'section': null, 'w': gw, 'h': gh});
    var spot = current.length >= clockMaxWidgets ? null : clockFreeSpot(current, gw, gh);
    if (spot == null) {
      flush();
      spot = (0, 0);
    }
    current.add(cw.patch({'x': spot.$1, 'y': spot.$2}));
  }
  flush();
  return (pages: pages, skipped: skipped);
}

/// Punkty czujnika na zewnątrz (Config `outdoor`, pkt 10.2): temperatura (°C) i wilgotność (%) z `describe`.
List<DataPoint> clockOutdoorTempPoints(List<DataPoint> points) => [
  for (final p in points)
    if (p.kind == PointKind.sensor && p.unit == '°C') p,
];

List<DataPoint> clockOutdoorHumPoints(List<DataPoint> points) => [
  for (final p in points)
    if (p.kind == PointKind.sensor && p.unit == '%') p,
];

/// Config `outdoor` po wyborze urządzenia: punkt `temp` (gdy jest, inaczej pierwszy °C), `hum` (gdy jest, inaczej
/// pierwszy %, bez wilgotności - `""`).
Json clockOutdoorFor(String device, List<DataPoint> points) {
  String pick(List<DataPoint> list, String def, String none) =>
      list.any((p) => p.key == def) ? def : list.firstOrNull?.key ?? none;
  return {
    'device': device,
    'temp': pick(clockOutdoorTempPoints(points), 'temp', 'temp'),
    'hum': pick(clockOutdoorHumPoints(points), 'hum', ''),
  };
}

/// Domyślne punkty widżetów bez `point` (pkt 10.2): termostat i hub.
const clockThermostatPoints = ['temp', 'target', 'heating', 'mode'];
const clockHubPoints = ['online', 'devices', 'lastRun'];

/// Kolory kafli stylu C (makieta „C · Strona z widżetami”): tło, etykieta, wartość.
const clockTileColors = {
  'amber': (0xFFFFD8C7, 0xFF8A3A17, 0xFF5C2108),
  'blue': (0xFFD2E6FF, 0xFF1F5FAD, 0xFF0F3A70),
  'green': (0xFFCDEFD9, 0xFF1E6B3F, 0xFF0E3D22),
  'red': (0xFFFFD3DD, 0xFF9A2848, 0xFF5E1028),
  'purple': (0xFFE4DCFF, 0xFF5B3FB8, 0xFF33207A),
  'grey': (0xFFE3E6EC, 0xFF5A6275, 0xFF1B1F2A),
};

// ---------------------------------------------------------------- Budzik (fw 0.8.0, pkt 10.2 „Menu i budzik”)

/// Budzik z Config `alarms` (zawsze 2). `days` - dni ISO 1-7, pusta lista = jednorazowo.
class ClockAlarm {
  const ClockAlarm({
    this.on = false,
    this.time = '06:30',
    this.days = const [1, 2, 3, 4, 5],
    this.source = 'tone',
    this.station = '',
    this.vol = 50,
    this.rampS = 30,
    this.snoozeMin = 9,
  });

  factory ClockAlarm.fromJson(Object? j) {
    if (j is! Map) return const ClockAlarm();
    return ClockAlarm(
      on: j['on'] == true,
      time: j['time'] is String ? j['time'] as String : '06:30',
      days: j['days'] is List
          ? [
              for (final d in j['days'] as List)
                if (d is num) d.toInt(),
            ]
          : const [],
      source: j['source'] == 'radio' ? 'radio' : 'tone',
      station: j['station'] is String ? j['station'] as String : '',
      vol: (j['vol'] as num?)?.toInt() ?? 50,
      rampS: (j['rampS'] as num?)?.toInt() ?? 30,
      snoozeMin: (j['snoozeMin'] as num?)?.toInt() ?? 9,
    );
  }

  final bool on;
  final String time;
  final List<int> days;
  final String source, station;
  final int vol, rampS, snoozeMin;

  /// „6:30” bez zera wiodącego godziny.
  String get timeText => time.startsWith('0') && time.length == 5 ? time.substring(1) : time;
}

/// Budziki z Config; null = zegar bez budzika (fw starszy niż 0.8.0).
List<ClockAlarm>? clockAlarms(Map<String, dynamic>? cfg) {
  final a = cfg?['alarms'];
  if (a is! List) return null;
  return [for (var i = 0; i < 2; i++) ClockAlarm.fromJson(i < a.length ? a[i] : null)];
}

const clockWeekdays = ['pn', 'wt', 'śr', 'cz', 'pt', 'so', 'nd'];

/// „pn–pt”, „weekend”, „codziennie”, „jednorazowo”, „pn, śr, pt” (jak zegar: alarmDaysText).
String clockAlarmDays(List<int> days) {
  final s = {...days};
  if (s.isEmpty) return 'jednorazowo';
  if (s.length == 7) return 'codziennie';
  if (s.length == 5 && s.containsAll(const [1, 2, 3, 4, 5])) return 'pn–pt';
  if (s.length == 2 && s.containsAll(const [6, 7])) return 'weekend';
  return [
    for (var d = 1; d <= 7; d++)
      if (s.contains(d)) clockWeekdays[d - 1],
  ].join(', ');
}

const clockAlarmDayPresets = {
  'Pn–Pt': [1, 2, 3, 4, 5],
  'Weekend': [6, 7],
  'Codziennie': [1, 2, 3, 4, 5, 6, 7],
};
const clockAlarmRamps = {0: 'Od razu', 15: '15 s', 30: '30 s', 45: '45 s', 60: '60 s', 90: '90 s', 120: '120 s'};
const clockAlarmSnoozes = {5: '5 min', 9: '9 min', 10: '10 min', 15: '15 min', 20: '20 min', 30: '30 min'};

/// Wyłącznik czasowy radia (Set `sleepTimer`, minuty).
const clockSleepOptions = {15: '15 min', 30: '30 min', 60: '60 min', 90: '90 min'};

/// „16:22” z czasu unix (s), czas lokalny telefonu.
String clockHm(num unix) {
  final t = DateTime.fromMillisecondsSinceEpoch(unix.toInt() * 1000);
  return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}

/// „dziś 6:30”, „jutro 6:30”, „pn 6:30” względem [now].
String clockWhen(num unix, DateTime now) {
  final t = DateTime.fromMillisecondsSinceEpoch(unix.toInt() * 1000);
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final hm = clockHm(unix);
  if (days == 0) return 'dziś $hm';
  if (days == 1) return 'jutro $hm';
  return '${clockWeekdays[t.weekday - 1]} $hm';
}
