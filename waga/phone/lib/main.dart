import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:wspolne/wspolne.dart';

import 'data/repository.dart';
import 'firebase_options.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (firebaseConfigured) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
  runApp(const WagaApp());
}

class WagaApp extends StatelessWidget {
  const WagaApp({super.key});

  // Pomarańcz jak przyciski na zegarku
  static const _seed = Color(0xFFE67E00);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waga',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: firebaseConfigured ? const AuthGate() : const _NotConfiguredScreen(),
    );
  }
}

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
            appName: 'Waga',
            icon: Icons.monitor_weight_outlined,
            description: 'Poranne ważenie z zegarka: wykres, trend, cel, kalorie i aktywności.',
            watchApps: 'Waga',
          );
        }
        return HomeScreen(key: ValueKey(user.uid), repo: WeightRepository(user.uid, user.email ?? ''));
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
            'Brak konfiguracji Firebase.\n\nDodaj aplikację Android pl.grekot.waga w konsoli Firebase, '
            'zapisz google-services.json w android/app i uruchom node tools/configure.mjs.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
