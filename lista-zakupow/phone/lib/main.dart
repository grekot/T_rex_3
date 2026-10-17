import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:wspolne/wspolne.dart';

import 'firebase_options.dart';
import 'repository.dart';
import 'screens/lists_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (firebaseConfigured) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
  runApp(const ZakupyApp());
}

class ZakupyApp extends StatelessWidget {
  const ZakupyApp({super.key});

  static const _seed = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zakupy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: firebaseConfigured ? const AuthGate() : const _NotConfiguredScreen(),
    );
  }
}

/// Po zalogowaniu pokazuje listy, w przeciwnym razie ekran logowania.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen(
            appName: 'Lista zakupów',
            icon: Icons.shopping_cart_outlined,
            description: 'Listy synchronizują się z zegarkiem i z osobami, którym je udostępnisz.',
            watchApps: 'Zakupy',
          );
        }
        return ListsScreen(
          key: ValueKey(user.uid),
          repo: ShoppingRepository(user.uid, user.email ?? ''),
        );
      },
    );
  }
}

class _NotConfiguredScreen extends StatelessWidget {
  const _NotConfiguredScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Brak konfiguracji Firebase.\n\n'
            'Zapisz google-services.json w android/app i uruchom '
            '"node tools/configure.mjs", a potem zbuduj aplikację ponownie.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
