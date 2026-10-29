// Urządzenia bez Bluetooth (pkt 9.4: SoftAP + HTTP, ciasteczko sesji), parowanie kodem PoP (pkt 2)
// i przełącznik wielokanałowy (pkt 10.1) na atrapie węzła `switch4`. Prawdziwe gniazda - bez testWidgets
// (kreator SoftAP: softap_ui_test.dart).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/field_errors.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/data/pairing.dart';
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

    test('poziom control wystarcza dla onN / toggleN, nie dla chN', () async {
      expect(requiredLevelFor({'on2': true, 'toggle3': true}), AccessLevel.control);
      expect(requiredLevelFor({'ch2': {'name': 'x'}}), AccessLevel.config);
      final api = LocalApi(endpoint, token: fake.addPhone('Gość', access: 'control'));
      final r = await api.setJson({'on1': true, 'ch1': {'name': 'x'}});
      expect(r.errors, {'ch1': 'forbidden'});
    });
  });
}
