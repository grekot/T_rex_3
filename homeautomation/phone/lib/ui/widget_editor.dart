import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../data/device_store.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/scene.dart';
import '../services.dart';
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
  PointKind.sensor => [WidgetView.value, if (p.history != null) WidgetView.chart],
  PointKind.status => [WidgetView.status, WidgetView.value],
  PointKind.setpoint => [WidgetView.stepper, WidgetView.slider, WidgetView.value, if (p.history != null) WidgetView.chart],
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
  DeviceType.thermostat => [for (final k in ['temp', 'hum', 'target', 'heating', 'mode']) fallbackPoint(k)],
  DeviceType.onOff => [fallbackPoint('on')],
  DeviceType.dimmer => [fallbackPoint('on'), fallbackPoint('level')],
  _ => const [],
};

/// Punkty urządzenia z `describe` (albo zapasowe wg typu).
Future<List<DataPoint>> pointsOf(DeviceHub hub, PairedDevice d) async {
  final c = hub.controller(d.id);
  final desc = await c?.description().timeout(const Duration(seconds: 8), onTimeout: () => null);
  return desc?.points ?? fallbackPoints(d.type);
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
    return widget.forWatch ? [for (final v in all) if (watchWidgetViews.contains(v)) v] : all;
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
      Navigator.of(context).pop(
        DashWidget(id: newLocalId('w'), view: WidgetView.scene, size: WidgetSize.s2x1, sceneId: scene.id),
      );
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
        return ListView(
          children: [
            SectionHeader('${d.name}: co pokazać'),
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
        const SizedBox(height: 16),
        TextField(
          key: const Key('widgetLabel'),
          controller: _label,
          maxLength: 24,
          decoration: InputDecoration(
            labelText: 'Podpis (opcjonalnie)',
            hintText: _point?.name ?? _device!.name,
          ),
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
    segments: [
      for (final s in WidgetSize.values) ButtonSegment(value: s, label: Text(s.wire.replaceAll('x', '×'))),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

/// Wybór sceny domu do widżetu; właściciel (bez konta - każdy) może tu też tworzyć, zmieniać i usuwać sceny.
class ScenePickerScreen extends StatelessWidget {
  const ScenePickerScreen({super.key, required this.hub});

  final DeviceHub hub;

  Future<void> _edit(BuildContext context, [Scene? scene]) async {
    final saved = await Navigator.of(
      context,
    ).push<Scene>(MaterialPageRoute(builder: (_) => SceneEditorScreen(hub: hub, initial: scene)));
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
                  key: ValueKey('step-$i-${a.device ?? a.delay ?? a.scene ?? a.notify ?? a.log}'),
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
                        : 'Scena',
                  ),
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
              if (widget.hub.hubs.isNotEmpty)
                TextButton.icon(
                  key: const Key('sceneAddNotify'),
                  onPressed: _addNotify,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Powiadomienie'),
                ),
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
                onPressed: () => Navigator.of(context).pop(SceneAction.set(_device!.id, _point!.setFor(_value))),
                child: const Text('Dodaj krok'),
              ),
            ],
          ),
        },
      ),
    );
  }

  Widget _valuePicker(DataPoint p) => switch (p.kind) {
    PointKind.switchKind => SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('Włącz')),
        ButtonSegment(value: false, label: Text('Wyłącz')),
      ],
      selected: {_value == true},
      onSelectionChanged: (s) => setState(() => _value = s.first),
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
