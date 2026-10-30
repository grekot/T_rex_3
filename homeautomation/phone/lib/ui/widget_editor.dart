import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../data/device_store.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import '../models/scene.dart';
import '../services.dart';
import 'app_icons.dart';
import 'automations_screen.dart' show BranchEditorScreen, describeAction;
import 'dashboard_tiles.dart';
import 'point_controls.dart';
import 'widgets.dart';

/// Widoki, które zna zegarek (pkt 13a: bez wykresów i suwaków).
const watchWidgetViews = {
  WidgetView.value,
  WidgetView.toggle,
  WidgetView.stepper,
  WidgetView.status,
  WidgetView.thermostat,
  WidgetView.scene,
};

/// Widoki pasujące do rodzaju punktu (pierwszy = domyślny).
List<WidgetView> viewsFor(DataPoint p) => switch (p.kind) {
  PointKind.sensor => [WidgetView.value, WidgetView.gauge, if (p.history != null) WidgetView.chart],
  PointKind.status => [WidgetView.status, WidgetView.value],
  PointKind.setpoint => [
    WidgetView.stepper,
    WidgetView.slider,
    if (p.min != null && p.max != null) WidgetView.dial,
    WidgetView.value,
    if (p.history != null) WidgetView.chart,
  ],
  PointKind.switchKind => [WidgetView.toggle, WidgetView.status],
  PointKind.select => [WidgetView.value],
  PointKind.action => [WidgetView.toggle],
};

String kindLabel(PointKind k) => switch (k) {
  PointKind.sensor => 'odczyt',
  PointKind.status => 'stan',
  PointKind.setpoint => 'nastawa',
  PointKind.switchKind => 'przełącznik',
  PointKind.select => 'wybór',
  PointKind.action => 'przycisk',
};

/// Punkty, gdy urządzenie nie odpowiada na `describe` (np. jest offline) - wg typu.
List<DataPoint> fallbackPoints(DeviceType type) => switch (type) {
  DeviceType.thermostat => [
    for (final k in ['temp', 'hum', 'target', 'heating', 'mode']) fallbackPoint(k),
  ],
  DeviceType.onOff => [fallbackPoint('on')],
  DeviceType.dimmer => [fallbackPoint('on'), fallbackPoint('level')],
  _ => const [],
};

/// Punkty urządzenia z `describe` (albo zapasowe wg typu).
Future<List<DataPoint>> pointsOf(DeviceHub hub, PairedDevice d) async {
  final c = hub.controller(d.id);
  final desc = await c?.description().timeout(const Duration(seconds: 8), onTimeout: () => null);
  return [for (final p in desc?.points ?? fallbackPoints(d.type)) withChannelName(p, c, desc)];
}

/// Gotowy kafelek do dodania jednym dotknięciem (tytuł, opis, widżet w siatce 4).
typedef TilePreset = ({String title, String subtitle, DashWidget widget});

/// Propozycje kafelków dla urządzenia (pkt 13.1) - z punktów `describe` i stanu (kanały węzła).
List<TilePreset> tilePresets(PairedDevice d, List<DataPoint> points, Json? state) {
  DataPoint? pt(String key) => points.where((p) => p.key == key).firstOrNull;
  DashWidget w(WidgetView view, String? point, int gw, int gh, [Json extra = const {}, String? label]) => DashWidget(
    id: newLocalId('w'),
    view: view,
    device: d.id,
    point: point,
    label: label,
  ).resized(gw, gh).patch(extra);
  final out = <TilePreset>[];
  if (d.type == DeviceType.thermostat) {
    out.add((
      title: 'Termostat',
      subtitle: 'temperatura, nastawa − / +, grzanie · 4×2',
      widget: w(WidgetView.thermostat, null, 4, 2),
    ));
    out.add((
      title: 'Pokrętło nastawy',
      subtitle: 'półokrągły suwak, temperatura bieżąca · 2×3',
      widget: w(WidgetView.dial, 'target', 2, 3),
    ));
    if (pt('hum') != null || points.isEmpty) {
      out.add((
        title: 'Temperatura i wilgotność',
        subtitle: 'duża liczba, wilgotność w drugiej linii · 2×2',
        widget: w(WidgetView.value, 'temp', 2, 2, {'secondary': 'point:hum'}),
      ));
      out.add((
        title: 'Wilgotność - wskaźnik',
        subtitle: 'łuk ze strefami: sucho / dobrze / wilgotno · 2×2',
        widget: w(WidgetView.gauge, 'hum', 2, 2, {
          'min': 0,
          'max': 100,
          'zones': [
            [0, 35, 'amber'],
            [35, 60, 'green'],
            [60, 100, 'blue'],
          ],
        }),
      ));
    }
    out.add((
      title: 'Wykres 24 h',
      subtitle: 'temperatura, nastawa, pasy grzania, zakres w kafelku · 4×3',
      widget: w(WidgetView.chart, 'temp', 4, 3, {
        'series': [
          {'device': d.id, 'point': 'temp', 'line': 'smooth'},
          {'device': d.id, 'point': 'target', 'line': 'step'},
          {'device': d.id, 'point': 'heating', 'line': 'band'},
        ],
        'rangeSwitch': true,
      }),
    ));
    out.add((
      title: 'Harmonogram',
      subtitle: 'okres teraz, następna zmiana, pasek dnia · 4×2',
      widget: w(WidgetView.schedule, null, 4, 2),
    ));
    out.add((
      title: 'Pogoda',
      subtitle: 'temperatura na zewnątrz i ikona pogody z termostatu · 2×2',
      widget: w(WidgetView.weather, null, 2, 2),
    ));
    out.add((
      title: 'Pogoda z wykresem',
      subtitle: 'jak wyżej, z temperaturą z 24 h · 4×3',
      widget: w(WidgetView.weather, null, 4, 3),
    ));
    if (pt('outdoor.temp') != null) {
      out.add((
        title: 'Na zewnątrz',
        subtitle: 'temperatura z pogody · 2×1',
        widget: w(WidgetView.value, 'outdoor.temp', 2, 1),
      ));
    }
  } else if (d.type == DeviceType.hub) {
    out.add((
      title: 'Stan huba',
      subtitle: 'urządzenia, automatyki, ostatnie wykonanie, chmura · 4×2',
      widget: w(WidgetView.hub, null, 4, 2),
    ));
  } else if (d.type.isLight) {
    final n = state?['channels'] is int ? state!['channels'] as int : 1;
    if (n > 1) {
      out.add((
        title: 'Wszystkie wyjścia',
        subtitle: 'przycisk na kanał, ikona wł./wył. wszystkie · 4×2',
        widget: w(WidgetView.toggle, 'on', 4, 2, const {}, d.name),
      ));
      for (var i = 1; i <= n; i++) {
        final name = pt('on$i')?.name ?? 'Kanał $i';
        out.add((title: name, subtitle: 'jedno wyjście (kanał $i) · 2×1', widget: w(WidgetView.toggle, 'on$i', 2, 1)));
      }
      for (final p in points.where((p) => RegExp(r'^in\d+$').hasMatch(p.key))) {
        out.add((title: p.name, subtitle: 'stan wejścia · 2×1', widget: w(WidgetView.status, p.key, 2, 1)));
      }
    } else {
      out.add((
        title: 'Przełącznik',
        subtitle: 'ikona włącza i wyłącza · 2×1',
        widget: w(WidgetView.toggle, 'on', 2, 1, const {}, d.name),
      ));
      if (pt('level') != null || d.type == DeviceType.dimmer) {
        out.add((
          title: 'Jasność - pasek',
          subtitle: 'suwak obok nazwy, ikona wł./wył. · 4×1',
          widget: w(WidgetView.slider, 'level', 4, 1, const {}, d.name),
        ));
        out.add((
          title: 'Jasność - pokrętło',
          subtitle: 'półokrągły suwak · 2×3',
          widget: w(WidgetView.dial, 'level', 2, 3, const {}, d.name),
        ));
      }
    }
  }
  return out;
}

/// Wyjście do grupy (`group`, pkt 13.1): urządzenie, `on` / `onN`, nazwa do listy.
typedef GroupCandidate = ({String device, String point, String name});

/// Wyjścia, które można dodać do grupy: światła i przełączniki (kanały węzłów osobno, nazwy z `describe`).
Future<List<GroupCandidate>> groupCandidates(DeviceHub hub) async {
  final out = <GroupCandidate>[];
  for (final d in hub.devices) {
    if (!d.type.isLight || !hub.accessFor(d.id).canView) continue;
    final c = hub.controller(d.id);
    final n = c?.stateJson?['channels'];
    if (n is int && n > 1) {
      final desc = await c
          ?.description()
          .timeout(const Duration(seconds: 3), onTimeout: () => null)
          .catchError((_) => null);
      for (var i = 1; i <= n; i++) {
        out.add((device: d.id, point: 'on$i', name: '${d.name} · ${channelName(c, desc, 'on$i')}'));
      }
    } else {
      out.add((device: d.id, point: 'on', name: d.name));
    }
  }
  return out;
}

/// Nowa grupa wyjść: nazwa i zaznaczone wyjścia → kafelek `group` 2×2.
class GroupPickerScreen extends StatefulWidget {
  const GroupPickerScreen({super.key, required this.hub});

  final DeviceHub hub;

  @override
  State<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends State<GroupPickerScreen> {
  late final Future<List<GroupCandidate>> _all = groupCandidates(widget.hub);
  final _picked = <(String, String)>{};
  final _name = TextEditingController(text: 'Światła');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grupa wyjść')),
      body: FutureBuilder<List<GroupCandidate>>(
        future: _all,
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  key: const Key('groupName'),
                  controller: _name,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: 'Nazwa grupy'),
                ),
              ),
              const SectionHeader('Wyjścia'),
              if (all.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Nie ma jeszcze świateł ani przełączników.')),
              for (final c in all)
                CheckboxListTile(
                  key: Key('groupPick-${c.device}-${c.point}'),
                  title: Text(c.name),
                  value: _picked.contains((c.device, c.point)),
                  onChanged: (v) => setState(
                    () => v == true ? _picked.add((c.device, c.point)) : _picked.remove((c.device, c.point)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const Key('groupDone'),
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                          DashWidget(
                            id: newLocalId('w'),
                            view: WidgetView.group,
                            label: _name.text.trim().isEmpty ? 'Grupa' : _name.text.trim(),
                          ).resized(2, 2).patch({
                            'members': [
                              for (final c in all)
                                if (_picked.contains((c.device, c.point))) {'device': c.device, 'point': c.point},
                            ],
                          }),
                        ),
                  child: Text('Dodaj grupę (${_picked.length})'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dodawanie widżetu w 3 krokach (pkt 13): urządzenie → punkt danych → wygląd i rozmiar.
class AddWidgetScreen extends StatefulWidget {
  const AddWidgetScreen({super.key, required this.hub, this.forWatch = false});

  final DeviceHub hub;

  /// Kafelek pulpitu zegarka (pkt 13a): tylko widoki zegarka, rozmiar wybiera się w edytorze zegarka.
  final bool forWatch;

  @override
  State<AddWidgetScreen> createState() => _AddWidgetScreenState();
}

class _AddWidgetScreenState extends State<AddWidgetScreen> {
  int _step = 0;
  PairedDevice? _device;
  Future<List<DataPoint>>? _points;

  /// null + [_wholeThermostat] = widok „termostat”.
  DataPoint? _point;
  bool _wholeThermostat = false;
  WidgetView _view = WidgetView.value;
  WidgetSize _size = WidgetSize.s1x1;

  /// Wybrana ikona; null = domyślna.
  String? _icon;

  String get _defaultIcon =>
      widgetIconKey(view: _view, point: _wholeThermostat ? null : _point?.key, type: _device?.type);
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _pickDevice(PairedDevice d) => setState(() {
    _device = d;
    _points = pointsOf(widget.hub, d);
    _step = 1;
  });

  List<WidgetView> get _views {
    final all = _wholeThermostat ? [WidgetView.thermostat] : viewsFor(_point!);
    return widget.forWatch
        ? [
            for (final v in all)
              if (watchWidgetViews.contains(v)) v,
          ]
        : all;
  }

  void _pickPoint(DataPoint? p) => setState(() {
    _point = p;
    _wholeThermostat = p == null;
    _view = _views.firstOrNull ?? WidgetView.value;
    _size = p == null || _view == WidgetView.chart ? WidgetSize.s2x1 : WidgetSize.s1x1;
    _step = 2;
  });

  Future<void> _scene() async {
    final scene = await Navigator.of(
      context,
    ).push<Scene>(MaterialPageRoute(builder: (_) => ScenePickerScreen(hub: widget.hub)));
    if (scene != null && mounted) {
      Navigator.of(
        context,
      ).pop(DashWidget(id: newLocalId('w'), view: WidgetView.scene, size: WidgetSize.s2x1, sceneId: scene.id));
    }
  }

  void _done() {
    final label = _label.text.trim();
    Navigator.of(context).pop(
      DashWidget(
        id: newLocalId('w'),
        view: _view,
        size: _size,
        device: _device!.id,
        point: _wholeThermostat ? null : _point!.key,
        label: label.isEmpty ? null : label,
        icon: _icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Nowy widżet · krok ${_step + 1} z 3')),
        body: switch (_step) {
          0 => _devices(context),
          1 => _pointsStep(context),
          _ => _lookStep(context),
        },
      ),
    );
  }

  Widget _devices(BuildContext context) {
    final devices = [
      for (final d in widget.hub.devices)
        if (widget.hub.accessFor(d.id) != AccessLevel.none) d,
    ];
    return ListView(
      children: [
        const SectionHeader('Wybierz urządzenie'),
        for (final d in devices)
          ListTile(
            key: Key('pick-${d.id}'),
            leading: Icon((d.type == DeviceType.thermostat) ? Icons.thermostat : Icons.developer_board),
            title: Text(d.name),
            subtitle: Text('${d.type.label} · ${widget.hub.accessFor(d.id).label}'),
            onTap: () => _pickDevice(d),
          ),
        if (devices.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Brak urządzeń, do których masz dostęp.')),
        const Divider(),
        if (!widget.forWatch)
          ListTile(
            key: const Key('pickGroup'),
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Grupa wyjść'),
            subtitle: const Text('Kilka świateł jednym przyciskiem'),
            onTap: () async {
              final w = await Navigator.of(
                context,
              ).push<DashWidget>(MaterialPageRoute(builder: (_) => GroupPickerScreen(hub: widget.hub)));
              if (w != null && context.mounted) Navigator.of(context).pop(w);
            },
          ),
        ListTile(
          key: const Key('pickScene'),
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Scena'),
          subtitle: const Text('Jeden przycisk, kilka poleceń naraz'),
          onTap: _scene,
        ),
      ],
    );
  }

  Widget _pointsStep(BuildContext context) {
    final d = _device!;
    return FutureBuilder<List<DataPoint>>(
      future: _points,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final points = snap.data!;
        final presets = widget.forWatch
            ? const <TilePreset>[]
            : tilePresets(d, points, widget.hub.controller(d.id)?.stateJson);
        return ListView(
          children: [
            if (presets.isNotEmpty) ...[
              const SectionHeader('Gotowe kafelki'),
              for (final (i, p) in presets.indexed)
                ListTile(
                  key: Key('preset-$i'),
                  leading: Icon(dashWidgetIcon(p.widget, widget.hub)),
                  title: Text(p.title),
                  subtitle: Text(p.subtitle),
                  trailing: const Icon(Icons.add),
                  onTap: () => Navigator.of(context).pop(p.widget),
                ),
            ],
            SectionHeader(presets.isEmpty ? '${d.name}: co pokazać' : 'Albo wybierz punkt danych'),
            if ((d.type == DeviceType.thermostat))
              ListTile(
                key: const Key('pick-thermostat'),
                leading: const Icon(Icons.thermostat),
                title: const Text('Cały termostat'),
                subtitle: const Text('temperatura, nastawa − / +, grzanie'),
                onTap: () => _pickPoint(null),
              ),
            for (final p in points)
              ListTile(
                key: Key('pick-${p.key}'),
                title: Text(p.name),
                subtitle: Text([kindLabel(p.kind), ?p.unit].join(' · ')),
                onTap: () => _pickPoint(p),
              ),
            if (points.isEmpty && !(d.type == DeviceType.thermostat))
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Urządzenie nie podało listy punktów danych. Sprawdź, czy jest włączone.'),
              ),
          ],
        );
      },
    );
  }

  Widget _lookStep(BuildContext context) {
    final views = _views;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Wygląd', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final v in views)
              ChoiceChip(
                key: Key('view-${v.wire}'),
                label: Text(v.label),
                selected: _view == v,
                onSelected: (_) => setState(() => _view = v),
              ),
          ],
        ),
        if (!widget.forWatch) ...[
          const SizedBox(height: 16),
          Text('Rozmiar', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizeChooser(value: _size, onChanged: (s) => setState(() => _size = s)),
        ],
        const SizedBox(height: 8),
        ListTile(
          key: const Key('widgetIcon'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(appIcon(_icon ?? _defaultIcon)?.icon),
          title: const Text('Ikona'),
          subtitle: Text(appIcon(_icon ?? _defaultIcon)?.label ?? ''),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final key = await pickAppIcon(context, current: _icon, defaultKey: _defaultIcon);
            if (key != null) setState(() => _icon = key.isEmpty ? null : key);
          },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('widgetLabel'),
          controller: _label,
          maxLength: 24,
          decoration: InputDecoration(labelText: 'Podpis (opcjonalnie)', hintText: _point?.name ?? _device!.name),
        ),
        const SizedBox(height: 8),
        FilledButton(key: const Key('addWidgetDone'), onPressed: _done, child: const Text('Dodaj do pulpitu')),
      ],
    );
  }
}

class SizeChooser extends StatelessWidget {
  const SizeChooser({super.key, required this.value, required this.onChanged});

  final WidgetSize value;
  final ValueChanged<WidgetSize> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<WidgetSize>(
    segments: [for (final s in WidgetSize.values) ButtonSegment(value: s, label: Text(s.wire.replaceAll('x', '×')))],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

/// Wybór sceny domu do widżetu; właściciel (bez konta - każdy) może tu też tworzyć, zmieniać i usuwać sceny.
class ScenePickerScreen extends StatelessWidget {
  const ScenePickerScreen({super.key, required this.hub});

  final DeviceHub hub;

  Future<void> _edit(BuildContext context, [Scene? scene]) async {
    final saved = await Navigator.of(context).push<Scene>(
      MaterialPageRoute(
        builder: (_) => SceneEditorScreen(hub: hub, initial: scene),
      ),
    );
    if (saved != null && scene == null && context.mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _delete(BuildContext context, Scene scene) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć scenę „${scene.name}”?'),
        content: const Text('Zniknie u wszystkich domowników, a jej widżety przestaną działać.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok == true && context.mounted) await Services.of(context).scenes.remove(hub.homeId, scene.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Scena')),
        floatingActionButton: hub.canEditShared
            ? FloatingActionButton.extended(
                key: const Key('newScene'),
                heroTag: null,
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('Nowa scena'),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (hub.scenes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  hub.canEditShared
                      ? 'Nie ma jeszcze scen. Scena to kilka poleceń naraz, np. „Wychodzę z domu”.'
                      : 'Nie ma jeszcze scen. Układa je właściciel domu.',
                ),
              ),
            for (final sc in hub.scenes)
              ListTile(
                key: Key('pickScene-${sc.id}'),
                leading: const Icon(Icons.auto_awesome),
                title: Text(sc.name),
                subtitle: Text(describeScene(hub, sc)),
                onTap: () => Navigator.of(context).pop(sc),
                trailing: hub.canEditShared
                    ? PopupMenuButton<String>(
                        onSelected: (a) => a == 'edit' ? _edit(context, sc) : _delete(context, sc),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Zmień')),
                          PopupMenuItem(value: 'delete', child: Text('Usuń')),
                        ],
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// Krótki opis akcji sceny.
String describeScene(DeviceHub hub, Scene scene) => scene.actions
    .map(
      (a) => a.isSet
          ? '${hub.device(a.device!)?.name ?? a.device}: ${describeSet(a.set!)}'
          : a.delay != null
          ? 'czekaj ${a.delay} s'
          : a.notify != null
          ? 'powiadomienie'
          : a.log != null
          ? 'dziennik'
          : a.raw != null
          ? (a.isBranch ? 'jeśli…' : 'akcja huba')
          : 'scena ${hub.scene(a.scene!)?.name ?? a.scene}',
    )
    .join(' · ');

/// Edytor sceny (`homes/{h}/scenes/{id}`, pisze właściciel): nazwa i akcje - ustawienie urządzenia albo przerwa.
class SceneEditorScreen extends StatefulWidget {
  const SceneEditorScreen({super.key, required this.hub, this.initial});

  final DeviceHub hub;
  final Scene? initial;

  @override
  State<SceneEditorScreen> createState() => _SceneEditorScreenState();
}

class _SceneEditorScreenState extends State<SceneEditorScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late List<SceneAction> _actions = [...?widget.initial?.actions];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addStep() async {
    final step = await Navigator.of(
      context,
    ).push<SceneAction>(MaterialPageRoute(builder: (_) => SceneStepScreen(hub: widget.hub)));
    if (step != null) setState(() => _actions = [..._actions, step]);
  }

  /// Krok „Jeśli…” (nowy albo edycja kroku [i]) - wykonuje go hub.
  Future<void> _editBranch([int? i]) async {
    final j = await Navigator.of(context).push<Json>(
      MaterialPageRoute(
        builder: (_) => BranchEditorScreen(hub: widget.hub, initial: i == null ? null : _actions[i].raw),
      ),
    );
    if (j == null) return;
    final step = SceneAction.raw(j);
    setState(() => _actions = i == null ? [..._actions, step] : ([..._actions]..[i] = step));
  }

  Future<void> _addDelay() async {
    final text = await showTextInputDialog(context, title: 'Przerwa (sekundy)', initial: '30', maxLength: 5);
    final s = int.tryParse(text ?? '');
    if (s != null && s > 0) setState(() => _actions = [..._actions, SceneAction.delay(s)]);
  }

  Future<void> _save() async {
    final scene = Scene(id: widget.initial?.id ?? newLocalId('s'), name: _name.text.trim(), actions: _actions);
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Services.of(context).scenes.save(widget.hub.homeId, scene);
      unawaited(widget.hub.reloadHubs());
      navigator.pop(scene);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie zapisano sceny: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  String _actionText(SceneAction a) => a.isSet
      ? describeSet(a.set!)
      : a.delay != null
      ? 'czekaj ${a.delay} s${a.delay! > 60 ? ' (tylko z hubem)' : ''}'
      : a.notify != null
      ? 'powiadomienie: ${a.notify} (wysyła hub)'
      : a.log != null
      ? 'dziennik: ${a.log}'
      : a.isBranch
      ? '${describeAction(widget.hub, a.raw!)} (wykonuje hub)'
      : a.raw != null
      ? 'akcja huba'
      : 'scena ${widget.hub.scene(a.scene!)?.name ?? a.scene}';

  Future<void> _addNotify() async {
    final text = await showTextInputDialog(context, title: 'Treść powiadomienia', maxLength: 80);
    if (text != null && text.trim().isNotEmpty) {
      setState(() => _actions = [..._actions, SceneAction.notify(text.trim())]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Nowa scena' : 'Scena'),
        actions: [
          TextButton(
            key: const Key('sceneSave'),
            onPressed: _actions.isEmpty || name.isEmpty || _saving ? null : _save,
            child: const Text('Zapisz'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('sceneAddStep'),
        heroTag: null,
        onPressed: _addStep,
        icon: const Icon(Icons.add),
        label: const Text('Krok'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            key: const Key('sceneLabel'),
            controller: _name,
            maxLength: 24,
            decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'np. Wychodzę z domu'),
            onChanged: (_) => setState(() {}),
          ),
          Text(
            'Z hubem scenę wykonuje hub (także przerwy). Bez huba wysyła ją telefon, krok po kroku, '
            'z uprawnieniami osoby, która ją uruchamia.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SectionHeader('Kroki'),
          if (_actions.isEmpty) const Text('Dodaj co najmniej jeden krok.'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (a, b) => setState(() => _actions = reorder(_actions, a, b)),
            children: [
              for (final (i, a) in _actions.indexed)
                ListTile(
                  key: ValueKey('step-$i-${a.device ?? a.delay ?? a.scene ?? a.notify ?? a.log ?? a.raw.hashCode}'),
                  leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                  title: Text(
                    a.isSet
                        ? widget.hub.device(a.device!)?.name ?? a.device!
                        : a.delay != null
                        ? 'Przerwa'
                        : a.notify != null
                        ? 'Powiadomienie'
                        : a.log != null
                        ? 'Dziennik'
                        : a.isBranch
                        ? 'Jeśli…'
                        : a.raw != null
                        ? 'Akcja'
                        : 'Scena',
                  ),
                  onTap: a.isBranch ? () => _editBranch(i) : null,
                  subtitle: Text(_actionText(a)),
                  trailing: IconButton(
                    tooltip: 'Usuń krok',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _actions = [..._actions]..removeAt(i)),
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const Key('sceneAddDelay'),
                onPressed: _addDelay,
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Przerwa'),
              ),
              if (widget.hub.hubs.isNotEmpty) ...[
                TextButton.icon(
                  key: const Key('sceneAddNotify'),
                  onPressed: _addNotify,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Powiadomienie'),
                ),
                TextButton.icon(
                  key: const Key('sceneAddIf'),
                  onPressed: _editBranch,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Jeśli…'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Krok sceny: urządzenie → ustawialny punkt → wartość.
class SceneStepScreen extends StatefulWidget {
  const SceneStepScreen({super.key, required this.hub});

  final DeviceHub hub;

  @override
  State<SceneStepScreen> createState() => _SceneStepScreenState();
}

class _SceneStepScreenState extends State<SceneStepScreen> {
  PairedDevice? _device;
  Future<List<DataPoint>>? _points;
  DataPoint? _point;
  Object? _value;

  /// „Przełącz” zamiast wł. / wył. (`toggle` / `toggleN`, pkt 12).
  bool _toggle = false;

  /// Klucz przełączania dla punktu `on` / `onN`, inaczej null (np. `power` termostatu nie ma przełączania).
  static String? _toggleKey(DataPoint p) {
    final m = RegExp(r'^on(\d*)$').firstMatch(p.key);
    return p.kind == PointKind.switchKind && m != null ? 'toggle${m.group(1)}' : null;
  }

  @override
  Widget build(BuildContext context) {
    final step = _device == null ? 0 : (_point == null ? 1 : 2);
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          if (_point != null) {
            _point = null;
          } else {
            _device = null;
          }
        });
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Krok sceny')),
        body: switch (step) {
          0 => ListView(
            children: [
              const SectionHeader('Urządzenie'),
              for (final d in widget.hub.devices)
                if (widget.hub.accessFor(d.id).canControl)
                  ListTile(
                    key: Key('step-device-${d.id}'),
                    title: Text(d.name),
                    subtitle: Text(d.type.label),
                    onTap: () => setState(() {
                      _device = d;
                      _points = pointsOf(widget.hub, d);
                    }),
                  ),
            ],
          ),
          1 => FutureBuilder<List<DataPoint>>(
            future: _points,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final level = widget.hub.accessFor(_device!.id);
              final points = [
                for (final p in snap.data!)
                  if (p.kind.writable && level.atLeast(p.access)) p,
              ];
              return ListView(
                children: [
                  SectionHeader('${_device!.name}: co ustawić'),
                  for (final p in points)
                    ListTile(
                      key: Key('step-point-${p.key}'),
                      title: Text(p.name),
                      subtitle: Text(kindLabel(p.kind)),
                      onTap: () => setState(() {
                        _point = p;
                        _toggle = false;
                        _value = switch (p.kind) {
                          PointKind.switchKind || PointKind.action => true,
                          PointKind.select => p.options.firstOrNull,
                          _ => p.min ?? 0,
                        };
                      }),
                    ),
                  if (points.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Nie ma tu nic, co możesz ustawić.')),
                ],
              );
            },
          ),
          _ => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(_point!.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              _valuePicker(_point!),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('stepDone'),
                onPressed: () => Navigator.of(
                  context,
                ).pop(SceneAction.set(_device!.id, _toggle ? {_toggleKey(_point!)!: true} : _point!.setFor(_value))),
                child: const Text('Dodaj krok'),
              ),
            ],
          ),
        },
      ),
    );
  }

  Widget _valuePicker(DataPoint p) => switch (p.kind) {
    PointKind.switchKind => SegmentedButton<String>(
      key: const Key('stepSwitch'),
      segments: [
        const ButtonSegment(value: 'on', label: Text('Włącz')),
        const ButtonSegment(value: 'off', label: Text('Wyłącz')),
        if (_toggleKey(p) != null) const ButtonSegment(value: 'toggle', label: Text('Przełącz')),
      ],
      selected: {_toggle ? 'toggle' : (_value == true ? 'on' : 'off')},
      onSelectionChanged: (s) => setState(() {
        _toggle = s.first == 'toggle';
        if (!_toggle) _value = s.first == 'on';
      }),
    ),
    PointKind.select => Wrap(
      spacing: 8,
      children: [
        for (final o in p.options)
          ChoiceChip(label: Text(optionLabel(o)), selected: _value == o, onSelected: (_) => setState(() => _value = o)),
      ],
    ),
    PointKind.action => const Text('Naciśnięcie przycisku.'),
    _ when p.min != null && p.max != null => Column(
      children: [
        Text(p.format(_value), style: Theme.of(context).textTheme.headlineMedium),
        SetpointSlider(
          point: p,
          value: (_value as num? ?? p.min!).toDouble(),
          enabled: true,
          onChanged: (v) => setState(() => _value = v),
        ),
      ],
    ),
    _ => TextField(
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(labelText: 'Wartość', suffixText: p.unit),
      onChanged: (t) => _value = num.tryParse(t.replaceAll(',', '.')),
    ),
  };
}
