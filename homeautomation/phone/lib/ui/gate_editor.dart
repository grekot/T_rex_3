// Kafelek `gate` (brama, furtka): kanał do sterowania i opcjonalny czujnik stanu (np. kontaktron na wejściu).

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/home.dart';
import 'widget_editor.dart' show pointsOf;
import 'widgets.dart';

/// Punkt urządzenia do wyboru: urządzenie, klucz i opis na liście.
typedef GatePoint = ({String device, String point, String name});

/// Wyjścia, którymi można sterować bramą: kanały impulsowe (`action`) i zwykłe (`on` / `onN`) z poziomem `control`.
Future<List<GatePoint>> gateOutputs(DeviceHub hub) => _points(
  hub,
  (p, level) =>
      RegExp(r'^on\d*$').hasMatch(p.key) &&
      (p.kind == PointKind.action || p.kind == PointKind.switchKind) &&
      level.atLeast(p.access),
);

/// Czujniki stanu bramy: punkty dwustanowe (`status`, np. wejście `inN` z kontaktronem).
Future<List<GatePoint>> gateSensors(DeviceHub hub) => _points(hub, (p, _) => p.kind == PointKind.status);

Future<List<GatePoint>> _points(DeviceHub hub, bool Function(DataPoint, AccessLevel) keep) async {
  final out = <GatePoint>[];
  for (final d in hub.devices) {
    final level = hub.accessFor(d.id);
    if (!level.canView) continue;
    for (final p in await pointsOf(hub, d)) {
      if (keep(p, level)) out.add((device: d.id, point: p.key, name: '${d.name} · ${p.name}'));
    }
  }
  return out;
}

/// Wybór czujnika stanu bramy; `(null)` w rekordzie = bez czujnika, null = anulowano.
Future<({GatePoint? sensor})?> pickGateSensor(BuildContext context, DeviceHub hub) async {
  final sensors = await gateSensors(hub);
  if (!context.mounted) return null;
  return showDialog<({GatePoint? sensor})>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Czujnik stanu'),
      children: [
        SimpleDialogOption(
          key: const Key('gateSensor-none'),
          onPressed: () => Navigator.pop(ctx, (sensor: null)),
          child: const Text('Bez czujnika (sam przycisk)'),
        ),
        for (final s in sensors)
          SimpleDialogOption(
            key: Key('gateSensor-${s.device}-${s.point}'),
            onPressed: () => Navigator.pop(ctx, (sensor: s)),
            child: Text(s.name),
          ),
      ],
    ),
  );
}

/// Nowy kafelek bramy: nazwa, wyjście, czujnik i potwierdzenie → `gate` 2×2.
class GateEditorScreen extends StatefulWidget {
  const GateEditorScreen({super.key, required this.hub});

  final DeviceHub hub;

  @override
  State<GateEditorScreen> createState() => _GateEditorScreenState();
}

class _GateEditorScreenState extends State<GateEditorScreen> {
  late final Future<List<GatePoint>> _outputs = gateOutputs(widget.hub);
  final _name = TextEditingController(text: 'Brama');
  GatePoint? _output;
  GatePoint? _sensor;
  bool _confirm = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickSensor() async {
    final r = await pickGateSensor(context, widget.hub);
    if (r != null) setState(() => _sensor = r.sensor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brama / furtka'),
        actions: [
          TextButton(
            key: const Key('gateDone'),
            onPressed: _output == null
                ? null
                : () => Navigator.pop(
                    context,
                    DashWidget(
                      id: newLocalId('w'),
                      view: WidgetView.gate,
                      device: _output!.device,
                      point: _output!.point,
                      label: _name.text.trim().isEmpty ? null : _name.text.trim(),
                    ).resized(2, 2).patch({
                      'sensor': ?(_sensor == null ? null : {'device': _sensor!.device, 'point': _sensor!.point}),
                      'confirm': ?(_confirm ? null : false),
                    }),
                  ),
            child: const Text('Dodaj'),
          ),
        ],
      ),
      body: FutureBuilder<List<GatePoint>>(
        future: _outputs,
        builder: (context, snap) {
          final outputs = snap.data;
          if (outputs == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  key: const Key('gateName'),
                  controller: _name,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'np. Brama wjazdowa'),
                ),
              ),
              const SectionHeader('Czym sterować'),
              if (outputs.isEmpty) const ListTile(title: Text('Brak wyjść, którymi możesz sterować.')),
              RadioGroup<GatePoint>(
                groupValue: _output,
                onChanged: (v) => setState(() => _output = v),
                child: Column(
                  children: [
                    for (final o in outputs)
                      RadioListTile<GatePoint>(
                        key: Key('gateOutput-${o.device}-${o.point}'),
                        value: o,
                        title: Text(o.name),
                      ),
                  ],
                ),
              ),
              const SectionHeader('Stan bramy'),
              ListTile(
                key: const Key('gateSensor'),
                leading: const Icon(Icons.sensor_door_outlined),
                title: Text(_sensor?.name ?? 'Bez czujnika'),
                subtitle: const Text('Np. kontaktron na wejściu modułu: aktywne = otwarta'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _pickSensor,
              ),
              SwitchListTile(
                key: const Key('gateConfirmSwitch'),
                title: const Text('Pytaj przed wykonaniem'),
                value: _confirm,
                onChanged: (v) => setState(() => _confirm = v),
              ),
            ],
          );
        },
      ),
    );
  }
}
