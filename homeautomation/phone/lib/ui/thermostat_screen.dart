import 'package:flutter/material.dart';

import '../controllers/thermostat_controller.dart';
import '../data/device_store.dart';
import '../models/set_values.dart';
import '../models/thermostat_state.dart';
import 'format.dart';
import 'pairing_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'generic_device_screen.dart' show AccessBanner;
import 'widgets.dart';

/// Ekran główny termostatu: temperatura, nastawa, tryb, grzanie.
class ThermostatScreen extends StatefulWidget {
  const ThermostatScreen({super.key, required this.controller});

  final ThermostatController controller;

  @override
  State<ThermostatScreen> createState() => _ThermostatScreenState();
}

class _ThermostatScreenState extends State<ThermostatScreen> with WidgetsBindingObserver {
  ThermostatController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (c.connection == null) c.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.refreshRoute();
  }

  Future<void> _repair() async {
    final device = await Navigator.of(
      context,
    ).push<PairedDevice>(MaterialPageRoute(builder: (_) => PairingScreen(initialEndpoint: c.device.lastEndpoint)));
    if (device != null) await c.connect();
  }

  Future<void> _send(SetValues v) async {
    final r = await c.send(v);
    if (!mounted || r.errors.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeErrors(r.errors))));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final connected = c.phase == ConnectPhase.connected && c.state != null;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.config?.name ?? c.device.name),
            actions: [
              IconButton(
                tooltip: 'Harmonogram',
                icon: const Icon(Icons.calendar_month),
                onPressed: connected && c.config != null && c.canConfig
                    ? () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => ScheduleScreen(controller: c)))
                    : null,
              ),
              IconButton(
                tooltip: 'Ustawienia',
                icon: const Icon(Icons.settings),
                onPressed: connected && c.config != null && c.canConfig
                    ? () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(controller: c)))
                    : null,
              ),
            ],
          ),
          body: switch (c.phase) {
            ConnectPhase.connecting => ConnectingView(step: c.step),
            ConnectPhase.failed => FailedView(
              message: c.error ?? 'Nie udało się połączyć.',
              needsPairing: c.needsPairing,
              onRetry: c.connect,
              onPair: _repair,
            ),
            ConnectPhase.connected when c.needsPairing => FailedView(
              message: 'Termostat odrzucił token. Sparuj telefon ponownie.',
              needsPairing: true,
              onRetry: c.connect,
              onPair: _repair,
            ),
            ConnectPhase.connected => RefreshIndicator(
              onRefresh: c.connect,
              child: _Body(controller: c, send: _send),
            ),
          },
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.send});

  final ThermostatController controller;
  final Future<void> Function(SetValues) send;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.state!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        RouteChip(controller: c),
        if (!c.canControl) const AccessBanner(text: 'Masz tylko podgląd tego termostatu.'),
        if (s.sensorFault)
          _Banner(
            icon: Icons.warning_amber_rounded,
            text: s.protect == 'faultDuty'
                ? 'Awaria czujnika temperatury - termostat grzeje cyklicznie (ochrona przed zamarzaniem).'
                : 'Awaria czujnika temperatury - grzanie zablokowane.',
            error: true,
          ),
        if (!s.power)
          _Banner(
            icon: Icons.power_settings_new,
            text: s.protect == 'frost'
                ? 'System wyłączony - termostat pilnuje tylko ochrony przed zamarzaniem'
                      '${c.config == null || c.config!.frost.temp <= 0 ? '' : ' (${fmtTemp(c.config!.frost.temp)})'}.'
                : 'System wyłączony - termostat nie grzeje.',
          ),
        if (s.power && s.protect == 'frost')
          const _Banner(icon: Icons.ac_unit, text: 'Grzeje ochrona przed zamarzaniem (temperatura poniżej progu).'),
        if (!s.timeKnown)
          const _Banner(icon: Icons.schedule, text: 'Termostat nie zna aktualnego czasu - harmonogram nie działa.'),
        _CurrentCard(state: s),
        const SizedBox(height: 12),
        _TargetCard(controller: c),
        const SizedBox(height: 12),
        _ModeCard(state: s, send: send, enabled: c.canControl),
        const SizedBox(height: 12),
        _DetailsCard(state: s),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = error ? cs.errorContainer : cs.secondaryContainer;
    final fg = error ? cs.onErrorContainer : cs.onSecondaryContainer;
    return Card(
      color: bg,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: fg, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.state});

  final ThermostatState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final heatColor = state.heating ? const Color(0xFFE8590C) : cs.outline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('W pomieszczeniu', style: t.labelLarge),
                  Text(
                    state.temp == null ? '—' : fmtTemp(state.temp),
                    key: const Key('currentTemp'),
                    style: t.displayMedium?.copyWith(fontWeight: FontWeight.w300),
                  ),
                  Row(
                    children: [
                      Icon(Icons.water_drop_outlined, size: 18, color: cs.primary),
                      const SizedBox(width: 4),
                      Text('Wilgotność ${fmtPercent(state.hum)}', key: const Key('humidity'), style: t.bodyLarge),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Icon(Icons.local_fire_department, size: 48, color: heatColor),
                Text(
                  state.heating ? 'Grzeje' : 'Nie grzeje',
                  key: const Key('heating'),
                  style: t.labelLarge?.copyWith(color: heatColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.controller});

  final ThermostatController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.state!;
    final target = c.displayTarget ?? s.target;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        child: Column(
          children: [
            Text('Nastawa', style: t.labelLarge),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  key: const Key('targetDown'),
                  iconSize: 32,
                  tooltip: '−0,5 °C',
                  onPressed: target > targetMin && c.canControl ? () => c.stepTarget(-targetStep) : null,
                  icon: const Icon(Icons.remove),
                ),
                Column(
                  children: [
                    Text(
                      fmtTemp(target),
                      key: const Key('target'),
                      style: t.displaySmall?.copyWith(color: c.targetPending ? cs.tertiary : null),
                    ),
                    SizedBox(height: 16, child: c.targetPending ? Text('wysyłanie…', style: t.bodySmall) : null),
                  ],
                ),
                IconButton.filledTonal(
                  key: const Key('targetUp'),
                  iconSize: 32,
                  tooltip: '+0,5 °C',
                  onPressed: target < targetMax && c.canControl ? () => c.stepTarget(targetStep) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (s.mode == ThermostatMode.auto) ...[
              const SizedBox(height: 8),
              Text(_autoLine(s), key: const Key('autoLine'), style: t.bodyMedium, textAlign: TextAlign.center),
              if (!s.override)
                Text(
                  'Zmiana nastawy w AUTO działa do następnej zmiany w planie.',
                  style: t.bodySmall,
                  textAlign: TextAlign.center,
                ),
            ],
            if (c.lastSendError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  c.lastSendError!,
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _autoLine(ThermostatState s) {
    final until = s.nextChange == null ? '' : ' do ${s.nextChange}';
    if (s.override) return 'Nadpisanie ręczne$until';
    return '${s.comfortNow ? 'Komfort' : 'Eko'}$until';
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.state, required this.send, this.enabled = true});

  final ThermostatState state;
  final Future<void> Function(SetValues) send;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThermostatMode>(
                key: const Key('mode'),
                segments: const [
                  ButtonSegment(value: ThermostatMode.manual, label: Text('Ręczny'), icon: Icon(Icons.pan_tool_alt)),
                  ButtonSegment(value: ThermostatMode.auto, label: Text('AUTO'), icon: Icon(Icons.schedule)),
                ],
                selected: {state.mode},
                onSelectionChanged: enabled ? (s) => send(SetValues(mode: s.single)) : null,
              ),
            ),
          ),
          SwitchListTile(
            key: const Key('power'),
            title: const Text('System włączony'),
            subtitle: Text(state.power ? 'Termostat steruje kotłem' : 'Kocioł nie będzie włączany'),
            value: state.power,
            onChanged: enabled ? (v) => send(SetValues(power: v)) : null,
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.state});

  final ThermostatState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final rows = <(IconData, String, String)>[
      if (s.outdoor != null)
        (Icons.wb_cloudy_outlined, 'Na zewnątrz', '${fmtTemp(s.outdoor!.temp)} · ${fmtAge(s.outdoor!.age)}'),
      if (s.press != null) (Icons.speed, 'Ciśnienie', '${s.press!.round()} hPa'),
      if (s.lux != null) (Icons.light_mode_outlined, 'Światło', '${s.lux!.round()} lx'),
      if (s.wifiRssi != null) (Icons.network_wifi, 'Wi-Fi termostatu', '${s.wifiRssi} dBm'),
      (Icons.cloud_outlined, 'Termostat w chmurze', s.cloud ? 'połączony' : 'niepołączony'),
      (Icons.timer_outlined, 'Czas pracy', fmtUptime(s.uptime)),
    ];
    return Card(
      child: Column(
        children: [
          for (final (icon, label, value) in rows)
            ListTile(dense: true, leading: Icon(icon), title: Text(label), trailing: Text(value)),
        ],
      ),
    );
  }
}
