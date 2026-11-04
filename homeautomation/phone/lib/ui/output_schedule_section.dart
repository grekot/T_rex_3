// Sekcja „Harmonogram” na ekranie wyjścia (światło, przełącznik, kanały switch4): stałe godziny włączenia
// i wyłączenia w wybrane dni. Wpisy to automatyki huba (`OutputSchedule`) - działają bez telefonu i internetu.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/automation_store.dart';
import '../data/errors.dart';
import '../models/hub.dart';
import '../models/output_schedule.dart';
import '../services.dart';
import 'dashboard_tiles.dart' show channelName;
import 'widgets.dart';

class OutputScheduleSection extends StatefulWidget {
  const OutputScheduleSection({super.key, required this.controller, this.hub, this.automations, this.channels = 1});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub? hub;

  /// Do testów: automatyki huba zamiast tych z połączonego huba w [hub].
  final HubAutomations? automations;

  /// Kanały wyjścia (switch4: 4) - wpis na cały moduł (`on`) albo kanał (`onN`).
  final int channels;

  @override
  State<OutputScheduleSection> createState() => _OutputScheduleSectionState();
}

class _OutputScheduleSectionState extends State<OutputScheduleSection> {
  HubAutomations? _store;
  Future<List<OutputSchedule>>? _list;

  DeviceController<Object?, Object?> get c => widget.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store != null || _list != null) return;
    _store = widget.automations ?? _hubStore();
    _reload();
  }

  /// Automatyki huba, przez który urządzenie jest dostępne (albo pierwszego huba domu).
  HubAutomations? _hubStore() {
    final hubs = widget.hub?.hubs ?? const [];
    final h = hubs.where((x) => x.device.id == c.device.via).firstOrNull ?? hubs.firstOrNull;
    if (h == null) return null;
    final cloud = Services.of(context).cloud;
    return HubAutomations(hub: h, store: cloud.available ? cloud.store : null, homeId: cloud.homeId);
  }

  void _reload() {
    final s = _store;
    final list = s?.load().then((info) => schedulesFor(c.device.id, info.items));
    setState(() {
      _list = list;
    });
  }

  String _what(OutputSchedule s) {
    final action = s.on ? 'włącz' : 'wyłącz';
    if (s.point == 'on' || widget.channels < 2) return action;
    return '$action ${channelName(c, null, s.point)}';
  }

  Future<void> _edit([OutputSchedule? s]) async {
    final r = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ScheduleEditor(
        controller: c,
        channels: widget.channels,
        initial:
            s ??
            OutputSchedule(id: hubDocId('harmonogram'), device: c.device.id, point: 'on', on: true, minute: 7 * 60),
        isNew: s == null,
      ),
    );
    if (r == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (r.delete) {
        await _store!.remove(r.schedule.id);
      } else {
        final x = r.schedule;
        await _store!.save(x.toAutomation(name: 'Harmonogram: ${c.device.name} - ${_what(x)} ${x.time}'));
      }
      _reload();
    } on ThermostatException catch (e) {
      // Także odrzucona reguła (HubInvalidException) - komunikat z problemami huba.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggle(OutputSchedule s, bool on) async {
    try {
      await _store!.save(s.copyWith(enabled: on).toAutomation());
      _reload();
    } on ThermostatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Harmonogram'),
        if (store == null)
          const ListTile(
            key: Key('scheduleNoHub'),
            leading: Icon(Icons.schedule),
            title: Text('Harmonogram prowadzi hub'),
            subtitle: Text('Bez huba w domu nie ma stałych godzin - dodaj hub i przypisz do niego to urządzenie.'),
          )
        else
          FutureBuilder<List<OutputSchedule>>(
            future: _list,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                final e = snap.error;
                return ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Nie udało się wczytać harmonogramu'),
                  subtitle: Text(e is ThermostatException ? e.message : '$e'),
                  trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
                );
              }
              final list = snap.data ?? const [];
              return Column(
                children: [
                  if (list.isEmpty)
                    const ListTile(
                      key: Key('scheduleEmpty'),
                      leading: Icon(Icons.schedule),
                      title: Text('Brak stałych godzin'),
                      subtitle: Text('Np. „Pn–Pt 6:30 włącz, 7:15 wyłącz”. Wykonuje hub, także bez internetu.'),
                    ),
                  for (final s in list)
                    ListTile(
                      key: Key('schedule-${s.id}'),
                      leading: Icon(s.on ? Icons.toggle_on_outlined : Icons.toggle_off_outlined),
                      title: Text('${s.time} · ${_what(s)}'),
                      subtitle: Text(daysLabel(s.days)),
                      trailing: Switch(
                        key: Key('scheduleEnabled-${s.id}'),
                        value: s.enabled,
                        onChanged: c.canControl ? (v) => _toggle(s, v) : null,
                      ),
                      onTap: c.canControl ? () => _edit(s) : null,
                    ),
                  if (c.canControl)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('scheduleAdd'),
                        icon: const Icon(Icons.add_alarm),
                        label: const Text('Dodaj godzinę'),
                        onPressed: _edit,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

typedef _EditResult = ({OutputSchedule schedule, bool delete});

/// Edycja wpisu: kanał (gdy kilka), włącz / wyłącz, godzina, dni.
class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({required this.controller, required this.channels, required this.initial, required this.isNew});

  final DeviceController<Object?, Object?> controller;
  final int channels;
  final OutputSchedule initial;
  final bool isNew;

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late OutputSchedule _s = widget.initial;

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _s.minute ~/ 60, minute: _s.minute % 60),
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => _s = _s.copyWith(minute: t.hour * 60 + t.minute));
  }

  void _day(int d, bool on) {
    final days = {..._s.days};
    on ? days.add(d) : days.remove(d);
    if (days.isEmpty) return; // co najmniej jeden dzień
    setState(() => _s = _s.copyWith(days: [...days]..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.isNew ? 'Nowa godzina' : 'Zmień godzinę', style: t.titleMedium),
            const SizedBox(height: 12),
            if (widget.channels > 1) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in ['on', for (var i = 1; i <= widget.channels; i++) 'on$i'])
                    ChoiceChip(
                      key: Key('scheduleChannel-$p'),
                      label: Text(p == 'on' ? 'Wszystkie' : channelName(widget.controller, null, p)),
                      selected: _s.point == p,
                      onSelected: (_) => setState(() => _s = _s.copyWith(point: p)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Włącz'), icon: Icon(Icons.toggle_on_outlined)),
                ButtonSegment(value: false, label: Text('Wyłącz'), icon: Icon(Icons.toggle_off_outlined)),
              ],
              selected: {_s.on},
              onSelectionChanged: (v) => setState(() => _s = _s.copyWith(on: v.single)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('scheduleTime'),
              icon: const Icon(Icons.access_time),
              label: Text('Godzina ${_s.time}', style: t.titleMedium),
              onPressed: _pickTime,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    key: Key('scheduleDay-$d'),
                    label: Text(dayShort(d)),
                    selected: _s.days.contains(d),
                    onSelected: (on) => _day(d, on),
                  ),
              ],
            ),
            Wrap(
              spacing: 4,
              children: [
                for (final (label, days) in const [
                  ('Codziennie', [1, 2, 3, 4, 5, 6, 7]),
                  ('Pn–Pt', [1, 2, 3, 4, 5]),
                  ('Weekend', [6, 7]),
                ])
                  TextButton(
                    onPressed: () => setState(() => _s = _s.copyWith(days: days)),
                    child: Text(label),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!widget.isNew)
                  TextButton.icon(
                    key: const Key('scheduleDelete'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Usuń'),
                    onPressed: () => Navigator.pop(context, (schedule: _s, delete: true)),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('scheduleSave'),
                  onPressed: () => Navigator.pop(context, (schedule: _s, delete: false)),
                  child: const Text('Zapisz'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
