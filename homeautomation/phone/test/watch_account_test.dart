// Osobne konto zegarka (PRZEGLAD.md #9): domownik `control` zakładany przez właściciela, kopia pulpitu zegarka.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/home_repository.dart';
import 'package:homeautomation/data/watch_account.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/ui/watch_account_screen.dart';

import 'support/memory_cloud_store.dart';

/// Konta e-mail w pamięci: założenie albo logowanie tym samym hasłem.
class _FakeAccounts implements WatchAccounts {
  _FakeAccounts(this.store);

  final MemoryCloudStore store;
  final passwords = <String, String>{};
  int closed = 0;

  @override
  Future<WatchAccountSession> open(String email, String password) async {
    final known = passwords[email];
    if (known != null && known != password) {
      throw const ThermostatException('Konto z tym e-mailem już istnieje i hasło się nie zgadza.');
    }
    passwords[email] = password;
    final uid = 'w-${email.hashCode.abs()}';
    return WatchAccountSession(
      repo: HomeRepository(store: store, uid: uid, email: email, name: 'Zegarek', random: Random(3)),
      store: store,
      close: () async => closed++,
    );
  }
}

void main() {
  late MemoryCloudStore store;
  late HomeRepository owner;
  late Home home;
  late _FakeAccounts accounts;

  setUp(() async {
    store = MemoryCloudStore();
    owner = HomeRepository(store: store, uid: 'own', email: 'jan@gmail.com', name: 'Jan', random: Random(7));
    home = await owner.createHome('Dom');
    accounts = _FakeAccounts(store);
    store.set('users/own/watchDashboards/${home.id}', {
      'model:t-rex-3': {
        'tiles': [
          {'device': 'termostat-1', 'view': 'thermostat'},
        ],
      },
    });
  });

  test('podpowiedź adresu z dopiskiem +zegarek', () {
    expect(suggestWatchEmail('jan@gmail.com'), 'jan+zegarek@gmail.com');
    expect(suggestWatchEmail('jan+dom@gmail.com'), 'jan+zegarek@gmail.com');
    expect(suggestWatchEmail(''), '');
  });

  test('konto zegarka: domownik z control, dom na liście konta, zaproszenie skasowane, kopia pulpitu', () async {
    final r = await setUpWatchAccount(
      owner: owner,
      homeId: home.id,
      accounts: accounts,
      email: 'jan+zegarek@gmail.com',
      password: 'tajne123',
    );
    final h = home.id;
    expect(r.alreadyMember, isFalse);
    expect((store.get('homes/$h/members/${r.uid}') as Map)['role'], 'member');
    expect((store.get('homes/$h/members/${r.uid}') as Map)['name'], 'Zegarek');
    expect(store.get('homes/$h/access/${r.uid}'), {'_all': 'control'});
    expect(store.get('users/${r.uid}/homes/$h'), isTrue);
    expect(store.get('invites'), anyOf(isNull, isEmpty), reason: 'jednorazowy kod sprzątnięty');
    expect(store.get('users/${r.uid}/watchDashboards/$h'), store.get('users/own/watchDashboards/$h'));
    expect((r.dashboards, accounts.closed), (1, 1), reason: 'konto zegarka wylogowane z telefonu');

    // Powtórka (np. po zmianie pulpitu): bez nowego dołączania, poziom z powrotem control, świeży pulpit.
    store.set('homes/$h/access/${r.uid}/_all', 'view');
    store.set('users/own/watchDashboards/$h/model:t-rex-3/tiles', [
      {'device': 'swiatlo-1', 'view': 'toggle'},
    ]);
    final again = await setUpWatchAccount(
      owner: owner,
      homeId: h,
      accounts: accounts,
      email: 'jan+zegarek@gmail.com',
      password: 'tajne123',
    );
    expect((again.uid, again.alreadyMember), (r.uid, true));
    expect(store.get('homes/$h/access/${r.uid}/_all'), 'control');
    expect(store.get('users/${r.uid}/watchDashboards/$h/model:t-rex-3/tiles'), [
      {'device': 'swiatlo-1', 'view': 'toggle'},
    ]);
  });

  test('e-mail głównego konta i złe hasło istniejącego konta - błąd, nic nie zapisane', () async {
    await expectLater(
      setUpWatchAccount(owner: owner, homeId: home.id, accounts: accounts, email: 'JAN@gmail.com', password: 'x12345'),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('głównego konta'))),
    );
    accounts.passwords['jan+zegarek@gmail.com'] = 'inne-haslo';
    await expectLater(
      setUpWatchAccount(
        owner: owner,
        homeId: home.id,
        accounts: accounts,
        email: 'jan+zegarek@gmail.com',
        password: 'tajne123',
      ),
      throwsA(isA<ThermostatException>()),
    );
    expect((store.get('homes/${home.id}/members') as Map).keys, ['own']);
  });

  testWidgets('ekran: podpowiedź e-maila, walidacja hasła, wynik z instrukcją dla Zepp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WatchAccountScreen(owner: owner, homeId: home.id, accounts: accounts),
      ),
    );
    expect(find.text('jan+zegarek@gmail.com'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('watchPassword')), '123');
    await tester.tap(find.byKey(const Key('watchAccountSave')));
    await tester.pump();
    expect(find.textContaining('co najmniej 6 znaków'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('watchPassword')), 'tajne123');
    await tester.tap(find.byKey(const Key('watchAccountSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('watchAccountDone')), findsOneWidget);
    expect(find.textContaining('ma kopię pulpitu zegarka'), findsOneWidget);
    expect(find.textContaining('zaloguj się tym e-mailem'), findsOneWidget);
    expect(accounts.passwords.keys, ['jan+zegarek@gmail.com']);
  });
}
