import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wspolne/wspolne.dart';

import 'background/alert_worker.dart';
import 'ui/main_screen.dart';

class TermostatApp extends StatelessWidget {
  const TermostatApp({super.key, this.home, this.useLogin = false});

  /// Do testów: inny ekran startowy.
  final Widget? home;

  /// Firebase skonfigurowany: najpierw logowanie wspólnym kontem (jak w innych aplikacjach).
  final bool useLogin;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8590C), brightness: b),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'HomeAutomation',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      locale: const Locale('pl', 'PL'),
      supportedLocales: const [Locale('pl', 'PL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Zegar 24-godzinny w wybieraniu godzin harmonogramu niezależnie od ustawień telefonu.
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
      home: home ?? (useLogin ? const AuthGate() : const MainScreen()),
    );
  }
}

/// Logowanie ekranem z pakietu `wspolne`; po zalogowaniu wybór domu i ekran główny (pkt 12).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _sub;
  String? _syncedUid;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    // Powiadomienia w tle działają tylko dla zalogowanego konta.
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_synced && user?.uid == _syncedUid) return;
      _synced = true;
      _syncedUid = user?.uid;
      AlertScheduler.sync(loggedIn: user != null);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

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
            appName: 'HomeAutomation',
            icon: Icons.home_outlined,
            description: 'Termostat i urządzenia domowe - w domu i spoza domu.',
          );
        }
        return HomeGate(key: ValueKey(user.uid));
      },
    );
  }
}
