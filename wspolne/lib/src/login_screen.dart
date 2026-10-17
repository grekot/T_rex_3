import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Logowanie / zakładanie konta - to samo konto działa w Zakupach i w Powrocie.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.appName,
    required this.icon,
    required this.description,
    this.watchApps = '',
  });

  final String appName;
  final IconData icon;

  /// Krótko, do czego aplikacja (pod nazwą)
  final String description;

  /// Nazwy aplikacji na zegarku, w których loguje się tym samym kontem
  /// (puste = aplikacja bez zegarka, np. Sklep)
  final String watchApps;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      if (_register) {
        await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = authErrorMessage(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Wpisz e-mail, a potem kliknij „Nie pamiętam hasła”.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wysłano link do zmiany hasła na $email')),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = authErrorMessage(e.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(widget.icon, size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(widget.appName, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      (_register ? 'Załóż konto. ' : 'Zaloguj się. ') + widget.description,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.mail_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Podaj poprawny e-mail' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Hasło',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Ukryj hasło' : 'Pokaż hasło',
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'Hasło musi mieć co najmniej 6 znaków' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _busy
                            ? const SizedBox(
                                height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_register ? 'Załóż konto' : 'Zaloguj się'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() {
                        _register = !_register;
                        _error = null;
                      }),
                      child: Text(_register ? 'Mam już konto – zaloguj się' : 'Nie masz konta? Załóż je'),
                    ),
                    if (!_register)
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Nie pamiętam hasła'),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      widget.watchApps.isEmpty
                          ? 'To samo konto działa w aplikacjach Zakupy, Powrót i Sklep.'
                          : 'To samo konto działa w aplikacjach Zakupy i Powrót na telefonie. Tego samego e-maila '
                              'i hasła użyjesz w ustawieniach aplikacji ${widget.watchApps} na zegarku (aplikacja Zepp).',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String authErrorMessage(String code) {
  switch (code) {
    case 'invalid-email':
      return 'Niepoprawny adres e-mail.';
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      return 'Nieprawidłowy e-mail lub hasło.';
    case 'email-already-in-use':
      return 'Konto z tym e-mailem już istnieje – zaloguj się.';
    case 'weak-password':
      return 'Hasło jest za słabe (minimum 6 znaków).';
    case 'user-disabled':
      return 'To konto zostało zablokowane.';
    case 'too-many-requests':
      return 'Za dużo prób. Spróbuj ponownie za chwilę.';
    case 'network-request-failed':
      return 'Brak połączenia z internetem.';
    case 'operation-not-allowed':
      return 'Logowanie e-mailem nie jest włączone w Firebase (Authentication → Metoda logowania).';
    default:
      return 'Błąd logowania ($code).';
  }
}
