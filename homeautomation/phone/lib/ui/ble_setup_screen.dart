import 'dart:async';

import 'package:flutter/material.dart';

import '../data/device_store.dart';
import '../data/errors.dart';
import '../data/local_api.dart';
import '../data/local_endpoint.dart';
import '../data/pairing.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../provisioning/ble_transport.dart';
import '../provisioning/messages.dart';
import '../provisioning/prov_qr.dart';
import '../provisioning/provisioner.dart';
import '../services.dart';

enum _Step { scan, pop, connecting, wifi, joining, finding, done }

/// Nowe urządzenie przez Bluetooth (kontrakt pkt 9.2): skan `HA_*` → kod PoP → sesja security 1 →
/// `ha-pair` (token, urządzenie od razu sparowane) → sieć WiFi i hasło → połączenie → mDNS.
/// [softAp] - urządzenie bez Bluetooth (pkt 9.4): telefon łączy się z siecią WiFi `HA_<id>` (hasło = PoP),
/// a te same komunikaty idą przez HTTP. Z [expectedId] - zmiana sieci znanego urządzenia (pkt 9.3).
/// Z [qr] (kod z naklejki, pkt 9.1) - bez wybierania z listy i wpisywania PoP: łączy się od razu z urządzeniem
/// o nazwie z kodu. Zwraca [PairedDevice].
class BleSetupScreen extends StatefulWidget {
  const BleSetupScreen({super.key, this.expectedId, this.softAp = false, this.qr});

  final String? expectedId;
  final bool softAp;
  final ProvQr? qr;

  @override
  State<BleSetupScreen> createState() => _BleSetupScreenState();
}

class _BleSetupScreenState extends State<BleSetupScreen> {
  late _Step _step = widget.softAp ? _Step.pop : _Step.scan;

  /// SoftAP: użytkownik połączył się z siecią `HA_*` sam, w ustawieniach WiFi.
  bool _manualAp = false;
  String? _error;
  String? _progress;

  StreamSubscription<List<ProvCandidate>>? _scanSub;
  List<ProvCandidate> _found = const [];
  bool _scanning = false;

  ProvCandidate? _candidate;
  final _pop = TextEditingController();
  ProvTransport? _transport;
  Provisioner? _prov;
  HaPairResult? _pair;
  PairedDevice? _device;

  List<WifiNetwork> _networks = const [];
  bool _canScan = true;
  WifiNetwork? _network;
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final qr = widget.qr;
    if (qr != null) {
      _pop.text = qr.pop;
      // SoftAP: od razu do sieci z kodu; BLE: łączy się, gdy skan znajdzie urządzenie o nazwie z kodu.
      if (widget.softAp) WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scanSub == null && !_scanning && !widget.softAp) _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    unawaited(_transport?.close());
    _pop.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _changingWifi => widget.expectedId != null;

  void _startScan() {
    final backend = Services.of(context).provisioning;
    _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _error = backend.supported ? null : 'Bluetooth działa tylko w aplikacji na telefonie.';
      _found = const [];
    });
    if (!backend.supported) return;
    _scanSub = backend.scan().listen(
      (list) {
        final qr = widget.qr;
        if (qr != null) {
          final match = list.where((c) => c.name == qr.name).firstOrNull;
          if (match != null && _step == _Step.scan) {
            _choose(match);
            unawaited(_connect());
          }
          return;
        }
        final filtered = _changingWifi ? list.where((c) => c.id == widget.expectedId).toList() : list;
        setState(() => _found = filtered);
      },
      onError: (Object e) => setState(() => _error = '$e'),
      onDone: () => setState(() => _scanning = false),
    );
  }

  void _choose(ProvCandidate c) {
    _scanSub?.cancel();
    setState(() {
      _candidate = c;
      _scanning = false;
      _error = null;
      _step = _Step.pop;
    });
  }

  Future<void> _connect() async {
    // SoftAP: PoP z naklejki to 8 znaków hex małymi literami - hasło sieci HA_* i klucz security 1 (pkt 9.4).
    final pop = widget.softAp ? _pop.text.trim().toLowerCase() : _pop.text.trim();
    if (pop.isEmpty) {
      setState(() => _error = 'Wpisz kod z ekranu urządzenia.');
      return;
    }
    final services = Services.of(context);
    setState(() {
      _step = _Step.connecting;
      _error = null;
      _progress = widget.softAp ? 'Łączenie z siecią WiFi urządzenia…' : 'Łączenie przez Bluetooth…';
    });
    try {
      await _transport?.close();
      final transport = widget.softAp
          ? await services.softAp.connect(
              pop: pop,
              deviceId: widget.expectedId ?? widget.qr?.id,
              manual: _manualAp,
            )
          : await services.provisioning.connect(_candidate!);
      _transport = transport;
      final prov = Provisioner(transport, pop);
      setState(() => _progress = 'Sprawdzanie kodu…');
      await prov.start();
      _prov = prov;

      setState(() => _progress = 'Parowanie…');
      // Z kontem token telefonu jest przypisany do osoby (pkt 9.2); telefon konfigurujący ma `config`.
      final pair = await prov.haPair(
        await (services.pairing.clientName ?? defaultClientName)(),
        uid: services.cloud.uid,
      );
      if (_changingWifi && pair.id != widget.expectedId) {
        throw ProvisioningException('To inne urządzenie (${pair.id}) niż oczekiwane (${widget.expectedId}).');
      }
      _pair = pair;
      await services.store.saveToken(pair.id, pair.token);
      final existing = (await services.store.devices()).where((d) => d.id == pair.id).firstOrNull;
      final device = (existing ?? PairedDevice(id: pair.id, name: pair.id)).copyWith(
        type: DeviceType.fromWire(pair.type),
        access: AccessLevel.fromWire(pair.access),
      );
      await services.store.saveDevice(device);
      _device = device;

      _canScan = widget.softAp || services.provisioning.canScan(transport);
      if (_canScan) {
        setState(() => _progress = 'Urządzenie szuka sieci WiFi…');
        _networks = await prov.scanWifi();
      }
      setState(() {
        _step = _Step.wifi;
        _progress = null;
      });
    } on Object catch (e) {
      await _transport?.close();
      _transport = null;
      setState(() {
        _step = _Step.pop;
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
    final prov = _prov!;
    setState(() {
      _step = _Step.joining;
      _error = null;
      _progress = 'Urządzenie łączy się z siecią $ssid…';
    });
    WifiStatus status;
    try {
      await prov.setWifi(ssid, _password.text);
      status = await prov.waitForConnection(retries: widget.softAp ? 6 : 0);
    } on Object catch (e) {
      setState(() {
        _step = _Step.wifi;
        _progress = null;
        _error = e is ProvisioningException ? e.message : 'Błąd konfiguracji WiFi: $e';
      });
      return;
    }
    // Urządzenie wyłącza teraz Bluetooth (SoftAP: swoją sieć i restartuje się, ~3 s); dalej szukamy go w sieci.
    await _transport?.close();
    _transport = null;
    if (widget.softAp) {
      setState(() => _progress = 'Telefon wraca do sieci domowej…');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    await _find(status.ip);
  }

  Future<void> _find(String? ip) async {
    final services = Services.of(context);
    final id = _pair!.id;
    setState(() {
      _step = _Step.finding;
      _progress = 'Szukanie urządzenia w sieci domowej…';
    });
    LocalEndpoint? endpoint = (await services.discovery.find(id, timeout: const Duration(seconds: 20)))?.endpoint;
    if (endpoint == null && ip != null && ip.isNotEmpty) endpoint = LocalEndpoint(ip);
    var device = _device!;
    if (endpoint != null) {
      try {
        final info = await LocalApi(endpoint).info(timeout: const Duration(seconds: 3));
        device = device.copyWith(
          lastEndpoint: endpoint,
          name: info.name.isNotEmpty ? info.name : null,
          type: info.type,
        );
      } on ThermostatException {
        device = device.copyWith(lastEndpoint: endpoint);
      }
      await services.store.saveDevice(device);
    }
    if (!mounted) return;
    setState(() {
      _device = device;
      _step = _Step.done;
      _progress = null;
      _error = endpoint == null
          ? 'Urządzenie jest skonfigurowane, ale jeszcze go nie widać w sieci. Aplikacja połączy się z nim, gdy się pojawi.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _Step.connecting && _step != _Step.joining,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_changingWifi ? 'Zmiana sieci WiFi' : (widget.softAp ? 'Urządzenie bez Bluetootha' : 'Nowe urządzenie')),
        ),
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
              key: const Key('bleError'),
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
      case _Step.scan:
        return [
          Text(
            _changingWifi
                ? 'Urządzenie ${widget.expectedId} uruchamia się w trybie konfiguracji. '
                      'Gdy na jego ekranie pojawi się DODAJ W APLIKACJI, pojawi się też tutaj.'
                : 'Włącz urządzenie. W trybie konfiguracji (pierwsze uruchomienie albo po zmianie sieci) '
                      'pokazuje DODAJ W APLIKACJI i 8-znakowy kod.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: _scanning
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bluetooth_searching),
            title: Text(
              widget.qr != null
                  ? (_scanning ? 'Szukam ${widget.qr!.name} przez Bluetooth…' : 'Nie znaleziono ${widget.qr!.name}')
                  : (_scanning ? 'Szukam urządzeń przez Bluetooth…' : 'Wyszukiwanie zakończone'),
            ),
            trailing: _scanning ? null : TextButton(onPressed: _startScan, child: const Text('Szukaj ponownie')),
          ),
          for (final c in _found)
            ListTile(
              key: Key('ble-${c.id}'),
              leading: const CircleAvatar(child: Icon(Icons.bluetooth)),
              title: Text(c.id),
              subtitle: Text('Sygnał ${c.rssi} dBm'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _choose(c),
            ),
          ?error,
        ];

      case _Step.pop when widget.softAp:
        return [
          Text(
            _changingWifi ? 'Sieć urządzenia ${widget.expectedId}' : 'Kod z naklejki urządzenia',
            style: t.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Urządzenie w trybie konfiguracji (pierwsze uruchomienie, po zmianie sieci albo przycisk '
            'przytrzymany 3 s) wystawia własną sieć WiFi HA_… Wpisz 8 znaków kodu z jego naklejki - '
            'to hasło tej sieci. Telefon połączy się z nią na chwilę (bez internetu) i wróci do sieci domowej.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('pop'),
            controller: _pop,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textAlign: TextAlign.center,
            maxLength: 32,
            style: t.headlineSmall?.copyWith(letterSpacing: 4),
            decoration: const InputDecoration(hintText: 'kod z naklejki', counterText: '', border: OutlineInputBorder()),
            onSubmitted: (_) => _connect(),
          ),
          CheckboxListTile(
            key: const Key('manualAp'),
            contentPadding: EdgeInsets.zero,
            value: _manualAp,
            onChanged: (v) => setState(() => _manualAp = v ?? false),
            title: const Text('Jestem już połączony z siecią HA_… (ręcznie)'),
            subtitle: const Text('Gdy telefon nie łączy się sam - np. Android starszy niż 10.'),
          ),
          ?error,
          const SizedBox(height: 16),
          FilledButton(key: const Key('popNext'), onPressed: _connect, child: const Text('Połącz')),
        ];

      case _Step.pop:
        return [
          Text('Kod z urządzenia ${_candidate!.id}', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Przepisz 8 znaków widocznych na ekranie urządzenia (urządzenia bez ekranu mają go na naklejce). '
            'Wielkość liter ma znaczenie.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('pop'),
            controller: _pop,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textAlign: TextAlign.center,
            maxLength: 32,
            style: t.headlineSmall?.copyWith(letterSpacing: 4),
            decoration: const InputDecoration(hintText: 'kod PoP', counterText: '', border: OutlineInputBorder()),
            onSubmitted: (_) => _connect(),
          ),
          ?error,
          const SizedBox(height: 16),
          FilledButton(key: const Key('popNext'), onPressed: _connect, child: const Text('Dalej')),
          TextButton(
            onPressed: () {
              setState(() => _step = _Step.scan);
              _startScan();
            },
            child: const Text('Wybierz inne urządzenie'),
          ),
        ];

      case _Step.connecting || _Step.joining || _Step.finding:
        return [?progress];

      case _Step.wifi:
        final custom = _network == null;
        return [
          Text('Sieć WiFi dla ${_pair!.id}', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Urządzenie obsługuje sieci 2,4 GHz.', style: t.bodySmall),
          const SizedBox(height: 8),
          for (final n in _networks)
            ListTile(
              key: Key('wifi-${n.ssid}'),
              selected: _network?.ssid == n.ssid,
              onTap: () => setState(() => _network = n),
              leading: Icon(_network?.ssid == n.ssid ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(n.ssid),
              subtitle: Text('${n.rssi} dBm${n.secured ? '' : ' · otwarta'}'),
              trailing: Icon(n.secured ? Icons.wifi_lock : Icons.wifi),
            ),
          ListTile(
            key: const Key('wifi-custom'),
            selected: custom,
            onTap: () => setState(() => _network = null),
            leading: Icon(custom ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            title: Text(_canScan ? 'Inna sieć (ukryta)' : 'Nazwa sieci'),
          ),
          if (custom)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('ssid'),
                controller: _ssid,
                decoration: const InputDecoration(labelText: 'Nazwa sieci (SSID)'),
              ),
            ),
          if (custom || _network!.secured)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('wifiPassword'),
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Hasło WiFi',
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                onSubmitted: (_) => _join(),
              ),
            ),
          ?error,
          FilledButton(key: const Key('wifiJoin'), onPressed: _join, child: const Text('Połącz')),
        ];

      case _Step.done:
        final d = _device!;
        return [
          Icon(Icons.check_circle, size: 64, color: cs.primary),
          const SizedBox(height: 12),
          Text(
            _changingWifi ? 'Urządzenie działa w nowej sieci.' : 'Gotowe: ${d.name}',
            key: const Key('bleDone'),
            textAlign: TextAlign.center,
            style: t.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            [d.type.label, d.id, if (d.lastEndpoint != null) d.lastEndpoint!.display].join(' · '),
            textAlign: TextAlign.center,
          ),
          ?error,
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).pop(d), child: const Text('Zakończ')),
        ];
    }
  }
}
