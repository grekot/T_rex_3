import 'package:flutter/material.dart';

import '../data/weights.dart';

/// Wynik okna pomiaru: dzień + waga (dziesiąte) albo usunięcie
class EntryResult {
  const EntryResult(this.day, this.w, {this.delete = false});

  final String day;
  final int w;
  final bool delete;
}

/// Dodanie albo poprawka pomiaru: data, −/+ 0,1 kg jak na zegarku, albo wpisanie liczby.
Future<EntryResult?> showEntryDialog(
  BuildContext context, {
  required DateTime day,
  required int initial,
  bool existing = false,
  bool allowDateChange = true,
}) {
  return showDialog<EntryResult>(
    context: context,
    builder: (_) => _EntryDialog(day: day, initial: initial, existing: existing, allowDateChange: allowDateChange),
  );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.day, required this.initial, required this.existing, required this.allowDateChange});

  final DateTime day;
  final int initial;
  final bool existing;
  final bool allowDateChange;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late DateTime _day = widget.day;
  late int _w = widget.initial;
  late final TextEditingController _text = TextEditingController(text: formatKg(widget.initial));
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _step(int d) {
    final w = (_w + d).clamp(minWeight, maxWeight);
    setState(() {
      _w = w;
      _error = null;
      _text.text = formatKg(w);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

  void _save() {
    final w = parseKg(_text.text);
    if (w == null) {
      setState(() => _error = 'Wpisz wagę, np. 82,3');
      return;
    }
    Navigator.pop(context, EntryResult(dayKey(_day), w));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.existing ? 'Popraw pomiar' : 'Nowy pomiar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: widget.allowDateChange ? _pickDate : null,
            icon: const Icon(Icons.event_outlined),
            label: Text('${shortDate(_day)}  ${_day.year}'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(onPressed: () => _step(-1), icon: const Icon(Icons.remove)),
              Expanded(
                child: TextField(
                  controller: _text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(suffixText: 'kg', errorText: _error, border: InputBorder.none),
                  onChanged: (t) {
                    final w = parseKg(t);
                    if (w != null) _w = w;
                  },
                  onSubmitted: (_) => _save(),
                ),
              ),
              IconButton.filledTonal(onPressed: () => _step(1), icon: const Icon(Icons.add)),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.existing)
          TextButton(
            onPressed: () => Navigator.pop(context, EntryResult(dayKey(_day), 0, delete: true)),
            child: Text('Usuń', style: TextStyle(color: theme.colorScheme.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ],
    );
  }
}

/// Cel wagi: null = bez zmian (anulowano), (null,) = usuń cel
Future<(int?,)?> showGoalDialog(BuildContext context, {int? current, required int suggestion}) {
  final text = TextEditingController(text: formatKg(current ?? suggestion));
  return showDialog<(int?,)>(
    context: context,
    builder: (context) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Cel wagi'),
          content: TextField(
            controller: text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: 'kg', errorText: error),
          ),
          actions: [
            if (current != null) TextButton(onPressed: () => Navigator.pop(context, (null,)), child: const Text('Bez celu')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
            FilledButton(
              onPressed: () {
                final w = parseKg(text.text);
                if (w == null) {
                  setState(() => error = 'Wpisz wagę, np. 78,0');
                } else {
                  Navigator.pop(context, (w,));
                }
              },
              child: const Text('Zapisz'),
            ),
          ],
        ),
      );
    },
  );
}
