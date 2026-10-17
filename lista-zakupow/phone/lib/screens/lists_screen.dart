import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:wspolne/wspolne.dart';

import '../models.dart';
import '../repository.dart';
import 'list_screen.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key, required this.repo});

  final ShoppingRepository repo;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  late final Stream<List<ShoppingList>> _lists = widget.repo.watchLists();

  ShoppingRepository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    // Wpis w książce adresowej - dzięki niemu inni mogą dodać mnie do znajomych po e-mailu
    repo.registerEmail().catchError((_) {});
  }

  Future<void> _createList() async {
    final name = await askForName(context, title: 'Nowa lista', hint: 'np. Biedronka');
    if (name == null) return;
    await repo.createList(name);
  }

  Future<void> _renameList(ShoppingList list) async {
    final name = await askForName(context, title: 'Zmień nazwę', initial: list.name);
    if (name == null || name == list.name) return;
    await repo.renameList(list.id, name);
  }

  Future<void> _deleteOrLeave(ShoppingList list) async {
    final owner = list.isOwner(repo.uid);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(owner ? 'Usunąć listę „${list.name}”?' : 'Opuścić listę „${list.name}”?'),
        content: Text(owner
            ? (list.isShared
                ? 'Lista zniknie u wszystkich osób, którym ją udostępniono, i na zegarkach.'
                : 'Lista i wszystkie produkty znikną także z zegarka.')
            : 'Lista zniknie u Ciebie; pozostali nadal będą ją widzieć.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(owner ? 'Usuń' : 'Opuść')),
        ],
      ),
    );
    if (ok != true) return;
    if (owner) {
      await repo.deleteList(list.id);
    } else {
      await repo.leaveList(list.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listy zakupów'),
        actions: [
          IconButton(
            tooltip: 'Znajomi',
            icon: const Icon(Icons.group_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FriendsScreen(repo: repo, sharedItems: repo.watchLists())),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(repo.email)),
              const PopupMenuItem(value: 'logout', child: Text('Wyloguj')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createList,
        icon: const Icon(Icons.add),
        label: const Text('Nowa lista'),
      ),
      body: StreamBuilder<List<ShoppingList>>(
        stream: _lists,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(icon: Icons.error_outline, text: 'Błąd: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final lists = snapshot.data!;
          if (lists.isEmpty) {
            return const _Message(
              icon: Icons.shopping_basket_outlined,
              text: 'Nie masz jeszcze list.\nUtwórz pierwszą, np. „Biedronka”.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: lists.length,
            itemBuilder: (context, i) {
              final list = lists[i];
              final owner = list.isOwner(repo.uid);
              return Card(
                child: ListTile(
                  leading: Icon(list.isShared ? Icons.group : Icons.list_alt),
                  title: Text(list.name),
                  subtitle: _ListSubtitle(repo: repo, list: list),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ListScreen(repo: repo, list: list)),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'share') showShareSheet(context, repo, list, collection: 'lists');
                      if (v == 'rename') _renameList(list);
                      if (v == 'delete') _deleteOrLeave(list);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'share', child: Text('Udostępnij')),
                      const PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                      PopupMenuItem(value: 'delete', child: Text(owner ? 'Usuń listę' : 'Opuść listę')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// "do kupienia: 3 z 12 · od: zona@x.pl" / "· wspólna (2 os.)"
class _ListSubtitle extends StatefulWidget {
  const _ListSubtitle({required this.repo, required this.list});

  final ShoppingRepository repo;
  final ShoppingList list;

  @override
  State<_ListSubtitle> createState() => _ListSubtitleState();
}

class _ListSubtitleState extends State<_ListSubtitle> {
  // Strumień tworzony raz - inaczej każde odświeżenie listy list subskrybowałoby go od nowa
  late final Stream<List<ShoppingItem>> _items = widget.repo.watchItems(widget.list.id);

  String _sharing() {
    final list = widget.list;
    if (!list.isOwner(widget.repo.uid)) {
      return list.ownerEmail.isNotEmpty ? ' · od: ${list.ownerEmail}' : ' · udostępniona Tobie';
    }
    if (list.isShared) return ' · wspólna (${list.members.length} os.)';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShoppingItem>>(
      stream: _items,
      builder: (context, snapshot) {
        final items = snapshot.data;
        final String progress;
        if (items == null) {
          progress = '…';
        } else if (items.isEmpty) {
          progress = 'pusta';
        } else {
          final todo = items.where((i) => !i.checked).length;
          progress = todo == 0 ? 'wszystko kupione (${items.length})' : 'do kupienia: $todo z ${items.length}';
        }
        return Text(progress + _sharing());
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}
