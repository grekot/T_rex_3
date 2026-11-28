import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Konto Firebase (to samo co w Zakupach, Powrocie i Wadze) do zapisywania tras.
///
/// Logowanie jest dobrowolne: mapa i trasy działają bez konta i bez internetu. Konto jest
/// potrzebne tylko do „Moich tras”, wspólnych dla telefonu i przeglądarki.
///
/// Testy na komputerze bez prawdziwego projektu: `--dart-define=EMULATOR=localhost`
/// łączy z emulatorami Firebase (Auth 9099, Firestore 8080) projektu demo-mapychodzone.
class Konto {
  Konto._();

  static bool _dostepne = false;

  /// Czy w tej wersji da się zalogować (jest konfiguracja Firebase i się wczytała).
  static bool get dostepne => _dostepne;

  static const _emulator = String.fromEnvironment('EMULATOR');

  static Future<void> inicjuj() async {
    try {
      if (_emulator.isNotEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'demo',
            appId: '1:1:web:1',
            messagingSenderId: '1',
            projectId: 'demo-mapychodzone',
          ),
        );
        await FirebaseAuth.instance.useAuthEmulator(_emulator, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(_emulator, 8080);
        _dostepne = true;
        return;
      }
      if (!firebaseConfigured) return;
      // w przeglądarce Firebase ładuje biblioteki z sieci: bez internetu mapa rusza bez konta
      await Firebase.initializeApp(options: firebaseOptions).timeout(const Duration(seconds: 15));
      _dostepne = true;
    } on Object catch (e) {
      debugPrint('Firebase niedostępny: $e');
    }
  }

  static User? get uzytkownik => _dostepne ? FirebaseAuth.instance.currentUser : null;

  static Stream<User?> get zmiany =>
      _dostepne ? FirebaseAuth.instance.authStateChanges() : Stream<User?>.value(null);

  static Future<void> wyloguj() => FirebaseAuth.instance.signOut();
}
