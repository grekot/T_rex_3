import 'package:flutter/material.dart';

import '../controllers/thermostat_controller.dart';
import '../models/schedule.dart';
import '../models/set_values.dart';
import '../models/thermostat_config.dart';
import 'format.dart';
import 'widgets.dart';

/// Plan w harmonogramie: klucz w JSON-ie i nazwa w UI.
enum ScheduleDay {
  weekday('weekday', 'Pn–Pt'),
  saturday('saturday', 'Sobota'),
  sunday('sunday', 'Niedziela');

  const ScheduleDay(this.key, this.label);

  final String key;
  final String label;

  String errorKey() => 'schedule.$key';

  String of(ScheduleConfig s) => switch (this) {
    ScheduleDay.weekday => s.weekday,
    ScheduleDay.saturday => s.saturday,
    ScheduleDay.sunday => s.sunday,
  };
}

/// Harmonogram AUTO: 3 plany po maks. 4 okresy komfortu + temperatury komfort/eko.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.controller});

  final ThermostatController controller;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  ThermostatController get c => widget.controller;

  late ThermostatConfig _base;
  late double _comfort;
  late double _eco;
  late Map<ScheduleDay, List<TimePeriod>> _plans;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reset(c.config!);
    c.addListener(_onController);
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    super.dispose();
  }

  /// Nowa konfiguracja z termostatu (np. zmiana z innego telefonu albo częściowo udany zapis):
  /// bez lokalnych zmian przyjmujemy ją w całości, a przy zmianach tylko jako punkt odniesienia.
  void _onController() {
    final cfg = c.config;
    if (cfg == null || cfg == _base) return;
    setState(() {
      if (_dirty) {
        _base = cfg;
      } else {
        _reset(cfg);
      }
    });
  }

  void _reset(ThermostatConfig cfg) {
    _base = cfg;
    _comfort = cfg.comfort;
    _eco = cfg.eco;
    _plans = {
      for (final d in ScheduleDay.values) d: List.of(DayPlan.tryParse(d.of(cfg.schedule))?.periods ?? const []),
    };
  }

  String _planText(ScheduleDay d) => DayPlan(_plans[d]!).format();

  String? _basePlanText(ScheduleDay d) => DayPlan.tryParse(d.of(_base.schedule))?.format();

  bool get _dirty =>
      _comfort != _base.comfort || _eco != _base.eco || ScheduleDay.values.any((d) => _planText(d) != _basePlanText(d));

  String? _localError(ScheduleDay d) => DayPlan(_plans[d]!).validate();

  bool get _valid => ScheduleDay.values.every((d) => _localError(d) == null);

  Future<void> _save() async {
    String? changed(ScheduleDay d) {
      final text = _planText(d);
      return text == _basePlanText(d) ? null : text;
    }

    final values = SetValues(
      comfort: _comfort != _base.comfort ? _comfort : null,
      eco: _eco != _base.eco ? _eco : null,
      schedule: SchedulePatch(
        weekday: changed(ScheduleDay.weekday),
        saturday: changed(ScheduleDay.saturday),
        sunday: changed(ScheduleDay.sunday),
      ),
    );
    setState(() => _saving = true);
    final r = await c.send(values);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _errors = r.errors;
      // Zastosowane pola przychodzą w nowej konfiguracji; błędne zostają w edycji.
      if (r.errors.isEmpty && c.config != null) _reset(c.config!);
    });
    showSaveResult(context, r.errors, describeErrors);
  }

  Future<void> _editPeriod(ScheduleDay d, int i) async {
    final p = _plans[d]![i];
    final start = await pickDayTime(context, p.start, help: 'Początek komfortu');
    if (start == null || !mounted) return;
    final end = await pickDayTime(context, p.end, isEnd: true, help: 'Koniec komfortu (00:00 = 24:00)');
    if (end == null) return;
    setState(() {
      _plans[d]![i] = TimePeriod(start, end);
      _plans[d]!.sort((a, b) => a.start.compareTo(b.start));
    });
  }

  void _addPeriod(ScheduleDay d) {
    final list = _plans[d]!;
    final lastEnd = list.isEmpty ? 6 * 60 : list.last.end.minutes;
    final start = lastEnd >= 23 * 60 ? 23 * 60 - 60 : lastEnd + 60;
    setState(() => list.add(TimePeriod(DayTime(start), DayTime((start + 120).clamp(0, 1440)))));
  }

  void _copyFrom(ScheduleDay target, ScheduleDay source) {
    setState(() => _plans[target] = List.of(_plans[source]!));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: ScheduleDay.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Harmonogram'),
          actions: [
            TextButton(
              key: const Key('saveSchedule'),
              onPressed: _dirty && _valid && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Zapisz'),
            ),
          ],
          bottom: TabBar(
            tabs: [
              for (final d in ScheduleDay.values)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.label),
                      if (_localError(d) != null || _errors.containsKey(d.errorKey()))
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.error, size: 16, color: Theme.of(context).colorScheme.error),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: Column(
          children: [
            StepperTile(
              label: 'Komfort',
              subtitle: 'W okresach z planu',
              value: _comfort,
              min: 15,
              max: 30,
              step: 0.5,
              format: (v) => fmtTemp(v),
              errorText: _errors['comfort'] == null ? null : describeErrorCode(_errors['comfort']!),
              onChanged: (v) => setState(() => _comfort = v),
            ),
            StepperTile(
              label: 'Eko',
              subtitle: 'Poza okresami komfortu',
              value: _eco,
              min: 10,
              max: 25,
              step: 0.5,
              format: (v) => fmtTemp(v),
              errorText: _errors['eco'] == null ? null : describeErrorCode(_errors['eco']!),
              onChanged: (v) => setState(() => _eco = v),
            ),
            const Divider(height: 1),
            Expanded(child: TabBarView(children: [for (final d in ScheduleDay.values) _dayView(context, d)])),
          ],
        ),
      ),
    );
  }

  Widget _dayView(BuildContext context, ScheduleDay d) {
    final periods = _plans[d]!;
    final cs = Theme.of(context).colorScheme;
    final error =
        _localError(d) ??
        (_errors[d.errorKey()] == null ? null : 'Termostat: ${describeErrorCode(_errors[d.errorKey()]!)}');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DayTimeline(periods: periods),
        const SizedBox(height: 16),
        if (periods.isEmpty)
          const ListTile(
            leading: Icon(Icons.eco_outlined),
            title: Text('Cały dzień eko'),
            subtitle: Text('Brak okresów komfortu'),
          ),
        for (var i = 0; i < periods.length; i++)
          Card(
            child: ListTile(
              leading: Icon(Icons.wb_sunny_outlined, color: cs.primary),
              title: Text('${periods[i].start.format()} – ${periods[i].end.format()}'),
              subtitle: Text('Komfort ${fmtTemp(_comfort)}'),
              onTap: () => _editPeriod(d, i),
              trailing: IconButton(
                tooltip: 'Usuń okres',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => periods.removeAt(i)),
              ),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(error, style: TextStyle(color: cs.error)),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: periods.length < maxComfortPeriods ? () => _addPeriod(d) : null,
              icon: const Icon(Icons.add),
              label: Text(
                periods.length < maxComfortPeriods ? 'Dodaj okres komfortu' : 'Najwyżej $maxComfortPeriods okresy',
              ),
            ),
            for (final other in ScheduleDay.values)
              if (other != d)
                TextButton.icon(
                  onPressed: () => _copyFrom(d, other),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text('Jak ${other.label}'),
                ),
          ],
        ),
      ],
    );
  }
}
