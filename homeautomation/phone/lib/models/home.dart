// Dom, domownicy, uprawnienia i zaproszenia (kontrakt pkt 12).

import 'json_utils.dart';

/// Poziom dostępu do urządzenia. Kolejność ma znaczenie: każdy wyższy zawiera niższe.
enum AccessLevel {
  none('none', 'brak dostępu'),
  view('view', 'podgląd'),
  control('control', 'sterowanie'),
  config('config', 'pełny dostęp');

  const AccessLevel(this.wire, this.label);

  final String wire;
  final String label;

  static AccessLevel fromWire(Object? v) => switch (v) {
    'view' => view,
    'control' => control,
    'config' => config,
    _ => none,
  };

  /// Poziomy, które można nadać w zaproszeniu i ekranie „Domownicy”.
  static const grantable = [view, control, config];

  bool atLeast(AccessLevel other) => index >= other.index;

  bool get canView => atLeast(view);
  bool get canControl => atLeast(control);
  bool get canConfig => atLeast(config);
}

/// Pola Set, które wolno zmieniać z poziomem `control` (reszta wymaga `config`, pkt 12).
const controlSetKeys = {'power', 'target', 'mode', 'on', 'level', 'toggle', 'runScene', 'identify'};

/// Pole Set dostępne przy `control` (pkt 12): także kanały przełącznika `onN` / `toggleN` (pkt 10.1).
bool isControlKey(String key) => controlSetKeys.contains(key) || RegExp(r'^(on|toggle)\d+$').hasMatch(key);

/// Minimalny poziom potrzebny do wysłania tego Set.
AccessLevel requiredLevelFor(Json values) =>
    values.keys.every(isControlKey) ? AccessLevel.control : AccessLevel.config;

/// `homes/{homeId}` (tylko pola widoczne dla domowników).
class Home {
  const Home({required this.id, required this.name, required this.ownerUid});

  final String id;
  final String name;
  final String ownerUid;

  bool isOwner(String? uid) => uid != null && uid == ownerUid;
}

enum MemberRole {
  owner('owner'),
  member('member');

  const MemberRole(this.wire);

  final String wire;

  static MemberRole fromWire(Object? v) => v == 'owner' ? owner : member;
}

/// `homes/{h}/members/{uid}`.
class Member {
  const Member({required this.uid, required this.name, required this.email, required this.role, this.invite});

  final String uid;
  final String name;
  final String email;
  final MemberRole role;

  /// Kod zaproszenia, którym dołączył (dla domownika).
  final String? invite;

  String get label => name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);

  factory Member.fromJson(String uid, Json j) => Member(
    uid: uid,
    name: asString(j['name'], 'name'),
    email: asString(j['email'], 'email'),
    role: MemberRole.fromWire(j['role']),
    invite: asStringOrNull(j['invite'], 'invite'),
  );

  Json toJson() => {'name': name, 'email': email, 'role': role.wire, if (invite != null) 'invite': invite};
}

/// `homes/{h}/access/{uid}`: poziom per urządzenie + `_all` dla pozostałych (także nowych).
class HomeAccess {
  const HomeAccess({this.devices = const {}, this.all = AccessLevel.none, this.owner = false});

  /// Pełny dostęp właściciela domu.
  const HomeAccess.owner() : this(owner: true, all: AccessLevel.config);

  static const allKey = '_all';

  final Map<String, AccessLevel> devices;
  final AccessLevel all;
  final bool owner;

  AccessLevel levelFor(String deviceId) => owner ? AccessLevel.config : devices[deviceId] ?? all;

  factory HomeAccess.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    final devices = <String, AccessLevel>{};
    for (final e in j.entries) {
      if (e.key == allKey) continue;
      // Wpis urządzenia ma pierwszeństwo przed `_all`, także "none" (odebrane jedno urządzenie, pkt 12).
      if (e.value == 'none' || AccessLevel.fromWire(e.value) != AccessLevel.none) {
        devices[e.key.toString()] = AccessLevel.fromWire(e.value);
      }
    }
    return HomeAccess(devices: devices, all: AccessLevel.fromWire(j[allKey]));
  }

  /// Wpisy do zapisu (`_all` tylko, gdy jest jakiś poziom). Wyjątek "none" przy `_all` odbiera jedno urządzenie;
  /// bez `_all` jest zbędny (brak wpisu = brak dostępu).
  Map<String, String> toJson() => {
    for (final e in devices.entries)
      if (e.value != AccessLevel.none || all != AccessLevel.none) e.key: e.value.wire,
    if (all != AccessLevel.none) allKey: all.wire,
  };

  HomeAccess copyWith({Map<String, AccessLevel>? devices, AccessLevel? all}) =>
      HomeAccess(devices: devices ?? this.devices, all: all ?? this.all, owner: owner);
}

/// `invites/{kod}` - kod 8 znaków, ważny 24 h, z jednym poziomem (`level` → `access/{uid}/_all`).
/// Wyjątki dla urządzeń ([access].devices) nie idą do zaproszenia: właściciel dopisuje je po dołączeniu.
class Invite {
  const Invite({
    required this.code,
    required this.homeId,
    required this.createdBy,
    required this.expiresAt,
    required this.access,
  });

  /// Poziom ogólny z zaproszenia (`none` = bez dostępu do czasu ustawienia przez właściciela).
  AccessLevel get level => access.all;

  final String code;
  final String homeId;
  final String createdBy;

  /// ms od epoki.
  final int expiresAt;
  final HomeAccess access;

  bool expired(int nowMs) => nowMs >= expiresAt;

  factory Invite.fromJson(String code, Json j) => Invite(
    code: code,
    homeId: asString(j['homeId'], 'homeId'),
    createdBy: asString(j['createdBy'], 'createdBy'),
    expiresAt: asInt(j['expiresAt'], 'expiresAt'),
    access: HomeAccess(all: AccessLevel.fromWire(j['level'])),
  );

  Json toJson() => {
    'homeId': homeId,
    'createdBy': createdBy,
    'expiresAt': expiresAt,
    'level': level == AccessLevel.none ? 'none' : level.wire,
  };
}

/// Kod zaproszenia: 8 znaków bez mylących (0/O, 1/I/L).
const inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String newInviteCode(int Function(int max) random) =>
    String.fromCharCodes(List.generate(8, (_) => inviteAlphabet.codeUnitAt(random(inviteAlphabet.length))));

/// Kod wpisany przez użytkownika → postać z bazy (wielkie litery, bez spacji i myślników).
String normalizeInviteCode(String input) => input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
