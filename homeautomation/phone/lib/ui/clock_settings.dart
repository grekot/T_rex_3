// Ustawienia zegara `clock` (pkt 10.2, PLAN zegara pkt 9): ekrany i przejścia, jasność i noc, pogoda i jednostki,
// czujnik, zegar. Każda zmiana od razu idzie Setem (obiekt w całości, z obecnymi polami Config).

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../data/device_store.dart';
import '../data/errors.dart';
import '../data/hub_weather.dart';
import '../data/radio_logo_lookup.dart';
import '../data/theme_pack_catalog.dart';
import '../models/clock.dart';
import '../models/dashboard.dart' show reorder;
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/json_utils.dart';
import 'clock_pages.dart' show clockKnownDevices;
import 'clock_section.dart' show clockScreenList;
import 'format.dart';
import 'widget_editor.dart' show pointsOf;
import 'widgets.dart';

/// Wspólne dla stron ustawień: odczyt obiektów Config i Set z pokazaniem błędów.
mixin _ClockConfig<T extends StatefulWidget> on State<T> {
  DeviceController<Object?, Object?> get c;

  Json get cfg => c.config is Map ? (c.config! as Map).cast<String, dynamic>() : const {};

  Json obj(String key) => cfg[key] is Map ? (cfg[key] as Map).cast<String, dynamic>() : const {};

  /// Set pola [key] = obecny obiekt z [changes].
  Future<Map<String, String>> setIn(String key, Json changes) => send({
    key: {...obj(key), ...changes},
  });

  /// Set z komunikatem; zwraca błędy pól.
  Future<Map<String, String>> send(Json values) async {
    final r = await c.sendJson(values);
    if (mounted) showSaveResult(context, r.errors, describeErrors);
    return r.errors;
  }

  // Zmiana stanu / konfiguracji przebudowuje całe build() strony. ListenableBuilder w page() nie wystarczał: dostawał
  // gotowe children z wartościami sprzed zapisu, więc przełącznik zmieniał się dopiero po ponownym wejściu.
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Widget page(String title, List<Widget> children) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children),
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
    final all = [
      ...clockScreens.keys.where(
        (k) => (k != 'news' || clockHasNews(cfg)) && (k != 'radio' || clockHasRadioScreen(cfg)),
      ),
      for (final p in ClockPage.listFrom(cfg)) 'page:${p.id}',
    ];
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
          final hold = (s['holdS'] as num?)?.toInt();   // null = zegar bez screens.holdS (starszy firmware)
          final transition = s['transition'] as String? ?? 'cards';
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
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
              if (hold != null)
                ListTile(
                  title: const Text('Po ręcznej zmianie ekranu'),
                  subtitle: Text(
                    hold == 0
                        ? 'Pokaz stoi na wybranym ekranie do środkowego przycisku (w rogu ikona pauzy)'
                        : 'Pokaz stoi na wybranym ekranie, potem wraca do głównego',
                  ),
                  trailing: DropdownButton<int>(
                    key: const Key('clockHold'),
                    value: hold,
                    items: [
                      for (final v in {...clockHoldOptions.keys, hold})
                        DropdownMenuItem(value: v, child: Text(clockHoldOptions[v] ?? '${(v / 60).round()} min')),
                    ],
                    onChanged: (v) => setIn('screens', {'holdS': v}),
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

  /// Punkty `describe` urządzeń (czujnik na zewnątrz).
  final _points = <String, List<DataPoint>>{};

  /// Błędy pól `outdoor` z ostatniego zapisu.
  Map<String, String> _outErrors = const {};

  Json? get _outdoor => cfg['outdoor'] is Map ? (cfg['outdoor'] as Map).cast<String, dynamic>() : null;

  @override
  void initState() {
    super.initState();
    final dev = _outdoor?['device'];
    if (dev is String) _pointsOf(dev);
  }

  Future<List<DataPoint>> _pointsOf(String id) async {
    final cached = _points[id];
    if (cached != null) return cached;
    final d = widget.hub?.device(id);
    final pts = d == null ? const <DataPoint>[] : await pointsOf(widget.hub!, d);
    if (mounted) setState(() => _points[id] = pts);
    return pts;
  }

  Future<void> _setOutdoor(Json? value) async {
    final errors = await send({'outdoor': value});
    if (!mounted) return;
    setState(
      () => _outErrors = {
        for (final e in errors.entries)
          if (e.key == 'outdoor' || e.key.startsWith('outdoor.')) e.key: e.value,
      },
    );
  }

  Future<void> _pickOutdoor() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) =>
          _OutdoorPicker(hub: widget.hub!, clock: c, current: _outdoor?['device'] as String?, points: _pointsOf),
    );
    if (picked == null) return;
    if (picked.isEmpty) return _setOutdoor(null);
    await _setOutdoor(clockOutdoorFor(picked, await _pointsOf(picked)));
  }

  /// Odczyt z czujnika (State `outdoor.src`) albo dlaczego go nie ma.
  String _outdoorNow() {
    final s = c.stateJson?['outdoor'];
    if (_outdoor == null) return 'Temperatura i wilgotność z prognozy pogody';
    if (s is Map && s['src'] == 'sensor' && s['temp'] is num) {
      final hum = s['hum'] is num ? ', wilg. ${(s['hum'] as num).round()} %' : '';
      return 'Teraz ${fmtNumber((s['temp'] as num).toDouble(), decimals: 1)} °C$hum';
    }
    return 'Brak odczytu z ostatnich 30 min - zegar pokazuje temperaturę z Open-Meteo';
  }

  /// Błąd pola `outdoor…` pod polem (null bez błędu).
  Widget? _outError(List<String> keys) {
    final code = keys.map((k) => _outErrors[k]).nonNulls.firstOrNull;
    return code == null
        ? null
        : Text(describeErrorCode(code), style: TextStyle(color: Theme.of(context).colorScheme.error));
  }

  List<Widget> _outdoorSection() {
    final out = _outdoor;
    if (_hubC == null) {
      return const [Text('Temperatura z Open-Meteo. Czujnik jako źródło wymaga huba - to hub przysyła odczyty.')];
    }
    final dev = out?['device'] as String?;
    final pts = dev == null ? const <DataPoint>[] : _points[dev] ?? const <DataPoint>[];
    final t = out?['temp'] as String? ?? 'temp';
    final h = out?['hum'] as String? ?? '';
    final temps = {for (final p in clockOutdoorTempPoints(pts)) p.key: p.name};
    final hums = {'': 'bez wilgotności', for (final p in clockOutdoorHumPoints(pts)) p.key: p.name};
    if (!hums.containsKey(h)) hums[h] = h;
    if (!temps.containsKey(t)) temps[t] = t;
    return [
      ListTile(
        key: const Key('clockOutdoor'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.sensors),
        title: Text(dev == null ? 'Open-Meteo (internet)' : widget.hub?.device(dev)?.name ?? dev),
        subtitle: _outError(['outdoor', 'outdoor.device']) ?? Text(_outdoorNow()),
        trailing: const Icon(Icons.edit_outlined),
        onTap: widget.hub == null ? null : _pickOutdoor,
      ),
      if (out != null) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Temperatura'),
          subtitle: _outError(['outdoor.temp']),
          trailing: DropdownButton<String>(
            key: const Key('clockOutdoorTemp'),
            value: t,
            items: [for (final e in temps.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => _setOutdoor({...out, 'temp': v}),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wilgotność'),
          subtitle: _outError(['outdoor.hum']),
          trailing: DropdownButton<String>(
            key: const Key('clockOutdoorHum'),
            value: h,
            items: [for (final e in hums.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => _setOutdoor({...out, 'hum': v}),
          ),
        ),
      ],
    ];
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
      const SectionHeader('Temperatura na zewnątrz - źródło'),
      ..._outdoorSection(),
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

/// Źródło temperatury na zewnątrz: Open-Meteo i urządzenia znane hubowi zegara z punktem temperatury (°C, `describe`).
/// Wynik: id urządzenia, `''` = Open-Meteo (bez czujnika, `outdoor: null`).
class _OutdoorPicker extends StatefulWidget {
  const _OutdoorPicker({required this.hub, required this.clock, required this.current, required this.points});

  final DeviceHub hub;
  final DeviceController<Object?, Object?> clock;
  final String? current;
  final Future<List<DataPoint>> Function(String id) points;

  @override
  State<_OutdoorPicker> createState() => _OutdoorPickerState();
}

class _OutdoorPickerState extends State<_OutdoorPicker> {
  List<PairedDevice>? _devices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final known = await clockKnownDevices(widget.hub, widget.clock);
    final candidates = known
        .map(widget.hub.device)
        .nonNulls
        .where((d) => d.type != DeviceType.hub && d.id != widget.clock.device.id)
        .toList();
    final pts = await Future.wait(candidates.map((d) => widget.points(d.id)));
    if (!mounted) return;
    setState(
      () => _devices = [
        for (final (i, d) in candidates.indexed)
          if (clockOutdoorTempPoints(pts[i]).isNotEmpty) d,
      ],
    );
  }

  Widget _option(String id, String title, String? subtitle) => SimpleDialogOption(
    key: Key('clockOutdoor-${id.isEmpty ? 'none' : id}'),
    onPressed: () => Navigator.pop(context, id),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon((widget.current ?? '') == id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    return SimpleDialog(
      title: const Text('Źródło temperatury na zewnątrz'),
      children: [
        _option('', 'Open-Meteo (internet)', 'temperatura i wilgotność z prognozy pogody'),
        if (devices == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (devices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('Hub zegara nie zna urządzeń z temperaturą.'),
          )
        else
          for (final d in devices) _option(d.id, d.name, d.type.label),
      ],
    );
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

// ---------------------------------------------------------------- Motyw

/// Paczki zegara - motywy (`themePack`, `.dctp`) albo treści ciekawostek (`contentPack`, `.dccp`): zainstalowane
/// (State `themePacks` / `contentPacks`), postęp (`themeInstall` / `contentInstall`), usuwanie i paczki do pobrania
/// z indeksu. Wolne miejsce (`themeFree`) jest wspólne - obie leżą w LittleFS zegara.
mixin _ClockPacks<T extends StatefulWidget> on State<T>, _ClockConfig<T> {
  Future<List<ClockPack>>? _index;

  Future<void> _install(String setKey, ClockPack p) => send({
    setKey: {
      'install': {'url': p.url, 'sha256': p.sha256},
    },
  });

  Future<void> _remove(String setKey, ClockPack p, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć paczkę „${p.name}”?'),
        content: Text(what),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            key: const Key('clockPackRemoveOk'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await send({
        setKey: {'remove': p.id},
      });
    }
  }

  /// Instalacja w toku albo jej wynik.
  Widget? _installState(Object? s) {
    if (s is! Map) return null;
    final (text, busy) = switch (s['state']) {
      'download' => ('Pobieranie paczki ${s['id'] ?? ''}…', true),
      'verify' => ('Sprawdzanie paczki ${s['id'] ?? ''}…', true),
      'done' => ('Paczka ${s['id'] ?? ''} zainstalowana', false),
      'error' => ('Instalacja nieudana: ${describeErrorCode('${s['error'] ?? ''}')}', false),
      _ => ('${s['state']}', false),
    };
    return ListTile(
      key: const Key('clockPackInstall'),
      contentPadding: EdgeInsets.zero,
      title: Text(text),
      subtitle: busy ? const LinearProgressIndicator() : null,
    );
  }

  /// Sekcja paczek; [below] - pod zainstalowaną paczką (np. wybór motywu z niej).
  List<Widget> packSection({
    required bool content,
    required Future<List<ClockPack>> Function() load,
    Widget Function(ClockPack)? below,
  }) {
    final st = c.stateJson;
    final setKey = content ? 'contentPack' : 'themePack';
    final install = st?[content ? 'contentInstall' : 'themeInstall'];
    final installed = ClockPack.listFrom(st?[content ? 'contentPacks' : 'themePacks']);
    final free = (st?['themeFree'] as num?)?.toInt();
    final busy = switch ((install as Map?)?['state']) {
      'download' || 'verify' => true,
      _ => false,
    };
    String itemsText(ClockPack p) => content
        ? '${p.items.length} kat., ${p.items.fold<int>(0, (n, i) => n + i.count)} poz.'
        : '${p.items.length} mot.';
    // FutureBuilder niżej buduje się dopiero po przewinięciu - błąd bez niego nie może zostać „nieobsłużony”
    _index ??= load()..ignore();
    return [
      SectionHeader(content ? 'Paczki ciekawostek' : 'Paczki motywów'),
      Text(
        '${content ? 'Dodatkowe ciekawostki, zagadki i cytaty' : 'Dodatkowe motywy'} bez aktualizacji firmware, '
        'osobno w każdym zegarze${free == null ? '' : ' (wolne miejsce: ${clockBytesText(free)})'}.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      ?_installState(install),
      if (installed.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('Ten zegar nie ma jeszcze paczek.')),
      for (final p in installed) ...[
        ListTile(
          key: Key('clockPack-${p.id}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(content ? Icons.library_books_outlined : Icons.collections_outlined),
          title: Text(p.name),
          subtitle: Text('wersja ${p.version} · ${itemsText(p)} · ${clockBytesText(p.size)}'),
          // Zestaw wbudowany w firmware jest nieusuwalny (wyłącza się go kategoriami)
          trailing: content && p.id == 'wbudowane'
              ? null
              : IconButton(
                  key: Key('clockPackRemove-${p.id}'),
                  tooltip: 'Usuń paczkę',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy
                      ? null
                      : () => _remove(
                          setKey,
                          p,
                          content
                              ? 'Ciekawostki z tej paczki przestaną się pojawiać.'
                              : 'Gdy zegar pokazuje motyw z tej paczki, wróci do motywu, na którym ten motyw się opiera.',
                        ),
                ),
        ),
        ?below?.call(p),
      ],
      const SectionHeader('Do pobrania'),
      FutureBuilder<List<ClockPack>>(
        future: _index,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
          if (snap.hasError) {
            return const Text('Katalog paczek jest niedostępny (brak internetu albo jeszcze nie opublikowany).');
          }
          final have = {for (final p in installed) p.id: p.version};
          final offer = [
            for (final p in snap.data ?? const <ClockPack>[])
              if (!have.containsKey(p.id) || clockVersionNewer(p.version, have[p.id]!)) p,
          ];
          if (offer.isEmpty) return const Text('Brak nowych paczek.');
          return Column(
            children: [
              for (final p in offer)
                ListTile(
                  key: Key('clockPackOffer-${p.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: p.thumb == null
                      ? Icon(content ? Icons.library_books_outlined : Icons.collections_outlined)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            p.thumb!,
                            width: 56,
                            height: 42,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(Icons.collections_outlined),
                          ),
                        ),
                  title: Text(p.name),
                  subtitle: Text(
                    [
                      if (p.author != null) p.author!,
                      itemsText(p),
                      clockBytesText(p.size),
                      if (free != null && p.size > free) 'za mało miejsca',
                    ].join(' · '),
                  ),
                  trailing: FilledButton.tonal(
                    key: Key('clockPackInstall-${p.id}'),
                    onPressed: busy || (free != null && p.size > free) ? null : () => _install(setKey, p),
                    child: Text(have.containsKey(p.id) ? 'Aktualizuj' : 'Zainstaluj'),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }
}

class ClockThemePage extends StatefulWidget {
  const ClockThemePage({super.key, required this.controller, this.loadIndex = loadThemePackIndex});

  final DeviceController<Object?, Object?> controller;

  /// Indeks paczek do pobrania (w testach podmieniany).
  final Future<List<ClockPack>> Function() loadIndex;

  @override
  State<ClockThemePage> createState() => _ClockThemePageState();
}

class _ClockThemePageState extends State<ClockThemePage> with _ClockConfig, _ClockPacks {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  /// Set `theme` bez `packs` (lista paczek jest tylko do odczytu).
  Future<Map<String, String>> _setTheme(Json changes) => send({
    'theme': {...obj('theme'), ...changes}..remove('packs'),
  });

  @override
  Widget build(BuildContext context) {
    final t = obj('theme');
    final chosen = t['name'] as String? ?? 'pastel';
    final seasonal = t['seasonal'] == true;
    final packs = clockHasThemePacks(cfg, c.stateJson);
    return page('Motyw', [
      SwitchListTile(
        key: const Key('clockSeasonal'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Według pory roku'),
        subtitle: Text(
          'Adwent 1-23.12 (6.12 Mikołajki), Boże Narodzenie 24.12-6.01, zima, roztopy, wiosna, Wielkanoc, lato, '
          'wakacje 28.06-31.08, babie lato, jesień i szaruga według kalendarza; '
          'zimą i w święta po zachodzie słońca wersja wieczorna'
          '${packs ? '. Okresy z zainstalowanych paczek mają pierwszeństwo' : ''}',
        ),
        value: seasonal,
        onChanged: (v) => _setTheme({'seasonal': v}),
      ),
      SwitchListTile(
        key: const Key('clockAnimations'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Animacje ozdób'),
        subtitle: const Text('Lekkie kołysanie ozdób w narożnikach (ekran trochę bardziej grzeje czujnik)'),
        value: t['animations'] != false,
        onChanged: (v) => _setTheme({'animations': v}),
      ),
      SectionHeader(seasonal ? 'Motyw (gdy wyłączysz porę roku)' : 'Motyw'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
        children: [
          for (final MapEntry(key: k, value: th) in clockThemes.entries)
            _ThemeTile(
              key: Key('clockTheme-$k'),
              theme: th,
              selected: k == chosen,
              onTap: () => _setTheme({'name': k}),
            ),
        ],
      ),
      if (packs)
        ...packSection(
          content: false,
          load: widget.loadIndex,
          below: (p) => Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in p.items)
                ChoiceChip(
                  key: Key('clockTheme-${p.id}/${t.id}'),
                  label: Text(t.name),
                  selected: chosen == '${p.id}/${t.id}',
                  onSelected: (_) => _setTheme({'name': '${p.id}/${t.id}'}),
                ),
            ],
          ),
        ),
    ]);
  }
}

/// Miniatura ekranu głównego zegara w kolorach motywu (karta godziny, pogoda, trzy kafle).
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({super.key, required this.theme, required this.selected, required this.onTap});

  final ClockTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(int color) => Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(6)),
        child: const SizedBox.expand(),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Color(theme.bg),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 3 : 1),
              ),
              child: Column(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(color: Color(theme.card), borderRadius: BorderRadius.circular(6)),
                            alignment: Alignment.center,
                            child: Text(
                              '15:52',
                              style: TextStyle(color: Color(theme.ink), fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        tile(theme.tiles[3]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        tile(theme.tiles[0]),
                        const SizedBox(width: 4),
                        tile(theme.tiles[1]),
                        const SizedBox(width: 4),
                        tile(theme.tiles[2]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(theme.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
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

// ---------------------------------------------------------------- Wiadomości

/// „1 kanał”, „3 kanały”, „5 kanałów”.
String clockFeedsText(int n) {
  final few = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return '$n ${n == 1
      ? 'kanał'
      : few
      ? 'kanały'
      : 'kanałów'}';
}

/// Kanały RSS i ostrzeżenia IMGW (Config `news`): lista kanałów, słowa kluczowe, pobieranie, stan z State `news`.
class ClockNewsPage extends StatefulWidget {
  const ClockNewsPage({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<ClockNewsPage> createState() => _ClockNewsPageState();
}

class _ClockNewsPageState extends State<ClockNewsPage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  List<ClockFeed> get _feeds => ClockFeed.listFrom(obj('news'));

  List<String> get _keywords => [
    for (final k in (obj('news')['keywords'] as List? ?? const []))
      if (k is String) k,
  ];

  Future<void> _setFeeds(List<ClockFeed> feeds) => setIn('news', {
    'feeds': [for (final f in feeds) f.toJson()],
  });

  Future<void> _edit(int index) async {
    final feeds = _feeds;
    final f = await showDialog<ClockFeed>(
      context: context,
      builder: (_) => _FeedDialog(feed: feeds[index]),
    );
    if (f != null) await _setFeeds([...feeds]..[index] = f);
  }

  Future<void> _add() async {
    final feeds = _feeds;
    if (feeds.length >= clockMaxFeeds) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Najwyżej $clockMaxFeeds kanałów.')));
      return;
    }
    final used = {for (final f in feeds) f.url};
    final pick = await showDialog<Object>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Dodaj kanał'),
        children: [
          ListTile(
            key: const Key('clockFeedOwn'),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Własny adres RSS'),
            onTap: () => Navigator.pop(ctx, 'own'),
          ),
          ListTile(
            key: const Key('clockFeedImgw'),
            leading: const Icon(Icons.thunderstorm_outlined),
            title: const Text('Ostrzeżenia IMGW'),
            subtitle: const Text('Ostrzeżenia meteo dla powiatu'),
            onTap: () => Navigator.pop(ctx, 'imgw'),
          ),
          const Divider(),
          for (final s in clockNewsSuggestions.where((s) => !used.contains(s.url)))
            ListTile(
              key: Key('clockFeedSuggest-${s.name}'),
              leading: const Icon(Icons.rss_feed),
              title: Text(s.name),
              subtitle: Text(Uri.parse(s.url).host),
              onTap: () => Navigator.pop(ctx, ClockFeed(name: s.name, url: s.url)),
            ),
        ],
      ),
    );
    if (!mounted || pick == null) return;
    final f = pick is ClockFeed
        ? pick
        : await showDialog<ClockFeed>(
            context: context,
            builder: (_) => _FeedDialog(
              feed: pick == 'imgw' ? const ClockFeed(name: 'IMGW', imgw: '', alert: true) : null,
            ),
          );
    if (f != null) await _setFeeds([..._feeds, f]);
  }

  Future<void> _remove(int index) async {
    final f = _feeds[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć kanał „${f.name}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            key: const Key('clockFeedRemoveOk'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok == true) await _setFeeds([..._feeds]..removeAt(index));
  }

  Future<void> _addKeyword() async {
    final words = _keywords;
    if (words.length >= clockMaxKeywords) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Najwyżej $clockMaxKeywords słów.')));
      return;
    }
    final w = await showTextInputDialog(
      context,
      title: 'Słowo kluczowe',
      hint: 'np. burz (pasuje też „burza”)',
      fieldKey: const Key('clockKeywordField'),
    );
    if (w == null || !mounted) return;
    final err = clockKeywordError(w);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    if (words.any((k) => k.toLowerCase() == w.toLowerCase())) return;
    await setIn('news', {
      'keywords': [...words, w],
    });
  }

  /// Stan z zegara (State `news`): liczba pozycji, wiek pobrania, błędy kanałów, nieprzeczytane ważne.
  List<Widget> _status() {
    final s = c.stateJson?['news'];
    final unread = (c.stateJson?['newsUnread'] as num?)?.toInt() ?? 0;
    if (s is! Map) return const [];
    final age = s['age'];
    final alert = s['alert'];
    return [
      const SectionHeader('Na zegarze'),
      ListTile(
        key: const Key('clockNewsStatus'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.newspaper_outlined),
        title: Text('${s['items'] ?? 0} wiadomości'),
        subtitle: Text(age is num ? 'pobrane ${fmtAge(age.toInt())}' : 'jeszcze nie pobrane'),
      ),
      for (final e in (s['errors'] as List? ?? const []))
        if (e is Map)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            title: Text('${e['name']}'),
            subtitle: Text('${e['error']}'),
          ),
      if (unread > 0)
        ListTile(
          key: const Key('clockNewsUnread'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.notification_important_outlined, color: Theme.of(context).colorScheme.error),
          title: Text(alert is Map ? '${alert['title']}' : 'Ważne wiadomości: $unread'),
          subtitle: Text(alert is Map ? '${alert['source']} · nieprzeczytane: $unread' : 'nieprzeczytane'),
          trailing: c.canControl
              ? TextButton(
                  key: const Key('clockNewsRead'),
                  onPressed: () => send({'newsRead': true}),
                  child: const Text('Przeczytane'),
                )
              : null,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!clockHasNews(cfg)) {
      return page('Wiadomości', const [Text('Ten zegar nie ma jeszcze wiadomości - zaktualizuj jego firmware.')]);
    }
    final n = obj('news');
    final feeds = _feeds;
    final words = _keywords;
    final refresh = (n['refreshMin'] as num?)?.toInt() ?? 10;
    final jump = (n['jumpS'] as num?)?.toInt() ?? 60;
    final onScreen = clockScreenList(cfg).contains('news');
    return page('Wiadomości', [
      const Text(
        'Zegar sam pobiera kanały RSS i ostrzeżenia IMGW. Ważna wiadomość (z kanału alarmowego albo ze słowem '
        'kluczowym w tytule) pokazuje pasek i przełącza zegar na ekran wiadomości.',
      ),
      if (!onScreen)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Ekranu „Wiadomości” nie ma w pokazie (Ekrany) - zegar przełączy się na niego tylko przy ważnej wiadomości.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ..._status(),
      SectionHeader('Kanały (${feeds.length}/$clockMaxFeeds)'),
      if (feeds.isEmpty) const Text('Bez kanałów zegar nic nie pobiera.'),
      for (final (i, f) in feeds.indexed)
        ListTile(
          key: Key('clockFeed-$i'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(f.isImgw ? Icons.thunderstorm_outlined : Icons.rss_feed),
          title: Text(f.name),
          subtitle: Text(
            f.isImgw ? 'Ostrzeżenia IMGW · ${clockPowiaty[f.imgw] ?? 'powiat'} (${f.imgw})' : f.url ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _edit(i),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Alarmowy: każda nowa pozycja ważna',
                child: Switch(
                  key: Key('clockFeedAlert-$i'),
                  value: f.alert,
                  onChanged: (v) => _setFeeds([...feeds]..[i] = f.copyWith(alert: v)),
                ),
              ),
              IconButton(
                key: Key('clockFeedRemove-$i'),
                tooltip: 'Usuń',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(i),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const Key('clockFeedAdd'),
          icon: const Icon(Icons.add),
          label: const Text('Dodaj kanał'),
          onPressed: feeds.length < clockMaxFeeds ? _add : null,
        ),
      ),
      SectionHeader('Słowa kluczowe (${words.length}/$clockMaxKeywords)'),
      Text(
        'Wiadomość ze słowem w tytule jest ważna - z każdego kanału. Wielkość liter i polskie znaki bez znaczenia, '
        'wystarczy fragment („burz” pasuje do „burza”).',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final w in words)
            InputChip(
              key: Key('clockKeyword-$w'),
              label: Text(w),
              deleteIcon: const Icon(Icons.close, size: 18),
              deleteButtonTooltipMessage: 'Usuń',
              onDeleted: () => setIn('news', {'keywords': words.where((k) => k != w).toList()}),
            ),
          ActionChip(
            key: const Key('clockKeywordAdd'),
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Dodaj słowo'),
            onPressed: words.length < clockMaxKeywords ? _addKeyword : null,
          ),
        ],
      ),
      const SectionHeader('Pobieranie i przeskok'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Pobieranie co'),
        subtitle: const Text('Po błędzie zegar ponawia po 5 min'),
        trailing: DropdownButton<int>(
          key: const Key('clockNewsRefresh'),
          value: refresh,
          items: [
            for (final v in {5, 10, 15, 30, 60, 120, refresh}) DropdownMenuItem(value: v, child: Text('$v min')),
          ],
          onChanged: (v) => setIn('news', {'refreshMin': v}),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ekran wiadomości przy ważnej'),
        subtitle: Text(
          jump == 0
              ? 'Tylko pasek, bez przełączania ekranu'
              : 'Na $jump s; w nocy i przy wstrzymanym pokazie tylko z kanału alarmowego',
        ),
        trailing: DropdownButton<int>(
          key: const Key('clockNewsJump'),
          value: jump,
          items: [
            for (final v in {0, 10, 30, 60, 120, 300, 600, jump})
              DropdownMenuItem(value: v, child: Text(v == 0 ? 'tylko pasek' : '$v s')),
          ],
          onChanged: (v) => setIn('news', {'jumpS': v}),
        ),
      ),
    ]);
  }
}

/// Edycja kanału: nazwa, adres RSS albo kod powiatu IMGW, alarmowy. Zwraca kanał albo null (Anuluj).
class _FeedDialog extends StatefulWidget {
  const _FeedDialog({this.feed});

  final ClockFeed? feed;

  @override
  State<_FeedDialog> createState() => _FeedDialogState();
}

class _FeedDialogState extends State<_FeedDialog> {
  late final _name = TextEditingController(text: widget.feed?.name ?? '');
  late final _url = TextEditingController(text: widget.feed?.url ?? 'https://');
  late final _teryt = TextEditingController(text: widget.feed?.imgw ?? '');
  late bool _imgw = widget.feed?.isImgw ?? false;
  late bool _alert = widget.feed?.alert ?? false;
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _teryt.dispose();
    super.dispose();
  }

  String? get _nameError => clockFeedNameError(_name.text.trim());
  String? get _sourceError => _imgw ? clockTerytError(_teryt.text.trim()) : clockFeedUrlError(_url.text.trim());

  void _save() {
    if (_nameError != null || _sourceError != null) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop(
      context,
      ClockFeed(
        name: _name.text.trim(),
        url: _imgw ? null : _url.text.trim(),
        imgw: _imgw ? _teryt.text.trim() : null,
        alert: _alert,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final powiat = clockPowiaty[_teryt.text.trim()];
    return AlertDialog(
      title: const Text('Kanał'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              key: const Key('clockFeedKind'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('RSS')),
                ButtonSegment(value: true, label: Text('IMGW')),
              ],
              selected: {_imgw},
              onSelectionChanged: (v) => setState(() => _imgw = v.single),
            ),
            TextField(
              key: const Key('clockFeedName'),
              controller: _name,
              decoration: InputDecoration(labelText: 'Nazwa (na ekranie)', errorText: _tried ? _nameError : null),
              onChanged: (_) => setState(() {}),
            ),
            if (_imgw)
              TextField(
                key: const Key('clockFeedTeryt'),
                controller: _teryt,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Kod TERYT powiatu',
                  hintText: '1201',
                  helperText: powiat != null ? 'powiat $powiat' : 'np. 1201 = bocheński, 1261 = Kraków',
                  errorText: _tried ? _sourceError : null,
                ),
                onChanged: (_) => setState(() {}),
              )
            else
              TextField(
                key: const Key('clockFeedUrl'),
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'Adres RSS / Atom', errorText: _tried ? _sourceError : null),
                onChanged: (_) => setState(() {}),
              ),
            SwitchListTile(
              key: const Key('clockFeedAlertEdit'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarmowy'),
              subtitle: const Text('Każda nowa pozycja ważna: pasek i ekran wiadomości, także w nocy'),
              value: _alert,
              onChanged: (v) => setState(() => _alert = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(key: const Key('clockFeedSave'), onPressed: _save, child: const Text('Zapisz')),
      ],
    );
  }
}

// ---------------------------------------------------------------- Radio

/// Radio internetowe zegara: sterowanie (Set `radioOn`, `radioStation`, `radioVol`, `radioMute`, State `radio`),
/// lista stacji i ustawienia (Config `radio`).
class ClockRadioPage extends StatefulWidget {
  const ClockRadioPage({super.key, required this.controller, this.findLogos});

  final DeviceController<Object?, Object?> controller;

  /// Szukanie logo stacji (testy podstawiają własne); domyślnie katalog radio-browser.info.
  final Future<List<String>> Function(String name, String streamUrl)? findLogos;

  @override
  State<ClockRadioPage> createState() => _ClockRadioPageState();
}

class _ClockRadioPageState extends State<ClockRadioPage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  /// Głośność, moc i czas ekranu radia w czasie przesuwania suwaka (Set dopiero po puszczeniu).
  double? _vol, _maxW, _showS;

  List<ClockStation> get _stations => clockStationsFrom(obj('radio'));

  Future<void> _setStations(List<ClockStation> list) => setIn('radio', {
    'stations': [for (final s in list) clockStationJson(s)],
  });

  Future<void> _edit(int? index) async {
    final list = _stations;
    if (index == null && list.length >= clockMaxStations) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Najwyżej $clockMaxStations stacji.')));
      return;
    }
    final s = await showDialog<ClockStation>(
      context: context,
      builder: (_) => _StationDialog(
        station: index == null ? null : list[index],
        withLogo: clockHasRadioScreen(cfg),
        findLogos: widget.findLogos ?? (name, url) => findStationLogos(name: name, streamUrl: url),
      ),
    );
    if (s == null) return;
    await _setStations(index == null ? [...list, s] : ([...list]..[index] = s));
  }

  Future<void> _remove(int index) async {
    final s = _stations[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć stację „${s.name}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            key: const Key('clockStationRemoveOk'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok == true) await _setStations([..._stations]..removeAt(index));
  }

  /// Stan odtwarzania z State `radio`.
  String _playText(Json st) {
    final r = st['radio'] is Map ? st['radio'] as Map : const {};
    if (st['radioOn'] != true) return 'Wyłączone';
    final what = st['radioStation'] as String? ?? '';
    return switch (r['state']) {
      'connecting' => 'Łączenie: $what…',
      'error' => 'Brak połączenia ze stacją $what (${r['error'] ?? 'błąd'}), kolejna próba za kilka minut',
      'playing' => [
        if (st['radioMute'] == true) 'Wyciszone' else 'Gra',
        '$what${r['title'] is String && (r['title'] as String).isNotEmpty ? ' - ${r['title']}' : ''}',
      ].join(': '),
      _ => what,
    };
  }

  List<Widget> _control(List<ClockStation> stations) {
    final st = c.stateJson ?? const <String, dynamic>{};
    final on = st['radioOn'] == true;
    final mute = st['radioMute'] == true;
    final vol = _vol ?? ((st['radioVol'] as num?)?.toDouble() ?? 50).clamp(0, 100).toDouble();
    final r = st['radio'] is Map ? st['radio'] as Map : const {};
    return [
      SwitchListTile(
        key: const Key('clockRadioOn'),
        contentPadding: EdgeInsets.zero,
        secondary: Icon(on ? Icons.radio : Icons.radio_outlined),
        title: const Text('Radio'),
        subtitle: Text(_playText(st)),
        value: on,
        onChanged: c.canControl ? (v) => send({'radioOn': v}) : null,
      ),
      if (on && r['codec'] != null)
        Text(
          [
            '${r['codec']}',
            if (r['kbps'] is num) '${r['kbps']} kb/s',
            if (r['buffer'] is num) 'bufor ${r['buffer']} %',
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (on && r['logo'] == 'error')
        Text(
          'Logo tej stacji nie dało się pobrać albo to nie PNG / JPG do 64 KB - zegar pokazuje inicjały.',
          key: const Key('clockRadioLogoError'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      Row(
        children: [
          IconButton(
            key: const Key('clockRadioMute'),
            tooltip: mute ? 'Przywróć dźwięk' : 'Wycisz',
            icon: Icon(mute ? Icons.volume_off : Icons.volume_up),
            onPressed: c.canControl && on ? () => send({'radioMute': !mute}) : null,
          ),
          Expanded(
            child: Slider(
              key: const Key('clockRadioVol'),
              value: vol,
              max: 100,
              divisions: 20,
              label: '${vol.round()} %',
              onChanged: c.canControl ? (v) => setState(() => _vol = v) : null,
              onChangeEnd: (v) async {
                await send({'radioVol': v.round()});
                if (mounted) setState(() => _vol = null);
              },
            ),
          ),
          SizedBox(width: 48, child: Text('${vol.round()} %', textAlign: TextAlign.end)),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!clockHasRadio(cfg)) {
      return page('Radio', const [Text('Ten zegar nie ma radia - wymaga nowszego firmware.')]);
    }
    final r = obj('radio');
    final stations = _stations;
    final current = c.stateJson?['radioStation'] as String?;
    final on = c.stateJson?['radioOn'] == true;
    final muteOff = (r['muteOffMin'] as num?)?.toInt() ?? 10;
    final maxW = _maxW ?? ((r['maxW'] as num?)?.toDouble() ?? 0.8).clamp(0.1, 1.5).toDouble();
    final showS = _showS ?? ((r['showS'] as num?)?.toDouble() ?? 10).clamp(0, 120).toDouble();
    return page('Radio', [
      if (stations.isEmpty)
        const Text('Dodaj stację (strumień MP3), żeby włączyć radio. Bez stacji zegar nie pokazuje radia.')
      else
        ..._control(stations),
      Text(
        'Na zegarze: przytrzymanie lewego / prawego - głośność, dwuklik lewego / prawego na ekranie głównym '
        '${clockHasRadioScreen(cfg) ? 'i ekranie radia ' : ''}- poprzednia / następna stacja, dwuklik środkowego - '
        'włącz, wycisz, przywróć.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      SectionHeader('Stacje (${stations.length}/$clockMaxStations)'),
      for (final (i, s) in stations.indexed)
        ListTile(
          key: Key('clockStation-$i'),
          contentPadding: EdgeInsets.zero,
          leading: IconButton(
            key: Key('clockStationPlay-$i'),
            tooltip: 'Graj',
            icon: Icon(on && current == s.name ? Icons.graphic_eq : Icons.play_arrow),
            onPressed: c.canControl ? () => send({'radioStation': s.name}) : null,
          ),
          title: Text(s.name),
          subtitle: Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: on && current == s.name,
          onTap: () => _edit(i),
          trailing: IconButton(
            key: Key('clockStationRemove-$i'),
            tooltip: 'Usuń',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _remove(i),
          ),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const Key('clockStationAdd'),
          icon: const Icon(Icons.add),
          label: const Text('Dodaj stację'),
          onPressed: stations.length < clockMaxStations ? () => _edit(null) : null,
        ),
      ),
      const SectionHeader('Ustawienia'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Wyłącz po wyciszeniu'),
        subtitle: const Text('Wyciszone radio wyłącza się po tym czasie'),
        trailing: DropdownButton<int>(
          key: const Key('clockRadioMuteOff'),
          value: muteOff,
          items: [
            for (final v in {0, 1, 5, 10, 15, 30, 60, 120, muteOff})
              DropdownMenuItem(value: v, child: Text(v == 0 ? 'nigdy' : '$v min')),
          ],
          onChanged: (v) => setIn('radio', {'muteOffMin': v}),
        ),
      ),
      SwitchListTile(
        key: const Key('clockRadioResume'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Graj dalej po restarcie'),
        subtitle: const Text('Po zaniku zasilania albo aktualizacji radio włącza się samo'),
        value: r['resume'] == true,
        onChanged: (v) => setIn('radio', {'resume': v}),
      ),
      // Korekcja głośnika (fw 0.7.1 zgłasza radio.eq); zmiana działa w locie
      if (r['eq'] is String) ...[
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Korekcja głośnika'),
        ),
        SegmentedButton<String>(
          key: const Key('clockRadioEq'),
          segments: [
            for (final MapEntry(key: k, value: label) in clockRadioEq.entries)
              ButtonSegment(value: k, label: Text(label)),
          ],
          selected: {r['eq'] as String},
          onSelectionChanged: (v) => setIn('radio', {'eq': v.single}),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            clockRadioEqHints[r['eq']] ?? '',
            key: const Key('clockRadioEqHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
      if (clockHasRadioScreen(cfg)) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            showS == 0 ? 'Ekran radia po włączeniu: nie pokazuj' : 'Ekran radia po włączeniu: ${showS.round()} s',
          ),
          subtitle: const Text(
            'Po włączeniu radia albo zmianie stacji zegar pokazuje stację, logo i tytuł, potem wraca do poprzedniego ekranu',
          ),
        ),
        Slider(
          key: const Key('clockRadioShowS'),
          value: showS,
          max: 120,
          divisions: 24,
          label: showS == 0 ? 'nie' : '${showS.round()} s',
          onChanged: (v) => setState(() => _showS = v),
          onChangeEnd: (v) async {
            await setIn('radio', {'showS': v.round()});
            if (mounted) setState(() => _showS = null);
          },
        ),
      ],
      ExpansionTile(
        key: const Key('clockRadioAdvanced'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Zaawansowane'),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Moc przy 100 % głośności: ${maxW.toStringAsFixed(1).replaceAll('.', ',')} W'),
            subtitle: const Text(
              'Zasilanie zegara ma bezpiecznik 500 mA - przy głośnym graniu i jasnym ekranie '
              'większa moc może go wyzwolić.',
            ),
          ),
          Slider(
            key: const Key('clockRadioMaxW'),
            value: maxW,
            min: 0.1,
            max: 1.5,
            divisions: 14,
            label: '${maxW.toStringAsFixed(1)} W',
            onChanged: (v) => setState(() => _maxW = v),
            onChangeEnd: (v) async {
              await setIn('radio', {'maxW': double.parse(v.toStringAsFixed(1))});
              if (mounted) setState(() => _maxW = null);
            },
          ),
        ],
      ),
    ]);
  }
}

/// Edycja stacji: nazwa, adres strumienia MP3 i (zegar z ekranem radia) logo. Zwraca stację albo null (Anuluj).
class _StationDialog extends StatefulWidget {
  const _StationDialog({this.station, this.withLogo = false, required this.findLogos});

  final ClockStation? station;
  final bool withLogo;
  final Future<List<String>> Function(String name, String streamUrl) findLogos;

  @override
  State<_StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends State<_StationDialog> {
  late final _name = TextEditingController(text: widget.station?.name ?? '');
  late final _url = TextEditingController(text: widget.station?.url ?? 'https://');
  late final _logo = TextEditingController(text: widget.station?.logo ?? '');
  bool _tried = false, _searching = false;
  String? _searchNote;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _logo.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim(), url = _url.text.trim(), logo = _logo.text.trim();
    if (clockFeedNameError(name) != null || clockFeedUrlError(url) != null || clockLogoUrlError(logo) != null) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop(context, (name: name, url: url, logo: logo));
  }

  /// „Znajdź logo”: katalog radio-browser.info po adresie strumienia albo nazwie; kilka wyników - wybór z podglądem.
  Future<void> _find() async {
    setState(() {
      _searching = true;
      _searchNote = null;
    });
    final found = await widget.findLogos(_name.text.trim(), _url.text.trim());
    if (!mounted) return;
    setState(() => _searching = false);
    if (found.isEmpty) {
      setState(() => _searchNote = 'Nie znaleziono logo w katalogu radio-browser.info - wklej adres obrazka.');
      return;
    }
    final pick = found.length == 1
        ? found.first
        : await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Wybierz logo'),
              children: [
                for (final (i, u) in found.take(8).indexed)
                  SimpleDialogOption(
                    key: Key('clockLogoPick-$i'),
                    onPressed: () => Navigator.pop(ctx, u),
                    child: Row(
                      children: [
                        _LogoPreview(url: u, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(Uri.tryParse(u)?.host ?? u, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
    if (pick != null && mounted) setState(() => _logo.text = pick);
  }

  @override
  Widget build(BuildContext context) {
    final logo = _logo.text.trim();
    final logoErr = clockLogoUrlError(logo);
    return AlertDialog(
      title: const Text('Stacja'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('clockStationName'),
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Nazwa (na ekranie)',
                errorText: _tried ? clockFeedNameError(_name.text.trim()) : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('clockStationUrl'),
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Adres strumienia (MP3)',
                errorText: _tried ? clockFeedUrlError(_url.text.trim()) : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.withLogo) ...[
              TextField(
                key: const Key('clockStationLogo'),
                controller: _logo,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Logo (opcjonalnie, PNG / JPG)',
                  errorText: _tried ? logoErr : null,
                  helperText: clockLogoWarning(logo) ?? 'Bez logo zegar pokaże inicjały stacji',
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (logo.isNotEmpty && logoErr == null) ...[
                    _LogoPreview(url: logo, size: 76),
                    const SizedBox(width: 12),
                  ],
                  FilledButton.tonalIcon(
                    key: const Key('clockStationFindLogo'),
                    icon: _searching
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_search),
                    label: const Text('Znajdź logo'),
                    onPressed: _searching || clockFeedUrlError(_url.text.trim()) != null ? null : _find,
                  ),
                ],
              ),
              if (_searchNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_searchNote!, style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(key: const Key('clockStationSave'), onPressed: _save, child: const Text('Zapisz')),
      ],
    );
  }
}

/// Podgląd logo z sieci (biały kafel z zaokrągleniem jak na zegarze); błąd wczytania - ikona.
class _LogoPreview extends StatelessWidget {
  const _LogoPreview({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.18),
    child: Container(
      width: size,
      height: size,
      color: Colors.white,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, size: size * 0.5, color: Colors.grey),
      ),
    ),
  );
}

// ---------------------------------------------------------------- Dymki i ciekawostki

/// Dymki (Config `bubbles`): głośność sygnału i limit zwykłych dymków na dobę.
class ClockBubblesPage extends StatefulWidget {
  const ClockBubblesPage({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<ClockBubblesPage> createState() => _ClockBubblesPageState();
}

class _ClockBubblesPageState extends State<ClockBubblesPage> with _ClockConfig {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  double? _vol;

  @override
  Widget build(BuildContext context) {
    if (!clockHasBubbles(cfg)) {
      return page('Dymki', const [Text('Ten zegar nie ma dymków - wymaga nowszego firmware.')]);
    }
    final b = obj('bubbles');
    final vol = _vol ?? ((b['vol'] as num?)?.toDouble() ?? 30).clamp(0, 100).toDouble();
    final max = (b['maxPerDay'] as num?)?.toInt() ?? 30;
    return page('Dymki', [
      const Text(
        'Dymki to krótkie wiadomości na ekranie zegara - z aplikacji („Wiadomość” na ekranie zegara) albo '
        'z automatyki („Dymek na zegarze”). Odpowiedź środkowym przyciskiem może uruchomić inną automatykę.',
      ),
      const SectionHeader('Dźwięk'),
      Row(
        children: [
          const Icon(Icons.volume_down),
          Expanded(
            child: Slider(
              key: const Key('clockBubbleVol'),
              value: vol,
              max: 100,
              divisions: 20,
              label: '${vol.round()} %',
              onChanged: (v) => setState(() => _vol = v),
              onChangeEnd: (v) async {
                await setIn('bubbles', {'vol': v.round()});
                if (mounted) setState(() => _vol = null);
              },
            ),
          ),
          SizedBox(width: 48, child: Text('${vol.round()} %', textAlign: TextAlign.end)),
        ],
      ),
      Text(
        'Niezależnie od radia; grające radio na czas sygnału się ścisza.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SectionHeader('Limit'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Zwykłe dymki na dobę'),
        subtitle: const Text('Ważne dymki nie mają limitu'),
        trailing: DropdownButton<int>(
          key: const Key('clockBubbleMax'),
          value: max,
          items: [
            for (final v in {5, 10, 20, 30, 50, 100, 200, max}) DropdownMenuItem(value: v, child: Text('$v')),
          ],
          onChanged: (v) => setIn('bubbles', {'maxPerDay': v}),
        ),
      ),
    ]);
  }
}

const _dayLetters = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

/// Ciekawostki (Config `fun`): liczba dziennie, okno godzin, dni, kategorie z paczek treści, czas i dźwięk;
/// paczki treści jak paczki motywów.
class ClockFunPage extends StatefulWidget {
  const ClockFunPage({super.key, required this.controller, this.loadIndex = loadContentPackIndex});

  final DeviceController<Object?, Object?> controller;

  /// Indeks paczek treści (w testach podmieniany).
  final Future<List<ClockPack>> Function() loadIndex;

  @override
  State<ClockFunPage> createState() => _ClockFunPageState();
}

class _ClockFunPageState extends State<ClockFunPage> with _ClockConfig, _ClockPacks {
  @override
  DeviceController<Object?, Object?> get c => widget.controller;

  /// Kategorie z zainstalowanych paczek; ta sama kategoria w kilku paczkach - pozycje razem.
  Map<String, ({String name, int count})> get _categories {
    final out = <String, ({String name, int count})>{};
    for (final p in ClockPack.listFrom(c.stateJson?['contentPacks'])) {
      for (final i in p.items) {
        out[i.id] = (name: out[i.id]?.name ?? i.name, count: (out[i.id]?.count ?? 0) + i.count);
      }
    }
    return out;
  }

  Future<void> _window(bool start, String window) async {
    final parts = window.split('-');
    final from = _parseHhmm(parts.first) ?? const TimeOfDay(hour: 9, minute: 0);
    final to = _parseHhmm(parts.length > 1 ? parts[1] : '') ?? const TimeOfDay(hour: 20, minute: 0);
    final t = await _pickTime(context, start ? from : to);
    if (t == null || !mounted) return;
    final a = start ? t : from, b = start ? to : t;
    if (a.hour * 60 + a.minute >= b.hour * 60 + b.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Okno w ciągu jednego dnia: początek przed końcem (bez przejścia przez północ).')),
      );
      return;
    }
    await setIn('fun', {'window': '${_hhmm(a)}-${_hhmm(b)}'});
  }

  Future<void> _toggleCategory(String id, List<String> chosen, Iterable<String> all) async {
    final on = chosen.isEmpty ? {...all} : {...chosen};
    on.contains(id) ? on.remove(id) : on.add(id);
    if (on.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zostaw co najmniej jedną kategorię.')));
      return;
    }
    await setIn('fun', {
      'categories': on.containsAll(all)
          ? <String>[]
          : [
              for (final k in all)
                if (on.contains(k)) k,
            ],
    });
  }

  /// Stan z zegara (State `fun`).
  String? _today() {
    final f = c.stateJson?['fun'];
    if (f is! Map) return null;
    final next = f['next'];
    final nextText = next is num && next > 0
        ? ', następna o ${_hhmm(TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(next.toInt() * 1000)))}'
        : (next is String ? ', następna o $next' : '');
    return f['today'] is num ? 'Dziś pokazane: ${f['today']}$nextText' : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!clockHasBubbles(cfg)) {
      return page('Ciekawostki', const [Text('Ten zegar nie ma ciekawostek - wymaga nowszego firmware.')]);
    }
    final f = obj('fun');
    final enabled = f['enabled'] != false;
    final perDay = (f['perDay'] as num?)?.toInt() ?? 3;
    final window = f['window'] as String? ?? '09:00-20:00';
    final days = {
      for (final d in (f['days'] as List? ?? const [1, 2, 3, 4, 5, 6, 7]))
        if (d is int) d,
    };
    final chosen = [
      for (final k in (f['categories'] as List? ?? const []))
        if (k is String) k,
    ];
    final ttl = (f['ttlS'] as num?)?.toInt() ?? 60;
    final sound = clockBubbleSounds.containsKey(f['sound']) ? f['sound'] as String : 'pop';
    final cats = _categories;
    final today = _today();
    return page('Ciekawostki', [
      SwitchListTile(
        key: const Key('clockFunOn'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Ciekawostki w dymkach'),
        subtitle: Text(
          today ?? 'Święto dnia, ciekawostki, zagadki i cytaty o losowych porach (co najmniej 45 min odstępu)',
        ),
        value: enabled,
        onChanged: (v) => setIn('fun', {'enabled': v}),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Dziennie'),
        trailing: DropdownButton<int>(
          key: const Key('clockFunPerDay'),
          value: perDay,
          items: [for (var v = 1; v <= 12; v++) DropdownMenuItem(value: v, child: Text('$v'))],
          onChanged: enabled ? (v) => setIn('fun', {'perDay': v}) : null,
        ),
      ),
      ListTile(
        key: const Key('clockFunFrom'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Od godziny'),
        trailing: Text(window.split('-').first),
        enabled: enabled,
        onTap: () => _window(true, window),
      ),
      ListTile(
        key: const Key('clockFunTo'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Do godziny'),
        trailing: Text(window.contains('-') ? window.split('-')[1] : ''),
        enabled: enabled,
        onTap: () => _window(false, window),
      ),
      Wrap(
        spacing: 6,
        children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              key: Key('clockFunDay-$d'),
              label: Text(_dayLetters[d - 1]),
              selected: days.contains(d),
              onSelected: !enabled
                  ? null
                  : (v) {
                      final next = {...days};
                      v ? next.add(d) : next.remove(d);
                      if (next.isEmpty) return;
                      setIn('fun', {'days': next.toList()..sort()});
                    },
            ),
        ],
      ),
      const SectionHeader('Kategorie'),
      if (cats.isEmpty)
        const Text('Kategorie pokaże zegar z zestawem ciekawostek.')
      else
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final MapEntry(key: id, value: cat) in cats.entries)
              FilterChip(
                key: Key('clockFunCat-$id'),
                label: Text(cat.count > 0 ? '${cat.name} (${cat.count})' : cat.name),
                selected: chosen.isEmpty || chosen.contains(id),
                onSelected: enabled ? (_) => _toggleCategory(id, chosen, cats.keys) : null,
              ),
          ],
        ),
      const SectionHeader('Dymek'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Na ekranie'),
        trailing: DropdownButton<int>(
          key: const Key('clockFunTtl'),
          value: ttl,
          items: [
            for (final v in {...clockFunTtl, ttl})
              DropdownMenuItem(value: v, child: Text(v < 60 ? '$v s' : '${v ~/ 60} min')),
          ],
          onChanged: enabled ? (v) => setIn('fun', {'ttlS': v}) : null,
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Dźwięk'),
        trailing: DropdownButton<String>(
          key: const Key('clockFunSound'),
          value: sound,
          items: [
            for (final MapEntry(key: k, value: l) in clockBubbleSounds.entries)
              DropdownMenuItem(value: k, child: Text(l)),
          ],
          onChanged: enabled ? (v) => setIn('fun', {'sound': v}) : null,
        ),
      ),
      ...packSection(content: true, load: widget.loadIndex),
    ]);
  }
}
