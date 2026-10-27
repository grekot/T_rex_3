import 'package:flutter/material.dart';

import '../controllers/home_session.dart';
import '../data/errors.dart';

/// Pierwsze uruchomienie z kontem (pkt 12): załóż dom albo dołącz do domu kodem zaproszenia.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.session});

  final HomeSession session;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController(text: 'Dom');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on ThermostatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'Nie udało się: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Dom')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.home_outlined, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('Załóż swój dom', style: t.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Będziesz jego właścicielem: dodasz urządzenia i zaprosisz domowników, ustalając, czym mogą sterować.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('homeName'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nazwa domu', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('createHome'),
            onPressed: _busy || _name.text.trim().isEmpty ? null : () => _run(() => widget.session.create(_name.text.trim())),
            child: const Text('Załóż dom'),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),
          Text('Dołącz do domu', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('Wpisz 8-znakowy kod zaproszenia od właściciela domu (ważny 24 godziny).', style: t.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            key: const Key('inviteCode'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: 12,
            style: t.titleLarge?.copyWith(letterSpacing: 4),
            decoration: const InputDecoration(labelText: 'Kod zaproszenia', border: OutlineInputBorder(), counterText: ''),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('joinHome'),
            onPressed: _busy ? null : () => _run(() => widget.session.join(_code.text)),
            child: const Text('Dołącz'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, key: const Key('onboardingError'), style: TextStyle(color: cs.error)),
            ),
        ],
      ),
    );
  }
}
