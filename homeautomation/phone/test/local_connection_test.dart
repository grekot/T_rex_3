// Integracja z atrapą termostatu (tool/fake): parowanie, stan na żywo, set przez WS i HTTP.
// Prawdziwe gniazda - dlatego zwykłe test(), bez testWidgets.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_connection.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/models/thermostat_state.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../tool/fake/fake_thermostat_server.dart';

class ListDiscovery extends ThermostatDiscovery {
  ListDiscovery([this.items = const []]);

  final List<DiscoveredThermostat> items;

  @override
  Stream<List<DiscoveredThermostat>> watch() => Stream.value(items);
}

void main() {
  late FakeThermostat fake;
  late LocalEndpoint endpoint;
  late MemoryDeviceStore store;

  setUp(() async {
    fake = FakeThermostat(simulate: false);
    await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
    endpoint = LocalEndpoint('127.0.0.1', fake.port);
    store = MemoryDeviceStore();
  });

  tearDown(() => fake.stop());

  /// Parowanie kodem z kontem: `idToken` → najpierw `view`, po „sprawdzeniu w Google” poziom domownika.
  Future<PairedDevice> pair({String level = 'config'}) async {
    fake.idTokenDelay = const Duration(milliseconds: 100);
    final pairing = PairingService(
      store: store,
      clientName: () async => 'Test',
      idToken: () async => 'fake:uid-1:$level',
      mePoll: const Duration(milliseconds: 50),
    );
    final info = await pairing.probe(endpoint);
    await pairing.start(endpoint);
    return pairing.confirm(endpoint, info, fake.pairCode!);
  }

  group('parowanie', () {
    test('kod z ekranu daje token zapisany w magazynie', () async {
      final pairing = PairingService(store: store, clientName: () async => 'Test');
      final info = await pairing.probe(endpoint);
      expect(info.id, 'termostat-ab12cd');
      expect(info.paired, isFalse);

      final validity = await pairing.start(endpoint);
      expect(validity, const Duration(seconds: 120));
      expect(fake.pairCode, hasLength(6));

      await expectLater(
        pairing.confirm(endpoint, info, '000000'),
        throwsA(isA<PairingException>().having((e) => e.code, 'code', 'bad_code')),
      );

      final device = await pairing.confirm(endpoint, info, fake.pairCode!);
      expect(device.id, 'termostat-ab12cd');
      expect(device.name, 'Salon');
      expect(device.lastEndpoint, endpoint);
      // Każdy telefon ma własny token; bez konta (idToken) poziom `view` (pkt 2).
      final token = await store.token(device.id);
      expect(token, hasLength(64));
      expect(token, isNot(fake.token));
      expect(device.access, AccessLevel.view);
      expect(fake.phones.map((p) => (p.name, p.access)), [('Atrapa', 'config'), ('Test', 'view')]);
      expect((await store.devices()).single.access, AccessLevel.view);
    });

    test('3 błędne kody kończą parowanie', () async {
      final pairing = PairingService(store: store, clientName: () async => 'Test');
      final info = await pairing.probe(endpoint);
      await pairing.start(endpoint);
      for (final left in [2, 1, 0]) {
        await expectLater(
          pairing.confirm(endpoint, info, '000000'),
          throwsA(
            isA<PairingException>()
                .having((e) => e.code, 'code', 'bad_code')
                .having((e) => e.attemptsLeft, 'attemptsLeft', left)
                .having((e) => e.mustRestart, 'mustRestart', left == 0),
          ),
        );
      }
      expect(fake.pairCode, isNull);
      await expectLater(
        pairing.confirm(endpoint, info, fake.pairCode ?? '123456'),
        throwsA(isA<PairingException>().having((e) => e.code, 'code', 'not_pairing')),
      );
    });

    test('po 3 złych kodach: pair/start przez 60 s daje 429 locked z retryIn', () async {
      final pairing = PairingService(store: store, clientName: () async => 'Test');
      final info = await pairing.probe(endpoint);
      await pairing.start(endpoint);
      for (var i = 0; i < 3; i++) {
        await expectLater(pairing.confirm(endpoint, info, '000000'), throwsA(isA<PairingException>()));
      }
      await expectLater(
        pairing.start(endpoint),
        throwsA(
          isA<PairingException>()
              .having((e) => e.code, 'code', 'locked')
              .having((e) => e.retryIn, 'retryIn', inInclusiveRange(1, 61))
              .having((e) => e.message, 'message', contains('Spróbuj za')),
        ),
      );
    });

    test('potwierdzenie bez rozpoczęcia: 409 not_pairing', () async {
      final pairing = PairingService(store: store, clientName: () async => 'Test');
      final info = await pairing.probe(endpoint);
      await expectLater(
        pairing.confirm(endpoint, info, '123456'),
        throwsA(isA<PairingException>().having((e) => e.mustRestart, 'mustRestart', isTrue)),
      );
    });
  });

  group('uprawnienia telefonów (pkt 2, 12)', () {
    test('kod z kontem: najpierw view, potem poziom z domu przez /api/me', () async {
      fake.idTokenDelay = const Duration(milliseconds: 100);
      final levels = <AccessLevel>[];
      final pairing = PairingService(
        store: store,
        clientName: () async => 'Pixel',
        idToken: () async => 'fake:uid-7:control',
        mePoll: const Duration(milliseconds: 50),
      );
      final info = await pairing.probe(endpoint);
      await pairing.start(endpoint);
      final device = await pairing.confirm(endpoint, info, fake.pairCode!, onAccess: levels.add);
      expect(levels, [AccessLevel.view, AccessLevel.control]);
      expect(device.access, AccessLevel.control);
      expect(fake.phones.last.uid, 'uid-7');
    });

    test('token view: Set i /api/clients dają forbidden', () async {
      final api = LocalApi(endpoint, token: fake.addPhone('Gość', access: 'view'));
      expect((await api.me()).access, AccessLevel.view);
      final r = await api.set(const SetValues(target: 22));
      expect(r.errors, {'target': 'forbidden'});
      await expectLater(api.clients(), throwsA(isA<ForbiddenException>()));
    });

    test('token config: lista telefonów, usunięcie, describe', () async {
      final api = LocalApi(endpoint, token: fake.token);
      final other = fake.addPhone('Stary telefon', uid: 'u2', access: 'control');
      final phones = await api.clients();
      expect(phones.map((p) => (p.name, p.access)), [
        ('Atrapa', AccessLevel.config),
        ('Stary telefon', AccessLevel.control),
      ]);
      await api.deleteClient(phones.last.id);
      expect(fake.phones.map((p) => p.name), ['Atrapa']);
      await expectLater(LocalApi(endpoint, token: other).me(), throwsA(isA<UnauthorizedException>()));
      final d = await api.describe();
      expect(d.type, 'thermostat');
      expect(d.point('target')?.access, AccessLevel.control);
    });
  });

  group('połączenie lokalne', () {
    late ThermostatConnection conn;

    setUp(() async {
      final device = await pair();
      conn = await ConnectionManager(store: store, discovery: ListDiscovery()).connect(device);
    });

    tearDown(() => conn.close());

    test('wybiera ostatni adres i dostaje stan oraz konfigurację', () async {
      expect(conn.kind, ConnectionKind.local);
      expect(conn.routeDescription, endpoint.display);
      expect(conn.state!.id, 'termostat-ab12cd');
      expect(conn.config!.name, 'Salon');
      expect(conn.status, LinkStatus.online);
    });

    test('set przez WebSocket: ack i nowy stan', () async {
      final states = conn.states.map((s) => (s.mode, s.target)).asBroadcastStream();
      final modeResult = await conn.set(const SetValues(mode: ThermostatMode.manual));
      expect(modeResult.ok, isTrue);

      final next = states.firstWhere((s) => s.$2 == 22.5);
      final r = await conn.set(const SetValues(target: 22.5));
      expect(r.ok, isTrue);
      expect(r.errors, isEmpty);
      expect(await next.timeout(const Duration(seconds: 2)), (ThermostatMode.manual, 22.5));
      expect(fake.manualTarget, 22.5);
    });

    test('błędne pole wraca w errors, poprawne jest stosowane', () async {
      final config = conn.configs.firstWhere((c) => c.name == 'Kuchnia');
      final r = await conn.set(
        const SetValues(
          name: 'Kuchnia',
          schedule: SchedulePatch(weekday: '08:00-07:00'),
          target: 40,
        ),
      );
      expect(r.ok, isFalse);
      expect(r.errors, {'schedule.weekday': 'format', 'target': 'range'});
      expect((await config.timeout(const Duration(seconds: 2))).name, 'Kuchnia');
      expect(fake.config.schedule.weekday, '06:00-08:00,15:00-22:00');
    });

    test('zmiana z gałki przychodzi na żywo', () async {
      final before = conn.state!.target;
      final next = conn.states.firstWhere((s) => s.target == before + 0.5);
      fake.knob(0.5);
      expect((await next.timeout(const Duration(seconds: 2))).override, isTrue);
    });

    test('awaria czujnika: temp null i flaga', () async {
      final next = conn.states.firstWhere((s) => s.sensorFault);
      fake.toggleFault();
      final s = await next.timeout(const Duration(seconds: 2));
      expect(s.temp, isNull);
      expect(s.heating, isFalse);
    });
  });

  test('bez WebSocketu set idzie przez POST /api/set', () async {
    final device = await pair();
    final conn = LocalConnection(
      codec: thermostatCodec,
      deviceId: device.id,
      endpoint: endpoint,
      token: (await store.token(device.id))!,
      connector: (uri) => WebSocketChannel.connect(uri.replace(path: '/nie-ma')),
    );
    await conn.open();
    expect(conn.status, LinkStatus.reconnecting);
    final r = await conn.set(const SetValues(mode: ThermostatMode.manual, target: 19.5));
    expect(r.ok, isTrue);
    expect(r.state!.target, 19.5);
    expect(conn.state!.target, 19.5);

    final bad = await conn.set(const SetValues(eco: 18.5, comfort: 99));
    expect(bad.errors, {'comfort': 'range'});
    expect(conn.config!.eco, 18.5, reason: 'po błędzie stan i konfiguracja są odświeżane');
    await conn.close();
  });

  test('termostat zajęty: ack i POST /api/set dają error busy', () async {
    final device = await pair();
    final conn = await ConnectionManager(store: store, discovery: ListDiscovery()).connect(device);
    fake.busy = true;
    final viaWs = await conn.set(const SetValues(target: 20));
    expect(viaWs.ok, isFalse);
    expect(viaWs.error, 'busy');
    expect(viaWs.errors, isEmpty);
    await conn.close();

    final http = LocalConnection(
      codec: thermostatCodec,
      deviceId: device.id,
      endpoint: endpoint,
      token: fake.token,
      connector: (uri) => WebSocketChannel.connect(uri.replace(path: '/nie-ma')),
    );
    fake.busy = false;
    await http.open();
    fake.busy = true;
    final viaHttp = await http.set(const SetValues(target: 20));
    expect(viaHttp.error, 'busy');
    await http.close();
  });

  test('POST /api/set z błędem: 400, ale ze state i config (kontrakt pkt 3)', () async {
    final api = LocalApi(endpoint, token: fake.token);
    final r = await api.set(const SetValues(name: 'Bardzo długa nazwa termostatu ponad limit', eco: 17.3));
    expect(r.ok, isFalse);
    expect(r.errors, {'name': 'length'});
    expect(r.config!.eco, 17.5, reason: 'liczby zaokrąglane do kroku 0,5');
    expect(r.state, isNotNull);
    api.close();
  });

  test('/api/cloud: konto urządzenia - linking → binding (przypisanie do domu) → linked, odłączanie', () async {
    fake.cloudLinkDelay = const Duration(milliseconds: 200);
    final device = await pair();
    final conn = LocalConnection(codec: thermostatCodec, deviceId: device.id, endpoint: endpoint, token: fake.token);
    await conn.open();
    expect(conn.state!.cloud, isFalse);
    Future<void> noBind(String _) async {}

    await expectLater(
      conn.linkCloud(apiKey: 'zly', dbUrl: 'https://db', homeId: 'h1', bind: noBind),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('klucz API'))),
    );
    await expectLater(
      conn.linkCloud(apiKey: 'k', dbUrl: 'http://bez-tls', homeId: 'h1', bind: noBind),
      throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('zły adres bazy'))),
    );

    // Urządzenie potwierdza dopiero, gdy aplikacja zapisze deviceAccounts.
    final bound = <String, String>{};
    fake.cloudBound = bound.containsKey;
    final linked = conn.states.firstWhere((s) => s.cloud);
    final seen = <String>[];
    final deviceUid = await LocalApi(endpoint, token: fake.token).cloud(
      apiKey: 'k',
      dbUrl: 'https://db',
      homeId: 'h1',
      bind: (uid) async => bound[uid] = device.id,
      pollInterval: const Duration(milliseconds: 50),
      onStatus: (s) => seen.add(s.status),
    );
    expect(deviceUid, fake.deviceUid);
    expect(bound, {fake.deviceUid: device.id});
    expect(seen.toSet(), {'linking', 'binding', 'linked'});
    final status = await conn.cloudStatus();
    expect((status.status, status.deviceUid, status.connected), ('linked', fake.deviceUid, true));
    expect(fake.cloudHomeId, 'h1');
    await linked.timeout(const Duration(seconds: 2));

    final unlinked = conn.states.firstWhere((s) => !s.cloud);
    await conn.unlinkCloud();
    expect(fake.cloudHomeId, isNull);
    expect((await conn.cloudStatus()).status, 'none');
    await unlinked.timeout(const Duration(seconds: 2));
    await conn.close();
  });

  test('telefony: zmiana poziomu (PATCH) i token dla huba (POST)', () async {
    final api = LocalApi(endpoint, token: fake.token);
    final other = fake.addPhone('Pixel', uid: 'u2', access: 'view');
    await api.setClientAccess(other.substring(0, 8), AccessLevel.control);
    expect(fake.phones.last.access, 'control');
    final t = await api.createClient('hub', AccessLevel.config);
    expect((t.token.length, t.access), (64, AccessLevel.config));
    expect((await LocalApi(endpoint, token: t.token).me()).access, AccessLevel.config);
    await expectLater(
      LocalApi(endpoint, token: other).createClient('x', AccessLevel.view),
      throwsA(isA<ForbiddenException>()),
    );
  });

  test('ochrona przed zamarzaniem: frost w Config, zakresy, protect w State', () async {
    final api = LocalApi(endpoint, token: fake.token);
    final r = await api.set(const SetValues(frostTemp: 8.5, frostFaultDutyMin: 3));
    expect(r.errors, {'frost.faultDutyMin': 'range'});
    final cfg = await api.config();
    expect((cfg.frost.temp, cfg.frost.faultDutyMin), (8.5, 0));
    await api.set(const SetValues(power: false));
    expect((await api.state()).protect, 'frost');
  });

  group('OTA (pkt 3a)', () {
    Uint8List image(int size, {int first = 0xE9}) => Uint8List(size)..[0] = first;

    test('wgranie obrazu: postęp, 200 restartIn, po restarcie nowa wersja fw', () async {
      fake
        ..otaDelay = Duration.zero
        ..otaRestart = const Duration(milliseconds: 200);
      final api = LocalApi(endpoint, token: fake.token);
      final before = (await api.info()).fw;
      var lastSent = 0;
      final restartIn = await api.uploadFirmware(image(200 * 1024), onSent: (s, t) => lastSent = s);
      expect(restartIn, 2);
      expect(lastSent, 200 * 1024);
      expect((await api.otaStatus()).state, 'done');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect((await api.info()).fw, isNot(before));
      expect((await api.otaStatus()).state, 'idle');
      api.close();
    });

    test('zły obraz: 400 i komunikat po polsku, stan error', () async {
      fake.otaDelay = Duration.zero;
      final api = LocalApi(endpoint, token: fake.token);
      await expectLater(
        api.uploadFirmware(image(4096, first: 0x00)),
        throwsA(isA<ThermostatException>().having((e) => e.message, 'message', contains('nagłówek'))),
      );
      final s = await api.otaStatus();
      expect(s.state, 'error');
      expect(s.error, 'Wrong Magic Byte');
      api.close();
    });

    test('OTA wymaga tokenu', () async {
      final api = LocalApi(endpoint, token: 'zly');
      await expectLater(api.uploadFirmware(image(2048)), throwsA(isA<UnauthorizedException>()));
      api.close();
    });
  });

  test('zły token: UnauthorizedException', () async {
    final conn = LocalConnection(codec: thermostatCodec, deviceId: fake.id, endpoint: endpoint, token: 'zly');
    await expectLater(conn.open(), throwsA(isA<UnauthorizedException>()));
    expect(conn.status, LinkStatus.unauthorized);
    await conn.close();
  });

  group('wybór drogi', () {
    test('stary adres nie odpowiada → mDNS → zapis nowego adresu', () async {
      final device = await pair();
      final stale = device.copyWith(lastEndpoint: const LocalEndpoint('127.0.0.1', 1));
      await store.saveDevice(stale);
      final steps = <String>[];
      final conn = await ConnectionManager(
        store: store,
        discovery: ListDiscovery([DiscoveredThermostat(id: fake.id, endpoint: endpoint)]),
      ).connect(stale, onStep: steps.add);
      expect(conn.kind, ConnectionKind.local);
      expect(conn.routeDescription, endpoint.display);
      expect(steps, hasLength(2));
      expect((await store.devices()).single.lastEndpoint, endpoint);
      await conn.close();
    });

    test('pod starym adresem inny termostat → nie łączy się z nim', () async {
      final device = await pair();
      final other = PairedDevice(id: 'termostat-ffffff', name: 'Inny', lastEndpoint: endpoint);
      await store.saveToken(other.id, fake.token);
      await expectLater(
        ConnectionManager(store: store, discovery: ListDiscovery()).connect(other),
        throwsA(isA<NoRouteException>()),
      );
      expect(device.id, isNot(other.id));
    });

    test('brak termostatu w sieci i brak chmury → NoRouteException', () async {
      await store.saveToken('termostat-000000', 'x');
      await expectLater(
        ConnectionManager(
          store: store,
          discovery: ListDiscovery(),
        ).connect(const PairedDevice(id: 'termostat-000000', name: 'X')),
        throwsA(isA<NoRouteException>()),
      );
    });

    test('brak tokenu → trzeba sparować', () async {
      await expectLater(
        ConnectionManager(
          store: store,
          discovery: ListDiscovery(),
        ).connect(PairedDevice(id: fake.id, name: 'X', lastEndpoint: endpoint)),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
