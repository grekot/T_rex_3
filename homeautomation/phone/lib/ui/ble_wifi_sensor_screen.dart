// „Dodaj czujnik WiFi (zasilanie USB)” (kontrakt pkt 15.7): czujnik `btsensor` 1.3.0+ pracuje prosto przez WiFi
// do huba (0.3.35+), bez bramki Bluetooth. Przebieg: najpierw ekran, potem zasilanie czujnika (okno konfiguracji 3 min)
// → `HA_ble-*` z sygnałem ≥ −60 dBm → sesja security 1 bez PoP → `ha-pair` z adresem huba → sieć i hasło → po
// `connected` dopiero szukanie w hubie (`POST /api/ble/scan`) → czujnik w `paired`: nowy - nazwa i `POST /api/devices`,
// już dodany - `POST /api/devices` z dotychczasową nazwą (nowy klucz, ten sam wpis); albo już dodany z `link: "wifi"`
// bez `error: "key"` (klucz bez zmian).

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cloud_access.dart' show writeDeviceIndex;
import '../data/errors.dart';
import '../data/hub_api.dart';
import '../data/pairing.dart';
import '../models/device_type.dart';
import '../models/hub.dart';
import '../provisioning/ble_transport.dart';
import '../provisioning/messages.dart';
import '../provisioning/provisioner.dart';
import '../services.dart';
import 'wifi_chooser.dart';

/// Nazwa czujnika w trybie konfiguracji WiFi (`HA_ble-<mac>`).
const bleSensorProvPrefix = 'HA_ble-';

/// Najsłabszy sygnał czujnika, który bierzemy (security 1 bez PoP - tylko czujnik tuż obok telefonu).
const bleSensorMinRssi = -60;

enum _Step { intro, scan, connecting, wifi, joining, hub, name, done }

class BleWifiSensorScreen extends StatefulWidget {
  const BleWifiSensorScreen({
    super.key,
    required this.api,
    required this.hubId,
    required this.hubIp,
    required this.canLink,
    this.interval = const Duration(milliseconds: 1500),
    this.hubTimeout = const Duration(minutes: 3),
  });

  final HubApi api;
  final String hubId;

  /// Adres huba w sieci domowej - czujnik wysyła na niego datagramy.
  final String hubIp;
  final bool canLink;
  final Duration interval;

  /// Jak długo czekać na czujnik w hubie po połączeniu z siecią.
  final Duration hubTimeout;

  @override
  State<BleWifiSensorScreen> createState() => _BleWifiSensorScreenState();
}

class _BleWifiSensorScreenState extends State<BleWifiSensorScreen> {
  _Step _step = _Step.intro;
  String? _error;
  String? _progress;

  StreamSubscription<List<ProvCandidate>>? _scanSub;
  List<ProvCandidate> _found = const [];
  bool _scanning = false;

  ProvTransport? _transport;
  Provisioner? _prov;
  SensorPairResult? _pair;

  List<WifiNetwork> _networks = const [];
  bool _canScan = true;
  WifiNetwork? _network;
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  /// Czujnik był już w hubie (po `paired` dopisywany ponownie z dotychczasową nazwą).
  bool _existing = false;
  String? _existingName;
  BlePaired? _paired;
  bool _added = false;
  bool _hubScanning = false;

  @override
  void dispose() {
    _scanSub?.cancel();
    unawaited(_transport?.close());
    if (_hubScanning) unawaited(widget.api.bleStop().catchError((_) {}));
    _ssid.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _startScan() {
    final backend = Services.of(context).provisioning;
    _scanSub?.cancel();
    setState(() {
      _step = _Step.scan;
      _scanning = true;
      _error = backend.supported ? null : 'Bluetooth działa tylko w aplikacji na telefonie.';
      _found = const [];
    });
    if (!backend.supported) return;
    _scanSub = backend.scan().listen(
      (list) {
        final sensors = [
          for (final c in list)
            if (c.name.startsWith(bleSensorProvPrefix)) c,
        ];
        setState(() => _found = sensors);
        // Jeden czujnik tuż obok - od razu; kilka - użytkownik wybiera (pkt 15.7).
        final near = sensors.where((c) => c.rssi >= bleSensorMinRssi).toList();
        if (near.length == 1 && sensors.length == 1 && _step == _Step.scan) unawaited(_connect(near.single));
      },
      onError: (Object e) => setState(() => _error = '$e'),
      onDone: () => setState(() => _scanning = false),
    );
  }

  Future<void> _connect(ProvCandidate c) async {
    await _scanSub?.cancel();
    if (!mounted) return;
    final services = Services.of(context);
    setState(() {
      _step = _Step.connecting;
      _scanning = false;
      _error = null;
      _progress = 'Łączenie z czujnikiem przez Bluetooth…';
    });
    try {
      await _transport?.close();
      final transport = await services.provisioning.connect(c);
      _transport = transport;
      // Security 1 bez PoP (pkt 15.7) - czujnik bez ekranu i naklejki.
      final prov = Provisioner(transport, '');
      try {
        await prov.start();
      } on ProvisioningException {
        throw const ProvisioningException(
          'Czujnik wymaga kodu z naklejki - ta wersja aplikacji go jeszcze nie obsługuje.',
        );
      }
      _prov = prov;
      setState(() => _progress = 'Przekazuję czujnikowi adres huba…');
      _pair = await prov.haPairSensor(
        await (services.pairing.clientName ?? defaultClientName)(),
        hubId: widget.hubId,
        hubIp: widget.hubIp,
      );
      _canScan = services.provisioning.canScan(transport);
      if (_canScan) {
        setState(() => _progress = 'Czujnik szuka sieci WiFi…');
        _networks = await prov.scanWifi();
      }
      setState(() {
        _step = _Step.wifi;
        _progress = null;
      });
    } on Object catch (e) {
      await _transport?.close();
      _transport = null;
      if (!mounted) return;
      setState(() {
        _step = _Step.scan;
        _progress = null;
        _error = e is ProvisioningException ? e.message : 'Nie udało się połączyć: $e';
      });
    }
  }

  Future<void> _join() async {
    final ssid = (_network?.ssid ?? _ssid.text).trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'Wybierz sieć albo wpisz jej nazwę.');
      return;
    }
    setState(() {
      _step = _Step.joining;
      _error = null;
      _progress = 'Czujnik łączy się z siecią $ssid…';
    });
    try {
      await _prov!.setWifi(ssid, _password.text);
      await _prov!.waitForConnection();
    } on Object catch (e) {
      setState(() {
        _step = _Step.wifi;
        _progress = null;
        _error = e is ProvisioningException ? e.message : 'Błąd konfiguracji WiFi: $e';
      });
      return;
    }
    // Czujnik wyłącza teraz konfigurację i od następnego cyklu wysyła datagramy do huba.
    await _transport?.close();
    _transport = null;
    await _waitForHub();
  }

  static String _norm(String mac) => mac.replaceAll(':', '').toLowerCase();

  /// Dopiero po `connected` szukanie w hubie (wcześniej hub sparowałby czujnik przez bramkę, pkt 15.7).
  Future<void> _waitForHub() async {
    final pair = _pair!;
    setState(() {
      _step = _Step.hub;
      _error = null;
      _progress = 'Czujnik połączył się z siecią. Czekam, aż odezwie się do huba (do 3 min)…';
    });
    try {
      final old = (await widget.api.devices()).where((d) => d.id == pair.id).firstOrNull;
      _existing = old != null;
      _existingName = old?.name;
      await widget.api.bleScan(seconds: widget.hubTimeout.inSeconds);
      _hubScanning = true;
      final deadline = DateTime.now().add(widget.hubTimeout);
      while (mounted) {
        // Czujnik po provisioningu zwykle paruje się od nowa (0x13 z nowym kluczem) - także już dodany: hub trzyma
        // wtedy klucz jako oczekujący (`error: "key"`), dopóki aplikacja nie dopisze czujnika ponownie.
        final seen = await widget.api.bleSeen();
        final p = seen.paired.where((p) => _norm(p.mac) == _norm(pair.mac)).firstOrNull;
        if (p != null) {
          _paired = p;
          break;
        }
        if (_existing) {
          final d = (await widget.api.devices()).where((d) => d.id == pair.id).firstOrNull;
          if (d != null && d.state['link'] == 'wifi' && d.error != 'key') break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw const ThermostatException(
            'Czujnik nie odezwał się do huba. Sprawdź, czy hub jest w tej samej sieci, i podłącz zasilanie '
            'czujnika ponownie - okno konfiguracji otworzy się od nowa.',
          );
        }
        await Future<void>.delayed(widget.interval);
      }
      _hubScanning = false;
      await widget.api.bleStop().catchError((_) {});
      // Już dodany z nowym kluczem: ten sam wpis (to samo id) z dotychczasową nazwą - historia, pulpity
      // i automatyki zostają; bez pytania o nazwę.
      if (_existing && _paired != null && mounted) {
        await _register(_existingName ?? pair.id, index: false);
      }
    } on ThermostatException catch (e) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        _error = e.message;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _progress = null;
      _step = _existing ? _Step.done : _Step.name;
      if (_existing) _added = true;
    });
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _error = null);
    try {
      await _register(name);
      if (mounted) setState(() => _step = _Step.done);
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Dopisanie czujnika z `paired` do huba (`POST /api/devices`); [index] - wpis w `deviceIndex` (nowy czujnik).
  Future<void> _register(String name, {bool index = true}) async {
    final cloud = Services.of(context).cloud;
    final id = await widget.api.addDevice({
      'adapter': HubAdapter.ble.wire,
      'deviceId': _paired!.mac,
      'paired': true,
      'name': name,
    });
    if (index && widget.canLink) {
      await writeDeviceIndex(cloud.store, cloud.homeId!, id, DeviceType.sensor, name, via: widget.hubId);
    }
    _added = true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step != _Step.connecting && _step != _Step.joining) Navigator.of(context).pop(_added);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Czujnik WiFi (zasilanie USB)')),
        body: ListView(padding: const EdgeInsets.all(16), children: _content(context)),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              key: const Key('bleWifiError'),
              style: TextStyle(color: cs.error),
            ),
          );
    final progress = _progress == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_progress!, textAlign: TextAlign.center),
              ],
            ),
          );

    switch (_step) {
      case _Step.intro:
        return [
          Text(
            'Czujnik btsensor może pracować prosto przez WiFi do huba - bez bramki Bluetooth w zasięgu.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 16),
          Card(
            color: cs.tertiaryContainer,
            child: ListTile(
              key: const Key('bleWifiBattery'),
              leading: Icon(Icons.battery_alert_outlined, color: cs.onTertiaryContainer),
              title: Text('Tylko z zasilaniem USB', style: TextStyle(color: cs.onTertiaryContainer)),
              subtitle: Text(
                'Przez WiFi czujnik zużywa dużo więcej prądu: 2 × AAA wystarczą na ok. 2-3 tygodnie.',
                style: TextStyle(color: cs.onTertiaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: CircleAvatar(child: Text('1')),
            title: Text('Najpierw stuknij „Szukaj czujnika”'),
            subtitle: Text('Czujnik jeszcze bez zasilania. Zbliż telefon do czujnika.'),
          ),
          const ListTile(
            leading: CircleAvatar(child: Text('2')),
            title: Text('Potem podłącz zasilanie USB czujnika'),
            subtitle: Text('Przez 3 min czujnik czeka na konfigurację WiFi (już działający - wyjmij i włóż wtyczkę).'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('bleWifiStart'),
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Szukaj czujnika'),
            onPressed: _startScan,
          ),
        ];

      case _Step.scan:
        return [
          Text('Teraz podłącz zasilanie USB czujnika.', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Telefon trzymaj tuż obok czujnika - bierzemy tylko czujnik z silnym sygnałem.', style: t.bodySmall),
          const SizedBox(height: 12),
          ListTile(
            leading: _scanning
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bluetooth_searching),
            title: Text(_scanning ? 'Szukam czujnika w trybie konfiguracji…' : 'Wyszukiwanie zakończone'),
            trailing: _scanning
                ? null
                : TextButton(
                    key: const Key('bleWifiAgain'),
                    onPressed: _startScan,
                    child: const Text('Szukaj ponownie'),
                  ),
          ),
          if (_found.length > 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Kilka czujników czeka na konfigurację - wybierz swój.'),
            ),
          for (final c in _found)
            ListTile(
              key: Key('bleWifi-${c.id}'),
              enabled: c.rssi >= bleSensorMinRssi,
              leading: const CircleAvatar(child: Icon(Icons.sensors)),
              title: Text(c.id),
              subtitle: Text(
                c.rssi >= bleSensorMinRssi
                    ? 'Sygnał ${c.rssi} dBm'
                    : 'Za daleko (${c.rssi} dBm) - zbliż telefon do czujnika',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _connect(c),
            ),
          ?error,
        ];

      case _Step.connecting || _Step.joining:
        return [?progress];

      case _Step.wifi:
        return [
          Text('Sieć WiFi dla ${_pair!.id}', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Czujnik obsługuje sieci 2,4 GHz. Hub musi być w tej samej sieci.', style: t.bodySmall),
          const SizedBox(height: 8),
          WifiChooser(
            networks: _networks,
            network: _network,
            onNetwork: (n) => setState(() => _network = n),
            ssid: _ssid,
            password: _password,
            onSubmit: _join,
            canScan: _canScan,
          ),
          ?error,
          FilledButton(key: const Key('bleWifiJoin'), onPressed: _join, child: const Text('Połącz')),
        ];

      case _Step.hub:
        return [
          ?progress,
          ?error,
          if (_error != null)
            FilledButton(key: const Key('bleWifiHubRetry'), onPressed: _waitForHub, child: const Text('Czekaj dalej')),
        ];

      case _Step.name:
        return [
          Text('Czujnik ${_pair!.id} pracuje przez WiFi.', style: t.titleMedium),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bleWifiName'),
            controller: _name,
            autofocus: true,
            maxLength: 32,
            decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'np. Salon, Sypialnia'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _add(),
          ),
          ?error,
          FilledButton(
            key: const Key('bleWifiAdd'),
            onPressed: _name.text.trim().isEmpty ? null : _add,
            child: const Text('Dodaj do huba'),
          ),
        ];

      case _Step.done:
        return [
          Icon(Icons.check_circle, size: 64, color: cs.primary),
          const SizedBox(height: 12),
          Text(
            _existing
                ? '${_existingName ?? _pair!.id} pracuje teraz przez WiFi.'
                : 'Dodano ${_name.text.trim()} - czujnik pracuje przez WiFi.',
            key: const Key('bleWifiDone'),
            textAlign: TextAlign.center,
            style: t.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Odczyty przychodzą co minutę. Powrót na Bluetooth: ekran czujnika → „Wróć na Bluetooth”.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).pop(_added), child: const Text('Zakończ')),
        ];
    }
  }
}
