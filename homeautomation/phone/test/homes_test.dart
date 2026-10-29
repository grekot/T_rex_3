// Dom, domownicy, zaproszenia, poziomy dostępu (pkt 12), opis punktów (pkt 14), pulpity (pkt 13), historia.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/dashboard_store.dart';
import 'package:homeautomation/data/device_icons.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/history.dart';
import 'package:homeautomation/data/home_repository.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/models/describe.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/home.dart';

import 'support/memory_cloud_store.dart';

void main() {
  group('poziomy dostępu', () {
    test('_all dla urządzeń bez wpisu, wpis per urządzenie ma pierwszeństwo', () {
      final a = HomeAccess.fromJson({'termostat-1': 'view', '_all': 'control', 'x': 'bzdura'});
      expect(a.levelFor('termostat-1'), AccessLevel.view);
      expect(a.levelFor('nowe'), AccessLevel.control);
      expect(a.levelFor('x'), AccessLevel.control, reason: 'nieznany poziom = brak wpisu');
      expect(a.toJson(), {'termostat-1': 'view', '_all': 'control'});
      expect(HomeAccess.fromJson(null).levelFor('a'), AccessLevel.none);
      expect(const HomeAccess.owner().levelFor('a'), AccessLevel.config);

      // „none” przy ogólnym `_all` odbiera jedno urządzenie (pkt 12); bez `_all` jest zbędne.
      final cut = HomeAccess.fromJson({'_all': 'control', 'd1': 'none'});
      expect((cut.levelFor('d1'), cut.levelFor('d2')), (AccessLevel.none, AccessLevel.control));
      expect(cut.toJson(), {'d1': 'none', '_all': 'control'});
      expect(const HomeAccess(devices: {'d1': AccessLevel.none}).toJson(), isEmpty);
    });

    test('kolejność poziomów i pola sterowania', () {
      expect(AccessLevel.config.atLeast(AccessLevel.control), isTrue);
      expect(AccessLevel.view.canControl, isFalse);
      expect(requiredLevelFor({'target': 21, 'mode': 'auto'}), AccessLevel.control);
      expect(requiredLevelFor({'target': 21, 'name': 'Salon'}), AccessLevel.config);
    });

    test('kod zaproszenia: 8 znaków bez mylących, normalizacja wpisu', () {
      final code = newInviteCode(Random(1).nextInt);
      expect(code, hasLength(8));
      expect(code.split('').every(inviteAlphabet.contains), isTrue);
      expect(normalizeInviteCode(' ab3d-ef7h '), 'AB3DEF7H');
    });
  });

  group('HomeRepository', () {
    late _RecordingStore store;
    var now = DateTime(2026, 10, 27, 12);
    HomeRepository repo(String uid, [String name = '']) =>
        HomeRepository(store: store, uid: uid, name: name, email: '$uid@x.pl', random: Random(7), clock: () => now);

    setUp(() {
      store = _RecordingStore();
      now = DateTime(2026, 10, 27, 12);
    });

    test('założenie domu, zaproszenie i dołączenie jedną operacją (jak wymagają reguły)', () async {
      final owner = repo('own', 'Grzegorz');
      final home = await owner.createHome('Dom');
      expect(store.get('homes/${home.id}/ownerUid'), 'own');
      expect(store.get('homes/${home.id}/members/own/role'), 'owner');
      expect(store.get('users/own/homes/${home.id}'), true);
      expect((await owner.myHomes()).single.name, 'Dom');

      final invite = await owner.createInvite(
        home.id,
        const HomeAccess(devices: {'termostat-1': AccessLevel.view}, all: AccessLevel.control),
      );
      expect(store.get('invites/${invite.code}/createdBy'), 'own');
      expect(store.get('invites/${invite.code}/level'), 'control', reason: 'zaproszenie ma jeden poziom');
      expect(store.get('users/own/inviteAccess/${home.id}/${invite.code}'), {'termostat-1': 'view'});
      expect(store.get('invites/${invite.code}/expiresAt'), now.add(const Duration(hours: 24)).millisecondsSinceEpoch);

      store.updates.clear();
      final joined = await repo('ania', 'Ania').joinByCode(invite.code.toLowerCase());
      expect(joined.id, home.id);
      // Jeden update na korzeniu: members, usedInvites i access/_all (liść) - nic więcej.
      expect(store.updates.single.keys.toSet(), {
        'homes/${home.id}/members/ania',
        'homes/${home.id}/usedInvites/${invite.code}',
        'homes/${home.id}/access/ania/_all',
      });
      expect(store.get('homes/${home.id}/access/ania'), {'_all': 'control'});

      // Właściciel widzi nowego domownika i dopisuje wyjątki z zaproszenia.
      final applied = await owner.applyInviteExceptions(home.id, await owner.members(home.id).first);
      expect(applied, ['ania']);
      expect(store.get('users/own/inviteAccess/${home.id}/${invite.code}'), isNull);
      expect(store.get('homes/${home.id}/usedInvites/${invite.code}'), 'ania');
      expect(store.get('homes/${home.id}/members/ania'), {
        'name': 'Ania',
        'email': 'ania@x.pl',
        'role': 'member',
        'invite': invite.code,
      });
      expect(store.get('homes/${home.id}/access/ania'), {'termostat-1': 'view', '_all': 'control'});
      expect(store.get('users/ania/homes/${home.id}'), true);
      expect(store.get('invites/${invite.code}'), isNotNull, reason: 'zaproszenie kasuje tylko właściciel');

      final members = await owner.members(home.id).first;
      expect(members.map((m) => m.label), ['Grzegorz', 'Ania'], reason: 'właściciel pierwszy');
      expect((await owner.accessOf(home, 'ania').first).levelFor('termostat-1'), AccessLevel.view);
      expect((await owner.accessOf(home, 'own').first).levelFor('termostat-1'), AccessLevel.config);

      await owner.setAccess(home.id, 'ania', const HomeAccess(all: AccessLevel.view));
      expect(store.get('homes/${home.id}/access/ania'), {'_all': 'view'});

      await owner.removeMember(home.id, 'ania');
      expect(store.get('homes/${home.id}/access/ania'), isNull);
      expect(store.get('homes/${home.id}/members/ania'), isNull);
    });

    test('domownik sam wychodzi z domu', () async {
      final owner = repo('own');
      final home = await owner.createHome('Dom');
      final invite = await owner.createInvite(home.id, const HomeAccess(all: AccessLevel.view));
      final ania = repo('ania');
      await ania.joinByCode(invite.code);
      await ania.leaveHome(home.id);
      expect(store.get('homes/${home.id}/members/ania'), isNull);
      expect(store.get('homes/${home.id}/access/ania'), isNull);
      expect(store.get('users/ania/homes/${home.id}'), isNull);
    });

    test('deviceIndex: właściciel uzupełnia go z devices, domownik z niego czyta', () async {
      store.set('homes/h1/ownerUid', 'own');
      store.set('homes/h1/devices/t1/info', {'type': 'thermostat', 'name': 'Salon', 'fw': '1.0', 'api': 2});
      store.set('homes/h1/devices/s1/info', {'type': 'switch', 'name': 'Lampa', 'via': 'hub-1'});
      final owner = TestCloudAccess(store, uid: 'own')..homeOwnerUid = 'own';
      final list = await owner.devices();
      expect(list.map((d) => (d.id, d.name, d.via)).toSet(), {('t1', 'Salon', null), ('s1', 'Lampa', 'hub-1')});
      expect(store.get('homes/h1/deviceIndex'), {
        't1': {'type': 'thermostat', 'name': 'Salon'},
        's1': {'type': 'switch', 'name': 'Lampa', 'via': 'hub-1'},
      });

      // Domownik nie listuje devices (reguły) - bierze indeks, także dla urządzeń bez dostępu.
      final member = TestCloudAccess(_NoListStore(store), uid: 'ania')..homeOwnerUid = 'own';
      expect((await member.devices()).map((d) => d.id).toSet(), {'t1', 's1'});
    });

    test('ikona urządzenia: deviceIndex/{id}/icon - pisze właściciel, widzą domownicy (pkt 12-13)', () async {
      store.set('homes/h1/deviceIndex/s1', {'type': 'switch', 'name': 'Lampa', 'via': 'hub-1'});
      final owner = DeviceIcons(cache: MemoryTextCache())..attach(store, 'h1', canEdit: true, owner: 'hubA');
      final member = DeviceIcons(cache: MemoryTextCache())..attach(store, 'h1', canEdit: false, owner: 'hubB');
      await pumpEventQueue();

      await owner.set(const PairedDevice(id: 's1', name: 'Lampa', type: DeviceType.onOff), 'ceiling');
      expect(store.get('homes/h1/deviceIndex/s1'), {
        'type': 'switch',
        'name': 'Lampa',
        'via': 'hub-1',
        'icon': 'ceiling',
      });
      expect(member.of('s1'), 'ceiling');

      // Urządzenie spoza indeksu dostaje cały wpis, żeby domownicy nie widzieli urządzenia bez typu i nazwy.
      await owner.set(const PairedDevice(id: 't1', name: 'Salon'), 'heating');
      expect(store.get('homes/h1/deviceIndex/t1'), {'type': 'thermostat', 'name': 'Salon', 'icon': 'heating'});

      // Domownik nie zmienia; „Domyślna” u właściciela usuwa pole.
      await member.set(const PairedDevice(id: 's1', name: 'Lampa', type: DeviceType.onOff), 'tv');
      expect(store.get('homes/h1/deviceIndex/s1/icon'), 'ceiling');
      await owner.set(const PairedDevice(id: 's1', name: 'Lampa', type: DeviceType.onOff), '');
      expect((store.get('homes/h1/deviceIndex/s1/icon'), member.of('s1')), (null, null));

      // Odłącza tylko ten, kto podłączył (nowy DeviceHub po zmianie domu podłącza się przed dispose starego).
      owner.detach('inny');
      expect(owner.of('t1'), 'heating');
      owner.detach('hubA');
      expect(owner.of('t1'), isNull);
    });

    test('nieznany i wygasły kod', () async {
      final owner = repo('own');
      final home = await owner.createHome('Dom');
      await expectLater(repo('b').joinByCode('ZZZZZZZZ'), throwsA(isA<ThermostatException>()));

      final invite = await owner.createInvite(home.id, const HomeAccess(all: AccessLevel.view));
      now = now.add(const Duration(hours: 25));
      await expectLater(
        repo('b').joinByCode(invite.code),
        throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('wygasło'))),
      );
      expect(store.get('homes/${home.id}/members/b'), isNull);
    });
  });

  group('describe', () {
    final d = DeviceDescription.fromJson({
      'type': 'thermostat',
      'points': [
        {'key': 'outdoor.temp', 'name': 'Na zewnątrz', 'kind': 'sensor', 'unit': '°C', 'decimals': 1},
        {
          'key': 'target',
          'name': 'Nastawa',
          'kind': 'setpoint',
          'unit': '°C',
          'min': 15,
          'max': 30,
          'step': 0.5,
          'access': 'control',
          'history': 'target',
        },
        {'key': 'on', 'name': 'Zasilanie', 'kind': 'switch'},
      ],
    });

    test('punkty, klucze z kropką, formatowanie i Set', () {
      final out = d.point('outdoor.temp')!;
      expect(
        out.valueIn({
          'outdoor': {'temp': 4.25},
        }),
        4.25,
      );
      expect(out.format(4.25), '4,3 °C');
      expect(out.setFor(5), {
        'outdoor': {'temp': 5},
      });
      final target = d.point('target')!;
      expect(
        (target.kind, target.min, target.step, target.access, target.history),
        (PointKind.setpoint, 15.0, 0.5, AccessLevel.control, 'target'),
      );
      expect(d.point('on')!.kind, PointKind.switchKind);
      expect(d.point('on')!.access, AccessLevel.config, reason: 'bez "access" - config');
    });
  });

  group('pulpity', () {
    const widgetJson = {
      'name': 'Dom',
      'order': 0,
      'widgets': [
        {
          'id': 'w1',
          'device': 'termostat-ab12cd',
          'point': 'target',
          'view': 'stepper',
          'size': '2x1',
          'label': 'Salon',
        },
        {'id': 'w3', 'view': 'scene', 'size': '2x1', 'label': 'Wychodzę z domu', 'sceneId': 'wyjscie'},
      ],
    };

    test('JSON z kontraktu w obie strony', () {
      final d = Dashboard.fromJson('d1', DashboardScope.shared, widgetJson);
      expect(d.widgets.first.view, WidgetView.stepper);
      expect(d.widgets.first.size, WidgetSize.s2x1);
      expect(d.widgets.last.sceneId, 'wyjscie');
      expect(d.toJson(), widgetJson);
      expect(reorder([1, 2, 3], 0, 3), [2, 3, 1]);
    });

    test('chmura: prywatne i wspólne, kopia na czas bez internetu, preferencje', () async {
      final store = MemoryCloudStore();
      final cache = MemoryTextCache();
      store.set('homes/h1/dashboards/s1', widgetJson);
      final dash = CloudDashboardStore(store, 'u1', cache: cache);
      await dash.save('h1', const Dashboard(id: 'p1', name: 'Mój', scope: DashboardScope.private));
      expect(store.get('users/u1/dashboards/h1/p1/name'), 'Mój');

      final list = await dash.watch('h1').firstWhere((l) => l.length == 2);
      expect(list.map((d) => (d.id, d.scope)), [('p1', DashboardScope.private), ('s1', DashboardScope.shared)]);

      // Bez internetu: najpierw kopia lokalna.
      final offline = CloudDashboardStore(_DeadStore(), 'u1', cache: cache);
      expect((await offline.watch('h1').first).map((d) => d.id), ['p1', 's1']);

      await dash.savePrefs('h1', const HomePrefs(defaultDashboard: 's1'));
      expect(store.get('users/u1/prefs/h1'), {'defaultDashboard': 's1'});
      expect((await dash.prefs('h1')).defaultDashboard, 's1');

      await dash.remove('h1', list.first);
      expect(store.get('users/u1/dashboards/h1/p1'), isNull);
    });
  });

  test('historia: pola z dwóch dni, ostatnie 24 h, posortowane', () async {
    final store = MemoryCloudStore();
    const base = 'history/h1/t1';
    store.set('$base/2026-10-26/1000', {'t': 20.0});
    store.set('$base/2026-10-26/1300', {'t': 20.5});
    store.set('$base/2026-10-27/0015', {'t': 21.0, 'target': 21});
    store.set('$base/2026-10-27/1145', {'t': 21.5});
    final h = await loadHistory(store, homeId: 'h1', deviceId: 't1', field: 't', now: DateTime(2026, 10, 27, 12));
    expect(h.map((p) => p.value), [20.5, 21.0, 21.5]);
    expect(h.first.at, DateTime(2026, 10, 26, 13));
  });
}

/// Zapamiętuje wywołania `update` (dołączanie ma być jedną operacją).
class _RecordingStore extends MemoryCloudStore {
  final updates = <Map<String, Object?>>[];

  @override
  Future<void> update(String path, Map<String, Object?> values) {
    updates.add({for (final e in values.entries) path.isEmpty ? e.key : '$path/${e.key}': e.value});
    return super.update(path, values);
  }
}

/// Domownik: bez płytkiego listowania `homes/{h}/devices` (jak w regułach).
class _NoListStore extends MemoryCloudStore {
  _NoListStore(MemoryCloudStore from) {
    root.addAll(from.root);
  }

  @override
  Future<List<String>> childKeys(String path) async => throw StateError('PERMISSION_DENIED');
}

/// Brak połączenia: strumienie nigdy nic nie przysyłają.
class _DeadStore extends MemoryCloudStore {
  @override
  Stream<Object?> watch(String path) => const Stream.empty();
}
