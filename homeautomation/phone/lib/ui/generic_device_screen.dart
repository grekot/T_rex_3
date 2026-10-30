import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/field_errors.dart';
import '../data/device_store.dart';
import '../models/describe.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import '../models/light.dart';
import 'device_admin_section.dart';
import 'format.dart';
import 'pairing_screen.dart';
import 'point_controls.dart';
import 'widgets.dart';

/// Szczegóły urządzenia innego niż termostat: lista punktów danych z `describe` (pkt 14) z kontrolkami
/// wg rodzaju i poziomu dostępu, a niżej ustawienia techniczne.
class GenericDeviceScreen extends StatefulWidget {
  const GenericDeviceScreen({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<GenericDeviceScreen> createState() => _GenericDeviceScreenState();
}

class _GenericDeviceScreenState extends State<GenericDeviceScreen> {
  DeviceController<Object?, Object?> get c => widget.controller;
  Future<DeviceDescription?>? _describe;
  Object? _describedConnection;

  @override
  void initState() {
    super.initState();
    if (c.connection == null) c.connect();
    _describedConnection = c.connection;
    _describe = c.description();
    c.addListener(_onController);
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    // Po (ponownym) połączeniu pytamy o opis jeszcze raz (raz na połączenie).
    final conn = c.connection;
    if (conn == null || identical(conn, _describedConnection)) return;
    setState(() {
      _describedConnection = conn;
      _describe = c.description();
    });
  }

  Future<void> _rename() async {
    final name = await showTextInputDialog(context, title: 'Nazwa', initial: c.device.name, maxLength: 24);
    if (name == null || !mounted) return;
    final r = await c.sendJson({'name': name});
    if (mounted) showSaveResult(context, r.errors, describeErrors);
  }

  /// „Pokaż, który to”: dioda na płytce miga 10 s (pkt 10.1).
  Future<void> _identify() async {
    final r = await c.sendJson(const LightSet(identify: true).toJson());
    if (!mounted) return;
    if (r.errors.isNotEmpty) {
      showSaveResult(context, r.errors, describeErrors);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Dioda na płytce i przyciski migają przez 10 s.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final state = c.stateJson;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.device.name),
            actions: [
              if (state != null && c.canConfig)
                IconButton(tooltip: 'Zmień nazwę', icon: const Icon(Icons.edit), onPressed: _rename),
            ],
          ),
          body: switch (c.phase) {
            ConnectPhase.connecting => ConnectingView(step: c.step),
            ConnectPhase.failed || ConnectPhase.connected when state == null || c.needsPairing => FailedView(
              message: c.error ?? 'Nie udało się połączyć.',
              needsPairing: c.needsPairing,
              onRetry: c.connect,
              onPair: () async {
                final d = await Navigator.of(context).push<PairedDevice>(
                  MaterialPageRoute(builder: (_) => PairingScreen(initialEndpoint: c.device.lastEndpoint)),
                );
                if (d != null) await c.connect();
              },
            ),
            _ => RefreshIndicator(onRefresh: c.connect, child: _body(context, state!)),
          },
        );
      },
    );
  }

  String? _inputName(int k) {
    final cfg = c.config;
    return cfg is LightConfig && k <= cfg.inputs.length ? cfg.inputs[k - 1].name : null;
  }

  /// Przełącznik z ustawieniami z firmware 1.4 (pkt 10.1: diody, progi temperatury, impulsy, liczniki).
  bool get _extended => switch (c.config) {
    final LightConfig cfg => cfg.hasIndicator || cfg.hasTempLimits,
    _ => false,
  };

  ChannelConfig? _channel(int n) {
    final cfg = c.config;
    return cfg is LightConfig && n >= 1 && n <= cfg.channels.length ? cfg.channels[n - 1] : null;
  }

  /// Druga linia kanału `onN`: odliczanie do wyłączenia / włączenia, czas impulsu.
  Widget? _pointSubtitle(DataPoint p) {
    final ls = c.state;
    final m = RegExp(r'^on(\d+)$').firstMatch(p.key);
    if (ls is! LightState || m == null) return null;
    final n = int.parse(m.group(1)!);
    final ch = _channel(n);
    if (ls.offIn[n] case final s?) {
      return CountdownText(
        key: Key('offIn-$n'),
        seconds: s,
        prefix: ch?.isPulse == true ? 'Impuls trwa, jeszcze' : 'Wyłączy się za',
      );
    }
    if (ls.waitIn[n] case final s?) {
      return CountdownText(key: Key('wait-$n'), seconds: s, prefix: 'Włączy się za', suffix: ' (minimalna przerwa)');
    }
    if (ch != null && ch.isPulse) return Text('Impuls ${fmtMillis(ch.pulse)}');
    if (ch != null && ch.autoOff > 0) return Text('Wyłącza się sam po ${fmtSeconds(ch.autoOff)}');
    return null;
  }

  /// Opis stanu wejścia wg rodzaju (`kind`), np. „otwarte” dla kontaktronu.
  String? _statusText(DataPoint p, Object? v) {
    if (p.key == 'overheat') return v == true ? 'za gorąco' : 'w normie';
    final m = RegExp(r'^in(\d+)$').firstMatch(p.key);
    final cfg = c.config;
    if (m == null || cfg is! LightConfig || !_extended) return null;
    final k = int.parse(m.group(1)!);
    return k <= cfg.inputs.length ? cfg.inputs[k - 1].kind.stateText(v == true) : null;
  }

  Widget _body(BuildContext context, Json state) {
    final cs = Theme.of(context).colorScheme;
    final ls = c.state is LightState ? c.state! as LightState : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        RouteChip(controller: c),
        if (!c.canControl) const AccessBanner(text: 'Masz tylko podgląd tego urządzenia.'),
        if (ls != null && (ls.overheat || ls.overheatOff))
          Card(
            key: const Key('overheatBanner'),
            color: ls.overheatOff ? cs.errorContainer : cs.tertiaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.device_thermostat,
                color: ls.overheatOff ? cs.onErrorContainer : cs.onTertiaryContainer,
              ),
              title: Text(
                ls.overheatOff ? 'Przegrzanie - wszystkie kanały wyłączone' : 'Wysoka temperatura w obudowie',
                style: TextStyle(color: ls.overheatOff ? cs.onErrorContainer : cs.onTertiaryContainer),
              ),
              subtitle: Text(
                '${ls.temp == null ? '' : 'Teraz ${fmtTemp(ls.temp)}. '}'
                '${ls.overheatOff ? 'Włączanie jest zablokowane, aż urządzenie ostygnie o 5 °C.' : 'Sprawdź obciążenie kanałów i wentylację puszki.'}',
                style: TextStyle(color: ls.overheatOff ? cs.onErrorContainer : cs.onTertiaryContainer),
              ),
            ),
          ),
        if (ls case LightState(inputFaults: final faults) when faults.isNotEmpty)
          Card(
            key: const Key('inputFaultBanner'),
            color: cs.errorContainer,
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
              title: Text(
                [
                  for (final k in faults)
                    'Wejście $k${_inputName(k) == null ? '' : ' (${_inputName(k)})'}: usterka przewodu - zablokowane',
                ].join('\n'),
                style: TextStyle(color: cs.onErrorContainer),
              ),
              subtitle: Text(
                'Ponad 30 zmian w 5 s (przerwany przewód albo zakłócenia). Wejście nie przełącza światła; '
                'wróci samo po minucie spokoju.',
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ),
        if (_extended && c.canControl)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OutlinedButton.icon(
                key: const Key('identify'),
                icon: const Icon(Icons.highlight),
                label: const Text('Pokaż, który to'),
                onPressed: _identify,
              ),
            ),
          ),
        FutureBuilder<DeviceDescription?>(
          future: _describe,
          builder: (context, snap) {
            final d = snap.data;
            if (snap.connectionState == ConnectionState.waiting && d == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (d == null || d.points.isEmpty) {
              // Bez opisu: surowy stan.
              return Card(
                child: Column(
                  children: [
                    for (final e in state.entries.where((e) => e.value is! Map))
                      ListTile(dense: true, title: Text(e.key), trailing: Text('${e.value}')),
                  ],
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final p in d.points)
                    PointTile(
                      point: p,
                      value: p.valueIn(state),
                      enabled: c.access.atLeast(p.access),
                      subtitle: _pointSubtitle(p),
                      statusText: _statusText(p, p.valueIn(state)),
                      actionLabel: p.kind == PointKind.action && RegExp(r'^on\d+$').hasMatch(p.key)
                          ? 'Impuls'
                          : 'Wykonaj',
                      onSet: (v) async {
                        final r = await c.sendJson(p.setFor(v));
                        if (context.mounted && r.errors.isNotEmpty) showSaveResult(context, r.errors, describeErrors);
                      },
                    ),
                ],
              ),
            );
          },
        ),
        if (c.lastSendError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(c.lastSendError!, style: TextStyle(color: cs.error)),
          ),
        if (c.device.type.isLight && c.canConfig)
          if (c.config case LightConfig(channels: final ch, inputs: final ins) when ch.isNotEmpty || ins.isNotEmpty)
            _ChannelsSection(controller: c, channels: ch, inputs: ins, state: ls, extended: _extended)
          else
            _DefaultOnSection(controller: c),
        if (c.device.type.isLight && c.canConfig && _extended)
          if (c.config case final LightConfig cfg) _ExtrasSection(controller: c, config: cfg, state: ls),
        DeviceAdminSection(
          controller: c,
          cloudLinked: state['cloud'] == true,
          uptime: state['uptime'] is num ? (state['uptime'] as num).toInt() : null,
        ),
      ],
    );
  }
}

/// Światła: zachowanie po zaniku zasilania (`defaultOn`, pkt 10).
class _DefaultOnSection extends StatelessWidget {
  const _DefaultOnSection({required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  Widget build(BuildContext context) {
    final cfg = controller.config;
    final current = cfg is LightConfig ? cfg.defaultOn : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Po zaniku zasilania'),
        for (final d in DefaultOn.values)
          ListTile(
            title: Text(d.label),
            leading: Icon(current == d ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            onTap: () async {
              final r = await controller.sendJson(LightSet(defaultOn: d).toJson());
              if (context.mounted && r.errors.isNotEmpty) showSaveResult(context, r.errors, describeErrors);
            },
          ),
      ],
    );
  }
}

/// Ikona wejścia wg rodzaju.
IconData inputKindIcon(InputKind k) => switch (k) {
  InputKind.button => Icons.radio_button_checked,
  InputKind.switch_ => Icons.toggle_on_outlined,
  InputKind.contact => Icons.sensor_door_outlined,
  InputKind.motion => Icons.directions_walk,
  InputKind.leak => Icons.water_drop_outlined,
  InputKind.other => Icons.input,
};

/// Liczniki kanału: „1830 łączeń · 412,5 h pracy”.
String? _counters(LightState? s, int n) {
  final cycles = s?.cycles[n], hours = s?.hours[n];
  if (cycles == null && hours == null) return null;
  return [if (cycles != null) '$cycles łączeń', if (hours != null) '${fmtNumber(hours)} h pracy'].join(' · ');
}

/// Przełącznik wielokanałowy z wejściami (pkt 10.1): kanały (nazwa, stan po zaniku zasilania, wyłączanie po czasie,
/// impuls, minimalna przerwa, liczniki) i wejścia zwierane do masy (nazwa, rodzaj, tryb, kanały, druga funkcja, NC)
/// - działają lokalnie w węźle, bez sieci.
class _ChannelsSection extends StatelessWidget {
  const _ChannelsSection({
    required this.controller,
    required this.channels,
    this.inputs = const [],
    this.state,
    this.extended = false,
  });

  final DeviceController<Object?, Object?> controller;
  final List<ChannelConfig> channels;
  final List<InputConfig> inputs;
  final LightState? state;

  /// Firmware z ustawieniami 1.4 (pkt 10.1).
  final bool extended;

  Set<int> get _faults => state?.inputFaults ?? const {};

  String _targets(List<int> outs) => outs.isEmpty
      ? 'nic (tylko stan dla huba)'
      : outs.map((n) => n <= channels.length ? channels[n - 1].name : 'kanał $n').join(', ');

  Future<void> _send(BuildContext context, LightSet set) async {
    final r = await controller.sendJson(set.toJson());
    if (context.mounted) showSaveResult(context, r.errors, describeErrors);
  }

  Future<void> _editChannel(BuildContext context, int n, ChannelConfig ch) async {
    final patch = await showDialog<ChannelPatch>(
      context: context,
      builder: (_) => _ChannelDialog(n: n, channel: ch, extended: extended, counters: _counters(state, n)),
    );
    if (patch == null || patch.toJson().isEmpty || !context.mounted) return;
    await _send(context, LightSet(channel: {n: patch}));
  }

  Future<void> _editInput(BuildContext context, int k, InputConfig x) async {
    final patch = await showDialog<InputPatch>(
      context: context,
      builder: (_) => _InputDialog(k: k, input: x, channels: channels, extended: extended),
    );
    if (patch == null || patch.toJson().isEmpty || !context.mounted) return;
    await _send(context, LightSet(input: {k: patch}));
  }

  String _channelSubtitle(int n, ChannelConfig ch) => [
    if (ch.isPulse)
      'Impuls ${fmtMillis(ch.pulse)}'
    else ...[
      'Po zaniku zasilania: ${ch.defaultOn.label.toLowerCase()}',
      if (ch.autoOff > 0) 'wyłącza się po ${fmtSeconds(ch.autoOff)}',
      if (ch.minOff > 0) 'przerwa min. ${fmtSeconds(ch.minOff)}',
    ],
    ?_counters(state, n),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (channels.isNotEmpty) const SectionHeader('Kanały'),
        for (final (i, ch) in channels.indexed)
          ListTile(
            key: Key('channel-${i + 1}'),
            leading: CircleAvatar(child: ch.isPulse ? const Icon(Icons.touch_app_outlined) : Text('${i + 1}')),
            title: Text(ch.name),
            subtitle: Text(_channelSubtitle(i + 1, ch)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editChannel(context, i + 1, ch),
          ),
        if (inputs.isNotEmpty) const SectionHeader('Wejścia (przyciski, łączniki, czujniki)'),
        for (final (i, x) in inputs.indexed)
          ListTile(
            key: Key('input-${i + 1}'),
            leading: _faults.contains(i + 1)
                ? Icon(Icons.warning_amber_rounded, color: error)
                : Icon(
                    extended
                        ? inputKindIcon(x.kind)
                        : (x.mode == InputMode.momentary ? Icons.radio_button_checked : Icons.toggle_on_outlined),
                  ),
            title: Text(x.name),
            subtitle: Text(
              _faults.contains(i + 1)
                  ? 'Usterka przewodu - zablokowane · ${x.mode.label}'
                  : [
                      if (extended && x.kind != InputKind.button) x.kind.label,
                      x.mode.label,
                      'steruje: ${_targets(x.outs)}',
                      if (x.longOuts.isNotEmpty) 'długie: ${_targets(x.longOuts)}',
                      if (x.invert) 'styk NC',
                    ].join(' · '),
              style: _faults.contains(i + 1) ? TextStyle(color: error) : null,
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editInput(context, i + 1, x),
          ),
      ],
    );
  }
}

/// Lista wyboru wartości z gotowych [presets] (plus bieżąca, jeśli spoza listy).
class _PresetDropdown extends StatelessWidget {
  const _PresetDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.presets,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> presets;
  final String Function(int) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = {...presets, value}.toList()..sort();
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final v in values) DropdownMenuItem(value: v, child: Text(format(v)))],
      onChanged: (v) => onChanged(v ?? 0),
    );
  }
}

class _ChannelDialog extends StatefulWidget {
  const _ChannelDialog({required this.n, required this.channel, this.extended = false, this.counters});

  final int n;
  final ChannelConfig channel;
  final bool extended;

  /// Opis liczników („1830 łączeń · 412,5 h pracy”), gdy urządzenie je podaje.
  final String? counters;

  @override
  State<_ChannelDialog> createState() => _ChannelDialogState();
}

class _ChannelDialogState extends State<_ChannelDialog> {
  late final _name = TextEditingController(text: widget.channel.name);
  late DefaultOn _defaultOn = widget.channel.defaultOn;
  late int _pulse = widget.channel.pulse;
  late int _autoOff = widget.channel.autoOff;
  late String _autoOffPress = widget.channel.autoOffPress;
  late int _minOff = widget.channel.minOff;
  bool _reset = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ChannelPatch _patch() {
    final ch = widget.channel;
    T? changed<T>(T now, T was) => now != was ? now : null;
    return ChannelPatch(
      name: changed(_name.text.trim(), ch.name),
      defaultOn: changed(_defaultOn, ch.defaultOn),
      pulse: changed(_pulse, ch.pulse),
      autoOff: _pulse > 0 ? null : changed(_autoOff, ch.autoOff),
      autoOffPress: _pulse > 0 || _autoOff == 0 ? null : changed(_autoOffPress, ch.autoOffPress),
      minOff: _pulse > 0 ? null : changed(_minOff, ch.minOff),
      resetCounters: _reset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pulse = _pulse > 0;
    return AlertDialog(
      title: Text('Kanał ${widget.n}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('channelName'),
              controller: _name,
              maxLength: 32,
              decoration: const InputDecoration(labelText: 'Nazwa'),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.extended) ...[
              SegmentedButton<bool>(
                key: const Key('channelKind'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Zwykły'), icon: Icon(Icons.lightbulb_outline)),
                  ButtonSegment(value: true, label: Text('Impulsowy'), icon: Icon(Icons.touch_app_outlined)),
                ],
                selected: {pulse},
                onSelectionChanged: (s) =>
                    setState(() => _pulse = s.first ? (widget.channel.pulse > 0 ? widget.channel.pulse : 500) : 0),
              ),
              const SizedBox(height: 8),
            ],
            if (pulse) ...[
              _PresetDropdown(
                key: const Key('channelPulse'),
                label: 'Czas impulsu',
                value: _pulse,
                presets: const [200, 500, 1000, 2000, 3000, 5000, 10000],
                format: fmtMillis,
                onChanged: (v) => setState(() => _pulse = v),
              ),
              const SizedBox(height: 4),
              Text(
                'Brama, furtka, elektrozaczep: każde włączenie zamyka przekaźnik na ten czas. '
                'Kanał nigdy nie włącza się sam po starcie.',
                style: t.bodySmall,
              ),
            ] else ...[
              Text('Po zaniku zasilania', style: t.labelLarge),
              RadioGroup<DefaultOn>(
                groupValue: _defaultOn,
                onChanged: (v) => setState(() => _defaultOn = v!),
                child: Column(
                  children: [
                    for (final d in DefaultOn.values)
                      RadioListTile<DefaultOn>(
                        key: Key('defaultOn-${d.wire}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: d,
                        title: Text(d.label),
                      ),
                  ],
                ),
              ),
              if (widget.extended) ...[
                _PresetDropdown(
                  key: const Key('channelAutoOff'),
                  label: 'Wyłącz sam po',
                  value: _autoOff,
                  presets: const [0, 30, 60, 120, 180, 300, 600, 900, 1800, 3600, 7200, 14400, 28800, 86400],
                  format: fmtSeconds,
                  onChanged: (v) => setState(() => _autoOff = v),
                ),
                if (_autoOff > 0)
                  RadioGroup<String>(
                    groupValue: _autoOffPress,
                    onChanged: (v) => setState(() => _autoOffPress = v!),
                    child: const Column(
                      children: [
                        RadioListTile<String>(
                          key: Key('autoOffPress-off'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: 'off',
                          title: Text('Ponowne naciśnięcie przycisku wyłącza'),
                        ),
                        RadioListTile<String>(
                          key: Key('autoOffPress-extend'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: 'extend',
                          title: Text('Ponowne naciśnięcie odlicza od nowa'),
                          subtitle: Text('przytrzymanie przycisku wyłącza (schody, korytarz)'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                _PresetDropdown(
                  key: const Key('channelMinOff'),
                  label: 'Minimalna przerwa po wyłączeniu',
                  value: _minOff,
                  presets: const [0, 10, 30, 60, 120, 300, 600, 1800, 3600],
                  format: fmtSeconds,
                  onChanged: (v) => setState(() => _minOff = v),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pompa, sprężarka, wentylator: wcześniejsze włączenie czeka do końca przerwy.',
                  style: t.bodySmall,
                ),
              ],
            ],
            if (widget.counters != null) ...[
              const SizedBox(height: 12),
              Text('Liczniki: ${widget.counters}', style: t.bodyMedium),
              CheckboxListTile(
                key: const Key('resetCounters'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _reset,
                onChanged: (v) => setState(() => _reset = v ?? false),
                title: const Text('Wyzeruj liczniki (po wymianie przekaźnika)'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('channelSave'),
          onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, _patch()),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.k, required this.input, required this.channels, this.extended = false});

  final int k;
  final InputConfig input;
  final List<ChannelConfig> channels;

  /// Firmware 1.4: rodzaj, czujka ruchu, kilka kanałów, druga funkcja, NC.
  final bool extended;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _name = TextEditingController(text: widget.input.name);
  late InputMode _mode = widget.input.mode;
  late InputKind _kind = widget.input.kind;
  late final _outs = {...widget.input.outs};
  late final _longOuts = {...widget.input.longOuts};
  late bool _invert = widget.input.invert;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static bool _same(Set<int> a, List<int> b) => a.length == b.length && a.containsAll(b);

  InputPatch _patch() {
    final x = widget.input;
    final outs = _outs.toList()..sort();
    final longOuts = _longOuts.toList()..sort();
    return InputPatch(
      name: _name.text.trim() != x.name ? _name.text.trim() : null,
      mode: _mode != x.mode ? _mode : null,
      outs: _same(_outs, x.outs) ? null : outs,
      longOuts: _mode != InputMode.momentary || _same(_longOuts, x.longOuts) ? null : longOuts,
      kind: _kind != x.kind ? _kind : null,
      invert: _invert != x.invert ? _invert : null,
    );
  }

  /// Wybór kanałów: przy firmware 1.4 kilka naraz, wcześniej jeden.
  Widget _channelChips(String keyPrefix, Set<int> selected) => Wrap(
    spacing: 6,
    runSpacing: 0,
    children: [
      for (final (i, ch) in widget.channels.indexed)
        FilterChip(
          key: Key('$keyPrefix-${i + 1}'),
          label: Text('${i + 1}: ${ch.name}'),
          selected: selected.contains(i + 1),
          onSelected: (v) => setState(() {
            if (!widget.extended) selected.clear();
            v ? selected.add(i + 1) : selected.remove(i + 1);
          }),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final modes = widget.extended ? InputMode.values : InputMode.values.where((m) => m != InputMode.motion);
    return AlertDialog(
      title: Text('Wejście ${widget.k}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('inputName'),
              controller: _name,
              maxLength: 32,
              decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'np. Przedpokój'),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.extended) ...[
              DropdownButtonFormField<InputKind>(
                key: const Key('inputKind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Co jest podłączone'),
                items: [
                  for (final k in InputKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Row(children: [Icon(inputKindIcon(k), size: 20), const SizedBox(width: 8), Text(k.label)]),
                    ),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 8),
            ],
            Text(widget.extended ? 'Jak działa' : 'Co jest podłączone', style: t.labelLarge),
            RadioGroup<InputMode>(
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
              child: Column(
                children: [
                  for (final m in modes)
                    RadioListTile<InputMode>(
                      key: Key('mode-${m.wire}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: m,
                      title: Text(m.label),
                      subtitle: Text(m.help),
                    ),
                ],
              ),
            ),
            Text(widget.extended ? 'Przełącza kanały' : 'Przełącza kanał', style: t.labelLarge),
            _channelChips('inputOut', _outs),
            if (_outs.isEmpty) Text('Żaden - wejście tylko jako stan dla huba i automatyk.', style: t.bodySmall),
            if (widget.extended && _mode == InputMode.momentary) ...[
              const SizedBox(height: 8),
              Text('Długie naciśnięcie (≥ 0,8 s) przełącza', style: t.labelLarge),
              _channelChips('inputLongOut', _longOuts),
            ],
            if (widget.extended)
              SwitchListTile(
                key: const Key('inputInvert'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _invert,
                onChanged: (v) => setState(() => _invert = v),
                title: const Text('Styk normalnie zamknięty (NC)'),
                subtitle: const Text('kontaktron NC, czujka alarmowa, krańcówka - aktywne = rozwarte'),
              ),
            const SizedBox(height: 8),
            Text(
              'Działa w samym urządzeniu - bez sieci i telefonu. Kilka wejść może sterować tym samym kanałem.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('inputSave'),
          onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, _patch()),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

/// Diody przycisków i ochrona przed przegrzaniem (pkt 10.1, `indicator`, `tempWarn`, `tempOff`).
class _ExtrasSection extends StatelessWidget {
  const _ExtrasSection({required this.controller, required this.config, this.state});

  final DeviceController<Object?, Object?> controller;
  final LightConfig config;
  final LightState? state;

  static String _deg(int v) => v <= 0 ? 'nie' : '$v °C';

  Future<void> _send(BuildContext context, LightSet set) async {
    if (set.toJson().isEmpty) return;
    final r = await controller.sendJson(set.toJson());
    if (context.mounted) showSaveResult(context, r.errors, describeErrors);
  }

  Future<void> _editIndicator(BuildContext context) async {
    final r = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _IndicatorDialog(on: config.indicatorOn ?? 60, off: config.indicatorOff ?? 5),
    );
    if (r == null || !context.mounted) return;
    await _send(
      context,
      LightSet(
        indicatorOn: r.$1 != config.indicatorOn ? r.$1 : null,
        indicatorOff: r.$2 != config.indicatorOff ? r.$2 : null,
      ),
    );
  }

  Future<void> _editTemp(BuildContext context) async {
    var warn = config.tempWarn ?? 60, off = config.tempOff ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ochrona przed przegrzaniem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PresetDropdown(
                key: const Key('tempWarn'),
                label: 'Ostrzeżenie powyżej',
                value: warn,
                presets: const [0, 40, 45, 50, 55, 60, 65, 70, 80, 90],
                format: _deg,
                onChanged: (v) => setState(() => warn = v),
              ),
              const SizedBox(height: 8),
              _PresetDropdown(
                key: const Key('tempOff'),
                label: 'Wyłączenie wszystkich kanałów powyżej',
                value: off,
                presets: const [0, 50, 60, 70, 80, 90, 100],
                format: _deg,
                onChanged: (v) => setState(() => off = v),
              ),
              const SizedBox(height: 8),
              Text(
                'Działa z czujnikiem temperatury w obudowie. Po wyłączeniu kanały można włączyć dopiero, '
                'gdy temperatura spadnie o 5 °C.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
            FilledButton(
              key: const Key('tempSave'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _send(
      context,
      LightSet(tempWarn: warn != config.tempWarn ? warn : null, tempOff: off != config.tempOff ? off : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final temp = state?.temp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Diody i temperatura'),
        if (config.hasIndicator)
          ListTile(
            key: const Key('indicatorTile'),
            leading: const Icon(Icons.light_mode_outlined),
            title: const Text('Diody przycisków'),
            subtitle: Text('kanał włączony ${config.indicatorOn ?? '—'} % · wyłączony ${config.indicatorOff ?? '—'} %'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editIndicator(context),
          ),
        if (config.hasTempLimits)
          ListTile(
            key: const Key('tempTile'),
            leading: const Icon(Icons.device_thermostat),
            title: const Text('Ochrona przed przegrzaniem'),
            subtitle: Text(
              '${temp == null ? 'Brak czujnika w obudowie' : 'W obudowie ${fmtTemp(temp)}'} · '
              'ostrzeżenie: ${_deg(config.tempWarn ?? 0)} · wyłączenie: ${_deg(config.tempOff ?? 0)}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editTemp(context),
          ),
      ],
    );
  }
}

class _IndicatorDialog extends StatefulWidget {
  const _IndicatorDialog({required this.on, required this.off});

  final int on;
  final int off;

  @override
  State<_IndicatorDialog> createState() => _IndicatorDialogState();
}

class _IndicatorDialogState extends State<_IndicatorDialog> {
  late double _on = widget.on.toDouble();
  late double _off = widget.off.toDouble();

  Widget _slider(String key, String label, double v, ValueChanged<double> set) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ${v.round()} %'),
      Slider(key: Key(key), value: v, min: 0, max: 100, divisions: 20, onChanged: (x) => setState(() => set(x))),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Diody przycisków'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _slider('indicatorOn', 'Kanał włączony', _on, (x) => _on = x),
        _slider('indicatorOff', 'Kanał wyłączony', _off, (x) => _off = x),
        Text(
          'Dioda N świeci przy przycisku kanału N: słabo przy wyłączonym, mocno przy włączonym.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
      FilledButton(
        key: const Key('indicatorSave'),
        onPressed: () => Navigator.pop(context, (_on.round(), _off.round())),
        child: const Text('Zapisz'),
      ),
    ],
  );
}

/// Pasek „tylko podgląd” / „bez dostępu”.
class AccessBanner extends StatelessWidget {
  const AccessBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer,
      child: ListTile(
        leading: Icon(Icons.visibility_outlined, color: cs.onSecondaryContainer),
        title: Text(text, style: TextStyle(color: cs.onSecondaryContainer)),
      ),
    );
  }
}

/// Czy poziom wystarcza do ustawienia punktu.
bool canSet(AccessLevel level, DataPoint p) => p.kind.writable && level.atLeast(p.access);
