// „Przyciski zdalne” zegara (pkt 10.2, PLAN zegara pkt 9): zwykłe automatyki huba z wyzwalaczem naciśnięcia
// (`{"device","input","press"}`) i akcją `{"device":"zegar-…","set":{"showScreen":…}}`, z polem `owner` = zegar.

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/automation_store.dart';
import '../data/device_store.dart';
import '../data/errors.dart';
import '../models/clock.dart';
import '../models/describe.dart';
import '../models/hub.dart';
import '../services.dart';
import 'clock_section.dart' show clockScreenList;
import 'widget_editor.dart' show pointsOf;

const _presses = {'short': 'krótko', 'double': 'podwójnie', 'triple': 'potrójnie', 'long': 'długo'};

/// Wpis listy: automatyka zegara z wyzwalaczem naciśnięcia.
typedef ClockButton = ({String device, String input, String press, String action});

ClockButton? clockButtonOf(Automation a, String clockId) {
  if (a.owner != clockId || a.when.length != 1 || a.then.length != 1) return null;
  final w = a.when.single, t = a.then.single;
  final set = t['set'];
  if (w['device'] is! String || w['input'] is! String || t['device'] != clockId || set is! Map) return null;
  final action = set['showScreen'];
  if (action is! String) return null;
  return (
    device: w['device'] as String,
    input: w['input'] as String,
    press: '${w['press'] ?? 'short'}',
    action: action,
  );
}

class ClockButtonsScreen extends StatefulWidget {
  const ClockButtonsScreen({super.key, required this.controller, required this.hub, this.automations});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub hub;

  /// Do testów: automatyki huba zamiast z kontrolera huba zegara.
  final HubAutomations? automations;

  @override
  State<ClockButtonsScreen> createState() => _ClockButtonsScreenState();
}

class _ClockButtonsScreenState extends State<ClockButtonsScreen> {
  HubAutomations? _store;
  Future<List<Automation>>? _list;

  DeviceController<Object?, Object?> get c => widget.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store != null || _list != null) return;
    _store = widget.automations ?? _hubStore();
    _reload();
  }

  HubAutomations? _hubStore() {
    final h = c.device.via == null ? null : widget.hub.controller(c.device.via!);
    if (h == null) return null;
    final cloud = Services.of(context).cloud;
    return HubAutomations(hub: h, store: cloud.available ? cloud.store : null, homeId: cloud.homeId);
  }

  void _reload() {
    final list = _store?.load().then(
      (i) => [
        for (final a in i.items)
          if (clockButtonOf(a, c.device.id) != null) a,
      ],
    );
    setState(() {
      _list = list;
    });
  }

  String _deviceName(String id) => widget.hub.device(id)?.name ?? id;

  String _actionName(String a) => clockScreenName(a, ClockPage.listFrom(c.config));

  Future<void> _add() async {
    final r = await Navigator.of(context).push<Automation>(
      MaterialPageRoute(
        builder: (_) => _AddButtonScreen(controller: c, hub: widget.hub),
      ),
    );
    if (r == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store!.save(r);
      _reload();
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(Automation a) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store!.remove(a.id);
      _reload();
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Przyciski zdalne')),
      floatingActionButton: _store == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('clockButtonAdd'),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj przycisk'),
              onPressed: _add,
            ),
      body: _store == null
          ? const Center(child: Text('Zegar nie jest w hubie albo hub jest niedostępny.'))
          : FutureBuilder<List<Automation>>(
              future: _list,
              builder: (context, snap) {
                if (snap.hasError) {
                  final e = snap.error;
                  return Center(child: Text(e is ThermostatException ? e.message : '$e'));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                if (list.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Pilot Bluetooth, przycisk węzła albo czujnika może przełączać ekrany zegara '
                        '(następny, główny, rozjaśnij w nocy, wybrany ekran). Wykonuje to hub.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final a in list)
                      if (clockButtonOf(a, c.device.id) case final b?)
                        ListTile(
                          key: Key('clockButton-${a.id}'),
                          leading: const Icon(Icons.smart_button_outlined),
                          title: Text('${_deviceName(b.device)} · ${b.input} · ${_presses[b.press] ?? b.press}'),
                          subtitle: Text('→ ${_actionName(b.action)}'),
                          trailing: IconButton(
                            key: Key('clockButtonDelete-${a.id}'),
                            tooltip: 'Usuń',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(a),
                          ),
                        ),
                  ],
                );
              },
            ),
    );
  }
}

/// Nowy przycisk: urządzenie i wejście (przycisk, wejście węzła, przycisk czujnika BTHome), naciśnięcie, ekran.
class _AddButtonScreen extends StatefulWidget {
  const _AddButtonScreen({required this.controller, required this.hub});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub hub;

  @override
  State<_AddButtonScreen> createState() => _AddButtonScreenState();
}

class _AddButtonScreenState extends State<_AddButtonScreen> {
  PairedDevice? _device;
  List<DataPoint> _inputs = const [];
  DataPoint? _input;
  String _press = 'short';
  String _action = 'next';

  DeviceController<Object?, Object?> get c => widget.controller;

  /// Urządzenia z przyciskami znane hubowi zegara (przez hub albo sam zegar - jego przyciski `in1`-`in3`).
  List<PairedDevice> get _devices => [
    for (final d in widget.hub.devices)
      if (d.id == c.device.id || (d.via != null && d.via == c.device.via)) d,
  ];

  Future<void> _pickDevice(PairedDevice d) async {
    setState(() {
      _device = d;
      _inputs = const [];
      _input = null;
    });
    final points = await pointsOf(widget.hub, d);
    final inputs = [
      for (final p in points)
        if (p.kind == PointKind.button || RegExp(r'^in\d+$').hasMatch(p.key)) p,
    ];
    if (!mounted || _device != d) return;
    setState(() {
      _inputs = inputs;
      _input = inputs.firstOrNull;
      if (_input?.kind != PointKind.button && _press == 'triple') _press = 'short';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ble = _input?.kind == PointKind.button;
    final screens = clockScreenList(c.config is Map ? (c.config! as Map).cast<String, dynamic>() : null);
    final pages = ClockPage.listFrom(c.config);
    final d = _device, input = _input;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dodaj przycisk'),
        actions: [
          TextButton(
            key: const Key('clockButtonSave'),
            onPressed: d == null || input == null
                ? null
                : () {
                    final what = clockScreenName(_action, pages);
                    Navigator.pop(
                      context,
                      Automation(
                        id: hubDocId('zegar ${c.device.name} ${d.name} ${input.key} $_press'),
                        name: 'Zegar ${c.device.name}: ${d.name} ${input.name} ${_presses[_press]} → $what',
                        when: [
                          {'device': d.id, 'input': input.key, 'press': _press},
                        ],
                        then: [
                          {
                            'device': c.device.id,
                            'set': {'showScreen': _action},
                          },
                        ],
                        owner: c.device.id,
                      ),
                    );
                  },
            child: const Text('Zapisz'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Przycisk', style: t.titleSmall),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final x in _devices)
                ChoiceChip(
                  key: Key('clockButtonDevice-${x.id}'),
                  label: Text(x.name),
                  selected: d?.id == x.id,
                  onSelected: (_) => _pickDevice(x),
                ),
            ],
          ),
          if (d != null && _inputs.isEmpty) const Text('To urządzenie nie ma przycisków ani wejść.'),
          if (_inputs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in _inputs)
                  ChoiceChip(
                    key: Key('clockButtonInput-${p.key}'),
                    label: Text(p.name),
                    selected: input?.key == p.key,
                    onSelected: (_) => setState(() => _input = p),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('Naciśnięcie', style: t.titleSmall),
          SegmentedButton<String>(
            key: const Key('clockButtonPress'),
            showSelectedIcon: false,
            segments: [
              for (final MapEntry(key: k, value: l) in _presses.entries)
                if (k != 'triple' || ble) ButtonSegment(value: k, label: Text(l)),
            ],
            selected: {_press},
            onSelectionChanged: (v) => setState(() => _press = v.single),
          ),
          const SizedBox(height: 16),
          Text('Zegar pokaże', style: t.titleSmall),
          RadioGroup<String>(
            groupValue: _action,
            onChanged: (v) => setState(() => _action = v ?? 'next'),
            child: Column(
              children: [
                for (final k in [...clockCommands.keys, ...screens])
                  RadioListTile<String>(
                    key: Key('clockButtonAction-$k'),
                    value: k,
                    title: Text(clockScreenName(k, pages)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
