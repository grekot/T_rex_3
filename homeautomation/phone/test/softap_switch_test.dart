// Urządzenia bez Bluetooth (pkt 9.4: SoftAP + HTTP, ciasteczko sesji), parowanie kodem PoP (pkt 2)
// i przełącznik wielokanałowy (pkt 10.1) na atrapie węzła `switch4`. Prawdziwe gniazda - bez testWidgets
// (kreator SoftAP: softap_ui_test.dart).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/field_errors.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/pairing.dart';
import 'package:homeautomation/models/describe.dart';
import 'package:homeautomation/models/device_info.dart';
import 'package:homeautomation/models/home.dart';
import 'package:homeautomation/models/light.dart';
import 'package:homeautomation/provisioning/messages.dart';
import 'package:homeautomation/provisioning/provisioner.dart';
import 'package:homeautomation/provisioning/softap_transport.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../tool/fake/fake_thermostat_server.dart';
import 'support/fake_prov_device.dart';

/// Urządzenie w trybie SoftAP: `POST /<endpoint>` z bajtami protobuf, sesja po ciasteczku (jak esp_http_server
/// w `wifi_prov_scheme_softap`). Bez właściwego ciasteczka - 400 (nowa sesja wymagałaby nowego uzgodnienia).
class _SoftApServer {
  _SoftApServer(this.device);

  final FakeProvDevice device;
  final cookies = <String?>[];
  late HttpServer server;
  String? _session;

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> start() async {
    server = await shelf_io.serve((Request req) async {
      final endpoint = req.url.path;
      final cookie = req.headers['cookie'];
      cookies.add(cookie);
      final headers = <String, String>{'Content-Type': 'application/octet-stream'};
      if (_session == null) {
        _session = '4321';
        headers['Set-Cookie'] = 'session=$_session; Path=/';
      } else if (cookie != 'session=$_session') {
        return Response(400, body: 'no session');
      }
      final body = Uint8List.fromList(await req.read().expand((b) => b).toList());
      final out = await device.exchange(endpoint, body);
      return Response.ok(out, headers: headers);
    }, InternetAddress.loopbackIPv4, 0);
  }

  Future<void> stop() => server.close(force: true);
}

/// Telefon „łączy się” z siecią urządzenia: tylko zapisuje, z czym.
class _RecordingJoiner implements ApJoiner {
  final joins = <(String?, String)>[];
  int releases = 0;

  @override
  bool get supported => true;

  @override
  Future<void> join({String? ssid, required String passphrase}) async => joins.add((ssid, passphrase));

  @override
  Future<void> release() async => releases++;
}

void main() {
  group('SoftAP (pkt 9.4)', () {
    late _SoftApServer ap;
    late FakeProvDevice device;

    setUp(() async {
      device = FakeProvDevice(
        pop: 'ab12cd34',
        id: 'swiatlo-0c4f21',
        type: 'switch',
        token: 'tok-softap',
        networks: const [FakeNetwork('Dom', -50, password: 'tajne123')],
        connectPolls: 1,
      );
      ap = _SoftApServer(device);
      await ap.start();
    });

    tearDown(() => ap.stop());

    test('ten sam protokół przez HTTP: security 1, ha-pair, skan, sieć, status; ciasteczko sesji', () async {
      final joiner = _RecordingJoiner();
      final transport = await SoftApProvisioning(joiner: joiner, base: ap.base).connect(pop: 'ab12cd34');
      expect(joiner.joins, [(null, 'ab12cd34')], reason: 'bez znanego id - sieci HA_* do wyboru');

      final p = Provisioner(transport, 'ab12cd34');
      await p.start();
      final pair = await p.haPair('Pixel 8', uid: 'u1');
      expect((pair.id, pair.type, pair.token, pair.access), ('swiatlo-0c4f21', 'switch', 'tok-softap', 'config'));
      expect((await p.scanWifi()).single.ssid, 'Dom');
      await p.setWifi('Dom', 'tajne123');
      final s = await p.waitForConnection(interval: Duration.zero, retries: 3);
      expect(s.state, WifiStationState.connected);

      expect(ap.cookies.first, isNull);
      expect(ap.cookies.skip(1).toSet(), {'session=4321'}, reason: 'kolejne żądania z ciasteczkiem');
      await transport.close();
      expect(joiner.releases, 1, reason: 'telefon zwalnia sieć HA_*');
    });

    test('zmiana sieci znanego urządzenia: telefon łączy się z HA_<id>', () async {
      final joiner = _RecordingJoiner();
      await SoftApProvisioning(joiner: joiner, base: ap.base).connect(pop: 'ab12cd34', deviceId: 'swiatlo-0c4f21');
      expect(joiner.joins, [('HA_swiatlo-0c4f21', 'ab12cd34')]);
    });
  });

  group('węzeł switch4 na atrapie', () {
    late FakeLight fake;
    late LocalEndpoint endpoint;

    setUp(() async {
      fake = FakeLight(id: 'swiatlo-0c4f21', name: 'Parter', channels: 4)
        ..softAp = true
        ..pop = 'ab12cd34'
        ..cloudCapable = false;
      await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
      endpoint = LocalEndpoint('127.0.0.1', fake.port);
    });

    tearDown(() => fake.stop());

    test('/api/info: prov, pair, cloud, channels', () async {
      final info = await LocalApi(endpoint).info();
      expect((info.prov, info.pair, info.cloud, info.channels, info.inputs), (ProvScheme.softap, PairMethod.pop, false, 4, 8));
    });

    test('parowanie kodem PoP (wielkość liter bez znaczenia) - telefon dostaje control', () async {
      final store = MemoryDeviceStore();
      final pairing = PairingService(store: store, clientName: () async => 'Pixel');
      final info = await pairing.probe(endpoint);
      await pairing.start(endpoint);
      final d = await pairing.confirm(endpoint, info, 'AB12CD34');
      expect(d.access, AccessLevel.control);
    });

    test('kanały i wejścia: State/Config płasko, on/toggle = wszystkie, onN, toggleN, chN, inputK, błędy pól', () async {
      final api = LocalApi(endpoint, token: fake.token);
      var r = await api.setJson(const LightSet(channelOn: {2: true}, channelToggle: {3}).toJson());
      expect(r.errors, isEmpty);
      var s = LightState.fromJson(await api.stateJson());
      expect((s.channels, '${s.channelOn}', s.on, s.onCount), (4, '[false, true, true, false]', true, 2));

      r = await api.setJson(const LightSet(toggle: true).toJson());
      s = LightState.fromJson(await api.stateJson());
      expect(s.channelOn, [false, false, false, false], reason: 'coś świeciło → wszystko gaśnie');

      r = await api.setJson(const LightSet(channel: {2: ChannelPatch(name: 'Kinkiet', defaultOn: DefaultOn.off)}).toJson());
      final c = LightConfig.fromJson(await api.configJson());
      expect((c.channels[1].name, c.channels[1].defaultOn, c.channels.length), ('Kinkiet', DefaultOn.off, 4));
      expect(c.inputs.map((x) => x.out).toList(), [1, 2, 3, 4, 1, 2, 3, 4], reason: 'wejścia k i k+4 → kanał k');
      expect(c.inputs.first.mode, InputMode.momentary);

      r = await api.setJson({
        'ch2': {'defaultOn': 'zly'},
        'on2': 'tak',
        'input1': {'mode': 'detached'},
        'input2': {'out': 9},
      });
      expect(r.errors, {'ch2.defaultOn': 'value', 'on2': 'type', 'input1.mode': 'value', 'input2.out': 'range'});
      expect(describeErrors(r.errors), allOf(contains('Kanał 2 - po zaniku zasilania'), contains('Wejście 1 - tryb')));

      // Wejścia: nazwa, tryb, kanał; przełączanie lokalnie w węźle; describe z nazwą i kanałem.
      r = await api.setJson(
        const LightSet(
          input: {
            2: InputPatch(name: 'Schody dół', out: 3),
            4: InputPatch(name: 'Łącznik taras', mode: InputMode.follow),
          },
        ).toJson(),
      );
      expect(r.errors, isEmpty);
      final d = await api.describe();
      expect(d.point('on2')!.name, 'Kinkiet');
      expect((d.point('in2')!.name, d.point('in2')!.kind.name), ('Schody dół', 'status'));

      final before = LightState.fromJson(await api.stateJson()).channelOn[2];
      fake.press(2);
      var st = LightState.fromJson(await api.stateJson());
      expect((st.inputs.length, st.channelOn[2]), (8, !before), reason: 'przycisk przełącza kanał 3');
      fake.press(4);
      st = LightState.fromJson(await api.stateJson());
      expect((st.inputs[3], st.channelOn[3]), (true, true), reason: 'łącznik „położenie”: kanał = wejście');

      // Usterka wejścia (inNFault): wejście zablokowane, pole w State, brak pola = sprawne.
      fake.setInputFault(2, true);
      final before2 = LightState.fromJson(await api.stateJson()).channelOn[2];
      fake.press(2);
      st = LightState.fromJson(await api.stateJson());
      expect(('${st.inputFaults}', st.channelOn[2]), ('{2}', before2));
      expect(st.toJson()['in2Fault'], isTrue);
      fake.setInputFault(2, false);
      expect(LightState.fromJson(await api.stateJson()).inputFaults, isEmpty);
    });

    test('1.4: Config kanałów i wejść, describe (impuls, inputKind, kanały, temp), info, błędy pól', () async {
      final api = LocalApi(endpoint, token: fake.token);
      var r = await api.setJson(
        const LightSet(
          channel: {
            1: ChannelPatch(autoOff: 180, autoOffPress: 'extend'),
            2: ChannelPatch(name: 'Brama', pulse: 500),
            3: ChannelPatch(minOff: 60),
          },
          input: {
            1: InputPatch(outs: [1, 4], longOuts: [2]),
            3: InputPatch(kind: InputKind.contact, invert: true, out: 0),
            2: InputPatch(mode: InputMode.motion, kind: InputKind.motion),
          },
          indicatorOn: 80,
          tempWarn: 55,
          tempOff: 70,
        ).toJson(),
      );
      expect(r.errors, isEmpty);
      final cfgJson = await api.configJson();
      final c = LightConfig.fromJson(cfgJson);
      expect(
        (c.channels[0].autoOff, c.channels[0].autoOffPress, c.channels[1].isPulse, c.channels[2].minOff),
        (180, 'extend', true, 60),
      );
      expect(c.inputs[0].outs, [1, 4]);
      expect(c.inputs[0].longOuts, [2]);
      expect(c.inputs[0].out, 1);
      expect((c.inputs[2].kind, c.inputs[2].invert, c.inputs[2].outs.isEmpty), (InputKind.contact, true, true));
      expect(c.inputs[1].mode, InputMode.motion);
      expect((c.indicatorOn, c.indicatorOff, c.tempWarn, c.tempOff), (80, 5, 55, 70));
      expect(cfgJson['input1'], containsPair('out', [1, 4]));
      expect(cfgJson['input3'], containsPair('out', 0), reason: 'jeden kanał / żaden jako liczba');
      expect(LightConfig.fromJson(c.toJson()).toJson(), c.toJson());

      final d = await api.describe();
      expect((d.point('on1')!.kind, d.point('on2')!.kind), (PointKind.switchKind, PointKind.action));
      expect((d.point('temp')!.unit, d.point('overheat')!.kind), ('°C', PointKind.status));
      final raw = await api.describeJson();
      final in1 = (raw['points'] as List).firstWhere((p) => p['key'] == 'in1') as Map;
      expect(in1['inputKind'], 'button');
      expect(in1['channels'], [1, 4]);
      final http = HttpClient();
      final res = await (await http.getUrl(Uri.parse('http://127.0.0.1:${fake.port}/api/info'))).close();
      final info = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      http.close();
      expect((info['tempSensor'], info['wifiReconnects'], info['sensor']), (true, 0, 'ds18b20'));
      // DHT22 (1.4.2): wilgotność w State i describe.
      fake
        ..sensor = 'dht22'
        ..hum = 48;
      expect(LightState.fromJson(await api.stateJson()).hum, 48);
      expect((await api.describe()).point('hum')!.unit, '%');

      r = await api.setJson({
        'ch1': {'autoOff': -1, 'autoOffPress': 'x', 'pulse': 50, 'minOff': 4000},
        'input1': {
          'kind': 'kot',
          'out': [1, 9],
          'longOut': 'a',
          'invert': 1,
        },
        'indicator': {'on': 101},
        'tempWarn': 20,
        'tempOff': 'x',
      });
      expect(r.errors, {
        'ch1.autoOff': 'range',
        'ch1.autoOffPress': 'value',
        'ch1.pulse': 'range',
        'ch1.minOff': 'range',
        'input1.kind': 'value',
        'input1.out': 'range',
        'input1.longOut': 'type',
        'input1.invert': 'type',
        'indicator.on': 'range',
        'tempWarn': 'range',
        'tempOff': 'type',
      });
      expect(
        describeErrors(r.errors),
        allOf(
          contains('Kanał 1 - wyłączanie po czasie'),
          contains('Wejście 1 - długie naciśnięcie'),
          contains('Ostrzeżenie o temperaturze'),
        ),
      );
    });

    test('1.4: odliczanie autoOff, impuls, minimalna przerwa, przyciski, liczniki, przegrzanie, identify', () async {
      await fake.stop();
      var now = DateTime(2026, 10, 30, 12);
      fake = FakeLight(id: 'swiatlo-0c4f21', name: 'Parter', channels: 4, clock: () => now)..cloudCapable = false;
      await fake.start(port: 0, address: InternetAddress.loopbackIPv4);
      final api = LocalApi(LocalEndpoint('127.0.0.1', fake.port), token: fake.token);
      Future<LightState> state() async => LightState.fromJson(await api.stateJson());
      void after(int seconds) {
        now = now.add(Duration(seconds: seconds));
        fake.tickCountdowns();
      }

      await api.setJson(
        const LightSet(
          channel: {
            1: ChannelPatch(autoOff: 180, autoOffPress: 'extend'),
            2: ChannelPatch(pulse: 500),
            3: ChannelPatch(minOff: 60),
          },
          input: {
            1: InputPatch(longOuts: [4]),
            2: InputPatch(mode: InputMode.motion, out: 1),
          },
        ).toJson(),
      );

      // Wyłączanie po czasie: odliczanie w State, krótkie naciśnięcie odlicza od nowa, długie wyłącza.
      await api.setJson({'on1': true});
      expect((await state()).offIn, {1: 180});
      after(100);
      expect((await state()).offIn[1], 80);
      fake.press(1);
      expect((await state()).offIn[1], 180, reason: 'extend: od nowa');
      after(180);
      var s = await state();
      expect((s.channelOn[0], s.offIn.containsKey(1)), (false, false));
      fake.press(2); // czujka ruchu włącza
      expect((await state()).channelOn[0], isTrue);
      fake.press(1, true); // długie: longOut = kanał 4
      s = await state();
      expect((s.channelOn[0], s.channelOn[3]), (true, true), reason: 'longOut ma pierwszeństwo przed „długie = wyłącz”');

      // Impuls: włączenie na 0,5 s.
      await api.setJson({'on2': true});
      s = await state();
      expect((s.channelOn[1], s.offIn[2]), (true, 1));
      now = now.add(const Duration(milliseconds: 600));
      fake.tickCountdowns();
      expect((await state()).channelOn[1], isFalse);

      // Minimalna przerwa: włączenie zaraz po wyłączeniu czeka, „przełącz” rezygnuje.
      await api.setJson({'on3': true});
      await api.setJson({'on3': false});
      after(10);
      await api.setJson({'on3': true});
      s = await state();
      expect((s.channelOn[2], s.waitIn[3]), (false, 50));
      after(50);
      expect((await state()).channelOn[2], isTrue);
      await api.setJson({'on3': false});
      await api.setJson({'on3': true});
      await api.setJson({'toggle3': true});
      s = await state();
      expect((s.channelOn[2], s.waitIn.containsKey(3)), (false, false));

      // Liczniki i zerowanie.
      expect((s.cycles[2], s.cycles[3]), (1, 2));
      await api.setJson(const LightSet(channel: {3: ChannelPatch(resetCounters: true)}).toJson());
      s = await state();
      expect((s.cycles[3], s.hours[3]), (0, 0.0));

      // Przegrzanie: ostrzeżenie, potem wyłączenie wszystkiego i blokada do spadku o 5 °C.
      await api.setJson({'tempOff': 70});
      fake.setTemp(61);
      s = await state();
      expect((s.overheat, s.overheatOff, s.temp), (true, false, 61.0));
      fake.setTemp(72);
      s = await state();
      expect((s.overheatOff, s.on), (true, false));
      final r = await api.setJson({'on4': true});
      expect(r.errors, {'on4': 'overheat'});
      expect(describeErrors(r.errors), contains('przegrzane'));
      fake.setTemp(66);
      expect((await state()).overheatOff, isTrue);
      fake.setTemp(64);
      s = await state();
      expect((s.overheatOff, s.overheat), (false, true));

      // „Pokaż, który to” - poziom control.
      final guest = LocalApi(LocalEndpoint('127.0.0.1', fake.port), token: fake.addPhone('Gość', access: 'control'));
      expect((await guest.setJson(const LightSet(identify: true).toJson())).errors, isEmpty);
      expect(fake.identifyCount, 1);
      expect(requiredLevelFor({'identify': true}), AccessLevel.control);
    });

    test('poziom control wystarcza dla onN / toggleN, nie dla chN', () async {
      expect(requiredLevelFor({'on2': true, 'toggle3': true}), AccessLevel.control);
      expect(requiredLevelFor({'ch2': {'name': 'x'}}), AccessLevel.config);
      final api = LocalApi(endpoint, token: fake.addPhone('Gość', access: 'control'));
      final r = await api.setJson({'on1': true, 'ch1': {'name': 'x'}});
      expect(r.errors, {'ch1': 'forbidden'});
    });
  });
}
