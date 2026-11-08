// Strony z widżetami zegara (pkt 10.2, PLAN zegara pkt 1.5, 8.6, 9): lista stron, edytor siatki 4×3 z podglądem
// 320×240 w stylu C, „Z pulpitu telefonu…”, przy zapisie opisy z `describe` i rozwinięcie `room` / `group`.
// Tylko urządzenia znane hubowi zegara - inne wyszarzone.

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../data/device_store.dart';
import '../data/errors.dart';
import '../data/hub_api.dart';
import '../models/clock.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/json_utils.dart';
import '../models/room.dart';
import '../services.dart';
import 'app_icons.dart';
import 'clock_section.dart' show clockScreenList;
import 'dashboard_tiles.dart' show fallbackPoint;
import 'format.dart';
import 'widget_editor.dart' show pointsOf;
import 'widgets.dart';

/// Urządzenia znane hubowi zegara: hub, jego urządzenia (`via`) i - w domu - lista `GET /api/devices` huba.
Future<Set<String>> clockKnownDevices(DeviceHub hub, DeviceController<Object?, Object?> clock) async {
  final hubId = clock.device.via;
  if (hubId == null) return const {};
  final out = <String>{
    hubId,
    for (final d in hub.devices)
      if (d.via == hubId) d.id,
  };
  final api = hub.controller(hubId)?.localApi;
  if (api != null) {
    try {
      out.addAll((await HubApi(api).devices()).map((d) => d.id));
    } on ThermostatException {
      // Bez listy huba - wystarczy `via`.
    }
  }
  return out;
}

/// Napisy stanu `[fałsz, prawda]` dla punktu dwustanowego.
List<String> _labelsFor(DataPoint p) => switch (p.key) {
  'heating' => const ['nie grzeje', 'grzeje'],
  'night' => const ['dzień', 'noc'],
  final k when RegExp(r'^on\d*$').hasMatch(k) => const ['wył.', 'wł.'],
  final k when RegExp(r'^in\d+$').hasMatch(k) => const ['rozwarte', 'zwarte'],
  _ => const ['nie', 'tak'],
};

/// Opis punktu: z `describe` urządzenia albo zapasowy.
Future<DataPoint> _point(DeviceHub hub, String device, String key, Map<String, List<DataPoint>> cache) async {
  final d = hub.device(device);
  if (d != null && !cache.containsKey(device)) cache[device] = await pointsOf(hub, d);
  return (cache[device] ?? const []).where((p) => p.key == key).firstOrNull ?? fallbackPoint(key);
}

bool _generic(String key) => const {'temp', 'hum', 'on', 'press'}.contains(key);

/// Widżet do zapisu na zegarze: `label`, `unit`, `decimals`, `labels`, `min`/`max` z `describe`; `room` rozwinięty na
/// `items` (temperatura, wilgotność) i `members` (światła), `thermostat` i `hub` z listą `points` (pkt 10.2).
Future<DashWidget> enrichClockWidget(
  DashWidget w,
  DeviceHub hub,
  List<Room> rooms, [
  Map<String, List<DataPoint>>? describeCache,
]) async {
  final cache = describeCache ?? {};
  String devName(String id) => hub.device(id)?.name ?? id;
  Json pointInfo(DataPoint p) => {
    'unit': ?p.unit,
    'decimals': ?p.decimals,
    if (p.kind == PointKind.status || p.kind == PointKind.switchKind) 'labels': _labelsFor(p),
  };
  switch (w.view) {
    case WidgetView.thermostat:
      return w
          .patch({'points': clockThermostatPoints, 'unit': '°C', 'decimals': 1})
          .copyWith(label: w.label ?? devName(w.device ?? ''));
    case WidgetView.hub:
      return w.patch({'points': clockHubPoints}).copyWith(label: w.label ?? 'Hub');
    case WidgetView.valueList:
      final items = <Json>[];
      for (final i in w.items) {
        final p = await _point(hub, i.device, i.point, cache);
        items.add({
          'device': i.device,
          'point': i.point,
          'label': i.label ?? (_generic(i.point) ? devName(i.device) : p.name),
          ...pointInfo(p),
          'labels': ?i.labels,
        });
      }
      return w.patch({'items': items});
    case WidgetView.chart:
      final series = <Json>[];
      for (final s in w.series.take(2)) {
        final p = await _point(hub, s.device, s.point, cache);
        series.add({'device': s.device, 'point': s.point, 'unit': ?p.unit, 'decimals': ?p.decimals});
      }
      final first = w.series.firstOrNull;
      return w
          .patch({'series': series, 'range': w.range == '6h' ? '6h' : '24h'})
          .copyWith(label: w.label ?? (first == null ? 'Wykres' : devName(first.device)));
    case WidgetView.group:
      return w.copyWith(label: w.label ?? 'Grupa');
    case WidgetView.room:
      final room = rooms.where((r) => r.id == w.room).firstOrNull;
      final ids = room?.devices ?? const <String>[];
      // Temperatura i wilgotność: termostat pokoju, inaczej pierwsze urządzenie z punktem `temp`.
      final sorted = [...ids]
        ..sort(
          (a, b) => (hub.device(a)?.type == DeviceType.thermostat ? 0 : 1).compareTo(
            hub.device(b)?.type == DeviceType.thermostat ? 0 : 1,
          ),
        );
      final items = <Json>[];
      for (final id in sorted) {
        final d = hub.device(id);
        if (d == null) continue;
        final keys = (cache[id] ??= await pointsOf(hub, d)).map((p) => p.key).toSet();
        if (!keys.contains('temp')) continue;
        items.add({'device': id, 'point': 'temp', 'unit': '°C', 'decimals': 1});
        if (keys.contains('hum')) items.add({'device': id, 'point': 'hum', 'unit': '%', 'decimals': 0});
        break;
      }
      final members = <Json>[
        for (final id in ids)
          if (hub.device(id)?.type.isLight ?? false)
            for (final k in _outputsOf(hub, id)) {'device': id, 'point': k},
      ];
      return w.patch({'items': items, 'members': members}).copyWith(label: w.label ?? room?.name ?? 'Pokój');
    default:
      final d = w.device, k = w.point;
      if (d == null || k == null) return w;
      final p = await _point(hub, d, k, cache);
      return w
          .patch({
            ...pointInfo(p),
            'min': ?(w.min ?? p.min),
            'max': ?(w.max ?? p.max),
            if (w.labels != null) 'labels': w.labels,
          })
          .copyWith(label: w.label ?? (_generic(k) ? devName(d) : p.name));
  }
}

/// Wyjścia urządzenia: kanały `onN` węzła wielokanałowego albo `on`.
List<String> _outputsOf(DeviceHub hub, String id) {
  final n = hub.controller(id)?.stateJson?['channels'];
  return n is int && n > 1 ? [for (var i = 1; i <= n; i++) 'on$i'] : const ['on'];
}

/// Urządzenia widżetu (do wyszarzania nieznanych hubowi zegara).
Set<String> _devicesOf(DashWidget w) => {for (final (d, _) in clockWidgetPairs(w)) d, ?w.device};

// ---------------------------------------------------------------- lista stron

class ClockPagesScreen extends StatefulWidget {
  const ClockPagesScreen({super.key, required this.controller, required this.hub, this.dashboards, this.rooms});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub hub;

  /// Do testów: pulpity i pokoje zamiast z magazynów.
  final List<Dashboard>? dashboards;
  final List<Room>? rooms;

  @override
  State<ClockPagesScreen> createState() => _ClockPagesScreenState();
}

class _ClockPagesScreenState extends State<ClockPagesScreen> {
  late List<ClockPage> _pages = ClockPage.listFrom(c.config);
  Set<String> _known = const {};
  bool _dirty = false;
  bool _saving = false;
  List<String> _problems = const [];

  DeviceController<Object?, Object?> get c => widget.controller;

  @override
  void initState() {
    super.initState();
    clockKnownDevices(widget.hub, c).then((k) {
      if (mounted) setState(() => _known = k);
    });
  }

  void _set(List<ClockPage> pages) => setState(() {
    _pages = pages;
    _dirty = true;
    _problems = const [];
  });

  String _newId() {
    for (var i = 1; ; i++) {
      if (!_pages.any((p) => p.id == 'p$i')) return 'p$i';
    }
  }

  Future<void> _addPage() async {
    final title = await showTextInputDialog(context, title: 'Nazwa strony', initial: 'Dom', maxLength: 16);
    if (title == null || title.trim().isEmpty || !mounted) return;
    final p = ClockPage(id: _newId(), title: title.trim());
    _set([..._pages, p]);
    await _edit(p);
  }

  Future<void> _edit(ClockPage p) async {
    final r = await Navigator.of(context).push<ClockPage>(
      MaterialPageRoute(
        builder: (_) => ClockPageEditor(page: p, hub: widget.hub, known: _known, clock: c),
      ),
    );
    if (r != null) _set([for (final x in _pages) x.id == r.id ? r : x]);
  }

  Future<List<Dashboard>> _dashboards() async {
    if (widget.dashboards != null) return widget.dashboards!;
    return Services.of(context).dashboards.watch(widget.hub.homeId).first;
  }

  Future<List<Room>> _rooms() async {
    if (widget.rooms != null) return widget.rooms!;
    try {
      return await Services.of(context).rooms.watch().first.timeout(const Duration(seconds: 5));
    } on Object {
      return const [];
    }
  }

  /// „Z pulpitu telefonu…”: pulpit albo jego sekcja → nowe strony (po kolei, ile się zmieści).
  Future<void> _fromDashboard() async {
    final list = await _dashboards();
    if (!mounted) return;
    final pick = await showDialog<(Dashboard, String?)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Z pulpitu telefonu'),
        children: [
          for (final d in list) ...[
            SimpleDialogOption(
              key: Key('clockFromDash-${d.id}'),
              onPressed: () => Navigator.pop(ctx, (d, null)),
              child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final s in d.sections)
              SimpleDialogOption(
                key: Key('clockFromDash-${d.id}-${s.id}'),
                onPressed: () => Navigator.pop(ctx, (d, s.id)),
                child: Padding(padding: const EdgeInsets.only(left: 16), child: Text(s.title)),
              ),
          ],
        ],
      ),
    );
    if (pick == null || !mounted) return;
    final (dash, section) = pick;
    final widgets = [
      for (final w in dash.widgets)
        if (section == null || w.section == section) w,
    ];
    final title = section == null ? dash.name : dash.sections.firstWhere((s) => s.id == section).title;
    var n = 0;
    final r = clockPagesFromDashboard(
      widgets,
      title: title.length > 16 ? title.substring(0, 16) : title,
      newId: () {
        final used = {..._pages.map((p) => p.id)};
        var i = 1;
        while (used.contains('p$i') || i <= n) {
          i++;
        }
        n = i;
        return 'p$i';
      },
    );
    final room = clockMaxPages - _pages.length;
    final added = r.pages.take(room).toList();
    _set([..._pages, ...added]);
    final notes = [
      if (r.skipped.isNotEmpty) 'Pominięte: ${r.skipped.join(', ')}.',
      if (r.pages.length > room) 'Zmieściło się ${added.length} z ${r.pages.length} stron (najwyżej $clockMaxPages).',
    ];
    if (notes.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notes.join(' '))));
    }
  }

  /// Zapis: opisy z `describe`, sprawdzenie limitów, Set `pages` i `screens.list` (nowe strony na koniec pokazu,
  /// usunięte z niego wypadają).
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final rooms = await _rooms();
      final cache = <String, List<DataPoint>>{};
      final pages = [
        for (final p in _pages)
          p.copyWith(widgets: [for (final w in p.widgets) await enrichClockWidget(w, widget.hub, rooms, cache)]),
      ];
      final problems = clockPagesProblems(pages);
      if (problems.isNotEmpty) {
        setState(() => _problems = problems);
        return;
      }
      final cfg = c.config is Map ? (c.config! as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final old = ClockPage.listFrom(cfg).map((p) => 'page:${p.id}').toSet();
      final ids = pages.map((p) => 'page:${p.id}').toSet();
      final list = [
        for (final k in clockScreenList(cfg))
          if (!k.startsWith('page:') || ids.contains(k)) k,
      ];
      for (final k in ids.difference(old)) {
        if (list.length < clockMaxScreens) list.add(k);
      }
      final screens = cfg['screens'] is Map ? (cfg['screens'] as Map).cast<String, dynamic>() : <String, dynamic>{};
      final r = await c.sendJson({
        'pages': [for (final p in pages) p.toJson()],
        'screens': {...screens, 'list': list},
      });
      if (!mounted) return;
      if (r.errors.isNotEmpty) {
        setState(() => _problems = [describeErrors(r.errors)]);
        return;
      }
      setState(() {
        _pages = pages;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zapisano strony na zegarze.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pairs = clockPairs(_pages).length;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Niezapisane zmiany'),
            content: const Text('Wyjść bez zapisu stron na zegarze?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zostań')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wyjdź')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Strony z widżetami'),
          actions: [
            TextButton(
              key: const Key('clockPagesSave'),
              onPressed: _saving || !_dirty ? null : _save,
              child: const Text('Zapisz'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Stan urządzeń domu na ekranie zegara (bez sterowania). Odczyty przysyła hub, więc tylko urządzenia '
              'znane hubowi zegara. Odczyty: $pairs z $clockMaxPairs.',
            ),
            const SizedBox(height: 12),
            for (final p in _pages)
              Card(
                key: Key('clockPage-${p.id}'),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(p.title),
                      subtitle: Text('${p.widgets.length} z $clockMaxWidgets widżetów'),
                      trailing: IconButton(
                        key: Key('clockPageDelete-${p.id}'),
                        tooltip: 'Usuń stronę',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _set([..._pages]..remove(p)),
                      ),
                      onTap: () => _edit(p),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: ClockPagePreview(page: p, hub: widget.hub, known: _known),
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('clockPageAdd'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nowa strona'),
                  onPressed: _pages.length >= clockMaxPages ? null : _addPage,
                ),
                OutlinedButton.icon(
                  key: const Key('clockFromDashboard'),
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Z pulpitu telefonu…'),
                  onPressed: _pages.length >= clockMaxPages ? null : _fromDashboard,
                ),
              ],
            ),
            for (final p in _problems)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  p,
                  key: const Key('clockPagesProblem'),
                  style: TextStyle(color: cs.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- edytor strony

class ClockPageEditor extends StatefulWidget {
  const ClockPageEditor({super.key, required this.page, required this.hub, required this.known, required this.clock});

  final ClockPage page;
  final DeviceHub hub;
  final Set<String> known;
  final DeviceController<Object?, Object?> clock;

  @override
  State<ClockPageEditor> createState() => _ClockPageEditorState();
}

/// Rozmiary widżetu na zegarze (w × h) do wyboru.
const _sizes = [(1, 1), (2, 1), (1, 2), (2, 2), (3, 1), (4, 1), (4, 2), (4, 3)];

const _colors = {
  'auto': 'Auto',
  'amber': 'Brzoskwinia',
  'blue': 'Niebo',
  'green': 'Mięta',
  'red': 'Róż',
  'purple': 'Lawenda',
  'grey': 'Szary',
};

class _ClockPageEditorState extends State<ClockPageEditor> {
  late ClockPage _p = widget.page;
  late final _title = TextEditingController(text: widget.page.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _put(DashWidget w) => setState(() {
    final i = _p.widgets.indexWhere((x) => x.id == w.id);
    _p = _p.copyWith(widgets: i < 0 ? [..._p.widgets, w] : ([..._p.widgets]..[i] = w));
  });

  /// Nowe miejsce dla widżetu o zmienionym rozmiarze: obecne, jeśli wolne, inaczej pierwsze wolne.
  DashWidget? _resized(DashWidget w, int gw, int gh) {
    final others = _p.widgets.where((x) => x.id != w.id);
    final x = w.x ?? 0, y = w.y ?? 0;
    final stay =
        x + gw <= clockCols &&
        y + gh <= clockRows &&
        clockFreeSpot(
              [
                ...others,
                w.patch({'x': null, 'y': null}),
              ],
              gw,
              gh,
            ) !=
            null &&
        _fits(others, x, y, gw, gh);
    final spot = stay ? (x, y) : clockFreeSpot(others, gw, gh);
    return spot == null ? null : w.patch({'w': gw, 'h': gh, 'x': spot.$1, 'y': spot.$2});
  }

  /// Widżet [w] (z bieżącym rozmiarem) w lewym górnym rogu (x, y); null = nie mieści się albo nachodzi na inny.
  DashWidget? _moved(DashWidget w, int x, int y) {
    final gw = clockW(w), gh = clockH(w);
    if (x + gw > clockCols || y + gh > clockRows) return null;
    return _fits(_p.widgets.where((o) => o.id != w.id), x, y, gw, gh) ? w.patch({'x': x, 'y': y}) : null;
  }

  static bool _fits(Iterable<DashWidget> others, int x, int y, int w, int h) {
    for (final o in others) {
      final ox = o.x ?? 0, oy = o.y ?? 0;
      if (x < ox + clockW(o) && ox < x + w && y < oy + clockH(o) && oy < y + h) return false;
    }
    return true;
  }

  Future<void> _add() async {
    if (_p.widgets.length >= clockMaxWidgets) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Najwyżej $clockMaxWidgets widżetów.')));
      return;
    }
    final w = await Navigator.of(context).push<DashWidget>(
      MaterialPageRoute(
        builder: (_) => _AddClockWidget(hub: widget.hub, known: widget.known, clock: widget.clock),
      ),
    );
    if (w == null || !mounted) return;
    final spot = clockFreeSpot(_p.widgets, clockW(w), clockH(w));
    if (spot == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Na stronie nie ma miejsca na ten rozmiar.')));
      return;
    }
    _put(w.patch({'x': spot.$1, 'y': spot.$2}));
  }

  Future<void> _editWidget(DashWidget w) async {
    final r = await showModalBottomSheet<DashWidget?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _WidgetSheet(widget: w, resize: (gw, gh) => _resized(w, gw, gh), move: _moved),
    );
    if (r == null || !mounted) return;
    if (r.id == '') {
      setState(() => _p = _p.copyWith(widgets: [..._p.widgets]..removeWhere((x) => x.id == w.id)));
    } else {
      _put(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strona zegara'),
        actions: [
          TextButton(
            key: const Key('clockPageDone'),
            onPressed: () =>
                Navigator.pop(context, _p.copyWith(title: _title.text.trim().isEmpty ? _p.title : _title.text.trim())),
            child: const Text('Gotowe'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('clockPageTitle'),
            controller: _title,
            maxLength: 16,
            decoration: const InputDecoration(labelText: 'Nazwa strony (pasek u góry)'),
            onChanged: (v) => setState(() => _p = _p.copyWith(title: v.trim().isEmpty ? _p.title : v.trim())),
          ),
          ClockPagePreview(page: _p, hub: widget.hub, known: widget.known, onTap: _editWidget),
          const SizedBox(height: 8),
          Text(
            'Dotknij widżetu, żeby zmienić położenie, rozmiar, kolor albo go usunąć.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('clockWidgetAdd'),
              icon: const Icon(Icons.add),
              label: Text('Dodaj widżet (${_p.widgets.length}/$clockMaxWidgets)'),
              onPressed: _add,
            ),
          ),
        ],
      ),
    );
  }
}

/// Zmiana widżetu: etykieta, położenie, rozmiar, kolor, ikony stanu, usunięcie (wynik z `id` = '' = usuń).
class _WidgetSheet extends StatefulWidget {
  const _WidgetSheet({required this.widget, required this.resize, required this.move});

  final DashWidget widget;
  final DashWidget? Function(int w, int h) resize;
  final DashWidget? Function(DashWidget w, int x, int y) move;

  @override
  State<_WidgetSheet> createState() => _WidgetSheetState();
}

class _WidgetSheetState extends State<_WidgetSheet> {
  late DashWidget _w = widget.widget;
  late final _label = TextEditingController(text: widget.widget.label ?? '');

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// Siatka 4 x 3 strony: dotknięcie pola przenosi tam lewy górny róg; pola, w których widżet się nie zmieści, wyszarzone.
  Widget _position(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final x0 = _w.x ?? 0, y0 = _w.y ?? 0, gw = clockW(_w), gh = clockH(_w);
    return SizedBox(
      width: 4 * 44,
      child: GridView.count(
        crossAxisCount: clockCols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.2,
        children: [
          for (var y = 0; y < clockRows; y++)
            for (var x = 0; x < clockCols; x++)
              Builder(
                builder: (context) {
                  final covered = x >= x0 && x < x0 + gw && y >= y0 && y < y0 + gh;
                  final target = widget.move(_w, x, y);
                  return InkWell(
                    key: Key('clockWidgetPos-$x-$y'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: target == null ? null : () => setState(() => _w = target),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: covered
                            ? cs.primary
                            : target == null
                            ? cs.surfaceContainerHighest
                            : cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }

  /// Ikona stanu na zegarze (`iconOn` / `iconOff`, klucz z katalogu aplikacji); bez ikon - kropka jak dotąd.
  Widget _iconTile(String field, String title) {
    final key = _w.extra[field] as String?;
    final icon = appIcon(key);
    return ListTile(
      key: Key('clockWidget-$field'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon?.icon ?? Icons.circle, size: icon == null ? 12 : 24),
      title: Text(title),
      subtitle: Text(icon?.label ?? 'bez ikony (kropka)'),
      onTap: () async {
        final k = await pickAppIcon(context, current: key);
        if (k == null || !mounted) return;
        setState(() => _w = _w.patch({field: k.isEmpty ? null : k}));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('clockWidgetLabel'),
              controller: _label,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Etykieta (puste - z nazwy urządzenia)'),
            ),
            const Text('Rozmiar'),
            Wrap(
              spacing: 6,
              children: [
                for (final (gw, gh) in _sizes)
                  ChoiceChip(
                    key: Key('clockWidgetSize-${gw}x$gh'),
                    label: Text('$gw×$gh'),
                    selected: clockW(_w) == gw && clockH(_w) == gh,
                    onSelected: (_) {
                      final r = widget.resize(gw, gh);
                      if (r == null) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('Na stronie nie ma miejsca na ten rozmiar.')));
                        return;
                      }
                      setState(() => _w = r);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Położenie (lewy górny róg widżetu)'),
            const SizedBox(height: 4),
            _position(context),
            const SizedBox(height: 8),
            const Text('Kolor kafla'),
            Wrap(
              spacing: 6,
              children: [
                for (final MapEntry(key: k, value: l) in _colors.entries)
                  ChoiceChip(
                    key: Key('clockWidgetColor-$k'),
                    avatar: k == 'auto'
                        ? null
                        : CircleAvatar(backgroundColor: Color(clockTileColors[k]!.$1), radius: 8),
                    label: Text(l),
                    selected: (_w.color ?? 'auto') == k,
                    onSelected: (_) => setState(() => _w = _w.patch({'color': k == 'auto' ? null : k})),
                  ),
              ],
            ),
            if (_w.view == WidgetView.status || _w.view == WidgetView.toggle) ...[
              const SizedBox(height: 8),
              _iconTile('iconOn', 'Ikona - włączone / otwarte'),
              _iconTile('iconOff', 'Ikona - wyłączone / zamknięte'),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  key: const Key('clockWidgetDelete'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Usuń'),
                  onPressed: () => Navigator.pop(context, const DashWidget(id: '', view: WidgetView.value)),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('clockWidgetOk'),
                  onPressed: () => Navigator.pop(
                    context,
                    _label.text.trim().isEmpty ? _w.copyWith(clearLabel: true) : _w.copyWith(label: _label.text.trim()),
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Nowy widżet: urządzenie (znane hubowi zegara), punkt, widok, rozmiar.
class _AddClockWidget extends StatefulWidget {
  const _AddClockWidget({required this.hub, required this.known, required this.clock});

  final DeviceHub hub;
  final Set<String> known;
  final DeviceController<Object?, Object?> clock;

  @override
  State<_AddClockWidget> createState() => _AddClockWidgetState();
}

class _AddClockWidgetState extends State<_AddClockWidget> {
  PairedDevice? _device;
  List<DataPoint> _points = const [];
  DataPoint? _point;
  WidgetView _view = WidgetView.value;
  (int, int) _size = (1, 1);

  List<WidgetView> get _views {
    final d = _device, p = _point;
    if (d == null) return const [];
    return [
      if (d.type == DeviceType.thermostat) WidgetView.thermostat,
      if (d.type == DeviceType.hub) WidgetView.hub,
      if (p != null) ...[
        if (p.kind == PointKind.status || p.kind == PointKind.switchKind || p.kind == PointKind.action)
          WidgetView.status
        else ...[
          WidgetView.value,
          if (p.min != null && p.max != null || p.unit == '%') ...[WidgetView.level, WidgetView.gauge],
          if (p.history != null) WidgetView.chart,
        ],
      ],
    ];
  }

  Future<void> _pickDevice(PairedDevice d) async {
    setState(() {
      _device = d;
      _point = null;
      _points = const [];
    });
    final points = d.type == DeviceType.hub ? const <DataPoint>[] : await pointsOf(widget.hub, d);
    if (!mounted || _device != d) return;
    setState(() {
      _points = [
        for (final p in points)
          if (p.kind != PointKind.action || RegExp(r'^on\d+$').hasMatch(p.key)) p,
      ];
      _point = _points.firstOrNull;
      _view = _views.firstOrNull ?? WidgetView.value;
      _size = _view == WidgetView.thermostat ? (2, 2) : (_view == WidgetView.hub ? (2, 1) : (1, 1));
    });
  }

  DashWidget _build() {
    final d = _device!, p = _point;
    final (gw, gh) = _view == WidgetView.chart && _size.$1 < 2 ? (4, 2) : _size;
    var w = DashWidget(
      id: newLocalId('w'),
      view: _view,
      device: _view == WidgetView.chart ? null : d.id,
      point: switch (_view) {
        WidgetView.thermostat || WidgetView.hub || WidgetView.chart => null,
        _ => p?.key,
      },
    );
    if (_view == WidgetView.chart && p != null) {
      w = w.patch({
        'series': [
          {'device': d.id, 'point': p.key},
        ],
        'range': '24h',
      });
    }
    return w.patch({'w': gw, 'h': gh});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final d = _device;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Widżet zegara'),
        actions: [
          TextButton(
            key: const Key('clockWidgetCreate'),
            onPressed: d == null || (_point == null && d.type != DeviceType.hub && d.type != DeviceType.thermostat)
                ? null
                : () => Navigator.pop(context, _build()),
            child: const Text('Dodaj'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Urządzenie', style: t.titleSmall),
          for (final x in widget.hub.devices)
            if (x.id != widget.clock.device.id)
              ListTile(
                key: Key('clockWidgetDevice-${x.id}'),
                dense: true,
                selected: d?.id == x.id,
                enabled: widget.known.contains(x.id),
                title: Text(x.name),
                subtitle: widget.known.contains(x.id) ? Text(x.type.label) : const Text('niedostępne dla zegara'),
                onTap: () => _pickDevice(x),
              ),
          if (_points.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Punkt', style: t.titleSmall),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in _points)
                  ChoiceChip(
                    key: Key('clockWidgetPoint-${p.key}'),
                    label: Text(p.name),
                    selected: _point?.key == p.key,
                    onSelected: (_) => setState(() {
                      _point = p;
                      if (!_views.contains(_view)) _view = _views.firstOrNull ?? WidgetView.value;
                    }),
                  ),
              ],
            ),
          ],
          if (d != null && _views.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Widok', style: t.titleSmall),
            Wrap(
              spacing: 6,
              children: [
                for (final v in _views)
                  ChoiceChip(
                    key: Key('clockWidgetView-${v.wire}'),
                    label: Text(v.label),
                    selected: _view == v,
                    onSelected: (_) => setState(() => _view = v),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Rozmiar', style: t.titleSmall),
            Wrap(
              spacing: 6,
              children: [
                for (final s in _sizes)
                  ChoiceChip(
                    key: Key('clockWidgetNewSize-${s.$1}x${s.$2}'),
                    label: Text('${s.$1}×${s.$2}'),
                    selected: _size == s,
                    onSelected: (_) => setState(() => _size = s),
                  ),
              ],
            ),
          ],
          if (widget.known.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Hub zegara nie jest dostępny - nie wiadomo, które urządzenia zna.',
                style: TextStyle(color: cs.error),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- podgląd 320×240 (styl C)

const _bg = Color(0xFFEEF1F6), _ink = Color(0xFF1B1F2A), _muted = Color(0xFF5A6275);

/// Strona tak, jak pokaże ją zegar: pasek 18 px (tytuł, godzina), siatka 4×3, kafle stylu C z bieżącymi wartościami.
class ClockPagePreview extends StatelessWidget {
  const ClockPagePreview({super.key, required this.page, required this.hub, required this.known, this.onTap});

  final ClockPage page;
  final DeviceHub hub;
  final Set<String> known;
  final void Function(DashWidget w)? onTap;

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: FittedBox(
        child: Container(
          key: Key('clockPreview-${page.id}'),
          width: 320,
          height: 240,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              SizedBox(
                height: 18,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Text(
                      page.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink),
                    ),
                    const Spacer(),
                    Text(
                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _muted),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    const gap = 6.0;
                    final cw = (box.maxWidth - gap * 3) / 4, ch = (box.maxHeight - gap * 2) / 3;
                    return Stack(
                      children: [
                        for (final w in page.widgets)
                          Positioned(
                            left: (w.x ?? 0) * (cw + gap),
                            top: (w.y ?? 0) * (ch + gap),
                            width: clockW(w) * cw + (clockW(w) - 1) * gap,
                            height: clockH(w) * ch + (clockH(w) - 1) * gap,
                            child: GestureDetector(
                              key: Key('clockTile-${w.id}'),
                              onTap: onTap == null ? null : () => onTap!(w),
                              child: _ClockTile(widget: w, hub: hub, known: known),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockTile extends StatelessWidget {
  const _ClockTile({required this.widget, required this.hub, required this.known});

  final DashWidget widget;
  final DeviceHub hub;
  final Set<String> known;

  Object? _value(String device, String key) => fallbackPoint(key).valueIn(hub.controller(device)?.stateJson);

  String _fmt(Object? v, {String? unit, int? decimals, List<String>? labels}) => switch (v) {
    null => '–',
    final bool b => (labels ?? const ['nie', 'tak'])[b ? 1 : 0],
    final num n =>
      '${fmtNumber(n.toDouble(), decimals: decimals ?? (n is int ? 0 : 1))}${unit == null
          ? ''
          : unit == '°C'
          ? '°'
          : ' $unit'}',
    _ => '$v',
  };

  String get _label {
    final w = widget;
    if (w.label != null) return w.label!;
    final d = w.device ?? w.items.firstOrNull?.device ?? w.series.firstOrNull?.device;
    return d == null ? w.view.label : (hub.device(d)?.name ?? d);
  }

  /// Ikona stanu (iconOn / iconOff) dla bieżącej wartości; jedna ustawiona służy obu stanom.
  IconData? get _stateIcon {
    final w = widget;
    if (w.view != WidgetView.status && w.view != WidgetView.toggle) return null;
    final on = appIcon(w.extra['iconOn'] as String?), off = appIcon(w.extra['iconOff'] as String?);
    final v = w.device == null || w.point == null ? null : _value(w.device!, w.point!);
    return (v == true ? on ?? off : off ?? on)?.icon;
  }

  String get _text {
    final w = widget;
    final d = w.device;
    final unit = w.extra['unit'] as String?, dec = (w.extra['decimals'] as num?)?.toInt();
    switch (w.view) {
      case WidgetView.thermostat when d != null:
        final s = hub.controller(d)?.stateJson;
        return '${_fmt(s?['temp'], unit: '°C', decimals: 1)} → ${_fmt(s?['target'], unit: '°C', decimals: 1)}';
      case WidgetView.hub when d != null:
        final s = hub.controller(d)?.stateJson;
        return '${s?['online'] ?? '–'}/${s?['devices'] ?? '–'}';
      case WidgetView.valueList:
        return [
          for (final i in w.items.take(3))
            _fmt(_value(i.device, i.point), unit: fallbackPoint(i.point).unit, labels: i.labels),
        ].join('  ');
      case WidgetView.group:
        final on = w.members.where((m) => _value(m.device, m.point) == true).length;
        return '$on z ${w.members.length}';
      case WidgetView.chart:
        return 'wykres ${w.range ?? '24h'}';
      case WidgetView.room:
        return 'pokój';
      default:
        if (d == null || w.point == null) return '–';
        return _fmt(_value(d, w.point!), unit: unit ?? fallbackPoint(w.point!).unit, decimals: dec, labels: w.labels);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final missing = _devicesOf(w).any((d) => !known.contains(d));
    final (bg, label, value) = clockTileColors[w.color] ?? (0xFFFFFFFF, 0xFF5A6275, 0xFF1B1F2A);
    final big = clockH(w) >= 2 || clockW(w) >= 2;
    return Opacity(
      opacity: missing ? 0.4 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
        decoration: BoxDecoration(color: Color(bg), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(label)),
                  ),
                ),
                if (_stateIcon case final i?) Icon(i, size: big ? 22 : 14, color: Color(label)),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                missing ? 'niedostępne' : _text,
                style: TextStyle(
                  fontSize: missing ? 11 : (big ? 22 : 18),
                  fontWeight: FontWeight.w800,
                  color: Color(value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
