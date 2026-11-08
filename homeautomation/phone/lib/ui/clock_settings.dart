// Ustawienia zegara `clock` (pkt 10.2, PLAN zegara pkt 9): ekrany i przejścia, jasność i noc, pogoda i jednostki,
// czujnik, zegar. Każda zmiana od razu idzie Setem (obiekt w całości, z obecnymi polami Config).

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../data/errors.dart';
import '../data/hub_weather.dart';
import '../models/clock.dart';
import '../models/dashboard.dart' show reorder;
import '../models/json_utils.dart';
import 'clock_section.dart' show clockScreenList;
import 'format.dart';
import 'widgets.dart';

/// Wspólne dla stron ustawień: odczyt obiektów Config i Set z pokazaniem błędów.
mixin _ClockConfig<T extends StatefulWidget> on State<T> {
  DeviceController<Object?, Object?> get c;

  Json get cfg => c.config is Map ? (c.config! as Map).cast<String, dynamic>() : const {};

  Json obj(String key) => cfg[key] is Map ? (cfg[key] as Map).cast<String, dynamic>() : const {};

  /// Set pola [key] = obecny obiekt z [changes].
  Future<void> setIn(String key, Json changes) => send({
    key: {...obj(key), ...changes},
  });

  Future<void> send(Json values) async {
    final r = await c.sendJson(values);
    if (mounted) showSaveResult(context, r.errors, describeErrors);
  }

  Widget page(String title, List<Widget> children) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListenableBuilder(
      listenable: c,
      builder: (context, _) =>
          ListView(padding: listPadding(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)), children: children),
    ),
  );
}

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parseHhmm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  return m == null ? null : TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
}

Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) => showTimePicker(
  context: context,
  initialTime: initial,
  builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
);

// ---------------------------------------------------------------- Ekrany

class ClockScreensPage extends StatefulWidget {
  const ClockScreensPage({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<ClockScreensPage> createState() => _ClockScreensPageState();
}

class _ClockScreensPageState extends State<ClockScreensPage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  /// Lista do pokazania: włączone w kolejności `screens.list`, potem wyłączone (wbudowane i strony).
  List<(String, bool)> _rows() {
    final on = clockScreenList(cfg);
    final all = [...clockScreens.keys, for (final p in ClockPage.listFrom(cfg)) 'page:${p.id}'];
    return [for (final k in on) (k, true), for (final k in all.where((k) => !on.contains(k))) (k, false)];
  }

  Future<void> _setList(List<String> list) async {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Co najmniej jeden ekran.')));
      return;
    }
    if (list.length > clockMaxScreens) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Najwyżej $clockMaxScreens ekranów w pokazie.')));
      return;
    }
    await setIn('screens', {'list': list});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ekrany')),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final rows = _rows();
          final pages = ClockPage.listFrom(cfg);
          final s = obj('screens');
          final interval = (s['intervalS'] as num?)?.toInt() ?? 15;
          final factor = (s['mainFactor'] as num?)?.toInt() ?? 1;
          final transition = s['transition'] as String? ?? 'cards';
          return ListView(
            padding: listPadding(context, const EdgeInsets.fromLTRB(0, 8, 0, 32)),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Włączone ekrany zegar pokazuje po kolei; przeciągnij, żeby zmienić kolejność.'),
              ),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (from, to) {
                  final list = clockScreenList(cfg);
                  if (from >= list.length) return; // przesuwa się tylko włączone
                  _setList(reorder(list, from, to.clamp(0, list.length)));
                },
                children: [
                  for (final (i, (k, on)) in rows.indexed)
                    ListTile(
                      key: Key('clockScreen-$k'),
                      leading: on
                          ? ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle))
                          : const Icon(Icons.visibility_off_outlined),
                      title: Text(clockScreenName(k, pages)),
                      subtitle: Text(k.startsWith('page:') ? 'strona z widżetami' : clockScreenHints[k] ?? ''),
                      trailing: Switch(
                        key: Key('clockScreenOn-$k'),
                        value: on,
                        onChanged: (v) {
                          final list = clockScreenList(cfg);
                          _setList(v ? [...list, k] : list.where((x) => x != k).toList());
                        },
                      ),
                    ),
                ],
              ),
              const SectionHeader('Pokaz'),
              ListTile(
                title: const Text('Czas na ekranie'),
                subtitle: Text(interval == 0 ? 'stoi na pierwszym ekranie' : '$interval s'),
                trailing: DropdownButton<int>(
                  key: const Key('clockInterval'),
                  value: interval,
                  items: [
                    for (final v in {0, 5, 10, 15, 20, 30, 45, 60, 120, 300, interval})
                      DropdownMenuItem(value: v, child: Text(v == 0 ? 'bez zmiany' : '$v s')),
                  ],
                  onChanged: (v) => setIn('screens', {'intervalS': v}),
                ),
              ),
              ListTile(
                title: const Text('Ekran główny dłużej'),
                subtitle: SegmentedButton<int>(
                  key: const Key('clockMainFactor'),
                  showSelectedIcon: false,
                  segments: [for (var f = 1; f <= 4; f++) ButtonSegment(value: f, label: Text('×$f'))],
                  selected: {factor.clamp(1, 4)},
                  onSelectionChanged: (v) => setIn('screens', {'mainFactor': v.single}),
                ),
              ),
              const SectionHeader('Przejście'),
              RadioGroup<String>(
                groupValue: transition,
                onChanged: (v) => setIn('screens', {'transition': v}),
                child: Column(
                  children: [
                    for (final MapEntry(key: k, value: label) in clockTransitions.entries)
                      RadioListTile<String>(
                        key: Key('clockTransition-$k'),
                        value: k,
                        title: Text(label),
                        secondary: ClockTransitionPreview(kind: k),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Mały podgląd przejścia: dwa „ekrany” zmieniają się co 1,6 s tą animacją co na zegarze.
class ClockTransitionPreview extends StatefulWidget {
  const ClockTransitionPreview({super.key, required this.kind});

  final String kind;

  /// Testy wyłączają animację (zegar okresowy blokuje `pumpAndSettle`).
  static bool animate = true;

  @override
  State<ClockTransitionPreview> createState() => _ClockTransitionPreviewState();
}

class _ClockTransitionPreviewState extends State<ClockTransitionPreview> {
  Timer? _timer;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    if (ClockTransitionPreview.animate) {
      _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
        if (mounted) setState(() => _n++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _screen(int n) {
    final (bg, fg, _) = clockTileColors[n.isEven ? 'blue' : 'amber']!;
    return Container(
      key: ValueKey(n),
      width: 64,
      height: 48,
      padding: const EdgeInsets.all(4),
      color: const Color(0xFFEEF1F6),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(bg), borderRadius: BorderRadius.circular(5)),
                child: Center(child: Container(width: 10, height: 3, color: Color(fg))),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 64,
        height: 48,
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: k == 'none' ? 0 : 450),
          // Nasunięcie: stary ekran zostaje pod spodem.
          layoutBuilder: (current, previous) => Stack(children: [...previous, ?current]),
          transitionBuilder: (child, a) {
            final incoming = child.key == ValueKey(_n);
            return switch (k) {
              'slide' => SlideTransition(
                position: Tween(begin: Offset(incoming ? 1 : -1, 0), end: Offset.zero).animate(a),
                child: child,
              ),
              'cover' =>
                incoming
                    ? SlideTransition(
                        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(a),
                        child: child,
                      )
                    : child,
              'cards' => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                  child: child,
                ),
              ),
              'fade' => FadeTransition(opacity: a, child: child),
              _ => child,
            };
          },
          child: _screen(_n),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Jasność i noc

class ClockDisplayPage extends StatefulWidget {
  const ClockDisplayPage({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<ClockDisplayPage> createState() => _ClockDisplayPageState();
}

class _ClockDisplayPageState extends State<ClockDisplayPage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  double? _bright, _nightBright;

  Future<void> _window(String current, {required bool start}) async {
    final parts = current.split('-');
    final from = _parseHhmm(parts.first) ?? const TimeOfDay(hour: 23, minute: 0);
    final to = _parseHhmm(parts.length > 1 ? parts[1] : '') ?? const TimeOfDay(hour: 6, minute: 30);
    final t = await _pickTime(context, start ? from : to);
    if (t == null) return;
    await setIn('night', {'window': start ? '${_hhmm(t)}-${_hhmm(to)}' : '${_hhmm(from)}-${_hhmm(t)}'});
  }

  @override
  Widget build(BuildContext context) {
    final hasLux = c.stateJson?.containsKey('lux') ?? false;
    return page('Jasność i noc', [
      Builder(
        builder: (context) {
          final d = obj('display');
          final b = _bright ?? ((d['brightness'] as num?)?.toDouble() ?? 80).clamp(5, 100).toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jasność w dzień'),
                trailing: Text('${b.round()} %'),
              ),
              Slider(
                key: const Key('clockBrightness'),
                value: b,
                min: 5,
                max: 100,
                divisions: 19,
                onChanged: (v) => setState(() => _bright = v),
                onChangeEnd: (v) async {
                  await setIn('display', {'brightness': v.round()});
                  if (mounted) setState(() => _bright = null);
                },
              ),
              SwitchListTile(
                key: const Key('clockAuto'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatycznie'),
                subtitle: Text(
                  hasLux
                      ? 'Według czujnika światła (jasność wyżej to maksimum)'
                      : 'Według pory dnia (zegar bez czujnika światła)',
                ),
                value: d['auto'] == true,
                onChanged: (v) => setIn('display', {'auto': v}),
              ),
              SwitchListTile(
                key: const Key('clockRotation'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Obróć ekran o 180°'),
                value: d['rotation'] == 180,
                onChanged: (v) => setIn('display', {'rotation': v ? 180 : 0}),
              ),
            ],
          );
        },
      ),
      const SectionHeader('Noc'),
      Builder(
        builder: (context) {
          final n = obj('night');
          final mode = n['mode'] as String? ?? 'off';
          final window = n['window'] as String? ?? '23:00-06:30';
          final nb = _nightBright ?? ((n['brightness'] as num?)?.toDouble() ?? 3).clamp(0, 30).toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tryb nocny'),
                trailing: DropdownButton<String>(
                  key: const Key('clockNightMode'),
                  value: clockNightModes.containsKey(mode) ? mode : 'off',
                  items: [
                    for (final MapEntry(key: k, value: label) in clockNightModes.entries)
                      DropdownMenuItem(
                        value: k,
                        enabled: hasLux || (k != 'lux' && k != 'both'),
                        child: Text(
                          label,
                          style: hasLux || (k != 'lux' && k != 'both')
                              ? null
                              : TextStyle(color: Theme.of(context).disabledColor),
                        ),
                      ),
                  ],
                  onChanged: (v) => setIn('night', {'mode': v}),
                ),
              ),
              if (!hasLux) const Text('„Według światła” wymaga czujnika światła (BH1750) - ten zegar go nie ma.'),
              if (mode == 'schedule' || mode == 'both') ...[
                ListTile(
                  key: const Key('clockNightFrom'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Od'),
                  trailing: Text(window.split('-').first),
                  onTap: () => _window(window, start: true),
                ),
                ListTile(
                  key: const Key('clockNightTo'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Do'),
                  trailing: Text(window.split('-').length > 1 ? window.split('-')[1] : ''),
                  onTap: () => _window(window, start: false),
                ),
              ],
              if (mode != 'off') ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Jasność w nocy'),
                  trailing: Text(nb.round() == 0 ? 'wygaszony' : '${nb.round()} %'),
                ),
                Slider(
                  key: const Key('clockNightBrightness'),
                  value: nb,
                  max: 30,
                  divisions: 30,
                  onChanged: (v) => setState(() => _nightBright = v),
                  onChangeEnd: (v) async {
                    await setIn('night', {'brightness': v.round()});
                    if (mounted) setState(() => _nightBright = null);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('W nocy pokazuj'),
                  trailing: DropdownButton<String>(
                    key: const Key('clockNightScreen'),
                    value: clockNightScreens.containsKey(n['screen']) ? n['screen'] as String : 'clock',
                    items: [
                      for (final MapEntry(key: k, value: label) in clockNightScreens.entries)
                        DropdownMenuItem(value: k, child: Text(label)),
                    ],
                    onChanged: (v) => setIn('night', {'screen': v}),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Pogoda i jednostki

class ClockWeatherPage extends StatefulWidget {
  const ClockWeatherPage({super.key, required this.controller, this.hub, this.locate = phoneLocation});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub? hub;
  final Future<({double lat, double lon})> Function() locate;

  @override
  State<ClockWeatherPage> createState() => _ClockWeatherPageState();
}

class _ClockWeatherPageState extends State<ClockWeatherPage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  DeviceController<Object?, Object?>? get _hubC {
    final via = c.device.via;
    return via == null ? null : widget.hub?.controller(via);
  }

  Future<void> _fromHub() async {
    final h = _hubC?.config;
    final loc = h is Map ? h['location'] : null;
    final w = h is Map ? h['weather'] : null;
    if (loc is! Map || loc['lat'] is! num) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hub nie ma położenia domu.')));
      return;
    }
    await setIn('weather', {
      'lat': loc['lat'],
      'lon': loc['lon'],
      if (w is Map && w['place'] is String) 'place': w['place'],
    });
  }

  Future<void> _fromPhone() async {
    try {
      final p = await widget.locate();
      await setIn('weather', {
        'lat': double.parse(p.lat.toStringAsFixed(3)),
        'lon': double.parse(p.lon.toStringAsFixed(3)),
      });
    } on ThermostatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _place() async {
    final name = await showTextInputDialog(
      context,
      title: 'Nazwa miejsca',
      initial: obj('weather')['place'] as String? ?? '',
      maxLength: 32,
    );
    if (name != null && name.trim().isNotEmpty) await setIn('weather', {'place': name.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final w = obj('weather');
    final u = obj('units');
    final hubName = c.device.via == null ? null : (widget.hub?.device(c.device.via!)?.name ?? c.device.via);
    Widget seg(String key, Map<String, String> options, String def) => SegmentedButton<String>(
      key: Key('clockUnit-$key'),
      showSelectedIcon: false,
      segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
      selected: {u[key] as String? ?? def},
      onSelectionChanged: (v) => setIn('units', {key: v.single}),
    );
    return page('Pogoda i jednostki', [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.hub_outlined),
        title: const Text('Źródło'),
        subtitle: Text(
          hubName == null
              ? 'Zegar nie jest w hubie - pobiera pogodę sam (Open-Meteo) dla lokalizacji niżej.'
              : 'Z huba $hubName (pogoda i prognoza). Lokalizacja niżej tylko awaryjnie - gdy hub nie przyśle '
                    'pogody przez 2 h.',
        ),
      ),
      const SectionHeader('Lokalizacja zegara'),
      ListTile(
        key: const Key('clockWeatherLoc'),
        contentPadding: EdgeInsets.zero,
        title: Text(w['place'] is String ? w['place'] as String : 'Bez nazwy miejsca'),
        subtitle: Text(w['lat'] is num ? '${w['lat']}, ${w['lon']}' : 'Nieustawiona'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: _place,
      ),
      Wrap(
        spacing: 8,
        children: [
          if (_hubC != null)
            OutlinedButton.icon(
              key: const Key('clockWeatherFromHub'),
              icon: const Icon(Icons.hub_outlined),
              label: const Text('Jak hub'),
              onPressed: _fromHub,
            ),
          OutlinedButton.icon(
            key: const Key('clockWeatherFromPhone'),
            icon: const Icon(Icons.my_location),
            label: const Text('Z telefonu'),
            onPressed: _fromPhone,
          ),
        ],
      ),
      const SectionHeader('Jednostki na ekranie'),
      const Text('Telefon, hub i automatyki zawsze dostają °C i hPa.'),
      const SizedBox(height: 8),
      seg('temp', const {'C': '°C', 'F': '°F'}, 'C'),
      const SizedBox(height: 8),
      seg('press', const {'hPa': 'hPa', 'mmHg': 'mmHg'}, 'hPa'),
      const SizedBox(height: 8),
      seg('wind', const {'kmh': 'km/h', 'ms': 'm/s'}, 'kmh'),
    ]);
  }
}

// ---------------------------------------------------------------- Czujnik

class ClockSensorPage extends StatefulWidget {
  const ClockSensorPage({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<ClockSensorPage> createState() => _ClockSensorPageState();
}

class _ClockSensorPageState extends State<ClockSensorPage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  double? _t, _h;

  String _v(Object? v, String unit, [int dec = 1]) =>
      v is num ? '${fmtNumber(v.toDouble(), decimals: dec)} $unit' : '–';

  @override
  Widget build(BuildContext context) {
    final s = c.stateJson ?? const <String, dynamic>{};
    final se = obj('sensor');
    final t = _t ?? ((se['tempOffset'] as num?)?.toDouble() ?? 0).clamp(-5, 5).toDouble();
    final h = _h ?? ((se['humOffset'] as num?)?.toDouble() ?? 0).clamp(-10, 10).toDouble();
    return page('Czujnik', [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Temperatura: ${_v(s['temp'], '°C')} (surowa ${_v(s['tempRaw'], '°C')})',
                key: const Key('clockRaw'),
              ),
              Text('Wilgotność: ${_v(s['hum'], '%', 0)} (surowa ${_v(s['humRaw'], '%', 0)})'),
              if (s['chipTemp'] is num) Text('Układ ESP32: ${_v(s['chipTemp'], '°C')}'),
            ],
          ),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Korekta temperatury'),
        trailing: Text('${t >= 0 ? '+' : ''}${fmtNumber(t, decimals: 1)} °C'),
      ),
      Slider(
        key: const Key('clockTempOffset'),
        value: t,
        min: -5,
        max: 5,
        divisions: 100,
        onChanged: (v) => setState(() => _t = (v * 10).round() / 10),
        onChangeEnd: (v) async {
          await setIn('sensor', {'tempOffset': (v * 10).round() / 10});
          if (mounted) setState(() => _t = null);
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Korekta wilgotności'),
        trailing: Text('${h >= 0 ? '+' : ''}${h.round()} %'),
      ),
      Slider(
        key: const Key('clockHumOffset'),
        value: h,
        min: -10,
        max: 10,
        divisions: 20,
        onChanged: (v) => setState(() => _h = v),
        onChangeEnd: (v) async {
          await setIn('sensor', {'humOffset': v.round()});
          if (mounted) setState(() => _h = null);
        },
      ),
      SwitchListTile(
        key: const Key('clockComp'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Kompensacja nagrzewania'),
        subtitle: const Text('Odejmuje ciepło płytki, WiFi i podświetlenia (model w zegarze)'),
        value: se['comp'] != false,
        onChanged: (v) => setIn('sensor', {'comp': v}),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Zegar

class ClockTimePage extends StatefulWidget {
  const ClockTimePage({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<ClockTimePage> createState() => _ClockTimePageState();
}

class _ClockTimePageState extends State<ClockTimePage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final k = obj('clock');
    return page('Zegar', [
      SwitchListTile(
        key: const Key('clockSeconds'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Sekundy'),
        value: k['seconds'] == true,
        onChanged: (v) => setIn('clock', {'seconds': v}),
      ),
      const SectionHeader('Format daty'),
      RadioGroup<String>(
        groupValue: k['dateFormat'] as String? ?? 'long',
        onChanged: (v) => setIn('clock', {'dateFormat': v}),
        child: Column(
          children: [
            for (final MapEntry(key: f, value: label) in clockDateFormats.entries)
              RadioListTile<String>(key: Key('clockDate-$f'), value: f, title: Text(label)),
          ],
        ),
      ),
    ]);
  }
}
