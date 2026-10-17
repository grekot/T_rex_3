import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:wspolne/wspolne.dart';

import 'firebase_options.dart';
import 'places_screen.dart';
import 'repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (firebaseConfigured) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
  runApp(const PowrotApp());
}

class PowrotApp extends StatelessWidget {
  const PowrotApp({super.key});

  // Pomarańcz jak akcenty T-Rex 3 i aplikacja na zegarku
  static const _seed = Color(0xFFE67E00);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Powrót',
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
            appName: 'Powrót',
            icon: Icons.near_me_outlined,
            description: 'Miejsca zapisane zegarkiem: nawigacja w Google Maps, trasa na zegarek i udostępnianie.',
            watchApps: 'Powrót',
          );
        }
        return PlacesScreen(key: ValueKey(user.uid), repo: PlacesRepository(user.uid, user.email ?? ''));
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
            'Zapisz google-services.json w android/app i uruchom w folderze powrot '
            '"node tools/configure.mjs", a potem zbuduj aplikację ponownie.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
