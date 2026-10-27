import 'dart:math';

import '../models/home.dart';
import 'cloud_store.dart';
import 'errors.dart';

/// Dom, domownicy, uprawnienia i zaproszenia w Realtime Database (kontrakt pkt 12).
/// Dołączenie to jedna operacja na wielu ścieżkach - tak wymagają reguły bazy.
class HomeRepository {
  HomeRepository({
    required this.store,
    required this.uid,
    this.email = '',
    this.name = '',
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final CloudStore store;
  final String uid;
  final String email;

  /// Wyświetlana nazwa (z konta); pusta = e-mail.
  final String name;
  final Random _random;
  final DateTime Function() _clock;

  String _home(String h) => 'homes/$h';

  /// Domy użytkownika (`users/{uid}/homes`).
  Future<List<Home>> myHomes() async {
    final ids = toJsonObject(await store.read('users/$uid/homes'))?.keys ?? const <String>[];
    final homes = <Home>[];
    for (final h in ids) {
      try {
        final name = await store.read('${_home(h)}/name');
        final owner = await store.read('${_home(h)}/ownerUid');
        if (owner is String) homes.add(Home(id: h, name: name is String ? name : 'Dom', ownerUid: owner));
      } on Object {
        // Usunięty z domu - wpis w users/{uid}/homes już nic nie daje.
      }
    }
    return homes;
  }

  Future<Home> readHome(String homeId) async {
    final name = await store.read('${_home(homeId)}/name');
    final owner = await store.read('${_home(homeId)}/ownerUid');
    return Home(id: homeId, name: name is String ? name : 'Dom', ownerUid: owner is String ? owner : '');
  }

  /// Nowy dom: właściciel = bieżące konto.
  Future<Home> createHome(String homeName) async {
    final id = await store.push('homes', {'name': homeName, 'ownerUid': uid});
    await store.write(
      '${_home(id)}/members/$uid',
      Member(uid: uid, name: name, email: email, role: MemberRole.owner).toJson(),
    );
    await store.write('users/$uid/homes/$id', true);
    return Home(id: id, name: homeName, ownerUid: uid);
  }

  Future<void> renameHome(String homeId, String homeName) => store.write('${_home(homeId)}/name', homeName);

  /// Dołączenie kodem: JEDEN zapis wielu ścieżek - `members/{uid}` z kodem, `usedInvites/{kod} = uid`
  /// i `access/{uid}/_all` = poziom z zaproszenia (liść); potem `users/{uid}/homes/{h}`. Wyjątki dla urządzeń
  /// dopisuje właściciel ([applyInviteExceptions]).
  /// Kod jest jednorazowy - zaproszenia nie kasujemy (robi to właściciel).
  Future<Home> joinByCode(String rawCode) async {
    final code = normalizeInviteCode(rawCode);
    final j = toJsonObject(await store.read('invites/$code'));
    if (j == null) throw const ThermostatException('Nie ma takiego zaproszenia - sprawdź kod.');
    final invite = Invite.fromJson(code, j);
    if (invite.expired(_clock().millisecondsSinceEpoch)) {
      throw const ThermostatException('Zaproszenie wygasło - poproś o nowe.');
    }
    final h = invite.homeId;
    try {
      await store.update('', {
        '${_home(h)}/members/$uid': Member(
          uid: uid,
          name: name,
          email: email,
          role: MemberRole.member,
          invite: code,
        ).toJson(),
        '${_home(h)}/usedInvites/$code': uid,
        if (invite.level != AccessLevel.none) '${_home(h)}/access/$uid/${HomeAccess.allKey}': invite.level.wire,
      });
    } on Object {
      throw const ThermostatException('Nie udało się dołączyć: kod został już użyty albo jesteś już w tym domu.');
    }
    await store.write('users/$uid/homes/$h', true);
    return readHome(h);
  }

  /// Wyjątki dla urządzeń przygotowane przy zaproszeniu: `users/{właściciel}/inviteAccess/{h}/{kod}`.
  String _pending(String homeId) => 'users/$uid/inviteAccess/$homeId';

  /// Nowe zaproszenie: poziom ogólny ([HomeAccess.all]) idzie do `invites/{kod}`, wyjątki per urządzenie
  /// zostają u właściciela i trafiają do `access` po dołączeniu. Zwraca kod (8 znaków, ważny [ttl]).
  Future<Invite> createInvite(String homeId, HomeAccess access, {Duration ttl = const Duration(hours: 24)}) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = newInviteCode(_random.nextInt);
      if (await store.read('invites/$code') != null) continue;
      final invite = Invite(
        code: code,
        homeId: homeId,
        createdBy: uid,
        expiresAt: _clock().add(ttl).millisecondsSinceEpoch,
        access: access,
      );
      await store.write('invites/$code', invite.toJson());
      final exceptions = HomeAccess(devices: access.devices).toJson();
      if (exceptions.isNotEmpty) await store.write('${_pending(homeId)}/$code', exceptions);
      return invite;
    }
    throw const ThermostatException('Nie udało się utworzyć kodu zaproszenia.');
  }

  Future<void> deleteInvite(String code) => store.write('invites/$code', null);

  /// Właściciel: domownik dołączył kodem, dla którego są przygotowane wyjątki → dopisuje je do `access/{uid}`
  /// (każdy liść osobno) i usuwa z listy oczekujących. Zwraca uid-y, którym dopisano wyjątki.
  Future<List<String>> applyInviteExceptions(String homeId, List<Member> members) async {
    final pending = toJsonObject(await store.read(_pending(homeId)).catchError((_) => null)) ?? const {};
    if (pending.isEmpty) return const [];
    final done = <String>[];
    for (final m in members) {
      final code = m.invite;
      final exc = code == null ? null : toJsonObject(pending[code]);
      if (exc == null) continue;
      await store.update('${_home(homeId)}/access/${m.uid}', {for (final e in exc.entries) e.key: e.value});
      await store.write('${_pending(homeId)}/$code', null);
      done.add(m.uid);
    }
    return done;
  }

  Stream<List<Member>> members(String homeId) => store.watch('${_home(homeId)}/members').map((v) {
    final j = toJsonObject(v) ?? const {};
    return [
      for (final e in j.entries)
        if (e.value is Map) Member.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
    ]..sort((a, b) => a.role == b.role ? a.label.compareTo(b.label) : (a.role == MemberRole.owner ? -1 : 1));
  });

  /// Uprawnienia osoby w domu na żywo (właściciel ma `config` wszędzie).
  Stream<HomeAccess> accessOf(Home home, String memberUid) {
    if (home.isOwner(memberUid)) return Stream.value(const HomeAccess.owner());
    return store.watch('${_home(home.id)}/access/$memberUid').map(HomeAccess.fromJson);
  }

  /// Właściciel ustawia poziomy domownika (całe `access/{uid}` naraz).
  Future<void> setAccess(String homeId, String memberUid, HomeAccess access) {
    final j = access.toJson();
    return store.write('${_home(homeId)}/access/$memberUid', j.isEmpty ? null : j);
  }

  /// Wyjście z domu (domownik): najpierw uprawnienia, potem wpis i dom na liście konta.
  Future<void> leaveHome(String homeId) async {
    await store.write('${_home(homeId)}/access/$uid', null);
    await store.write('${_home(homeId)}/members/$uid', null);
    await store.write('users/$uid/homes/$homeId', null);
  }

  /// Usunięcie domownika: jego wpis i uprawnienia (urządzenie odświeża je co 5 min, pkt 12).
  Future<void> removeMember(String homeId, String memberUid) async {
    await store.write('${_home(homeId)}/access/$memberUid', null);
    await store.write('${_home(homeId)}/members/$memberUid', null);
  }
}
