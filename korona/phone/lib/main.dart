import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:wspolne/wspolne.dart';

import 'data/peaks.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = await PeakCatalog.load();
  if (firebaseConfigured) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
  runApp(KoronaApp(catalog: catalog));
}

class KoronaApp extends StatelessWidget {
  const KoronaApp({super.key, required this.catalog});

  final PeakCatalog catalog;

  // Zieleń jak kropki zdobytych szczytów na zegarku
  static const _seed = Color(0xFF2E9E4F);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Korona',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: firebaseConfigured ? AuthGate(catalog: catalog) : _NotConfiguredScreen(catalog: catalog),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.catalog});

  final PeakCatalog catalog;

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
            appName: 'Korona',
            icon: Icons.landscape_outlined,
            description: 'Szczyty zdobyte z zegarkiem: postęp list, mapa i historia wejść.',
            watchApps: 'Korona',
          );
        }
        return HomeScreen(
          key: ValueKey(user.uid),
          catalog: catalog,
          repo: KoronaRepository(user.uid, user.email ?? ''),
        );
      },
    );
  }
}

class _NotConfiguredScreen extends StatelessWidget {
  const _NotConfiguredScreen({required this.catalog});

  final PeakCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Brak konfiguracji Firebase.\n\n'
                'Zapisz google-services.json w android/app i uruchom w folderze korona/phone '
                '"node tools/configure.mjs", a potem zbuduj aplikację ponownie.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => HomeScreen(catalog: catalog)),
                ),
                child: const Text('Pokaż przykładowe dane'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
