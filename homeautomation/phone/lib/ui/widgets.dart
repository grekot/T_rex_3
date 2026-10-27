import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../data/thermostat_connection.dart';

import '../models/schedule.dart';

/// Wiersz z wartością liczbową i przyciskami −/+.
class StepperTile extends StatelessWidget {
  const StepperTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onChanged,
    this.subtitle,
    this.errorText,
  });

  final String label;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final double step;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final String? errorText;

  double _snap(double v) => ((v / step).round() * step).clamp(min, max);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      title: Text(label),
      subtitle: errorText != null
          ? Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          : subtitle == null
          ? null
          : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(_snap(value - step)) : null,
          ),
          SizedBox(
            width: 72,
            child: Text(format(value), textAlign: TextAlign.center, style: t.titleMedium),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(_snap(value + step)) : null,
          ),
        ],
      ),
    );
  }
}

/// Wybór godziny w zegarze 24 h. Dla końca okresu `00:00` oznacza `24:00`.
Future<DayTime?> pickDayTime(BuildContext context, DayTime initial, {bool isEnd = false, String? help}) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour % 24, minute: initial.minute),
    helpText: help,
    initialEntryMode: TimePickerEntryMode.input,
  );
  if (picked == null) return null;
  final m = picked.hour * 60 + picked.minute;
  return DayTime(isEnd && m == 0 ? 1440 : m);
}

/// Pasek doby 0-24 h z zaznaczonymi okresami komfortu.
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.periods, this.height = 20});

  final List<TimePeriod> periods;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme.labelSmall;
    return Column(
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: _TimelinePainter(periods, comfort: cs.primary, eco: cs.surfaceContainerHighest),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final h in const [0, 6, 12, 18, 24]) Text('$h', style: t),
          ],
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.periods, {required this.comfort, required this.eco});

  final List<TimePeriod> periods;
  final Color comfort;
  final Color eco;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas
      ..save()
      ..clipRRect(r)
      ..drawRect(Offset.zero & size, Paint()..color = eco);
    final p = Paint()..color = comfort;
    for (final period in periods) {
      if (period.end <= period.start) continue;
      final x0 = size.width * period.start.minutes / 1440;
      final x1 = size.width * period.end.minutes / 1440;
      canvas.drawRect(Rect.fromLTRB(x0, 0, x1, size.height), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.periods != periods || old.comfort != comfort || old.eco != eco;
}

/// Nagłówek sekcji na liście ustawień.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// Pokazuje wynik zapisu: błędy pól albo „Zapisano”.
void showSaveResult(BuildContext context, Map<String, String> errors, String Function(Map<String, String>) describe) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(content: Text(errors.isEmpty ? 'Zapisano w termostacie.' : 'Nie wszystko zapisano:\n${describe(errors)}')),
  );
}

/// Łączenie z urządzeniem: wskaźnik i bieżący krok.
class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key, this.step});

  final String? step;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(step ?? 'Łączenie…')],
    ),
  );
}

/// Nie udało się połączyć: komunikat i „Ponów” albo „Sparuj ponownie”.
class FailedView extends StatelessWidget {
  const FailedView({
    super.key,
    required this.message,
    required this.needsPairing,
    required this.onRetry,
    required this.onPair,
  });

  final String message;
  final bool needsPairing;
  final VoidCallback onRetry;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(needsPairing ? Icons.key_off : Icons.wifi_off, size: 56, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (needsPairing)
            FilledButton.icon(onPressed: onPair, icon: const Icon(Icons.link), label: const Text('Sparuj ponownie'))
          else
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Ponów')),
        ],
      ),
    ),
  );
}

/// Którędy idą dane (Lokalnie · 192.168.1.20 / Chmura · Firebase) i stan łącza.
class RouteChip extends StatelessWidget {
  const RouteChip({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  Widget build(BuildContext context) {
    final conn = controller.connection!;
    final cs = Theme.of(context).colorScheme;
    final (statusText, color) = switch (conn.status) {
      LinkStatus.online => ('na żywo', cs.primary),
      LinkStatus.connecting || LinkStatus.reconnecting => ('łączenie ponownie…', cs.tertiary),
      LinkStatus.offline => ('urządzenie offline', cs.error),
      LinkStatus.unauthorized => ('brak dostępu', cs.error),
      LinkStatus.closed => ('rozłączono', cs.error),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Chip(
          avatar: Icon(conn.kind == ConnectionKind.local ? Icons.wifi : Icons.cloud, size: 18, color: color),
          label: Text('${conn.kind.label} · ${conn.routeDescription} · $statusText'),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// Okno z jednym polem tekstowym; zwraca przycięty tekst albo null (Anuluj / pusty).
/// Kontroler żyje w stanie okna - zwalniany dopiero po animacji zamknięcia.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  int? maxLength,
  Key? fieldKey,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _TextInputDialog(title: title, initial: initial, hint: hint, maxLength: maxLength, fieldKey: fieldKey),
).then((v) => v == null || v.trim().isEmpty ? null : v.trim());

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({required this.title, required this.initial, this.hint, this.maxLength, this.fieldKey});

  final String title;
  final String initial;
  final String? hint;
  final int? maxLength;
  final Key? fieldKey;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: widget.fieldKey,
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('OK')),
    ],
  );
}

/// Kafelki po dwa w rzędzie (trzy na szerokim ekranie), wysokość wg treści.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth > 700 ? 3 : 2;
      final width = (box.maxWidth - (columns - 1) * 4) / columns;
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );
}
