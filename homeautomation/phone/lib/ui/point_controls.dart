import 'package:flutter/material.dart';

import '../models/describe.dart';

/// Wiersz punktu danych z `describe` (pkt 14) z kontrolką wg `kind`.
class PointTile extends StatelessWidget {
  const PointTile({super.key, required this.point, required this.value, required this.enabled, required this.onSet});

  final DataPoint point;
  final Object? value;

  /// Poziom dostępu wystarcza do ustawienia.
  final bool enabled;
  final ValueChanged<Object?> onSet;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final t = Theme.of(context).textTheme;
    final key = Key('point-${p.key}');
    switch (p.kind) {
      case PointKind.switchKind:
        return SwitchListTile(
          key: key,
          title: Text(p.name),
          value: value == true,
          onChanged: enabled ? (v) => onSet(v) : null,
        );
      case PointKind.setpoint:
        final v = value is num ? (value as num).toDouble() : null;
        return ListTile(
          key: key,
          title: Text(p.name),
          subtitle: v == null || p.min == null || p.max == null
              ? null
              : SetpointSlider(point: p, value: v, enabled: enabled, onChanged: onSet),
          trailing: Text(p.format(value), style: t.titleMedium),
        );
      case PointKind.select:
        return ListTile(
          key: key,
          title: Text(p.name),
          trailing: DropdownButton<String>(
            value: p.options.contains(value) ? value as String : null,
            items: [for (final o in p.options) DropdownMenuItem(value: o, child: Text(optionLabel(o)))],
            onChanged: enabled ? (o) => onSet(o) : null,
          ),
        );
      case PointKind.action:
        return ListTile(
          key: key,
          title: Text(p.name),
          trailing: FilledButton.tonal(onPressed: enabled ? () => onSet(true) : null, child: const Text('Wykonaj')),
        );
      case PointKind.status:
        return ListTile(
          key: key,
          title: Text(p.name),
          trailing: Icon(
            value == true ? Icons.check_circle : Icons.radio_button_unchecked,
            color: value == true ? Theme.of(context).colorScheme.primary : null,
          ),
        );
      case PointKind.sensor:
        return ListTile(key: key, title: Text(p.name), trailing: Text(p.format(value), style: t.titleMedium));
    }
  }
}

/// Suwak nastawy: pokazuje wartość od razu, wysyła po puszczeniu.
class SetpointSlider extends StatefulWidget {
  const SetpointSlider({super.key, required this.point, required this.value, required this.enabled, required this.onChanged});

  final DataPoint point;
  final double value;
  final bool enabled;
  final ValueChanged<Object?> onChanged;

  @override
  State<SetpointSlider> createState() => _SetpointSliderState();
}

class _SetpointSliderState extends State<SetpointSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    final min = p.min!, max = p.max!;
    final step = p.step ?? 1;
    final divisions = ((max - min) / step).round();
    final v = (_drag ?? widget.value).clamp(min, max);
    return Slider(
      value: v,
      min: min,
      max: max,
      divisions: divisions > 0 && divisions <= 1000 ? divisions : null,
      label: p.format(v),
      onChanged: widget.enabled ? (x) => setState(() => _drag = x) : null,
      onChangeEnd: widget.enabled
          ? (x) {
              setState(() => _drag = null);
              final snapped = (x / step).round() * step;
              widget.onChanged(step % 1 == 0 ? snapped.round() : snapped);
            }
          : null,
    );
  }
}

/// Wartości `select` po polsku (znane z kontraktu).
String optionLabel(String o) => switch (o) {
  'manual' => 'Ręczny',
  'auto' => 'AUTO',
  'last' => 'Jak przed zanikiem',
  'on' => 'Włączone',
  'off' => 'Wyłączone',
  _ => o,
};
