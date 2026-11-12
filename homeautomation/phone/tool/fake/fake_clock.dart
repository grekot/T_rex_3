part of 'fake_thermostat_server.dart';

/// Zegar-termometr (type `clock`, kontrakt pkt 10.2, `nodes/deskclock`): pokój, pogoda, ekrany, noc, strony
/// z widżetami. Węzeł klasy B - bez własnej chmury (`cloudCapable = false`), parowanie kodem z ekranu.
class FakeClock extends FakeDevice {
  FakeClock({
    super.id = 'zegar-ab12cd',
    String name = 'Biurko',
    super.fw = '0.1.0-fake',
    super.token,
    super.statePeriod,
    super.clock,
    super.log,
    super.random,
    this.lux = false,
    this.warmup = false,
    bool withNews = true,
    bool withRadio = true,
    bool withThemePacks = true,
    bool withBubbles = true,
  }) : _name = name,
       bubbles = withBubbles ? {'vol': 30, 'maxPerDay': 30} : null,
       fun = withBubbles
           ? {
               'enabled': true,
               'perDay': 3,
               'window': '09:00-20:00',
               'days': [1, 2, 3, 4, 5, 6, 7],
               'categories': <dynamic>[],
               'ttlS': 60,
               'sound': 'pop',
             }
           : null,
       contentPacks = withBubbles
           ? [
               {
                 'id': 'wbudowane',
                 'version': '1.0.0',
                 'name': 'Wbudowane',
                 'size': 0,
                 'categories': [
                   {'id': 'swieta', 'name': 'Święta dnia', 'count': 120},
                   {'id': 'zagadki', 'name': 'Zagadki', 'count': 40},
                   {'id': 'cytaty', 'name': 'Cytaty', 'count': 60},
                 ],
               },
             ]
           : null,
       news = withNews
           ? {
               'feeds': <dynamic>[],
               'keywords': ['pilne', 'alarm', 'ostrzeżenie', 'ewakuacja'],
               'refreshMin': 10,
               'jumpS': 60,
             }
           : null,
       radio = withRadio
           ? {'stations': <dynamic>[], 'muteOffMin': 10, 'maxW': 0.8, 'resume': false, 'showS': 10, 'eq': 'music'}
           : null,
       themePacks = withThemePacks ? [] : null {
    cloudCapable = false;
    wifiApSupported = true;   // zegar fw 0.7.0: punkt sieci mesh (pkt 9.6)
  }

  /// Radio (`radio`); null = zegar bez radia. Stan: [radioOn], [radioMute], [radioVol], [radioStation].
  Map<String, dynamic>? radio;
  bool radioOn = false, radioMute = false;
  int radioVol = 40;
  String? radioStation;

  /// Zainstalowane paczki motywów (State `themePacks`); null = zegar bez paczek.
  List<Map<String, dynamic>>? themePacks;
  int themeFree = 5800000;
  Map<String, dynamic>? themeInstall;

  /// Pliki paczek pod adresem (`themePack.install.url`) - opis paczki jak w State `themePacks`.
  final packFiles = <String, Map<String, dynamic>>{};

  List<dynamic> get _stations => radio?['stations'] as List? ?? const [];

  String _name;

  /// Czujnik światła BH1750 (pole `lux`, tryb nocny `lux|both`).
  final bool lux;
  bool warmup;
  bool sensorFault = false;
  double temp = 21.4, hum = 46, press = 1016;
  String screen = 'main';

  /// Przyciski lewy, środkowy, prawy (`in1`-`in3`).
  final buttons = [false, false, false];

  Map<String, dynamic> screens = {
    'list': ['main', 'hours', 'days', 'chart'],
    'intervalS': 15,
    'mainFactor': 2,
    'transition': 'cards',
    'holdS': 0,
  };
  Map<String, dynamic> display = {'brightness': 80, 'auto': true, 'rotation': 0};
  Map<String, dynamic> night = {
    'mode': 'schedule',
    'window': '23:00-06:30',
    'darkLux': 5,
    'brightness': 3,
    'screen': 'clock',
  };
  Map<String, dynamic> clockCfg = {'seconds': false, 'dateFormat': 'long'};
  Map<String, dynamic> units = {'temp': 'C', 'press': 'hPa', 'wind': 'kmh'};
  Map<String, dynamic> weather = {'lat': 49.894, 'lon': 20.609, 'place': 'Kraków'};
  Map<String, dynamic> sensor = {'tempOffset': 0.0, 'humOffset': 0, 'comp': true};
  List<dynamic> pages = [];

  /// Czujnik na zewnątrz (`outdoor`): null = temperatura z Open-Meteo.
  Map<String, dynamic>? outdoor;

  /// Wiadomości (`news`); null = zegar sprzed tej funkcji (bez pola i ekranu `news`).
  Map<String, dynamic>? news;
  int newsUnread = 0;
  int wantsVer = 1;
  int identifies = 0;

  /// Odczyty od huba (`ext`): para `device/point` → `v`.
  final ext = <String, Object?>{};

  @override
  String get typeWire => 'clock';

  @override
  String get deviceName => _name;

  @override
  Map<String, Object?> get extraInfo => {'fwId': 'deskclock-n16r8'};

  String get _comfort => hum < 35
      ? 'sucho'
      : hum > 60
      ? 'wilgotno'
      : temp < 19
      ? 'chłodno'
      : temp > 25
      ? 'ciepło'
      : 'komfort';

  /// Temperatura z czujnika na zewnątrz (odczyt `ext`), null = pogoda.
  num? get _outSensor {
    final o = outdoor;
    final v = o == null ? null : ext['${o['device']}/${o['temp']}'];
    return v is num ? v : null;
  }

  @override
  Map<String, dynamic> stateJson() => {
    'id': id,
    'ts': _clock().millisecondsSinceEpoch ~/ 1000,
    'temp': warmup || sensorFault ? null : temp,
    'hum': sensorFault ? null : hum,
    'press': press,
    if (lux) 'lux': 120.0,
    'sensorFault': sensorFault,
    'warmup': warmup,
    'outTemp': _outSensor ?? 9.1,
    'outdoor': _outSensor == null
        ? {'temp': 9.1, 'src': 'weather', 'icon': 2, 'day': true, 'age': 600}
        : {'temp': _outSensor, 'src': 'sensor', 'hum': ext['${outdoor!['device']}/${outdoor!['hum']}'], 'age': 0},
    'night': false,
    'brightness': display['brightness'],
    'screen': screen,
    'comfort': _comfort,
    for (final (i, b) in buttons.indexed) 'in${i + 1}': b,
    'tempRaw': temp + 1.8,
    'humRaw': hum - 4,
    'chipTemp': 41.0,
    'wantsVer': wantsVer,
    'uptime': 3600,
    if (news != null) 'newsUnread': newsUnread,
    if ((news?['feeds'] as List?)?.isNotEmpty ?? false)
      'news': {'items': 8 * (news!['feeds'] as List).length, 'age': 120, 'errors': <dynamic>[], 'alert': null},
    if (_stations.isNotEmpty) ...{
      'radioOn': radioOn,
      'radioMute': radioMute,
      'radioVol': radioVol,
      'radioStation': radioStation,
      'radio': {
        'state': radioOn ? 'playing' : 'off',
        'title': null,
        'codec': radioOn ? 'MP3' : null,
        'kbps': radioOn ? 128 : null,
        'error': null,
        'buffer': radioOn ? 80 : 0,
        'logo': _logoOf(radioStation) == null ? 'none' : 'ok',
      },
    },
    if (themePacks != null) ...{'themePacks': themePacks, 'themeFree': themeFree},
    if (themeInstall != null) 'themeInstall': themeInstall,
    if (bubbles != null) ...{
      'meeting': meetingUntil != null,
      'meetingUntil': meetingUntil == 0 ? null : meetingUntil,
      'bubbleReply': bubbleReply,
      'bubble': bubbleShown.isEmpty ? null : {'id': bubbleShown.last['id'] ?? 'msg', 'source': 'set', 'since': 0},
      'bubbleQueue': 0,
      'fun': {'today': 1, 'next': null},
      'contentPacks': contentPacks,
    },
  };

  @override
  Map<String, dynamic> configJson() => {
    'name': _name,
    'screens': screens,
    'display': display,
    'night': night,
    'clock': clockCfg,
    'units': units,
    'weather': weather,
    'sensor': sensor,
    'pages': pages,
    'outdoor': outdoor,
    if (news != null) 'news': news,
    if (radio != null) 'radio': radio,
    if (bubbles != null) ...{'bubbles': bubbles, 'fun': fun},
  };

  /// Dymki (`bubbles`, `fun`); null = zegar sprzed dymków.
  Map<String, dynamic>? bubbles, fun;
  List<Map<String, dynamic>>? contentPacks;

  /// Przyjęte dymki (ostatni na wierzchu), odpowiedź z dymka (`bubbleReply`), koniec spotkania (0 = do wyłączenia).
  final bubbleShown = <Map<String, dynamic>>[];
  String? bubbleReply;
  int? meetingUntil;

  /// Set dymków, spotkania i ciekawostek (pkt 10.2 „Dymki i ciekawostki”).
  void _applyBubbles(Map<String, dynamic> v, Map<String, String> errors) {
    int bytes(Object? s) => s is String ? utf8.encode(s).length : -1;
    if (v['bubble'] case final Object b) {
      if (bubbles == null) {
        errors['bubble'] = 'unknown';
      } else if (b is! Map) {
        errors['bubble'] = 'value';
      } else {
        final e = {
          if (bytes(b['text']) < 1 || bytes(b['text']) > 200) 'bubble.text': 'length',
          if (b.containsKey('title') && bytes(b['title']) > 32) 'bubble.title': 'length',
          if (b.containsKey('reply') && (bytes(b['reply']) < 1 || bytes(b['reply']) > 24)) 'bubble.reply': 'length',
          if (b.containsKey('sound') && !const {'chime', 'pop', 'gong', 'alarm', 'none'}.contains(b['sound']))
            'bubble.sound': 'value',
          if (b.containsKey('ttlS') && !_num(b['ttlS'], 5, 3600)) 'bubble.ttlS': 'range',
          if (b.containsKey('waitMin') && !_num(b['waitMin'], 0, 720)) 'bubble.waitMin': 'range',
          if (b.containsKey('prio') && !const {'normal', 'high'}.contains(b['prio'])) 'bubble.prio': 'value',
          if (b.containsKey('id') && (!RegExp(r'^[a-z0-9-]{1,24}$').hasMatch('${b['id']}') || b['id'] == 'fun'))
            'bubble.id': 'value',
        };
        final normal = bubbleShown.where((x) => x['prio'] != 'high').length;
        if (e.isNotEmpty) {
          errors.addAll(e);
        } else if (b['prio'] != 'high' && normal >= ((bubbles!['maxPerDay'] as num?) ?? 30)) {
          errors['bubble'] = 'limit';
        } else {
          bubbleShown.add(b.cast<String, dynamic>());
        }
      }
    }
    if (v['bubbleCancel'] is String) {
      bubbleShown.removeWhere((x) => v['bubbleCancel'] == '*' || x['id'] == v['bubbleCancel']);
    }
    if (v.containsKey('meeting')) {
      final m = v['meeting'];
      if (bubbles == null) {
        errors['meeting'] = 'unknown';
      } else if (m == true) {
        meetingUntil = 0;
      } else if (m == false) {
        meetingUntil = null;
      } else if (_num(m, 1, 720)) {
        meetingUntil = _clock().millisecondsSinceEpoch ~/ 1000 + (m as num).toInt() * 60;
      } else {
        errors['meeting'] = 'range';
      }
    }
    if (v['bubbles'] case final Map b) {
      if (b.containsKey('vol') && !_num(b['vol'], 0, 100)) {
        errors['bubbles.vol'] = 'range';
      } else if (b.containsKey('maxPerDay') && !_num(b['maxPerDay'], 1, 200)) {
        errors['bubbles.maxPerDay'] = 'range';
      } else if (bubbles != null) {
        bubbles = {...bubbles!, ...b.cast<String, dynamic>()};
      }
    }
    if (v['fun'] case final Map f) {
      final w = RegExp(r'^(\d\d):(\d\d)-(\d\d):(\d\d)$').firstMatch('${f['window'] ?? '09:00-20:00'}');
      final e = {
        if (f.containsKey('perDay') && !_num(f['perDay'], 1, 12)) 'fun.perDay': 'range',
        if (w == null || '${w[1]}${w[2]}'.compareTo('${w[3]}${w[4]}') >= 0) 'fun.window': 'format',
        if (f.containsKey('days') && (f['days'] is! List || (f['days'] as List).any((d) => !_num(d, 1, 7))))
          'fun.days': 'value',
        if (f.containsKey('ttlS') && !_num(f['ttlS'], 10, 600)) 'fun.ttlS': 'range',
        if (f.containsKey('sound') && !const {'chime', 'pop', 'gong', 'alarm', 'none'}.contains(f['sound']))
          'fun.sound': 'value',
      };
      if (e.isNotEmpty) {
        errors.addAll(e);
      } else if (fun != null) {
        fun = {...fun!, ...f.cast<String, dynamic>()};
      }
    }
    if (v['contentPack'] case final Map p) {
      if (contentPacks == null) {
        errors['contentPack'] = 'unknown';
      } else if (p['remove'] is String && p['remove'] != 'wbudowane') {
        contentPacks!.removeWhere((x) => x['id'] == p['remove']);
      } else if (p['install'] case final Map i when packFiles.containsKey('${i['url']}')) {
        final f = packFiles['${i['url']}']!;
        contentPacks!
          ..removeWhere((x) => x['id'] == f['id'])
          ..add(f);
      } else {
        errors['contentPack'] = 'format';
      }
    }
  }

  /// Środkowy przycisk przy dymku z odpowiedzią: State `bubbleReply` = id (atrapa nie wraca sama do null).
  void replyToBubble() {
    final b = bubbleShown.lastWhere((x) => x['reply'] != null, orElse: () => const {});
    bubbleReply = b.isEmpty ? null : '${b['id'] ?? 'msg'}';
    _broadcastState();
  }

  /// Logo stacji (`stations[].logo`), null = bez logo.
  String? _logoOf(String? station) {
    for (final s in _stations) {
      if (s is Map && s['name'] == station && s['logo'] is String && (s['logo'] as String).isNotEmpty) {
        return s['logo'] as String;
      }
    }
    return null;
  }

  /// Błędy `radio` jak w kontrakcie (stacja: nazwa 1-24 B, `url` i opcjonalne `logo` http(s) ≤ 256 B bez spacji,
  /// `showS` 0-120).
  Map<String, String> _radioErrors(Map r) {
    final st = r['stations'];
    bool urlOk(Object? u) => u is String && RegExp(r'^https?://\S+$').hasMatch(u) && utf8.encode(u).length <= 256;
    bool stationOk(Object? s) =>
        s is Map &&
        s['name'] is String &&
        (s['name'] as String).isNotEmpty &&
        utf8.encode(s['name'] as String).length <= 24 &&
        urlOk(s['url']) &&
        (s['logo'] == null || s['logo'] == '' || urlOk(s['logo']));
    return {
      if (r.containsKey('stations'))
        if (st is! List || !st.every(stationOk))
          'radio.stations': 'value'
        else if (st.length > 12)
          'radio.stations': 'too_many',
      if (r.containsKey('muteOffMin') && !(r['muteOffMin'] == 0 || _num(r['muteOffMin'], 1, 120)))
        'radio.muteOffMin': 'range',
      if (r.containsKey('maxW') && !_num(r['maxW'], 0.1, 1.5)) 'radio.maxW': 'range',
      if (r.containsKey('resume') && r['resume'] is! bool) 'radio.resume': 'value',
      if (r.containsKey('showS') && !(r['showS'] is int && _num(r['showS'], 0, 120))) 'radio.showS': 'range',
      if (r.containsKey('eq') && !const ['off', 'voice', 'music'].contains(r['eq'])) 'radio.eq': 'value',
    };
  }

  /// Set radia i paczek motywów (pkt 10.2 „Radio”, „Paczki motywów”).
  void _applyRadioAndPacks(Map<String, dynamic> v, Map<String, String> errors) {
    if (v.containsKey('radio')) {
      final r = v['radio'];
      if (radio == null) {
        errors['radio'] = 'unknown';
      } else if (r is! Map) {
        errors['radio'] = 'value';
      } else {
        final e = _radioErrors(r);
        if (e.isEmpty) {
          radio = {...radio!, ...r.cast<String, dynamic>()};
          final names = [for (final s in _stations) (s as Map)['name']];
          if (radioStation != null && !names.contains(radioStation)) {
            radioOn = false;
            radioStation = null;
          }
        } else {
          errors.addAll(e);
        }
      }
    }
    final names = [for (final s in _stations) (s as Map)['name'] as String];
    if (v['radioOn'] case final bool on) {
      if (on && names.isEmpty) {
        errors['radioOn'] = 'no_stations';
      } else {
        radioOn = on;
        if (on) radioStation ??= names.first;
      }
    }
    if (v['radioStation'] case final Object s) {
      final i = names.indexOf('$radioStation');
      final next = switch (s) {
        'next' when names.isNotEmpty => names[(i + 1) % names.length],
        'prev' when names.isNotEmpty => names[(i - 1 + names.length) % names.length],
        final String n when names.contains(n) => n,
        _ => null,
      };
      if (next == null) {
        errors['radioStation'] = 'value';
      } else {
        radioStation = next;
        radioOn = true;
      }
    }
    if (v.containsKey('radioVol')) {
      if (_num(v['radioVol'], 0, 100)) {
        radioVol = (v['radioVol'] as num).round();
      } else {
        errors['radioVol'] = 'range';
      }
    }
    if (v['radioMute'] case final bool m) {
      if (radioOn) radioMute = m;
    }
    if (v['themePack'] case final Object p) {
      if (themePacks == null) {
        errors['themePack'] = 'unknown';
      } else if (p is Map && p['install'] is Map) {
        final url = '${(p['install'] as Map)['url']}';
        final file = packFiles[url];
        if (!url.startsWith('https://')) {
          errors['themePack'] = 'host';
        } else if (themeInstall?['state'] == 'download' || themeInstall?['state'] == 'verify') {
          errors['themePack'] = 'busy';
        } else if (file == null) {
          themeInstall = {'id': null, 'state': 'error', 'error': 'http'};
        } else if ((file['size'] as num? ?? 0) > themeFree) {
          errors['themePack'] = 'space';
        } else {
          themePacks!.removeWhere((x) => x['id'] == file['id']);
          themePacks!.add(file);
          themeInstall = {'id': file['id'], 'state': 'done', 'error': null};
        }
      } else if (p is Map && p['remove'] is String) {
        themePacks!.removeWhere((x) => x['id'] == p['remove']);
      } else {
        errors['themePack'] = 'format';
      }
    }
  }

  static const _builtInOld = {'main', 'hours', 'days', 'chart', 'calendar', 'air'};

  Set<String> get _builtIn => {..._builtInOld, if (news != null) 'news'};

  /// Błędy `news` jak `applyNews` w DeskConfig.cpp (kanał: nazwa 1-24 B, `url` http(s) albo `imgw` 4 cyfry).
  Map<String, String> _newsErrors(Map n) {
    int bytes(Object? s) => s is String ? utf8.encode(s).length : -1;
    bool feedOk(Object? f) {
      if (f is! Map || bytes(f['name']) < 1 || bytes(f['name']) > 24) return false;
      final url = f['url'], imgw = f['imgw'];
      if ((url == null) == (imgw == null)) return false;
      if (imgw != null) return imgw is String && RegExp(r'^\d{4}$').hasMatch(imgw);
      return url is String &&
          RegExp(r'^https?://\S+$').hasMatch(url) &&
          url.length > 10 &&
          utf8.encode(url).length <= 256;
    }

    final feeds = n['feeds'], words = n['keywords'];
    return {
      if (n.containsKey('feeds'))
        if (feeds is! List || !feeds.every(feedOk))
          'news.feeds': 'value'
        else if (feeds.length > 6)
          'news.feeds': 'too_many',
      if (n.containsKey('keywords'))
        if (words is! List || !words.every((w) => bytes(w) >= 2 && bytes(w) <= 32))
          'news.keywords': 'value'
        else if (words.length > 16)
          'news.keywords': 'too_many',
      if (n.containsKey('refreshMin') && !_num(n['refreshMin'], 5, 120)) 'news.refreshMin': 'range',
      if (n.containsKey('jumpS') && !(n['jumpS'] == 0 || _num(n['jumpS'], 10, 600))) 'news.jumpS': 'range',
    };
  }

  static const _views = {'value', 'status', 'values', 'level', 'gauge', 'chart', 'thermostat', 'group', 'room', 'hub'};
  static const _commands = {'next', 'prev', 'home', 'wake', 'info'};

  bool _num(Object? v, num min, num max) => v is num && v >= min && v <= max;

  /// Pary z `pages` jak `Wants.cpp` (bez powtórzeń).
  static Set<String> pairsOf(List<dynamic> pages) => {
    for (final p in pages)
      if (p is Map)
        for (final w in (p['widgets'] as List? ?? const []))
          if (w is Map) ...[
            if (w['device'] is String && w['point'] is String) '${w['device']}/${w['point']}',
            if (w['device'] is String)
              for (final k in (w['points'] as List? ?? const [])) '${w['device']}/$k',
            for (final key in ['items', 'series', 'members'])
              for (final i in (w[key] as List? ?? const []))
                if (i is Map) '${i['device']}/${i['point']}',
          ],
  };

  Map<String, String> _pagesErrors(Object? v) {
    if (v is! List) return {'pages': 'type'};
    if (utf8.encode(jsonEncode(v)).length > 6144) return {'pages': 'length'};
    if (v.length > 4 || pairsOf(v).length > 24) return {'pages': 'too_many'};
    final errors = <String, String>{};
    for (final p in v) {
      if (p is! Map || p['id'] is! String) return {'pages': 'value'};
      final widgets = p['widgets'] as List? ?? const [];
      if (widgets.length > 10) return {'pages': 'too_many'};
      for (final w in widgets) {
        final key = 'pages.${p['id']}.${w is Map ? w['id'] : '?'}';
        if (w is! Map || !_views.contains(w['view'])) {
          errors[key] = 'view';
          continue;
        }
        final x = (w['x'] as num?) ?? 0, y = (w['y'] as num?) ?? 0;
        final ww = (w['w'] as num?) ?? 1, hh = (w['h'] as num?) ?? 1;
        if (x < 0 || y < 0 || ww < 1 || hh < 1 || x + ww > 4 || y + hh > 3) errors[key] = 'value';
      }
    }
    return errors;
  }

  @override
  Map<String, String> applySet(Map<String, dynamic> v) {
    final errors = <String, String>{};
    if (v['name'] case final String n) _name = n;
    if (v.containsKey('pages')) {
      final e = _pagesErrors(v['pages']);
      if (e.isEmpty) {
        final before = pairsOf(pages);
        pages = v['pages'] as List;
        if (!before.containsAll(pairsOf(pages)) || !pairsOf(pages).containsAll(before)) wantsVer++;
      } else {
        errors.addAll(e);
      }
    }
    if (v['screens'] case final Map s) {
      final ids = {
        for (final p in pages)
          if (p is Map) 'page:${p['id']}',
      };
      final list = s['list'];
      if (list != null &&
          (list is! List ||
              list.isEmpty ||
              list.length > 6 ||
              list.any((k) => !_builtIn.contains(k) && !ids.contains(k)))) {
        errors['screens.list'] = 'value';
      } else if (s.containsKey('intervalS') && !(s['intervalS'] == 0 || _num(s['intervalS'], 5, 300))) {
        errors['screens.intervalS'] = 'range';
      } else if (s.containsKey('mainFactor') && !_num(s['mainFactor'], 1, 4)) {
        errors['screens.mainFactor'] = 'range';
      } else if (s.containsKey('holdS') && !(s['holdS'] == 0 || _num(s['holdS'], 60, 3600))) {
        errors['screens.holdS'] = 'range';
      } else if (s.containsKey('transition') &&
          !const {'cards', 'slide', 'cover', 'fade', 'none'}.contains(s['transition'])) {
        errors['screens.transition'] = 'value';
      } else {
        screens = {...screens, ...s.cast<String, dynamic>()};
      }
    }
    if (v['display'] case final Map d) {
      if (d.containsKey('brightness') && !_num(d['brightness'], 5, 100)) {
        errors['display.brightness'] = 'range';
      } else if (d.containsKey('rotation') && d['rotation'] != 0 && d['rotation'] != 180) {
        errors['display.rotation'] = 'value';
      } else {
        display = {...display, ...d.cast<String, dynamic>()};
      }
    }
    if (v['night'] case final Map n) {
      final mode = n['mode'];
      if (mode != null && !const {'off', 'schedule', 'lux', 'both'}.contains(mode) ||
          (!lux && (mode == 'lux' || mode == 'both'))) {
        errors['night.mode'] = 'value';
      } else if (n.containsKey('window') && !RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}$').hasMatch('${n['window']}')) {
        errors['night.window'] = 'format';
      } else if (n.containsKey('brightness') && !_num(n['brightness'], 0, 30)) {
        errors['night.brightness'] = 'range';
      } else {
        night = {...night, ...n.cast<String, dynamic>()};
      }
    }
    if (v['clock'] case final Map c) clockCfg = {...clockCfg, ...c.cast<String, dynamic>()};
    if (v['units'] case final Map u) units = {...units, ...u.cast<String, dynamic>()};
    if (v['weather'] case final Map w) {
      if (w.containsKey('lat') && !_num(w['lat'], -90, 90) || w.containsKey('lon') && !_num(w['lon'], -180, 180)) {
        errors['weather'] = 'range';
      } else if (w['place'] is String && utf8.encode(w['place'] as String).length > 32) {
        errors['weather.place'] = 'length';
      } else {
        weather = {...weather, ...w.cast<String, dynamic>()};
      }
    }
    if (v['sensor'] case final Map s) {
      if (s.containsKey('tempOffset') && !_num(s['tempOffset'], -5, 5)) {
        errors['sensor.tempOffset'] = 'range';
      } else if (s.containsKey('humOffset') && !_num(s['humOffset'], -10, 10)) {
        errors['sensor.humOffset'] = 'range';
      } else {
        sensor = {...sensor, ...s.cast<String, dynamic>()};
      }
    }
    if (v.containsKey('outdoor')) {
      final o = v['outdoor'];
      bool id(Object? x, int max) => x is String && RegExp('^[A-Za-z0-9._-]{1,$max}\$').hasMatch(x);
      if (o == null) {
        if (outdoor != null) wantsVer++;
        outdoor = null;
      } else if (o is! Map) {
        errors['outdoor'] = 'value';
      } else {
        final next = {'device': o['device'] ?? '', 'temp': o['temp'] ?? 'temp', 'hum': o['hum'] ?? ''};
        final e = {
          if (!id(next['device'], 32)) 'outdoor.device': 'value',
          if (!id(next['temp'], 24)) 'outdoor.temp': 'value',
          if (next['hum'] != '' && !id(next['hum'], 24)) 'outdoor.hum': 'value',
        };
        if (e.isEmpty) {
          wantsVer++;
          outdoor = next;
        } else {
          errors.addAll(e);
        }
      }
    }
    if (v['showScreen'] case final String s) {
      final ids = {
        for (final p in pages)
          if (p is Map) 'page:${p['id']}',
      };
      if (_commands.contains(s)) {
        if (s == 'home') screen = 'main';
      } else if (_builtIn.contains(s) || ids.contains(s)) {
        screen = s;
      } else {
        errors['showScreen'] = 'value';
      }
    }
    if (v.containsKey('news')) {
      final n = v['news'];
      if (news == null) {
        errors['news'] = 'unknown';
      } else if (n is! Map) {
        errors['news'] = 'value';
      } else {
        final e = _newsErrors(n);
        if (e.isEmpty) {
          news = {...news!, ...n.cast<String, dynamic>()};
        } else {
          errors.addAll(e);
        }
      }
    }
    if (v.containsKey('newsRead')) {
      if (news == null) {
        errors['newsRead'] = 'unknown';
      } else if (v['newsRead'] != true) {
        errors['newsRead'] = 'value';
      } else {
        newsUnread = 0;
      }
    }
    _applyRadioAndPacks(v, errors);
    _applyBubbles(v, errors);
    if (v['identify'] == true) identifies++;
    if (v['ext'] case final List list) {
      for (final e in list) {
        if (e is Map) ext['${e['device']}/${e['point']}'] = e['v'];
      }
    }
    _broadcastState();
    return errors;
  }

  @override
  Map<String, dynamic> describeJson() => {
    'type': 'clock',
    'points': [
      {'key': 'temp', 'name': 'Temperatura', 'kind': 'sensor', 'unit': '°C', 'decimals': 1, 'history': 't'},
      {'key': 'hum', 'name': 'Wilgotność', 'kind': 'sensor', 'unit': '%', 'history': 'hum'},
      {'key': 'press', 'name': 'Ciśnienie', 'kind': 'sensor', 'unit': 'hPa', 'min': 960, 'max': 1050},
      {'key': 'outTemp', 'name': 'Na zewnątrz', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
      {'key': 'night', 'name': 'Tryb nocny', 'kind': 'status'},
      {
        'key': 'showScreen',
        'name': 'Pokaż ekran',
        'kind': 'select',
        'options': [..._commands, ...(screens['list'] as List)],
        'access': 'control',
      },
      {'key': 'identify', 'name': 'Pokaż, który to', 'kind': 'action', 'access': 'control'},
      for (final (i, n) in const ['lewy', 'środkowy', 'prawy'].indexed)
        {'key': 'in${i + 1}', 'name': 'Przycisk $n', 'kind': 'status', 'inputKind': 'button'},
      if (lux) {'key': 'lux', 'name': 'Światło', 'kind': 'sensor', 'unit': 'lx'},
      if (news != null) ...[
        {'key': 'newsUnread', 'name': 'Ważne wiadomości', 'kind': 'sensor'},
        {'key': 'newsRead', 'name': 'Wiadomości przeczytane', 'kind': 'action', 'access': 'control'},
      ],
      if (_stations.isNotEmpty) ...[
        {'key': 'radioOn', 'name': 'Radio', 'kind': 'switch', 'access': 'control'},
        {
          'key': 'radioVol',
          'name': 'Głośność radia',
          'kind': 'setpoint',
          'unit': '%',
          'min': 0,
          'max': 100,
          'step': 5,
          'access': 'control',
        },
        {'key': 'radioMute', 'name': 'Radio wyciszone', 'kind': 'switch', 'access': 'control'},
        {
          'key': 'radioStation',
          'name': 'Stacja radia',
          'kind': 'select',
          'options': ['next', 'prev', for (final s in _stations) (s as Map)['name']],
          'access': 'control',
        },
      ],
      if (bubbles != null) ...[
        {'key': 'meeting', 'name': 'Spotkanie', 'kind': 'switch', 'access': 'control'},
        {'key': 'bubbleReply', 'name': 'Odpowiedź z dymka', 'kind': 'status'},
      ],
    ],
  };

  /// Klawisz `w`: rozgrzewanie wł./wył.; `b`: lewy przycisk wciśnięty / puszczony.
  void toggleWarmup() {
    warmup = !warmup;
    _broadcastState();
  }

  void toggleButton([int i = 0]) {
    buttons[i] = !buttons[i];
    _broadcastState();
  }
}
