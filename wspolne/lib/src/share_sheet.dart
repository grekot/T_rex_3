import 'package:flutter/material.dart';

import 'account_repository.dart';
import 'friends_screen.dart';
import 'models.dart';
import 'sharing.dart';

/// Okno "Udostępnij": zaznaczasz znajomych, którzy mają widzieć listę albo miejsce.
/// [collection]: kolekcja Firestore - 'lists' albo 'places'.
Future<void> showShareSheet(
  BuildContext context,
  AccountRepository repo,
  Shared list, {
  required String collection,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareSheet(repo: repo, list: list, collection: collection),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.repo, required this.list, required this.collection});

  final AccountRepository repo;
  final Shared list;
  final String collection;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final Set<String> _selected = widget.list.members.where((u) => u != widget.repo.uid).toSet();
  late final Stream<List<Friend>> _friends = widget.repo.watchFriends();
  bool _busy = false;

  Shared get list => widget.list;
  String get me => widget.repo.uid;

  Future<void> _addFriend() async {
    final friend = await showAddFriendDialog(context, widget.repo);
    if (friend != null) setState(() => _selected.add(friend.uid));
  }

  Future<void> _save(List<Friend> friends) async {
    final emails = {for (final f in friends) f.uid: f.email, ...list.memberEmails};
    final changes = planSharing(list: list, myUid: me, selected: _selected, knownEmails: emails);
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.applySharing(widget.collection, list.id, changes);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zapisano udostępnienie „${list.name}”')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = list.isOwner(me);
    return StreamBuilder<List<Friend>>(
      stream: _friends,
      builder: (context, snap) {
        final friends = snap.data ?? const <Friend>[];
        // Osoby do pokazania: znajomi + obecni członkowie spoza znajomych (bez mnie)
        final entries = <String, String>{for (final f in friends) f.uid: f.label};
        for (final uid in list.members) {
          if (uid != me && !entries.containsKey(uid)) {
            entries[uid] = list.memberEmails[uid]?.isNotEmpty == true ? list.memberEmails[uid]! : 'osoba bez e-maila';
          }
        }
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text('Udostępnij „${list.name}”', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    isOwner
                        ? (widget.collection == 'places'
                            ? 'Zaznaczeni widzą to miejsce w telefonie i na zegarku (Powrót) i mogą do niego nawigować.'
                            : 'Zaznaczeni widzą i edytują listę – także na zegarku.')
                        : 'Możesz dopisać swoich znajomych. Usuwać osoby może tylko właściciel.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (snap.connectionState == ConnectionState.waiting)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                else if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Nie masz jeszcze znajomych – dodaj kogoś poniżej.',
                        textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.outline)),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in entries.entries)
                          CheckboxListTile(
                            value: e.key == list.ownerId || _selected.contains(e.key),
                            title: Text(e.value),
                            subtitle: e.key == list.ownerId ? const Text('właściciel') : null,
                            // Właściciela nie da się odznaczyć; nie-właściciel nie usuwa obecnych członków
                            onChanged: e.key == list.ownerId || (!isOwner && list.members.contains(e.key))
                                ? null
                                : (v) => setState(() => v == true ? _selected.add(e.key) : _selected.remove(e.key)),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _addFriend,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Dodaj znajomego'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _busy ? null : () => _save(friends),
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Zapisz'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
