import 'package:flutter/material.dart';

import 'package:wspolne/wspolne.dart';

import '../import/dictation_sheet.dart';
import '../import/import_flow.dart';
import '../import/products_pl.dart';
import '../models.dart';
import '../repository.dart';
import '../sorting.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({super.key, required this.repo, required this.list});

  final ShoppingRepository repo;
  final ShoppingList list;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final Stream<List<ShoppingItem>> _items = widget.repo.watchItems(widget.list.id);
  // Nazwa i osoby z dostępem na żywo (ktoś mógł zmienić nazwę albo udostępnić listę)
  late final Stream<ShoppingList?> _list = widget.repo.watchList(widget.list.id);
  List<ShoppingItem> _current = const [];

  ShoppingRepository get repo => widget.repo;
  String get listId => widget.list.id;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _add() async {
    final name = _input.text.trim();
    if (name.isEmpty) return;
    _input.clear();
    _inputFocus.requestFocus();
    await _addNames([name]);
  }

  Future<void> _dictate() async {
    _inputFocus.unfocus();
    final names = await showDictationSheet(
      context,
      hints: [for (final i in _current) i.name, ...commonProducts],
    );
    if (names == null || names.isEmpty || !mounted) return;
    await _addNames(names, announce: true);
  }

  /// Dodaje produkty jak przy wpisywaniu: kupione wracają na listę, powtórek nie ma.
  /// [announce] - pokaż też, co dodano (przy dyktowaniu nie widać tego od razu).
  Future<void> _addNames(List<String> names, {bool announce = false}) async {
    final added = <String>[], restored = <String>[], onList = <String>[];
    for (final name in names) {
      final plan = planAdd(name, _current);
      switch (plan.decision) {
        case AddDecision.add:
          await repo.addItem(listId, name);
          added.add(name);
        case AddDecision.alreadyOnList:
          onList.add(plan.existing!.name);
        case AddDecision.uncheckExisting:
          await repo.setChecked(listId, plan.existing!.id, false);
          restored.add(plan.existing!.name);
      }
    }
    if (!mounted) return;
    String quoted(List<String> l) => l.map((n) => '„$n”').join(', ');
    final parts = [
      if (announce && added.isNotEmpty) 'Dodano: ${quoted(added)}',
      if (restored.isNotEmpty) '${quoted(restored)} ${restored.length == 1 ? 'wróciło' : 'wróciły'} na listę',
      if (onList.isNotEmpty) '${quoted(onList)} już ${onList.length == 1 ? 'jest' : 'są'} na liście',
    ];
    if (parts.isNotEmpty) _snack(parts.join('\n'));
  }

  Future<void> _delete(ShoppingItem item) async {
    await repo.deleteItem(listId, item.id);
    _snack(
      'Usunięto „${item.name}”',
      action: SnackBarAction(label: 'Cofnij', onPressed: () => repo.restoreItem(listId, item)),
    );
  }

  Future<void> _deleteChecked() async {
    final count = _current.where((i) => i.checked).length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć kupione ($count)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok == true) await repo.deleteChecked(listId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ShoppingList?>(
      stream: _list,
      initialData: widget.list,
      builder: (context, listSnap) {
        final list = listSnap.data;
        if (list == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.list.name)),
            body: const Center(child: Text('Ta lista została usunięta albo nie masz już do niej dostępu.')),
          );
        }
        return _buildList(context, list);
      },
    );
  }

  Widget _buildList(BuildContext context, ShoppingList list) {
    final theme = Theme.of(context);
    return StreamBuilder<List<ShoppingItem>>(
      stream: _items,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <ShoppingItem>[];
        _current = items;
        final todo = items.where((i) => !i.checked).toList();
        final done = items.where((i) => i.checked).toList();
        final shared = list.isShared ? ' · wspólna (${list.members.length} os.)' : '';

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(list.name),
                if (items.isNotEmpty || shared.isNotEmpty)
                  Text(
                    (items.isNotEmpty ? 'kupione ${done.length} z ${items.length}' : 'pusta') + shared,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Udostępnij',
                icon: Icon(list.isShared ? Icons.group : Icons.person_add_alt_1),
                onPressed: () => showShareSheet(context, repo, list, collection: 'lists'),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'clear') _deleteChecked();
                  if (v == 'uncheck') repo.uncheckAll(listId);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'clear',
                    enabled: done.isNotEmpty,
                    child: Text('Usuń kupione (${done.length})'),
                  ),
                  PopupMenuItem(
                    value: 'uncheck',
                    enabled: done.isNotEmpty,
                    child: const Text('Odznacz wszystko'),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: snapshot.hasError
                    ? Center(child: Text('Błąd: ${snapshot.error}'))
                    : !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : items.isEmpty
                            ? Center(
                                child: Text(
                                  'Lista jest pusta.\nDopisz produkty w polu na dole.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: theme.colorScheme.outline),
                                ),
                              )
                            : ListView(
                                padding: const EdgeInsets.only(bottom: 16),
                                children: [
                                  for (final item in todo) _tile(item),
                                  if (done.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                      child: Text('Kupione (${done.length})',
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(color: theme.colorScheme.outline)),
                                    ),
                                  for (final item in done) _tile(item),
                                ],
                              ),
              ),
              _AddBar(
                controller: _input,
                focusNode: _inputFocus,
                onSubmit: _add,
                onDictate: _dictate,
                onImport: () => startImport(context, repo: repo, list: list, currentItems: items),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(ShoppingItem item) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(item),
      child: CheckboxListTile(
        value: item.checked,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => repo.setChecked(listId, item.id, v ?? false),
        title: Text(
          item.name,
          style: item.checked
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline,
                )
              : null,
        ),
      ),
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onDictate,
    required this.onImport,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  /// Dyktowanie produktów głosem
  final VoidCallback onDictate;

  /// "Dodaj z kartki": zdjęcie, pisanie palcem albo wklejenie wielu produktów
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Dodaj z kartki (zdjęcie, pismo, wklejenie)',
                onPressed: onImport,
                icon: const Icon(Icons.document_scanner_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Dodaj produkt…',
                    counterText: '',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  // Po Enterze pole zostaje aktywne - można od razu wpisać kolejny produkt
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              IconButton(
                tooltip: 'Podyktuj produkty',
                onPressed: onDictate,
                icon: const Icon(Icons.mic_none),
              ),
              IconButton.filled(
                tooltip: 'Dodaj',
                onPressed: onSubmit,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
