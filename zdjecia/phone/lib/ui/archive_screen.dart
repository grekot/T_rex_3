// Archiwum z biblioteki Zdjęć Google w Firestore (ARCHIWUM.md): logowanie tym samym kontem co w Zakupach / Wadze,
// stan spisu, sprawdzenie po nowej wysyłce z PC, dokładanie nowych zdjęć z telefonu i wylogowanie.
import 'package:flutter/material.dart';

import '../pool_controller.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.pool});

  final PoolController pool;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _working = false;
  bool _showPassword = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _do(Future<String?> Function() job) async {
    setState(() {
      _working = true;
      _message = null;
    });
    final msg = await job();
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = msg;
    });
  }

  Future<void> _signIn() => _do(() async {
        final error = await widget.pool.archiveSignIn(_email.text, _password.text);
        if (error == null) _password.clear();
        return error;
      });

  Future<void> _check() => _do(() async {
        await widget.pool.archiveCheck();
        final s = widget.pool.archiveStatus;
        if (s.error != null) return s.error;
        await widget.pool.refresh();
        return 'Spis aktualny: ${s.count} zdjęć';
      });

  Future<void> _signOut() => _do(() async {
        await widget.pool.archiveSignOut();
        return 'Wylogowano - wspomnienia znów z galerii telefonu';
      });

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return ListenableBuilder(
      listenable: widget.pool,
      builder: (context, _) {
        final s = widget.pool.archiveStatus;
        return Scaffold(
          appBar: AppBar(title: const Text('Archiwum zdjęć')),
          body: ListView(
            padding: const EdgeInsets.all(16) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            children: [
              Text(
                'Najciekawsze zdjęcia z całej biblioteki Zdjęć Google, wybrane na komputerze z eksportu Takeout '
                'i zapisane w bazie, plus najlepsze nowe zdjęcia z telefonu. Z nich biorą się wspomnienia dla '
                'zegarka i zdjęcia dla zegarów w domu - telefon ściąga tylko te, które akurat są potrzebne.',
              ),
              const SizedBox(height: 16),
              if (!s.configured)
                const Text('Ta wersja aplikacji nie ma konfiguracji Firebase - archiwum niedostępne.')
              else if (s.signedIn) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(s.email!),
                  subtitle: Text(s.count == 0
                      ? 'W archiwum nie ma jeszcze zdjęć (wysyłka z komputera: zdjecia/tools/archiwum)'
                      : 'Zdjęć w archiwum: ${s.count}'),
                ),
                if (s.error != null)
                  Text(s.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dokładaj nowe zdjęcia z telefonu'),
                  subtitle: Text(
                    'Najlepsze według Gemini (ocena 7+), 3 dni po zrobieniu, najwyżej 2 z wydarzenia i 3 z dnia; '
                    'przypięte zawsze. Wracają jako wspomnienia po ${widget.pool.prefs.days} dniach. '
                    'Z telefonu w archiwum: ${widget.pool.archivePhoneCount}.',
                    style: small,
                  ),
                  value: widget.pool.prefs.archiveAuto,
                  onChanged: _working ? null : (v) => widget.pool.setArchiveAuto(v),
                ),
                if (widget.pool.archiveAddError != null)
                  Text('Dokładanie: ${widget.pool.archiveAddError}',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _working ? null : _check,
                      icon: const Icon(Icons.sync),
                      label: const Text('Sprawdź teraz'),
                    ),
                    TextButton(onPressed: _working ? null : _signOut, child: const Text('Wyloguj')),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Hasło',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                const SizedBox(height: 4),
                Text('To samo konto co w Zakupach i Wadze. Na telefonie zostaje tylko token, nie hasło.', style: small),
                const SizedBox(height: 12),
                FilledButton(onPressed: _working ? null : _signIn, child: const Text('Zaloguj')),
              ],
              if (_working) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!),
              ],
            ],
          ),
        );
      },
    );
  }
}
