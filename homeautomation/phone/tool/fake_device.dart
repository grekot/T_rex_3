// Atrapa urządzenia HomeAutomation (kontrakt v2) do testów aplikacji bez sprzętu.
//
//   dart run tool/fake_device.dart [--type thermostat|switch|dimmer|hub] [--port 8080]
//       [--id termostat-ab12cd] [--name Salon] [--token <hex>] [--no-mdns] [--fast]
//       [--channels 4] [--prov softap] [--pop ab12cd34] [--no-cloud]
//
// Węzeł switch4 (pkt 9.4, 10.1): --type switch --channels 4 --prov softap --pop ab12cd34 --no-cloud
// (wielokanałowy ma 2 wejścia na kanał: wejścia k i k+N → kanał k)
//
// Kilka urządzeń naraz: osobne procesy z innym --port i --id.
// Klawisze (Enter po każdym): k/j = gałka +/-0,5 (termostat), f = awaria czujnika (termostat),
// w = przycisk na ścianie (światło; w1..w8 = wejście węzła wielokanałowego), b = zajęty (503 busy), p = kod parowania, s = stan, t = token, q = koniec.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'fake/fake_thermostat_server.dart';
import 'fake/mdns_responder.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('type', defaultsTo: 'thermostat', allowed: ['thermostat', 'switch', 'dimmer', 'hub'], help: 'Typ urządzenia')
    ..addOption('port', defaultsTo: '8080', help: 'Port HTTP/WebSocket')
    ..addOption('id', help: 'Identyfikator (domyślnie termostat-ab12cd / swiatlo-0c4f21)')
    ..addOption('name', help: 'Nazwa urządzenia')
    ..addOption('token', help: 'Stały token (64 hex); domyślnie losowy przy każdym starcie')
    ..addFlag('mdns', defaultsTo: true, help: 'Ogłaszaj się przez mDNS (_homeauto._tcp)')
    ..addFlag('fast', help: 'Stan co 5 s zamiast co 30 s')
    ..addOption('channels', defaultsTo: '1', help: 'Kanały przełącznika (pkt 10.1)')
    ..addOption('prov', defaultsTo: 'ble', allowed: ['ble', 'softap'], help: 'Konfiguracja WiFi (pkt 9.4)')
    ..addOption('pop', help: 'Kod PoP z naklejki - parowanie kodem PoP zamiast 6 cyfr (pkt 2)')
    ..addFlag('cloud', defaultsTo: true, help: 'Obsługa /api/cloud (--no-cloud = węzeł klasy B)')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(argv);
  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final type = args.option('type')!;
  final period = Duration(seconds: args.flag('fast') ? 5 : 30);
  final FakeDevice fake = type == 'hub'
      ? FakeHub(
          id: args.option('id') ?? 'hub-51e96c',
          name: args.option('name') ?? 'Hub',
          token: args.option('token'),
          statePeriod: period,
          log: stdout.writeln,
        )
      : type == 'thermostat'
      ? FakeThermostat(
          id: args.option('id') ?? 'termostat-ab12cd',
          name: args.option('name') ?? 'Salon',
          token: args.option('token'),
          statePeriod: period,
          log: stdout.writeln,
        )
      : FakeLight(
          id: args.option('id') ?? 'swiatlo-0c4f21',
          name: args.option('name') ?? 'Salon - sufit',
          dimmable: type == 'dimmer',
          channels: int.parse(args.option('channels')!),
          token: args.option('token'),
          statePeriod: period,
          log: stdout.writeln,
        );
  fake
    ..softAp = args.option('prov') == 'softap'
    ..pop = args.option('pop')
    ..cloudCapable = args.flag('cloud');
  await fake.start(port: int.parse(args.option('port')!));

  final ips = [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses)
        if (!a.isLoopback) a.address,
  ];
  stdout
    ..writeln('Atrapa ${fake.typeWire} ${fake.id} („${fake.deviceName}”) słucha na porcie ${fake.port}')
    ..writeln('Adresy: ${ips.map((ip) => '$ip:${fake.port}').join(', ')}')
    ..writeln('Emulator Androida: 10.0.2.2:${fake.port}')
    ..writeln('Token: ${fake.token}');

  MdnsResponder? mdns;
  if (args.flag('mdns')) {
    mdns = MdnsResponder(
      instance: fake.id,
      port: fake.port,
      txt: {
        'id': fake.id,
        'type': fake.typeWire,
        'api': '2',
        'fw': fake.fw,
        if (fake.softAp) 'prov': 'softap',
        if (fake.channelCount > 1) 'ch': '${fake.channelCount}',
      },
      log: stdout.writeln,
    );
    await mdns.start();
  }
  stdout.writeln(
    'Klawisze: k/j gałka · f awaria · w / w1..w8 przycisk / wejście · x1..x8 usterka wejścia · b zajęty · p kod · s stan · t token · q koniec',
  );

  late StreamSubscription<String> sub;
  Future<void> quit() async {
    mdns?.stop();
    await fake.stop();
    await sub.cancel();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => quit());
  sub = stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    switch ((line.trim(), fake)) {
      case ('k', final FakeThermostat t):
        t.knob(0.5);
      case ('j', final FakeThermostat t):
        t.knob(-0.5);
      case ('f', final FakeThermostat t):
        t.toggleFault();
        stdout.writeln('Awaria czujnika: ${t.sensorFault ? 'TAK' : 'nie'}');
      case ('w', final FakeLight l):
        l.press();
        stdout.writeln('Światło: ${l.on ? 'włączone' : 'wyłączone'}');
      case (final String c, final FakeLight l) when RegExp(r'^x[1-9]$').hasMatch(c) && l.multi:
        final k = int.parse(c.substring(1));
        if (k <= l.inputs) {
          l.setInputFault(k, !l.inFault.contains(k));
          stdout.writeln('Wejście $k: ${l.inFault.contains(k) ? 'USTERKA (zablokowane)' : 'sprawne'}');
        }
      case (final String c, final FakeLight l) when RegExp(r'^w[1-9]$').hasMatch(c) && l.multi:
        final k = int.parse(c.substring(1));
        if (k <= l.inputs) {
          l.press(k);
          stdout.writeln('Wejście $k → kanały: ${[for (final o in l.chOn) o ? 'wł' : '-'].join(' ')}');
        }
      case ('b', _):
        fake.busy = !fake.busy;
        stdout.writeln('Zajęty (busy): ${fake.busy ? 'TAK' : 'nie'}');
      case ('p', _):
        stdout.writeln('Kod parowania: ${fake.pairCode ?? '(brak - aplikacja jeszcze nie zaczęła parowania)'}');
      case ('s', _):
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(fake.stateJson()));
      case ('t', _):
        stdout.writeln('Token: ${fake.token}');
      case ('q', _):
        quit();
    }
  });
}
