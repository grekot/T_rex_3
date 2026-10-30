import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/automation_store.dart';
import '../data/errors.dart';
import '../data/hub_api.dart';
import '../data/device_store.dart';
import '../models/dashboard.dart' show reorder;
import '../models/describe.dart';
import '../models/hub.dart';
import '../models/json_utils.dart';
import '../models/scene.dart';
import '../services.dart';
import 'dashboard_tiles.dart' show channelName, describeSet, fallbackPoint;
import 'point_controls.dart' show optionLabel;
import 'widget_editor.dart';
import 'widgets.dart';

const _dayNames = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

String _days(Object? v) {
  final d = v is List
      ? [
          for (final x in v)
            if (x is int && x >= 1 && x <= 7) x,
        ]
      : const <int>[];
  if (d.isEmpty || d.length == 7) return '';
  if (d.length == 5 && d.every((x) => x <= 5)) return ' (pn-pt)';
  if (d.length == 2 && d.contains(6) && d.contains(7)) return ' (weekend)';
  return ' (${d.map((x) => _dayNames[x - 1]).join(', ')})';
}

const _ops = {'eq': '=', 'ne': '≠', 'gt': '>', 'lt': '<', 'gte': '≥', 'lte': '≤'};

String _value(Object? v) => switch (v) {
  true => 'tak',
  false => 'nie',
  final String s => optionLabel(s),
  _ => '$v',
};

String _deviceName(DeviceHub hub, Object? id) => hub.device('$id')?.name ?? '$id';

/// Nazwa punktu; kanały i wejścia węzła (`onN`, `inN`) z nazwami z modułu.
String _pointName(DeviceHub hub, Object? device, String? key) {
  if (key == null) return '?';
  final c = device == null ? null : hub.controller('$device');
  return RegExp(r'^(on|in)\d+$').hasMatch(key) ? channelName(c, null, key) : fallbackPoint(key).name;
}

String _stateText(DeviceHub hub, Json j) {
  final op = _ops.keys.firstWhere(j.containsKey, orElse: () => 'eq');
  final forS = j['for'] is num ? ' przez ${j['for']} s' : '';
  final v = j[op];
  // Kanał (`on` / `onN`): „wł.” / „wył.” zamiast „tak” / „nie”.
  final value = v is bool && RegExp(r'^on\d*$').hasMatch('${j['point']}') ? (v ? 'wł.' : 'wył.') : _value(v);
  return '${_deviceName(hub, j['device'])}: ${_pointName(hub, j['device'], j['point'] as String?)} '
      '${_ops[op]} $value$forS';
}

/// Set akcji po polsku: kanały jako „Taras - wł.” / „Taras - przełącz” (`onN`, `toggleN`, pkt 10.1 i 12),
/// `on` / `toggle` węzła wielokanałowego - „wszystkie kanały”; reszta jak [describeSet].
String _describeDeviceSet(DeviceHub hub, Object? device, Json set) {
  final c = hub.controller('$device');
  final channels = c?.stateJson?['channels'];
  final multi = channels is int && channels > 1;
  final parts = <String>[];
  final rest = <String, dynamic>{};
  for (final e in set.entries) {
    final m = RegExp(r'^(on|toggle)(\d*)$').firstMatch(e.key);
    final toggle = m?.group(1) == 'toggle';
    if (m == null || (toggle ? e.value != true : e.value is! bool)) {
      rest[e.key] = e.value;
      continue;
    }
    final n = m.group(2)!;
    final what = n.isEmpty ? (multi ? 'wszystkie kanały' : null) : channelName(c, null, 'on$n');
    final verb = toggle ? 'przełącz' : (e.value == true ? 'wł.' : 'wył.');
    parts.add(what == null ? verb : '$what - $verb');
  }
  if (rest.isNotEmpty) parts.add(describeSet(rest));
  return parts.join(', ');
}

/// Opis wyzwalacza po polsku.
String describeTrigger(DeviceHub hub, Json j) {
  if (j['time'] is String) return 'o ${j['time']}${_days(j['days'])}';
  if (j['sun'] is String) {
    final o = j['offset'] is num ? (j['offset'] as num).toInt() : 0;
    final off = o == 0 ? '' : (o > 0 ? ' + $o min' : ' − ${-o} min');
    return '${j['sun'] == 'sunrise' ? 'wschód' : 'zachód'} słońca$off${_days(j['days'])}';
  }
  if (j['input'] is String) {
    final press = switch (j['press']) {
      'double' => 'podwójne naciśnięcie',
      'long' => 'długie naciśnięcie',
      _ => 'naciśnięcie',
    };
    return '$press: ${_deviceName(hub, j['device'])}, ${_pointName(hub, j['device'], j['input'] as String)}';
  }
  if (j['device'] != null) return 'gdy ${_stateText(hub, j)}';
  if (j['scene'] is String) return 'po scenie „${hub.scene(j['scene'] as String)?.name ?? j['scene']}”';
  return '$j';
}

/// Opis warunku po polsku.
String describeCondition(DeviceHub hub, Json j) {
  if (j['time'] is String) return 'pora ${j['time']}${_days(j['days'])}';
  if (j['sun'] is String) return j['sun'] == 'night' ? 'po zmroku' : 'za dnia';
  if (j['device'] != null) return _stateText(hub, j);
  if (j['days'] is List) return 'dni${_days(j['days'])}';
  return '$j';
}

/// „1 akcja”, „3 akcje”, „5 akcji”.
String _actionsCount(Object? list) {
  final n = list is List ? list.length : 0;
  if (n == 0) return 'nic';
  final word = n == 1 ? 'akcja' : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) ? 'akcje' : 'akcji');
  return '$n $word';
}

/// Opis akcji po polsku.
String describeAction(DeviceHub hub, Json j) {
  if (j['if'] is List) {
    final conds = [
      for (final c in j['if'] as List)
        if (c is Map) describeCondition(hub, c.cast<String, dynamic>()),
    ].join(' i ');
    final otherwise = j['else'] is List && (j['else'] as List).isNotEmpty
        ? ', inaczej → ${_actionsCount(j['else'])}'
        : '';
    return 'Jeśli $conds → ${_actionsCount(j['then'])}$otherwise';
  }
  if (j['device'] != null && j['set'] is Map) {
    return '${_deviceName(hub, j['device'])}: ${_describeDeviceSet(hub, j['device'], (j['set'] as Map).cast<String, dynamic>())}';
  }
  if (j['delay'] is num) return 'czekaj ${j['delay']} s';
  if (j['scene'] is String) return 'scena „${hub.scene(j['scene'] as String)?.name ?? j['scene']}”';
  if (j['notify'] is String) {
    final level = switch (j['level']) {
      'alarm' => 'alarm',
      'warning' => 'ostrzeżenie',
      _ => 'informacja',
    };
    return 'powiadomienie ($level): ${j['notify']}';
  }
  if (j['log'] is String) return 'dziennik: ${j['log']}';
  return '$j';
}

/// „Automatyki” huba: lista z włącznikiem, diagnostyka (problemy, wschód/zachód, czas), uruchom teraz, dziennik.
class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key, required this.hub, required this.controller, this.service});

  final DeviceHub hub;

  /// Kontroler huba.
  final DeviceController<Object?, Object?> controller;

  /// Do testów.
  final HubAutomations? service;

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  late HubAutomations _service;
  Future<AutomationsInfo>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final cloud = Services.of(context).cloud;
    _service =
        widget.service ??
        HubAutomations(hub: widget.controller, store: cloud.available ? cloud.store : null, homeId: cloud.homeId);
    _load = _service.load();
  }

  void _reload() => setState(() {
    _load = _service.load();
  });

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _save(Automation a) async {
    try {
      await _service.save(a);
      _reload();
    } on HubInvalidException catch (e) {
      _snack(e.message);
    } on ThermostatException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _edit([Automation? a]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AutomationEditorScreen(hub: widget.hub, service: _service, initial: a),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _menu(Automation a, String action) async {
    try {
      switch (action) {
        case 'run':
          await _service.run(a.id);
          _snack('Uruchomiono „${a.name}”.');
        case 'delete':
          await _service.remove(a.id);
          _reload();
      }
    } on ThermostatException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _log() async {
    List<HubLogEntry> entries;
    try {
      entries = await _service.log();
    } on ThermostatException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HubLogScreen(entries: entries)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automatyki'),
        actions: [
          IconButton(tooltip: 'Dziennik', icon: const Icon(Icons.history), onPressed: _log),
          IconButton(tooltip: 'Odśwież', icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newAutomation'),
        heroTag: null,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Automatyka'),
      ),
      body: FutureBuilder<AutomationsInfo>(
        future: _load,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(e is ThermostatException ? e.message : '$e', style: TextStyle(color: cs.error)),
              ),
            );
          }
          final info = snap.data;
          if (info == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              ListTile(
                leading: Icon(_service.isLocal ? Icons.home_outlined : Icons.cloud_outlined),
                title: Text(_service.isLocal ? 'Edycja w hubie (sieć domowa)' : 'Edycja przez chmurę'),
                subtitle: Text(
                  [
                    if (info.sunrise != null) 'wschód ${info.sunrise}, zachód ${info.sunset}',
                    if (!_service.isLocal) 'hub pobierze zmiany od razu (reload)',
                    if (info.pendingSync > 0) 'do wysłania do chmury: ${info.pendingSync}',
                  ].join(' · '),
                ),
              ),
              if (!info.timeKnown)
                Card(
                  color: cs.errorContainer,
                  child: ListTile(
                    leading: Icon(Icons.schedule, color: cs.onErrorContainer),
                    title: Text(
                      'Hub nie zna czasu - wyzwalacze o godzinie i od słońca czekają. Ustaw czas na ekranie huba.',
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
                ),
              for (final p in info.problems)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.error_outline, color: cs.error),
                  title: Text('Pominięta: $p', style: TextStyle(color: cs.error)),
                ),
              if (info.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nie ma jeszcze automatyk. Np. „Taras o zmroku”: o zachodzie słońca włącz światło na tarasie, '
                    'po 2 godzinach wyłącz.',
                  ),
                ),
              for (final a in info.items)
                ListTile(
                  key: Key('automation-${a.id}'),
                  leading: Switch(
                    value: a.enabled,
                    onChanged: (v) => _save(a.copyWith(enabled: v)),
                  ),
                  title: Text(a.name),
                  subtitle: Text(
                    [
                      ...a.when.map((t) => describeTrigger(widget.hub, t)),
                      if (a.then.isNotEmpty)
                        '→ ${describeAction(widget.hub, a.then.first)}${a.then.length > 1 ? '…' : ''}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _edit(a),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => _menu(a, v),
                    itemBuilder: (_) => [
                      if (_service.isLocal) const PopupMenuItem(value: 'run', child: Text('Uruchom teraz')),
                      const PopupMenuItem(value: 'delete', child: Text('Usuń')),
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

/// Dziennik wykonań scen i automatyk.
class HubLogScreen extends StatelessWidget {
  const HubLogScreen({super.key, required this.entries});

  final List<HubLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String two(int x) => x.toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('Dziennik huba')),
      body: entries.isEmpty
          ? const Center(child: Text('Dziennik jest pusty.'))
          : ListView(
              children: [
                for (final e in entries)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      e.ok ? Icons.check_circle_outline : Icons.error_outline,
                      color: e.ok ? null : cs.error,
                    ),
                    title: Text(
                      e.kind == 'log'
                          ? (e.text ?? '')
                          : '${e.kind == 'scene' ? 'Scena' : 'Automatyka'} ${e.name ?? e.id ?? ''}',
                    ),
                    subtitle: Text(
                      [
                        if (e.ts > 0)
                          () {
                            final d = DateTime.fromMillisecondsSinceEpoch(e.ts);
                            return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
                          }(),
                        if (e.trigger != null) e.trigger!,
                        if (e.error != null) e.error!,
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Edytor automatyki: nazwa, wyzwalacze (wystarczy jeden), warunki (wszystkie), akcje po kolei.
class AutomationEditorScreen extends StatefulWidget {
  const AutomationEditorScreen({super.key, required this.hub, required this.service, this.initial});

  final DeviceHub hub;
  final HubAutomations service;
  final Automation? initial;

  @override
  State<AutomationEditorScreen> createState() => _AutomationEditorScreenState();
}

class _AutomationEditorScreenState extends State<AutomationEditorScreen> with _RuleEditing {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late bool _enabled = widget.initial?.enabled ?? true;
  late List<Json> _when = [...?widget.initial?.when];
  late List<Json> _if = [...?widget.initial?.conditions];
  late List<Json> _then = [...?widget.initial?.then];
  List<String> _problems = const [];
  bool _saving = false;

  @override
  DeviceHub get hub => widget.hub;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final a = Automation(
      id: widget.initial?.id ?? hubDocId(name),
      name: name,
      enabled: _enabled,
      when: _when,
      conditions: _if,
      then: _then,
    );
    setState(() {
      _saving = true;
      _problems = const [];
    });
    final navigator = Navigator.of(context);
    try {
      await widget.service.save(a);
      navigator.pop(true);
    } on HubInvalidException catch (e) {
      setState(() => _problems = e.problems);
    } on ThermostatException catch (e) {
      setState(() => _problems = [e.message]);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTrigger(String kind) async {
    Json? t;
    switch (kind) {
      case 'time':
        final time = await _time('Godzina');
        if (time == null) return;
        final days = await _daysDialog();
        if (days == null) return;
        t = {'time': time, if (days.length < 7) 'days': days};
      case 'sun':
        t = await showDialog<Json>(context: context, builder: (_) => const _SunDialog());
      case 'state':
        t = await _stateRule(trigger: true);
      case 'input':
        final picked = await _pickPoint(inputs: true);
        if (picked == null || !mounted) return;
        final press = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(picked.$2.name),
            children: [
              for (final (v, l) in const [('short', 'Krótkie naciśnięcie'), ('double', 'Podwójne'), ('long', 'Długie')])
                SimpleDialogOption(key: Key('press-$v'), onPressed: () => Navigator.pop(ctx, v), child: Text(l)),
            ],
          ),
        );
        if (press == null) return;
        t = {'device': picked.$1.id, 'input': picked.$2.key, 'press': press};
      case 'scene':
        final s = await _pickScene();
        if (s != null) t = {'scene': s.id};
    }
    if (t != null) setState(() => _when = [..._when, t!]);
  }

  Future<void> _addCondition(String kind) async {
    final c = await _conditionOf(kind);
    if (c != null) setState(() => _if = [..._if, c]);
  }

  Future<void> _addAction(String kind) async {
    final a = await _actionOf(kind, 0);
    if (a != null) setState(() => _then = [..._then, a]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = _name.text.trim().isNotEmpty && _when.isNotEmpty && _then.isNotEmpty && !_saving;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Nowa automatyka' : 'Automatyka'),
        actions: [
          TextButton(key: const Key('automationSave'), onPressed: ready ? _save : null, child: const Text('Zapisz')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              key: const Key('automationName'),
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'np. Taras o zmroku'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SwitchListTile(
            title: const Text('Włączona'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          for (final p in _problems)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                p,
                key: const Key('automationProblem'),
                style: TextStyle(color: cs.error),
              ),
            ),
          _section(
            title: 'Kiedy',
            help: 'Wystarczy jedno z poniższych.',
            items: _when,
            describe: (j) => describeTrigger(hub, j),
            onChanged: (l) => setState(() => _when = l),
            add: const {
              'time': 'O godzinie',
              'sun': 'Wschód / zachód słońca',
              'state': 'Stan urządzenia',
              'input': 'Przycisk / wejście węzła',
              'scene': 'Po uruchomieniu sceny',
            },
            onAdd: _addTrigger,
            addKey: const Key('addTrigger'),
          ),
          _section(
            title: 'Tylko jeśli',
            help: 'Wszystkie muszą być spełnione (można nic nie dodawać).',
            items: _if,
            describe: (j) => describeCondition(hub, j),
            onChanged: (l) => setState(() => _if = l),
            add: _conditionKinds,
            onAdd: _addCondition,
            addKey: const Key('addCondition'),
          ),
          _section(
            title: 'Wtedy',
            help: 'Akcje po kolei, z uprawnieniami właściciela domu.',
            items: _then,
            describe: (j) => describeAction(hub, j),
            onChanged: (l) => setState(() => _then = l),
            add: _actionKinds(0),
            onAdd: _addAction,
            addKey: const Key('addAction'),
            reorderable: true,
          ),
        ],
      ),
    );
  }
}

/// Blok „Jeśli…” w akcjach automatyki albo sceny: `{"if":[warunki],"then":[akcje],"else":[akcje]}`
/// (ARCHITEKTURA pkt 4.5). Warunki jak w „Tylko jeśli”, bez „trwa od”; „to” albo „w przeciwnym razie” niepuste.
class BranchEditorScreen extends StatefulWidget {
  const BranchEditorScreen({super.key, required this.hub, this.depth = 1, this.initial});

  final DeviceHub hub;

  /// Poziom zagnieżdżenia (1-2).
  final int depth;
  final Json? initial;

  @override
  State<BranchEditorScreen> createState() => _BranchEditorScreenState();
}

class _BranchEditorScreenState extends State<BranchEditorScreen> with _RuleEditing {
  late List<Json> _if = _list('if');
  late List<Json> _then = _list('then');
  late List<Json> _else = _list('else');

  @override
  DeviceHub get hub => widget.hub;

  List<Json> _list(String key) => [
    for (final x in (widget.initial?[key] is List ? widget.initial![key] as List : const []))
      if (x is Map) x.cast<String, dynamic>(),
  ];

  @override
  Widget build(BuildContext context) {
    final ready = _if.isNotEmpty && (_then.isNotEmpty || _else.isNotEmpty);
    final d = widget.depth;
    return Scaffold(
      appBar: AppBar(
        title: Text(d > 1 ? 'Jeśli… (w bloku)' : 'Jeśli…'),
        actions: [
          TextButton(
            key: const Key('branchOk'),
            onPressed: ready
                ? () => Navigator.pop(context, <String, dynamic>{
                    'if': _if,
                    if (_then.isNotEmpty) 'then': _then,
                    if (_else.isNotEmpty) 'else': _else,
                  })
                : null,
            child: const Text('OK'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _section(
            title: 'Jeśli',
            help: 'Wszystkie muszą być spełnione w chwili wykonania tego kroku.',
            items: _if,
            describe: (j) => describeCondition(hub, j),
            onChanged: (l) => setState(() => _if = l),
            add: _conditionKinds,
            onAdd: (k) async {
              final c = await _conditionOf(k, allowFor: false);
              if (c != null) setState(() => _if = [..._if, c]);
            },
            addKey: Key('branchAddIf-$d'),
          ),
          _section(
            title: 'To',
            help: 'Akcje, gdy warunki są spełnione.',
            items: _then,
            describe: (j) => describeAction(hub, j),
            onChanged: (l) => setState(() => _then = l),
            add: _actionKinds(d),
            onAdd: (k) async {
              final a = await _actionOf(k, d);
              if (a != null) setState(() => _then = [..._then, a]);
            },
            addKey: Key('branchAddThen-$d'),
            reorderable: true,
            depth: d,
          ),
          _section(
            title: 'W przeciwnym razie',
            help: 'Akcje, gdy warunki nie są spełnione (można nic nie dodawać).',
            items: _else,
            describe: (j) => describeAction(hub, j),
            onChanged: (l) => setState(() => _else = l),
            add: _actionKinds(d),
            onAdd: (k) async {
              final a = await _actionOf(k, d);
              if (a != null) setState(() => _else = [..._else, a]);
            },
            addKey: Key('branchAddElse-$d'),
            reorderable: true,
            depth: d,
          ),
        ],
      ),
    );
  }
}

/// Wspólne dla edytora automatyki i bloku „Jeśli…”: wybór urządzeń, warunki, akcje, sekcje listy.
mixin _RuleEditing<W extends StatefulWidget> on State<W> {
  DeviceHub get hub;

  // ---- wybór urządzenia i punktu

  Future<(PairedDevice, DataPoint)?> _pickPoint({bool inputs = false, bool writable = false}) async {
    final d = await showDialog<PairedDevice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Urządzenie'),
        children: [
          for (final d in hub.devices)
            if (d.type.wire != 'hub')
              SimpleDialogOption(
                key: Key('auto-device-${d.id}'),
                onPressed: () => Navigator.pop(ctx, d),
                child: Text(d.name),
              ),
        ],
      ),
    );
    if (d == null || !mounted) return null;
    var points = await pointsOf(hub, d);
    points = [
      for (final p in points)
        if (inputs ? RegExp(r'^in\d+$').hasMatch(p.key) : (!writable || p.kind.writable)) p,
    ];
    if (inputs && points.isEmpty) {
      // Bez describe: wejścia wg stanu urządzenia.
      final n = (hub.controller(d.id)?.stateJson?['inputs'] as num?)?.toInt() ?? 8;
      points = [for (var k = 1; k <= n; k++) fallbackPoint('in$k')];
    }
    if (!mounted) return null;
    final p = await showDialog<DataPoint>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(d.name),
        children: [
          for (final p in points)
            SimpleDialogOption(
              key: Key('auto-point-${p.key}'),
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(p.name),
            ),
          if (points.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Brak punktów danych.')),
        ],
      ),
    );
    return p == null ? null : (d, p);
  }

  /// Warunek / wyzwalacz stanu: urządzenie → punkt → operator i wartość → „przez N s”.
  Future<Json?> _stateRule({required bool trigger, bool allowFor = true}) async {
    final picked = await _pickPoint();
    if (picked == null || !mounted) return null;
    final (d, p) = picked;
    return showDialog<Json>(
      context: context,
      builder: (_) => _StateDialog(device: d, point: p, trigger: trigger, allowFor: allowFor),
    );
  }

  Future<String?> _time(String title, {String initial = '18:00'}) async {
    final parts = initial.split(':');
    final t = await showTimePicker(
      context: context,
      helpText: title,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (t == null) return null;
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Future<List<int>?> _daysDialog([List<int> initial = const [1, 2, 3, 4, 5, 6, 7]]) => showDialog<List<int>>(
    context: context,
    builder: (_) => _DaysDialog(initial: initial),
  );

  /// Nowy warunek wybranego rodzaju ([allowFor] - pole „trwa od”; w bloku „Jeśli…” bez niego).
  Future<Json?> _conditionOf(String kind, {bool allowFor = true}) async {
    Json? c;
    switch (kind) {
      case 'time':
        final from = await _time('Od', initial: '22:00');
        if (from == null) return null;
        final to = await _time('Do', initial: '06:00');
        if (to == null) return null;
        final days = await _daysDialog();
        if (days == null) return null;
        c = {'time': '$from-$to', if (days.length < 7) 'days': days};
      case 'days':
        final days = await _daysDialog(const [6, 7]);
        if (days != null) c = {'days': days};
      case 'day' || 'night':
        c = {'sun': kind};
      case 'state':
        c = await _stateRule(trigger: false, allowFor: allowFor);
    }
    return c;
  }

  Future<Scene?> _pickScene() => showDialog<Scene>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Scena'),
      children: [
        for (final s in hub.scenes) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s), child: Text(s.name)),
        if (hub.scenes.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nie ma jeszcze scen.')),
      ],
    ),
  );

  /// Nowa akcja wybranego rodzaju; [depth] - poziom bloków „Jeśli…” (0 = główna lista).
  Future<Json?> _actionOf(String kind, int depth) async {
    Json? a;
    switch (kind) {
      case 'set':
        final step = await Navigator.of(
          context,
        ).push<SceneAction>(MaterialPageRoute(builder: (_) => SceneStepScreen(hub: hub)));
        if (step != null) a = step.toJson();
      case 'delay':
        final text = await showTextInputDialog(
          context,
          title: 'Przerwa (sekundy, do 24 h)',
          initial: '60',
          maxLength: 5,
        );
        final s = int.tryParse(text ?? '');
        if (s != null && s > 0) a = {'delay': s};
      case 'scene':
        final s = await _pickScene();
        if (s != null) a = {'scene': s.id};
      case 'notify':
        a = await showDialog<Json>(context: context, builder: (_) => const _NotifyDialog());
      case 'if':
        a = await _editBranch(null, depth + 1);
      case 'log':
        final text = await showTextInputDialog(context, title: 'Wpis w dzienniku', maxLength: 60);
        if (text != null && text.trim().isNotEmpty) a = {'log': text.trim()};
    }
    return a;
  }

  /// Blok „Jeśli…” (nowy albo [initial]) na poziomie [depth] (1-2, ARCHITEKTURA pkt 4.5).
  Future<Json?> _editBranch(Json? initial, int depth) => Navigator.of(context).push<Json>(
    MaterialPageRoute(
      builder: (_) => BranchEditorScreen(hub: hub, depth: depth, initial: initial),
    ),
  );

  Widget _section<T>({
    required String title,
    required String help,
    required List<Json> items,
    required String Function(Json) describe,
    required void Function(List<Json>) onChanged,
    required Map<String, String> add,
    required void Function(String) onAdd,
    required Key addKey,
    bool reorderable = false,
    int depth = 0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(help, style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final (i, j) in items.indexed)
          ListTile(
            key: j['if'] is List ? Key('branch-$depth-$i') : null,
            dense: true,
            title: Text(describe(j)),
            onTap: j['if'] is List
                ? () async {
                    final edited = await _editBranch(j, depth + 1);
                    if (edited != null) onChanged([...items]..[i] = edited);
                  }
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reorderable && i > 0)
                  IconButton(
                    tooltip: 'Wyżej',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: () => onChanged(reorder(items, i, i - 1)),
                  ),
                IconButton(
                  tooltip: 'Usuń',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onChanged([...items]..removeAt(i)),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<String>(
            key: addKey,
            onSelected: onAdd,
            itemBuilder: (_) => [for (final e in add.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.add), SizedBox(width: 8), Text('Dodaj')],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rodzaje warunków („Tylko jeśli” i blok „Jeśli…”).
const _conditionKinds = {
  'time': 'Pora dnia',
  'days': 'Dni tygodnia',
  'day': 'Za dnia',
  'night': 'Po zmroku',
  'state': 'Stan urządzenia',
};

/// Rodzaje akcji; „Jeśli…” najwyżej na 2 poziomach (na drugim już bez niego).
Map<String, String> _actionKinds(int depth) => {
  'set': 'Ustaw urządzenie',
  'delay': 'Przerwa',
  'scene': 'Uruchom scenę',
  'notify': 'Powiadomienie',
  'log': 'Wpis w dzienniku',
  if (depth < 2) 'if': 'Jeśli… (warunek)',
};

class _DaysDialog extends StatefulWidget {
  const _DaysDialog({required this.initial});

  final List<int> initial;

  @override
  State<_DaysDialog> createState() => _DaysDialogState();
}

class _DaysDialogState extends State<_DaysDialog> {
  late final _days = {...widget.initial};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Dni tygodnia'),
    content: Wrap(
      spacing: 6,
      children: [
        for (var d = 1; d <= 7; d++)
          FilterChip(
            key: Key('day-$d'),
            label: Text(_dayNames[d - 1]),
            selected: _days.contains(d),
            onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
      FilledButton(
        key: const Key('daysOk'),
        onPressed: _days.isEmpty ? null : () => Navigator.pop(context, _days.toList()..sort()),
        child: const Text('OK'),
      ),
    ],
  );
}

class _SunDialog extends StatefulWidget {
  const _SunDialog();

  @override
  State<_SunDialog> createState() => _SunDialogState();
}

class _SunDialogState extends State<_SunDialog> {
  String _sun = 'sunset';
  double _offset = 0;

  @override
  Widget build(BuildContext context) {
    final o = _offset.round();
    return AlertDialog(
      title: const Text('Słońce'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'sunrise', label: Text('Wschód')),
              ButtonSegment(value: 'sunset', label: Text('Zachód')),
            ],
            selected: {_sun},
            onSelectionChanged: (s) => setState(() => _sun = s.first),
          ),
          const SizedBox(height: 12),
          Text(o == 0 ? 'Dokładnie wtedy' : (o < 0 ? '$o min (wcześniej)' : '+$o min (później)')),
          Slider(value: _offset, min: -120, max: 120, divisions: 48, onChanged: (v) => setState(() => _offset = v)),
          Text('Godziny liczy hub z położenia domu (ekran huba).', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('sunOk'),
          onPressed: () => Navigator.pop(context, <String, dynamic>{'sun': _sun, if (o != 0) 'offset': o}),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _NotifyDialog extends StatefulWidget {
  const _NotifyDialog();

  @override
  State<_NotifyDialog> createState() => _NotifyDialogState();
}

class _NotifyDialogState extends State<_NotifyDialog> {
  final _text = TextEditingController();
  String _level = 'info';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Powiadomienie'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('notifyText'),
          controller: _text,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Treść', hintText: 'np. Drzwi tarasu otwarte'),
          onChanged: (_) => setState(() {}),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'info', label: Text('Info')),
            ButtonSegment(value: 'warning', label: Text('Uwaga')),
            ButtonSegment(value: 'alarm', label: Text('Alarm')),
          ],
          selected: {_level},
          onSelectionChanged: (s) => setState(() => _level = s.first),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
      FilledButton(
        key: const Key('notifyOk'),
        onPressed: _text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, <String, dynamic>{'notify': _text.text.trim(), 'level': _level}),
        child: const Text('OK'),
      ),
    ],
  );
}

/// Warunek / wyzwalacz stanu punktu: operator, wartość, „przez N s”.
class _StateDialog extends StatefulWidget {
  const _StateDialog({required this.device, required this.point, required this.trigger, this.allowFor = true});

  final PairedDevice device;
  final DataPoint point;
  final bool trigger;

  /// Pole „trwa od / co najmniej” (w bloku „Jeśli…” go nie ma).
  final bool allowFor;

  @override
  State<_StateDialog> createState() => _StateDialogState();
}

class _StateDialogState extends State<_StateDialog> {
  String _op = 'eq';
  Object? _value;
  final _number = TextEditingController();
  final _for = TextEditingController();

  bool get _bool => widget.point.kind == PointKind.status || widget.point.kind == PointKind.switchKind;
  bool get _select => widget.point.kind == PointKind.select;

  @override
  void initState() {
    super.initState();
    _value = _bool ? true : (_select ? widget.point.options.firstOrNull : null);
  }

  @override
  void dispose() {
    _number.dispose();
    _for.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    final ops = _bool || _select ? const ['eq', 'ne'] : _ops.keys.toList();
    final value = _bool || _select ? _value : num.tryParse(_number.text.replaceAll(',', '.'));
    final forS = int.tryParse(_for.text);
    return AlertDialog(
      title: Text('${widget.device.name}: ${p.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<String>(
              value: _op,
              isExpanded: true,
              items: [for (final o in ops) DropdownMenuItem(value: o, child: Text(_ops[o]!))],
              onChanged: (o) => setState(() => _op = o ?? 'eq'),
            ),
            if (_bool)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('tak / wł.')),
                  ButtonSegment(value: false, label: Text('nie / wył.')),
                ],
                selected: {_value == true},
                onSelectionChanged: (s) => setState(() => _value = s.first),
              )
            else if (_select)
              Wrap(
                spacing: 6,
                children: [
                  for (final o in p.options)
                    ChoiceChip(
                      label: Text(optionLabel(o)),
                      selected: _value == o,
                      onSelected: (_) => setState(() => _value = o),
                    ),
                ],
              )
            else
              TextField(
                key: const Key('stateValue'),
                controller: _number,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: 'Wartość', suffixText: p.unit),
                onChanged: (_) => setState(() {}),
              ),
            if (widget.allowFor)
              TextField(
                key: const Key('stateFor'),
                controller: _for,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.trigger ? 'Trwa co najmniej (s, opcjonalnie)' : 'Trwa od (s, opcjonalnie)',
                ),
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('stateOk'),
          onPressed: value == null
              ? null
              : () => Navigator.pop(context, <String, dynamic>{
                  'device': widget.device.id,
                  'point': p.key,
                  _op: value,
                  if (forS != null && forS > 0) 'for': forS,
                }),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
