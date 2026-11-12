// Budziki zegara `clock` (Config `alarms`, pkt 10.2 „Menu i budzik”, fw 0.8.0): dwie karty z godziną, dniami, dźwiękiem
// (wbudowany albo stacja z Config `radio`), głośnością, narastaniem i drzemką. Każda zmiana od razu idzie Setem
// częściowym ({"alarms":[{…},null]}) - te same pola zmienia menu na zegarze.

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/field_errors.dart';
import '../models/clock.dart';
import '../models/json_utils.dart';
import 'widgets.dart';

class ClockAlarmsPage extends StatefulWidget {
  const ClockAlarmsPage({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<ClockAlarmsPage> createState() => _ClockAlarmsPageState();
}

class _ClockAlarmsPageState extends State<ClockAlarmsPage> {
  DeviceController<Object?, Object?> get c => widget.controller;

  Json get _cfg => c.config is Map ? (c.config! as Map).cast<String, dynamic>() : const {};

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

  /// Set częściowy jednego budzika: pozostały `null` (bez zmian).
  Future<void> _set(int i, Json changes) async {
    final r = await c.sendJson({
      'alarms': [for (var k = 0; k < 2; k++) k == i ? changes : null],
    });
    if (mounted) showSaveResult(context, r.errors, describeErrors);
  }

  List<String> get _stations {
    final r = _cfg['radio'];
    final st = r is Map ? r['stations'] : null;
    return st is List
        ? [
            for (final s in st)
              if (s is Map && s['name'] is String) s['name'] as String,
          ]
        : const [];
  }

  Future<void> _pickTime(int i, ClockAlarm a) async {
    final p = a.time.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 6, minute: int.tryParse(p.last) ?? 30),
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    await _set(i, {'time': hhmm, 'on': true}); // jak na zegarze: ustawienie godziny włącza budzik
  }

  Widget _card(int i, ClockAlarm a) {
    final t = Theme.of(context).textTheme;
    final stations = _stations;
    final missing = a.source == 'radio' && !stations.contains(a.station);
    final source = a.source == 'radio' ? a.station : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: Key('clockAlarmOn-$i'),
              contentPadding: EdgeInsets.zero,
              title: Text('Budzik ${i + 1}', style: t.titleMedium),
              subtitle: Text('${a.timeText} · ${clockAlarmDays(a.days)}'),
              value: a.on,
              onChanged: (v) => _set(i, {'on': v}),
            ),
            ListTile(
              key: Key('clockAlarmTime-$i'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm),
              title: const Text('Godzina'),
              trailing: Text(a.timeText, style: t.headlineSmall),
              onTap: () => _pickTime(i, a),
            ),
            Text('Dni', style: t.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    key: Key('clockAlarmDay-$i-$d'),
                    label: Text(clockWeekdays[d - 1]),
                    selected: a.days.contains(d),
                    onSelected: (on) {
                      final s = {...a.days};
                      on ? s.add(d) : s.remove(d);
                      _set(i, {'days': s.toList()..sort()});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final MapEntry(key: label, value: days) in clockAlarmDayPresets.entries)
                  ActionChip(
                    key: Key('clockAlarmPreset-$i-$label'),
                    label: Text(label),
                    onPressed: () => _set(i, {'days': days}),
                  ),
              ],
            ),
            if (a.days.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Bez dni: zadzwoni raz, przy najbliższej godzinie, potem się wyłączy.', style: t.bodySmall),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('Dźwięk'),
              subtitle: missing
                  ? Text(
                      'Stacji „${a.station}” nie ma już na liście - zegar zagra dźwięk wbudowany.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    )
                  : a.source == 'radio'
                  ? const Text('Stacja rusza 30 s wcześniej; gdy nie odpowie, gra dźwięk wbudowany')
                  : null,
              trailing: DropdownButton<String>(
                key: Key('clockAlarmSource-$i'),
                value: source,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Dźwięk wbudowany')),
                  for (final s in {...stations, if (missing) a.station})
                    DropdownMenuItem(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) =>
                    _set(i, v == null || v.isEmpty ? {'source': 'tone'} : {'source': 'radio', 'station': v}),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.volume_up_outlined),
                const SizedBox(width: 16),
                const Text('Głośność'),
                Expanded(
                  child: _VolSlider(
                    key: Key('clockAlarmVol-$i'),
                    value: a.vol,
                    onChangeEnd: (v) => _set(i, {'vol': v}),
                  ),
                ),
                SizedBox(width: 48, child: Text('${a.vol} %', textAlign: TextAlign.end)),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.trending_up),
              title: const Text('Narastanie'),
              subtitle: const Text('Od cichego do ustawionej głośności'),
              trailing: DropdownButton<int>(
                key: Key('clockAlarmRamp-$i'),
                value: a.rampS,
                items: [
                  for (final v in {...clockAlarmRamps.keys, a.rampS})
                    DropdownMenuItem(value: v, child: Text(clockAlarmRamps[v] ?? '$v s')),
                ],
                onChanged: (v) => _set(i, {'rampS': v}),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.snooze),
              title: const Text('Drzemka'),
              subtitle: const Text('Dowolny przycisk = drzemka, przytrzymany 2 s = wyłączenie (do 10 drzemek)'),
              trailing: DropdownButton<int>(
                key: Key('clockAlarmSnooze-$i'),
                value: a.snoozeMin,
                items: [
                  for (final v in {...clockAlarmSnoozes.keys, a.snoozeMin})
                    DropdownMenuItem(value: v, child: Text(clockAlarmSnoozes[v] ?? '$v min')),
                ],
                onChanged: (v) => _set(i, {'snoozeMin': v}),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alarms = clockAlarms(_cfg) ?? const [ClockAlarm(), ClockAlarm()];
    final s = c.stateJson ?? const <String, dynamic>{};
    final st = s['alarm'] is Map ? (s['alarm'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final next = st['next'];
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Budzik')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (st['noTime'] == true && alarms.any((a) => a.on))
            Card(
              color: cs.errorContainer,
              child: const ListTile(
                leading: Icon(Icons.schedule),
                title: Text('Zegar nie zna czasu'),
                subtitle: Text('Budzik nie zadzwoni, dopóki zegar nie pobierze czasu z sieci.'),
              ),
            )
          else
            ListTile(
              key: const Key('clockAlarmNextInfo'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm_on),
              title: Text(
                next is Map && next['at'] is num
                    ? 'Następny: ${clockWhen(next['at'] as num, DateTime.now())}'
                    : 'Żaden budzik nie jest włączony',
              ),
              subtitle: const Text(
                'Budzik działa także bez sieci i huba (czas z zegara). Zmiany widać też w menu zegara.',
              ),
            ),
          for (var i = 0; i < alarms.length; i++) _card(i, alarms[i]),
        ],
      ),
    );
  }
}

/// Suwak głośności: zapis dopiero po puszczeniu (bez Setu przy każdym kroku).
class _VolSlider extends StatefulWidget {
  const _VolSlider({super.key, required this.value, required this.onChangeEnd});

  final int value;
  final ValueChanged<int> onChangeEnd;

  @override
  State<_VolSlider> createState() => _VolSliderState();
}

class _VolSliderState extends State<_VolSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) => Slider(
    value: _drag ?? widget.value.clamp(5, 100).toDouble(),
    min: 5,
    max: 100,
    divisions: 19,
    label: '${(_drag ?? widget.value).round()} %',
    onChanged: (v) => setState(() => _drag = v),
    onChangeEnd: (v) {
      setState(() => _drag = null);
      widget.onChangeEnd(v.round());
    },
  );
}
