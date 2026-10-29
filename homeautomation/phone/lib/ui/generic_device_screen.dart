import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/field_errors.dart';
import '../data/device_store.dart';
import '../models/describe.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import '../models/light.dart';
import 'device_admin_section.dart';
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

  Widget _body(BuildContext context, Json state) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        RouteChip(controller: c),
        if (!c.canControl) const AccessBanner(text: 'Masz tylko podgląd tego urządzenia.'),
        if (c.state case LightState(inputFaults: final faults) when faults.isNotEmpty)
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
        FutureBuilder<DeviceDescription?>(
          future: _describe,
          builder: (context, snap) {
            final d = snap.data;
            if (snap.connectionState == ConnectionState.waiting && d == null) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
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
            _ChannelsSection(
              controller: c,
              channels: ch,
              inputs: ins,
              faults: c.state is LightState ? (c.state! as LightState).inputFaults : const {},
            )
          else
            _DefaultOnSection(controller: c),
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

/// Przełącznik wielokanałowy z wejściami (pkt 10.1): kanały (nazwa, stan po zaniku zasilania) i wejścia
/// zwierane do masy (nazwa, tryb, kanał, który przełączają - lokalnie w węźle, bez sieci).
class _ChannelsSection extends StatelessWidget {
  const _ChannelsSection({
    required this.controller,
    required this.channels,
    this.inputs = const [],
    this.faults = const {},
  });

  final DeviceController<Object?, Object?> controller;
  final List<ChannelConfig> channels;
  final List<InputConfig> inputs;

  /// Wejścia z usterką (`inNFault`).
  final Set<int> faults;

  String _target(int out) =>
      out <= 0 || out > channels.length ? 'nic (tylko stan dla huba)' : 'kanał $out: ${channels[out - 1].name}';

  Future<void> _send(BuildContext context, LightSet set) async {
    final r = await controller.sendJson(set.toJson());
    if (context.mounted) showSaveResult(context, r.errors, describeErrors);
  }

  Future<void> _editChannel(BuildContext context, int n, ChannelConfig ch) async {
    final patch = await showDialog<ChannelPatch>(
      context: context,
      builder: (_) => _ChannelDialog(n: n, channel: ch),
    );
    if (patch == null || patch.toJson().isEmpty || !context.mounted) return;
    await _send(context, LightSet(channel: {n: patch}));
  }

  Future<void> _editInput(BuildContext context, int k, InputConfig x) async {
    final patch = await showDialog<InputPatch>(
      context: context,
      builder: (_) => _InputDialog(k: k, input: x, channels: channels),
    );
    if (patch == null || patch.toJson().isEmpty || !context.mounted) return;
    await _send(context, LightSet(input: {k: patch}));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (channels.isNotEmpty) const SectionHeader('Kanały'),
        for (final (i, ch) in channels.indexed)
          ListTile(
            key: Key('channel-${i + 1}'),
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(ch.name),
            subtitle: Text('Po zaniku zasilania: ${ch.defaultOn.label.toLowerCase()}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editChannel(context, i + 1, ch),
          ),
        if (inputs.isNotEmpty) const SectionHeader('Wejścia (przyciski i łączniki)'),
        for (final (i, x) in inputs.indexed)
          ListTile(
            key: Key('input-${i + 1}'),
            leading: faults.contains(i + 1)
                ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error)
                : Icon(x.mode == InputMode.momentary ? Icons.radio_button_checked : Icons.toggle_on_outlined),
            title: Text(x.name),
            subtitle: Text(
              faults.contains(i + 1)
                  ? 'Usterka przewodu - zablokowane · ${x.mode.label}'
                  : '${x.mode.label} · steruje: ${_target(x.out)}',
              style: faults.contains(i + 1) ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editInput(context, i + 1, x),
          ),
      ],
    );
  }
}

class _ChannelDialog extends StatefulWidget {
  const _ChannelDialog({required this.n, required this.channel});

  final int n;
  final ChannelConfig channel;

  @override
  State<_ChannelDialog> createState() => _ChannelDialogState();
}

class _ChannelDialogState extends State<_ChannelDialog> {
  late final _name = TextEditingController(text: widget.channel.name);
  late DefaultOn _defaultOn = widget.channel.defaultOn;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
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
            const SizedBox(height: 8),
            Text('Po zaniku zasilania', style: Theme.of(context).textTheme.labelLarge),
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
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('channelSave'),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  ChannelPatch(
                    name: _name.text.trim() != ch.name ? _name.text.trim() : null,
                    defaultOn: _defaultOn != ch.defaultOn ? _defaultOn : null,
                  ),
                ),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.k, required this.input, required this.channels});

  final int k;
  final InputConfig input;
  final List<ChannelConfig> channels;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _name = TextEditingController(text: widget.input.name);
  late InputMode _mode = widget.input.mode;
  late int _out = widget.input.out;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.input;
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
            Text('Co jest podłączone', style: Theme.of(context).textTheme.labelLarge),
            RadioGroup<InputMode>(
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
              child: Column(
                children: [
                  for (final m in InputMode.values)
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
            DropdownButtonFormField<int>(
              key: const Key('inputOut'),
              initialValue: _out,
              decoration: const InputDecoration(labelText: 'Steruje kanałem'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('Brak (tylko stan dla huba)')),
                for (final (i, ch) in widget.channels.indexed)
                  DropdownMenuItem(value: i + 1, child: Text('Kanał ${i + 1}: ${ch.name}')),
              ],
              onChanged: (v) => setState(() => _out = v ?? 0),
            ),
            const SizedBox(height: 8),
            Text(
              'Działa w samym urządzeniu - bez sieci i telefonu. Kilka wejść może sterować tym samym kanałem.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('inputSave'),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  InputPatch(
                    name: _name.text.trim() != x.name ? _name.text.trim() : null,
                    mode: _mode != x.mode ? _mode : null,
                    out: _out != x.out ? _out : null,
                  ),
                ),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
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
