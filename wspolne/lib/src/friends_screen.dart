import 'package:flutter/material.dart';

import 'account_repository.dart';
import 'ask_for_name.dart';
import 'models.dart';
import 'sharing.dart';

/// Znajomi - wspólni dla aplikacji Zakupy i Powrót (to samo konto, te same dane w Firebase).
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key, required this.repo, this.sharedItems, this.hint});

  final AccountRepository repo;

  /// Moje listy/miejsca - osoby, które mi coś udostępniły, pokazujemy jako "Proponowani"
  final Stream<List<Shared>>? sharedItems;

  /// Podpowiedź u góry ekranu (domyślnie ogólna)
  final String? hint;

  Future<void> _remove(BuildContext context, Friend friend) async {
    await repo.removeFriend(friend.uid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Usunięto ${friend.label} ze znajomych'),
        action: SnackBarAction(label: 'Cofnij', onPressed: () => repo.addKnownFriend(friend)),
      ));
  }

  Future<void> _rename(BuildContext context, Friend friend) async {
    final name = await askForName(context, title: 'Nazwa znajomego', initial: friend.name, hint: 'np. Żona');
    if (name != null) await repo.renameFriend(friend.uid, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Znajomi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddFriendDialog(context, repo),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Dodaj znajomego'),
      ),
      body: StreamBuilder<List<Friend>>(
        stream: repo.watchFriends(),
        builder: (context, friendsSnap) {
          final friends = friendsSnap.data;
          if (friends == null) return const Center(child: CircularProgressIndicator());
          return StreamBuilder<List<Shared>>(
            stream: sharedItems ?? const Stream<List<Shared>>.empty(),
            builder: (context, listsSnap) {
              final suggested = suggestedFriends(
                lists: listsSnap.data ?? const [],
                myUid: repo.uid,
                friends: friends,
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Text(
                      hint ??
                          'Znajomym udostępniasz listy i miejsca jednym stuknięciem („Udostępnij”). Znajomi są '
                              'wspólni dla aplikacji Zakupy i Powrót. Znajomy musi mieć konto – założone w jednej '
                              'z tych aplikacji na telefonie albo w ich ustawieniach w Zepp.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (friends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Nie masz jeszcze znajomych.',
                          textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.outline)),
                    ),
                  for (final f in friends)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(f.label.characters.first.toUpperCase())),
                        title: Text(f.label),
                        subtitle: f.name.isNotEmpty ? Text(f.email) : null,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'rename') _rename(context, f);
                            if (v == 'remove') _remove(context, f);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                            PopupMenuItem(value: 'remove', child: Text('Usuń ze znajomych')),
                          ],
                        ),
                      ),
                    ),
                  if (suggested.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                      child: Text('Proponowani (coś Ci udostępnili)',
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    for (final s in suggested)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(s.email),
                          trailing: IconButton(
                            tooltip: 'Dodaj do znajomych',
                            icon: const Icon(Icons.person_add_alt_1),
                            onPressed: () => repo.addKnownFriend(s),
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Okno dodawania znajomego po e-mailu. Zwraca dodanego znajomego albo null.
Future<Friend?> showAddFriendDialog(BuildContext context, AccountRepository repo) {
  return showDialog<Friend>(context: context, builder: (_) => _AddFriendDialog(repo: repo));
}

class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog({required this.repo});

  final AccountRepository repo;

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Podaj poprawny e-mail');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (result, friend) = await widget.repo.addFriend(email, name: _name.text);
      if (!mounted) return;
      switch (result) {
        case AddFriendResult.added:
        case AddFriendResult.alreadyFriend:
          Navigator.pop(context, friend);
        case AddFriendResult.notFound:
          setState(() => _error = 'Nie ma konta z tym e-mailem. Ta osoba musi najpierw założyć konto (w aplikacji Zakupy albo Powrót).');
        case AddFriendResult.self:
          setState(() => _error = 'To Twój własny adres.');
      }
    } catch (e) {
      setState(() => _error = 'Błąd: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dodaj znajomego'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail (konto w Zakupach)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nazwa (opcjonalnie)', hintText: 'np. Żona'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Dodaj'),
        ),
      ],
    );
  }
}
