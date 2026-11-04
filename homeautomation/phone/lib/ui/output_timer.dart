// „Wyłącz za…” (pkt 11): jednorazowe odliczanie w hubie dla wyjścia - okno wyboru czasu (z ekranu urządzenia
// i z przytrzymania kafelka) i sekcja „Odliczanie” z aktywnymi timerami urządzenia, czasem do końca i „Anuluj”.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/errors.dart';
import '../data/hub_timers.dart';
import '../models/hub_timer.dart';
import 'dashboard_tiles.dart' show channelName;
import 'format.dart';
import 'widgets.dart';

/// Gotowe czasy w oknie (minuty).
const timerPresets = [5, 15, 30, 60, 120];

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _fmtMinutes(int m) => m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min');

/// Opis timera: „Kanał 2 wyłączy się”, „włączy się”, inaczej pola Set.
String timerWhat(HubTimer t, DeviceController<Object?, Object?> c, {int channels = 1}) {
  final o = t.output;
  if (o == null) return 'ustawi ${t.set.entries.map((e) => '${e.key}: ${e.value}').join(', ')}';
  final verb = o.on ? 'włączy się' : 'wyłączy się';
  return o.point == 'on' || channels < 2 ? verb : '${channelName(c, null, o.point)} $verb';
}

/// „za 25 min” albo „po odliczeniu”, gdy hub nie zna jeszcze czasu.
String _left(HubTimer t, DateTime now) {
  final s = t.leftAt(now);
  return s == null ? 'po odliczeniu' : 'za ${fmtLeftShort(s)}';
}

/// Krótki dopisek na kafelek: „wył. za 25 min” / „wł. za 1 h”.
String timerShort(HubTimer t, DateTime now) => '${t.output?.on == true ? 'wł.' : 'wył.'} ${_left(t, now)}';

/// Okno „Wyłącz za…” i zapis w hubie; [point] - wyjście ustalone (kafelek, [name] - jego nazwa), inaczej wybór kanału.
Future<void> setOutputTimer(
  BuildContext context, {
  required DeviceController<Object?, Object?> controller,
  required HubTimers timers,
  int channels = 1,
  String? point,
  String? name,
}) async {
  final state = controller.stateJson;
  final start = point ?? 'on';
  final r = await showModalBottomSheet<_TimerChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TimerSheet(
      controller: controller,
      channels: point == null ? channels : 1,
      point: start,
      // Domyślnie przeciwnie do stanu: włączone - „wyłącz za…”.
      on: state?[start] is bool ? !(state![start] as bool) : false,
      title: point == null ? null : name ?? _who(controller, point),
      stateOf: (p) => state?[p],
    ),
  );
  if (r == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final at = await timers.add(controller.device.id, {r.point: r.on}, r.after);
    final who = point != null && name != null ? name : _who(controller, r.point);
    messenger.showSnackBar(SnackBar(content: Text('$who ${r.on ? 'włączy' : 'wyłączy'} się o ${_hhmm(at)}.')));
  } on ThermostatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Całe urządzenie - jego nazwa, kanał - nazwa kanału.
String _who(DeviceController<Object?, Object?> c, String point) =>
    point == 'on' ? c.device.name : channelName(c, null, point);

typedef _TimerChoice = ({String point, bool on, Duration after});

class _TimerSheet extends StatefulWidget {
  const _TimerSheet({
    required this.controller,
    required this.channels,
    required this.point,
    required this.on,
    required this.stateOf,
    this.title,
  });

  final DeviceController<Object?, Object?> controller;
  final int channels;
  final String point;
  final bool on;
  final Object? Function(String point) stateOf;
  final String? title;

  @override
  State<_TimerSheet> createState() => _TimerSheetState();
}

class _TimerSheetState extends State<_TimerSheet> {
  late String _point = widget.point;
  late bool _on = widget.on;
  int _minutes = 30;

  void _pick(String p) => setState(() {
    _point = p;
    final v = widget.stateOf(p);
    if (v is bool) _on = !v;
  });

  Future<void> _custom() async {
    final ctl = TextEditingController(text: '$_minutes');
    final m = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Za ile minut?'),
        content: TextField(
          key: const Key('timerCustomMinutes'),
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'min', helperText: 'Od 1 minuty do 7 dni'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(
            key: const Key('timerCustomOk'),
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (m != null && m >= 1 && m <= 7 * 24 * 60) setState(() => _minutes = m);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final custom = !timerPresets.contains(_minutes);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title == null ? 'Odliczanie' : 'Odliczanie · ${widget.title}', style: t.titleMedium),
            const SizedBox(height: 12),
            if (widget.channels > 1) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in ['on', for (var i = 1; i <= widget.channels; i++) 'on$i'])
                    ChoiceChip(
                      key: Key('timerChannel-$p'),
                      label: Text(p == 'on' ? 'Wszystkie' : channelName(widget.controller, null, p)),
                      selected: _point == p,
                      onSelected: (_) => _pick(p),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Wyłącz za…'), icon: Icon(Icons.toggle_off_outlined)),
                ButtonSegment(value: true, label: Text('Włącz za…'), icon: Icon(Icons.toggle_on_outlined)),
              ],
              selected: {_on},
              onSelectionChanged: (v) => setState(() => _on = v.single),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final m in timerPresets)
                  ChoiceChip(
                    key: Key('timerIn-$m'),
                    label: Text(_fmtMinutes(m)),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
                ChoiceChip(
                  key: const Key('timerInCustom'),
                  label: Text(custom ? _fmtMinutes(_minutes) : 'Inny…'),
                  selected: custom,
                  onSelected: (_) => _custom(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('timerStart'),
              icon: const Icon(Icons.timer_outlined),
              label: Text('${_on ? 'Włącz' : 'Wyłącz'} za ${_fmtMinutes(_minutes)}'),
              onPressed: () => Navigator.pop(context, (point: _point, on: _on, after: Duration(minutes: _minutes))),
            ),
            const SizedBox(height: 4),
            Text(
              'Odlicza hub - zadziała także przy wyłączonym telefonie i bez internetu.',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sekcja „Odliczanie” na ekranie wyjścia: aktywne timery urządzenia i „Wyłącz za…”. Bez huba z timerami - nic.
class OutputTimerSection extends StatefulWidget {
  const OutputTimerSection({super.key, required this.controller, this.hub, this.timers, this.channels = 1});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub? hub;

  /// Do testów: hub z timerami zamiast wybranego z [hub].
  final HubTimers? timers;
  final int channels;

  @override
  State<OutputTimerSection> createState() => _OutputTimerSectionState();
}

class _OutputTimerSectionState extends State<OutputTimerSection> {
  /// Odświeżanie „za ile” (co 15 s wystarczy przy minutach).
  Timer? _tick;

  DeviceController<Object?, Object?> get c => widget.controller;

  HubTimers? get _timers => widget.timers ?? widget.hub?.timersFor(c.device.id);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cancel(HubTimers timers, HubTimer t) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await timers.cancel(t.id);
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.hub ?? widget.timers?.hub;
    if (listenable == null) return const SizedBox.shrink();
    return ListenableBuilder(listenable: listenable, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final timers = _timers;
    if (timers == null || !timers.supported || !c.canControl) return const SizedBox.shrink();
    final list = timers.forDevice(c.device.id);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Odliczanie'),
        for (final t in list)
          ListTile(
            key: Key('timer-${t.id}'),
            leading: const Icon(Icons.timer_outlined),
            title: Text('${_capital(timerWhat(t, c, channels: widget.channels))} ${_left(t, now)}'),
            subtitle: Text(t.at == null ? 'hub nie zna jeszcze godziny' : 'o ${_hhmm(t.at!)}'),
            trailing: TextButton(
              key: Key('timerCancel-${t.id}'),
              onPressed: () => _cancel(timers, t),
              child: const Text('Anuluj'),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('timerAdd'),
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Wyłącz / włącz za…'),
            onPressed: () => setOutputTimer(context, controller: c, timers: timers, channels: widget.channels),
          ),
        ),
      ],
    );
  }

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
