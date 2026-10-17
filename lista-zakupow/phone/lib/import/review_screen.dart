import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../sorting.dart';
import 'parser.dart';

/// Ekran sprawdzenia: rozpoznane pozycje do poprawienia/odznaczenia przed dodaniem do listy.
/// Zwraca liczbę dodanych produktów.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.repo,
    required this.list,
    required this.candidates,
    required this.currentItems,
  });

  final ShoppingRepository repo;
  final ShoppingList list;
  final List<ImportCandidate> candidates;
  final List<ShoppingItem> currentItems;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late final List<ImportCandidate> _items = widget.candidates;
  late final List<TextEditingController> _controllers =
      _items.map((c) => TextEditingController(text: c.text)).toList();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  int get _selectedCount => _items.where((c) => c.selected && c.text.trim().isNotEmpty).length;

  void _edited(int i, String value) {
    setState(() {
      _items[i].text = value;
      _items[i].status = statusFor(value, widget.currentItems);
    });
  }

  void _revert(int i) {
    _controllers[i].text = _items[i].original;
    _edited(i, _items[i].original);
  }

  void _addRow() {
    setState(() {
      _items.add(ImportCandidate(original: '', text: '', status: ImportStatus.add, selected: true));
      _controllers.add(TextEditingController());
    });
  }

  void _removeRow(int i) {
    setState(() {
      _items.removeAt(i);
      _controllers.removeAt(i).dispose();
    });
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final repo = widget.repo;
    final listId = widget.list.id;
    final current = List<ShoppingItem>.of(widget.currentItems);
    final seen = <String>{};
    var added = 0;
    try {
      for (final c in _items) {
        final name = c.text.trim();
        if (!c.selected || name.isEmpty || !seen.add(normalizeName(name))) continue;
        final plan = planAdd(name, current);
        switch (plan.decision) {
          case AddDecision.add:
            await repo.addItem(listId, name);
            added++;
          case AddDecision.uncheckExisting:
            await repo.setChecked(listId, plan.existing!.id, false);
            added++;
          case AddDecision.alreadyOnList:
            break;
        }
      }
      if (mounted) Navigator.pop(context, added);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e')));
    }
  }

  String? _hint(ImportCandidate c) {
    switch (c.status) {
      case ImportStatus.onList:
        return 'już jest na liście';
      case ImportStatus.restore:
        return 'kupione wcześniej – wróci na listę';
      case ImportStatus.add:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Sprawdź – ${widget.list.name}')),
      body: _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nie rozpoznano żadnych produktów.\nSpróbuj wyraźniejszego zdjęcia albo napisz listę palcem.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    'Rozpoznano ${_items.length} pozycji. Popraw błędy i odznacz to, czego nie chcesz dodać.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                for (var i = 0; i < _items.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _items[i].selected,
                            onChanged: (v) => setState(() => _items[i].selected = v ?? false),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _controllers[i],
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                                  onChanged: (v) => _edited(i, v),
                                ),
                                if (_items[i].corrected && _items[i].original.isNotEmpty)
                                  InkWell(
                                    onTap: () => _revert(i),
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        'poprawiono z „${_items[i].original}” · cofnij',
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                                      ),
                                    ),
                                  ),
                                if (_hint(_items[i]) != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(_hint(_items[i])!,
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Usuń pozycję',
                            icon: const Icon(Icons.close),
                            onPressed: () => _removeRow(i),
                          ),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj pozycję ręcznie'),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy || _selectedCount == 0 ? null : _confirm,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.playlist_add),
            label: Text('Dodaj zaznaczone ($_selectedCount)'),
          ),
        ),
      ),
    );
  }
}
