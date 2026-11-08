// Kafelek `values` (pkt 13.1): wybór pozycji - urządzenie → punkt z `describe`, kolejność, własne etykiety.

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../data/device_store.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/home.dart';
import 'widget_editor.dart' show pointsOf;
import 'widgets.dart';

/// Wynik edycji: tytuł kafelka (gdy [ValuesEditorScreen.askLabel]) i pozycje.
typedef ValuesEdit = ({String? label, List<ValueItem> items});

/// Pozycje kafelka „Kilka wartości”: do [maxValueItems], z dowolnych urządzeń.
class ValuesEditorScreen extends StatefulWidget {
  const ValuesEditorScreen({super.key, required this.hub, this.initial = const [], this.askLabel = false});

  final DeviceHub hub;
  final List<ValueItem> initial;

  /// Nowy kafelek: pole na tytuł (w istniejącym tytuł zmienia się w ustawieniach kafelka).
  final bool askLabel;

  @override
  State<ValuesEditorScreen> createState() => _ValuesEditorScreenState();
}

class _ValuesEditorScreenState extends State<ValuesEditorScreen> {
  late List<ValueItem> _items = [...widget.initial];
  final _label = TextEditingController();

  /// Nazwy punktów z `describe` (urządzenie/punkt → nazwa) do listy.
  final _names = <String, String>{};

  DeviceHub get hub => widget.hub;

  @override
  void initState() {
    super.initState();
    for (final i in _items) {
      _loadName(i.device, i.point);
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _loadName(String device, String point) async {
    final d = hub.device(device);
    if (d == null) return;
    final points = await pointsOf(hub, d);
    final p = points.where((x) => x.key == point).firstOrNull;
    if (p != null && mounted) setState(() => _names['$device/$point'] = p.name);
  }

  String _title(ValueItem i) => i.label ?? _names['${i.device}/${i.point}'] ?? i.point;

  Future<void> _add() async {
    final d = await showDialog<PairedDevice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Urządzenie'),
        children: [
          for (final d in hub.devices)
            if (hub.accessFor(d.id) != AccessLevel.none)
              SimpleDialogOption(
                key: Key('values-device-${d.id}'),
                onPressed: () => Navigator.pop(ctx, d),
                child: Text(d.name),
              ),
        ],
      ),
    );
    if (d == null || !mounted) return;
    final points = await pointsOf(hub, d);
    if (!mounted) return;
    final p = await showDialog<DataPoint>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(d.name),
        children: [
          for (final p in points)
            SimpleDialogOption(
              key: Key('values-point-${p.key}'),
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(p.unit == null ? p.name : '${p.name} (${p.unit})'),
            ),
          if (points.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Brak punktów danych.')),
        ],
      ),
    );
    if (p == null) return;
    setState(() {
      _names['${d.id}/${p.key}'] = p.name;
      _items = [..._items, (device: d.id, point: p.key, label: null, labels: null)];
    });
  }

  Future<void> _rename(int i) async {
    final it = _items[i];
    final text = await showTextInputDialog(
      context,
      title: 'Etykieta (puste = nazwa z urządzenia)',
      initial: it.label ?? '',
      maxLength: 24,
    );
    if (text == null) return;
    final label = text.trim().isEmpty ? null : text.trim();
    setState(() => _items = [..._items]..[i] = (device: it.device, point: it.point, label: label, labels: it.labels));
  }

  @override
  Widget build(BuildContext context) {
    final full = _items.length >= maxValueItems;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kilka wartości'),
        actions: [
          TextButton(
            key: const Key('valuesDone'),
            onPressed: _items.isEmpty
                ? null
                : () => Navigator.pop<ValuesEdit>(context, (
                    label: _label.text.trim().isEmpty ? null : _label.text.trim(),
                    items: _items,
                  )),
            child: const Text('Gotowe'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (widget.askLabel)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                key: const Key('valuesLabel'),
                controller: _label,
                maxLength: 24,
                decoration: const InputDecoration(labelText: 'Nazwa kafelka', hintText: 'np. Rozdzielnia'),
              ),
            ),
          SectionHeader('Wartości (${_items.length} z $maxValueItems)'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Dowolne odczyty i stany, także z różnych urządzeń. Dotknij, aby zmienić etykietę.'),
          ),
          for (final (i, it) in _items.indexed)
            ListTile(
              key: Key('valuesItem-$i'),
              title: Text(_title(it)),
              subtitle: Text('${hub.device(it.device)?.name ?? it.device} · ${it.point}'),
              onTap: () => _rename(i),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0)
                    IconButton(
                      tooltip: 'Wyżej',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () => setState(() => _items = reorder(_items, i, i - 1)),
                    ),
                  IconButton(
                    tooltip: 'Usuń',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _items = [..._items]..removeAt(i)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              key: const Key('valuesAdd'),
              onPressed: full ? null : _add,
              icon: const Icon(Icons.add),
              label: Text(full ? 'Najwyżej $maxValueItems wartości' : 'Dodaj wartość'),
            ),
          ),
        ],
      ),
    );
  }
}
