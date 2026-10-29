import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/home.dart';
import 'cloud_store.dart';
import 'errors.dart';
import 'home_repository.dart';

/// Konto e-mail zegarka zalogowane obok konta właściciela (osobna instancja Firebase - telefon zostaje
/// zalogowany głównym kontem). [close] wylogowuje konto zegarka z telefonu.
class WatchAccountSession {
  const WatchAccountSession({required this.repo, required this.store, required this.close});

  /// Dom widziany kontem zegarka (dołączenie kodem).
  final HomeRepository repo;
  final CloudStore store;
  final Future<void> Function() close;
}

abstract class WatchAccounts {
  /// Zakłada konto, a gdy już jest - loguje (to samo hasło).
  Future<WatchAccountSession> open(String email, String password);
}

class FirebaseWatchAccounts implements WatchAccounts {
  FirebaseWatchAccounts(this.options);

  final FirebaseOptions options;

  static const _appName = 'watch-account';

  @override
  Future<WatchAccountSession> open(String email, String password) async {
    final app =
        Firebase.apps.where((a) => a.name == _appName).firstOrNull ??
        await Firebase.initializeApp(name: _appName, options: options);
    final auth = FirebaseAuth.instanceFor(app: app);
    UserCredential cred;
    try {
      cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') throw ThermostatException(_authMessage(e));
      try {
        cred = await auth.signInWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException catch (e) {
        throw ThermostatException(_authMessage(e));
      }
    }
    final user = cred.user!;
    final store = FirebaseCloudStore(FirebaseDatabase.instanceFor(app: app, databaseURL: options.databaseURL));
    return WatchAccountSession(
      repo: HomeRepository(store: store, uid: user.uid, email: user.email ?? email, name: 'Zegarek'),
      store: store,
      close: auth.signOut,
    );
  }

  static String _authMessage(FirebaseAuthException e) => switch (e.code) {
    'weak-password' => 'Hasło musi mieć co najmniej 6 znaków.',
    'invalid-email' => 'Niepoprawny adres e-mail.',
    'wrong-password' ||
    'invalid-credential' ||
    'user-disabled' => 'Konto z tym e-mailem już istnieje i hasło się nie zgadza.',
    'operation-not-allowed' => 'Logowanie e-mailem i hasłem jest wyłączone w projekcie Firebase.',
    'network-request-failed' => 'Brak internetu.',
    _ => 'Nie udało się zalogować konta zegarka (${e.code}).',
  };
}

/// Wynik [setUpWatchAccount].
class WatchAccountResult {
  const WatchAccountResult({required this.uid, required this.alreadyMember, required this.dashboards});

  final String uid;

  /// Konto było już domownikiem - tylko odświeżony poziom i pulpit.
  final bool alreadyMember;

  /// Ile pulpitów zegarka skopiowano z konta właściciela.
  final int dashboards;
}

/// Osobne konto zegarka (PRZEGLAD.md #9): Side Service w aplikacji Zepp trzyma refresh token konta, więc
/// zamiast głównego (dostęp też do Zakupów, Wagi...) zegarek dostaje konto domownika z poziomem `control`.
/// Właściciel zakłada je tutaj: jednorazowe zaproszenie (10 min) → dołączenie kontem zegarka → zaproszenie
/// skasowane. Pulpit zegarka (`users/{uid}/watchDashboards/{h}`, pkt 13a) jest prywatny, więc kopiujemy go
/// pod konto zegarka - przy każdym uruchomieniu (po zmianie pulpitu wystarczy powtórzyć).
Future<WatchAccountResult> setUpWatchAccount({
  required HomeRepository owner,
  required String homeId,
  required WatchAccounts accounts,
  required String email,
  required String password,
}) async {
  final mail = email.trim();
  if (mail.toLowerCase() == owner.email.trim().toLowerCase()) {
    throw const ThermostatException('To e-mail Twojego głównego konta - podaj inny, np. z dopiskiem +zegarek.');
  }
  final session = await accounts.open(mail, password);
  try {
    final watch = session.repo;
    if (watch.uid == owner.uid) throw const ThermostatException('To konto jest Twoim głównym kontem.');
    final memberPath = 'homes/$homeId/members/${watch.uid}';
    final alreadyMember = await owner.store.read(memberPath) != null;
    if (alreadyMember) {
      await owner.store.write('homes/$homeId/access/${watch.uid}/${HomeAccess.allKey}', AccessLevel.control.wire);
      await session.store.write('users/${watch.uid}/homes/$homeId', true);
    } else {
      final invite = await owner.createInvite(
        homeId,
        const HomeAccess(all: AccessLevel.control),
        ttl: const Duration(minutes: 10),
      );
      try {
        await watch.joinByCode(invite.code);
      } finally {
        await owner.deleteInvite(invite.code).catchError((_) {});
      }
    }
    final dashboards = toJsonObject(
      await owner.store.read('users/${owner.uid}/watchDashboards/$homeId').catchError((_) => null),
    );
    if (dashboards != null && dashboards.isNotEmpty) {
      await session.store.write('users/${watch.uid}/watchDashboards/$homeId', dashboards);
    }
    return WatchAccountResult(uid: watch.uid, alreadyMember: alreadyMember, dashboards: dashboards?.length ?? 0);
  } finally {
    await session.close().catchError((_) {});
  }
}

/// Podpowiedź adresu: `jan@gmail.com` → `jan+zegarek@gmail.com` (Gmail i wielu dostawców dostarcza je na to
/// samo konto pocztowe, a w Firebase to osobne konto).
String suggestWatchEmail(String ownerEmail) {
  final at = ownerEmail.indexOf('@');
  if (at <= 0) return '';
  final local = ownerEmail.substring(0, at).split('+').first;
  return '$local+zegarek${ownerEmail.substring(at)}';
}
