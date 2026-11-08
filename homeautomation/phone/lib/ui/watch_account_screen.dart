import 'package:flutter/material.dart';

import '../data/errors.dart';
import '../data/home_repository.dart';
import '../data/watch_account.dart';

/// „Konto dla zegarka” (Domownicy, tylko właściciel): osobne konto e-mail domownika z poziomem „sterowanie”,
/// którym loguje się aplikacja Dom w Zepp - zegarek nie trzyma wtedy dostępu do głównego konta.
class WatchAccountScreen extends StatefulWidget {
  const WatchAccountScreen({super.key, required this.owner, required this.homeId, required this.accounts});

  final HomeRepository owner;
  final String homeId;
  final WatchAccounts accounts;

  @override
  State<WatchAccountScreen> createState() => _WatchAccountScreenState();
}

class _WatchAccountScreenState extends State<WatchAccountScreen> {
  late final _email = TextEditingController(text: suggestWatchEmail(widget.owner.email));
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;
  WatchAccountResult? _done;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Podaj e-mail konta zegarka.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Hasło musi mieć co najmniej 6 znaków.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await setUpWatchAccount(
        owner: widget.owner,
        homeId: widget.homeId,
        accounts: widget.accounts,
        email: email,
        password: _password.text,
      );
      if (mounted) setState(() => _done = r);
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Nie udało się: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = _done;
    return Scaffold(
      appBar: AppBar(title: const Text('Konto dla zegarka')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Aplikacja Dom w Zepp trzyma dostęp do konta, którym się w niej zalogujesz. Twoje główne konto otwiera '
            'też Zakupy, Wagę i inne aplikacje, dlatego lepiej dać zegarkowi osobne konto: domownika z poziomem '
            '„sterowanie” (nastawa, włączanie świateł, sceny - bez ustawień urządzeń).',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('watchEmail'),
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'E-mail konta zegarka',
              helperText: 'Np. Twój adres z dopiskiem +zegarek - poczta trafi do Ciebie, a konto jest osobne.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('watchPassword'),
            controller: _password,
            enabled: !_busy,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Hasło (min. 6 znaków)',
              helperText: 'Wpiszesz je w ustawieniach aplikacji Dom w Zepp. Telefon go nie zapamiętuje.',
              helperMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Pokaż' : 'Ukryj',
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                key: const Key('watchAccountError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('watchAccountSave'),
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.watch),
            label: const Text('Załóż konto i dodaj do domu'),
          ),
          if (done != null) ...[
            const SizedBox(height: 24),
            Card(
              key: const Key('watchAccountDone'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done.alreadyMember ? 'Konto zegarka odświeżone' : 'Konto zegarka gotowe',
                      style: t.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_email.text.trim()} jest domownikiem z poziomem „sterowanie”'
                      '${done.dashboards > 0 ? ' i ma kopię pulpitu zegarka' : ''}.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Teraz w aplikacji Zepp: Profil → zegarek → Aplikacje → Dom → Ustawienia: Wyloguj, potem zaloguj '
                      'się tym e-mailem i hasłem i otwórz aplikację Dom na zegarku.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pulpit zegarka układasz dalej na ekranie „Zegarek”. Po zmianach powtórz tutaj zapis (ten sam '
                      'e-mail i hasło) - zegarek dostanie nowy pulpit. Poziom zmienisz w „Domownicy”.',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
