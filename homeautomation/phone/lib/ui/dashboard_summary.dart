import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../models/device_type.dart';
import '../models/json_utils.dart';
import '../models/light.dart';
import 'dashboard_tiles.dart' show tileHeatColor;
import 'device_tiles.dart' show openDevice;

/// Świecące wyjścia urządzenia (kanały węzła wielokanałowego albo `on`).
int _lightsOn(Json? s) {
  if (s == null) return 0;
  final n = s['channels'];
  if (n is int && n > 1) return [for (var i = 1; i <= n; i++) s['on$i'] == true].where((x) => x).length;
  return s['on'] == true ? 1 : 0;
}

/// Problemy urządzenia do pigułki „alarmy”: awaria czujnika, usterka wejścia, przegrzanie, zalanie, brak kontaktu.
List<String> deviceProblems(DeviceController<Object?, Object?> c) {
  final s = c.stateJson;
  if (s == null) return const [];
  final cfg = c.config;
  return [
    if (s['sensorFault'] == true) 'awaria czujnika',
    if (s['overheatOff'] == true) 'przegrzanie - kanały wyłączone' else if (s['overheat'] == true) 'wysoka temperatura',
    if (cfg is LightConfig)
      for (final (i, x) in cfg.inputs.indexed)
        if (x.kind == InputKind.leak && s['in${i + 1}'] == true) 'zalanie: ${x.name}',
    for (final e in s.entries)
      if (RegExp(r'^in(\d+)Fault$').firstMatch(e.key) case final m? when e.value == true)
        'usterka wejścia ${m.group(1)}',
    if (!c.live) 'brak kontaktu',
  ];
}

/// Podsumowanie domu nad pulpitem (pkt 13.1, plan pulpitów): pigułki „N świateł”, grzanie, alarmy.
/// Dotyk: lista urządzeń w tym stanie (światła - z „Wyłącz wszystkie”).
class DashSummary extends StatelessWidget {
  const DashSummary({super.key, required this.hub});

  final DeviceHub hub;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final controllers = [
          for (final d in hub.devices)
            if (hub.accessFor(d.id).canView) ?hub.controller(d.id),
        ];
        final lights = [
          for (final c in controllers)
            if (c.device.type.isLight && _lightsOn(c.stateJson) > 0) c,
        ];
        final lightCount = lights.fold(0, (n, c) => n + _lightsOn(c.stateJson));
        final thermos = [
          for (final c in controllers)
            if (c.device.type == DeviceType.thermostat && c.stateJson != null) c,
        ];
        final heating = thermos.where((c) => c.stateJson!['heating'] == true).toList();
        final problems = [
          for (final c in controllers)
            if (deviceProblems(c) case final p when p.isNotEmpty) (c, p),
        ];
        if (lightCount == 0 && thermos.isEmpty && problems.isEmpty) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final temp = thermos.isEmpty ? null : thermos.first.stateJson!['temp'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (lightCount > 0)
                _chip(
                  context,
                  key: 'summaryLights',
                  dot: cs.primary,
                  text: '$lightCount ${lightCount == 1 ? 'światło' : (lightCount < 5 ? 'światła' : 'świateł')}',
                  onTap: () => _lightsSheet(context, lights),
                ),
              if (thermos.isNotEmpty)
                _chip(
                  context,
                  key: 'summaryHeat',
                  dot: heating.isNotEmpty ? tileHeatColor : cs.outline,
                  text: [
                    heating.isNotEmpty ? 'Grzeje' : 'Nie grzeje',
                    if (temp is num) '${temp.toStringAsFixed(1).replaceAll('.', ',')}°',
                  ].join(' · '),
                  onTap: () => _listSheet(context, 'Ogrzewanie', [
                    for (final c in thermos)
                      (
                        c,
                        '${c.stateJson!['heating'] == true ? 'grzeje' : 'nie grzeje'} · ${c.stateJson!['temp'] ?? '—'} °C',
                      ),
                  ]),
                ),
              if (problems.isNotEmpty)
                _chip(
                  context,
                  key: 'summaryAlarms',
                  dot: cs.error,
                  text:
                      '${problems.length} ${problems.length == 1 ? 'alarm' : (problems.length < 5 ? 'alarmy' : 'alarmów')}',
                  onTap: () => _listSheet(context, 'Alarmy', [for (final (c, p) in problems) (c, p.join(', '))]),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(
    BuildContext context, {
    required String key,
    required Color dot,
    required String text,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: Key(key),
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(text, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }

  void _listSheet(BuildContext context, String title, List<(DeviceController<Object?, Object?>, String)> rows) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
            for (final (c, text) in rows)
              ListTile(
                title: Text(c.device.name),
                subtitle: Text(text),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  openDevice(context, c, hub: hub);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _lightsSheet(BuildContext context, List<DeviceController<Object?, Object?>> lights) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('Włączone światła', style: Theme.of(ctx).textTheme.titleMedium)),
            for (final c in lights)
              ListTile(
                title: Text(c.device.name),
                subtitle: Text('${_lightsOn(c.stateJson)} wł.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  openDevice(context, c, hub: hub);
                },
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const Key('summaryAllOff'),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Wyłącz wszystkie'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final errors = <String>[];
                  for (final c in lights.where((c) => c.canControl)) {
                    final r = await c.sendJson({'on': false});
                    if (r.errors.isNotEmpty) errors.add('${c.device.name}: ${describeErrors(r.errors)}');
                  }
                  if (errors.isNotEmpty && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
