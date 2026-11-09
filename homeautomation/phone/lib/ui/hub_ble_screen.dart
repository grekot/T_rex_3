// Czujniki Bluetooth (BTHome) przez węzły btnode (kontrakt pkt 11 „Czujniki Bluetooth”): szukanie, podgląd wartości,
// dodanie do huba (z kluczem dla szyfrowanych) i poprawienie klucza. Czujnik `btsensor` (hub 0.3.33+) paruje się sam
// po podłączeniu zasilania w czasie szukania (pkt 15.6) - wtedy tylko nazwa i zatwierdzenie (`paired: true`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/errors.dart';
import '../data/hub_api.dart';
import '../models/device_type.dart';
import '../models/hub.dart';
import '../models/json_utils.dart';
import '../services.dart';
import '../data/cloud_access.dart' show writeDeviceIndex;

/// Wartość z czujnika po polsku: `21,6 °C`, `45 %`, `bateria 87 %`, `okno otwarte`…
String bleValueText(String key, Object? v) {
  String num1(num x, [int d = 1]) => x.toStringAsFixed(d).replaceAll('.', ',');
  // Drugi obiekt tego samego rodzaju: `temp2` → `temp` (ale `co2` zostaje).
  final base = key == 'co2' ? key : key.replaceAll(RegExp(r'\d+$'), '');
  if (v is bool) {
    return switch (base) {
      'window' => v ? 'okno otwarte' : 'okno zamknięte',
      'door' || 'opening' => v ? 'otwarte' : 'zamknięte',
      'motion' || 'occupancy' => v ? 'ruch' : 'spokój',
      'batteryLow' => v ? 'słaba bateria' : 'bateria OK',
      'wet' || 'moisture' => v ? 'zalanie!' : 'sucho',
      'smoke' => v ? 'dym!' : 'bez dymu',
      _ => '$key: ${v ? 'tak' : 'nie'}',
    };
  }
  if (v is! num) return '$key: $v';
  return switch (base) {
    'temp' => '${num1(v)} °C',
    'hum' => '${num1(v, v % 1 == 0 ? 0 : 1)} %',
    'battery' => 'bateria ${v.round()} %',
    'voltage' => '${num1(v, 2)} V',
    'illuminance' => '${v.round()} lx',
    'moisture' => 'wilgotność gleby ${v.round()} %',
    'pressure' => '${v.round()} hPa',
    'co2' => '${v.round()} ppm CO₂',
    'power' => '${num1(v)} W',
    'energy' => '${num1(v, 2)} kWh',
    _ => '$key: ${num1(v, v % 1 == 0 ? 0 : 1)}',
  };
}

/// Opis znalezionego czujnika: wartości, przyciski, szyfrowanie.
String bleFoundSummary(BleFound f) => [
  for (final e in f.values.entries) bleValueText(e.key, e.value),
  if (f.buttons.isNotEmpty) f.buttons.length == 1 ? 'przycisk' : '${f.buttons.length} przyciski',
  if (f.trigger && f.buttons.isEmpty) 'nadaje przy zdarzeniu',
].join(' · ');

/// Pole klucza BTHome (32 znaki hex) z wklejaniem ze schowka.
class BleKeyField extends StatelessWidget {
  const BleKeyField({super.key, required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final text = controller.text.trim();
    return TextField(
      key: const Key('bleKey'),
      controller: controller,
      maxLength: 32,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        labelText: 'Klucz szyfrowania (bindkey)',
        hintText: '32 znaki 0-9 a-f',
        errorText: text.isEmpty || bleKeyPattern.hasMatch(text) ? null : 'Klucz ma 32 znaki 0-9 a-f',
        suffixIcon: IconButton(
          key: const Key('blePaste'),
          tooltip: 'Wklej',
          icon: const Icon(Icons.content_paste),
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final v = data?.text?.trim().replaceAll(RegExp(r'[\s:-]'), '');
            if (v == null || v.isEmpty) return;
            controller.text = v;
            onChanged();
          },
        ),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// „Dodaj czujnik Bluetooth”: szukanie przez węzły `btnode` (`POST /api/ble/scan`, `GET /api/ble/seen` co [interval]),
/// lista z podglądem wartości i siłą sygnału, dodanie (`POST /api/devices` `adapter: ble`). Sparowane `btsensor`
/// (`paired`) na górze: nowy - nazwa i dodanie, już dodany - zatwierdzenie nowego klucza.
class HubBleScreen extends StatefulWidget {
  const HubBleScreen({
    super.key,
    required this.api,
    required this.canLink,
    required this.hubId,
    this.interval = const Duration(milliseconds: 1500),
    this.seconds = 120,
  });

  final HubApi api;
  final bool canLink;
  final String hubId;
  final Duration interval;
  final int seconds;

  @override
  State<HubBleScreen> createState() => _HubBleScreenState();
}

class _HubBleScreenState extends State<HubBleScreen> {
  BleSeen? _seen;
  String? _error;

  /// Węzły `btnode` online przy starcie szukania (0 = nie ma czym szukać).
  int? _nodes;
  Timer? _timer;
  bool _added = false;
  final _addedMacs = <String>{};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_seen?.scanning ?? false) unawaited(widget.api.bleStop().catchError((_) {}));
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _error = null;
      _nodes = null;
    });
    try {
      final n = await widget.api.bleScan(seconds: widget.seconds);
      if (!mounted) return;
      setState(() => _nodes = n);
      if (n > 0) await _poll();
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _poll() async {
    try {
      final r = await widget.api.bleSeen();
      if (!mounted) return;
      setState(() {
        _seen = r;
        _error = null;
      });
      if (r.scanning) _timer = Timer(widget.interval, _poll);
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    try {
      await widget.api.bleStop();
    } on ThermostatException catch (_) {}
    await _poll();
  }

  /// Dodanie znalezionego ([found]) albo sparowanego ([paired]) czujnika o adresie [mac].
  Future<void> _add(String mac, {BleFound? found, bool paired = false}) async {
    final req = await showDialog<Json>(
      context: context,
      builder: (_) => _BleAddDialog(mac: mac, found: found, paired: paired),
    );
    if (req == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final cloud = Services.of(context).cloud;
    try {
      final id = await widget.api.addDevice(req);
      _added = true;
      if (widget.canLink) {
        await writeDeviceIndex(
          cloud.store,
          cloud.homeId!,
          id,
          DeviceType.sensor,
          req['name'] as String,
          via: widget.hubId,
        );
      }
      messenger.showSnackBar(SnackBar(content: Text('Dodano ${req['name']}.')));
      setState(() => _addedMacs.add(mac));
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Już dodany czujnik sparował się ponownie: ten sam wpis (`id`) i nazwa, klucz z parowania.
  Future<void> _confirmKey(BlePaired p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final old = (await widget.api.devices()).where((d) => d.id == p.id).firstOrNull;
      final name = old?.name ?? p.id!;
      await widget.api.addDevice({'adapter': HubAdapter.ble.wire, 'deviceId': p.mac, 'paired': true, 'name': name});
      _added = true;
      messenger.showSnackBar(SnackBar(content: Text('Zatwierdzono nowy klucz: $name.')));
      if (mounted) setState(() => _addedMacs.add(p.mac));
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static IconData _signal(int? rssi) => rssi == null
      ? Icons.signal_cellular_null
      : rssi >= -65
      ? Icons.signal_cellular_alt
      : rssi >= -80
      ? Icons.signal_cellular_alt_2_bar
      : Icons.signal_cellular_alt_1_bar;

  @override
  Widget build(BuildContext context) {
    final r = _seen;
    final scanning = _nodes == null || (r?.scanning ?? (_nodes ?? 0) > 0);
    final paired = [
      for (final p in r?.paired ?? const <BlePaired>[])
        if (!_addedMacs.contains(p.mac)) p,
    ];
    final pairedMacs = {for (final p in r?.paired ?? const <BlePaired>[]) p.mac};
    BleFound? heard(String mac) => r?.found.where((f) => f.mac == mac).firstOrNull;
    final found = [
      for (final f in r?.found ?? const <BleFound>[])
        if (!_addedMacs.contains(f.mac) && !pairedMacs.contains(f.mac)) f,
    ];
    final onlineNodes = r?.nodes.where((n) => n.online).length ?? _nodes ?? 0;
    final String status;
    if (_error != null) {
      status = _error!;
    } else if (_nodes == 0) {
      status = 'Hub nie ma działającego węzła Bluetooth (btnode). Dodaj węzeł do huba albo sprawdź, czy jest włączony.';
    } else if (scanning) {
      status =
          'Szukam przez $onlineNodes ${onlineNodes == 1 ? 'węzeł' : 'węzły'} Bluetooth'
          '${r?.remaining == null ? '' : ' - jeszcze ${r!.remaining} s'}. Czujnik nadaje co kilka-kilkanaście sekund; '
          'przycisk naciśnij, żeby się pokazał.';
    } else {
      status = 'Znalezione, jeszcze niedodane: ${paired.length + found.length}';
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_added);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Czujniki Bluetooth')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (scanning && _error == null && _nodes != 0) const LinearProgressIndicator(),
            ListTile(
              key: const Key('bleStatus'),
              leading: Icon(_nodes == 0 || _error != null ? Icons.bluetooth_disabled : Icons.bluetooth_searching),
              title: Text(status),
              trailing: scanning && _nodes != 0 && _error == null
                  ? TextButton(key: const Key('bleStop'), onPressed: _stop, child: const Text('Zakończ'))
                  : TextButton(key: const Key('bleAgain'), onPressed: _start, child: const Text('Szukaj')),
            ),
            if (scanning && _error == null && _nodes != 0)
              const ListTile(
                key: Key('blePairHint'),
                leading: Icon(Icons.power_outlined),
                title: Text('Czujnik btsensor: podłącz teraz jego zasilanie - sparuje się sam.'),
              ),
            for (final p in paired)
              ListTile(
                key: Key('blePaired-${p.mac}'),
                leading: const Icon(Icons.link),
                title: Text('Sparowany czujnik · ${p.mac}'),
                subtitle: Text(
                  [
                    if (heard(p.mac) case final f?) bleFoundSummary(f),
                    p.id == null ? 'stuknij, żeby dodać' : 'już dodany (${p.id}) - nowy klucz do zatwierdzenia',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
                trailing: p.id == null
                    ? null
                    : FilledButton(
                        key: Key('bleConfirmKey-${p.mac}'),
                        onPressed: () => _confirmKey(p),
                        child: const Text('Zatwierdź nowy klucz'),
                      ),
                onTap: p.id == null ? () => _add(p.mac, found: heard(p.mac), paired: true) : null,
              ),
            for (final f in found)
              ListTile(
                key: Key('bleFound-${f.mac}'),
                leading: Icon(f.encrypted ? Icons.lock_outline : Icons.sensors),
                title: Text('${f.kind == 'bthome' ? 'BTHome' : f.kind} · ${f.mac}'),
                subtitle: Text(
                  [
                    bleFoundSummary(f),
                    if (f.encrypted) 'szyfrowany - potrzebny klucz',
                    if (f.via != null) 'przez ${f.via}',
                    if (f.age != null && f.age! > 30) '${f.age} s temu',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_signal(f.rssi), size: 20),
                    if (f.rssi != null) Text('${f.rssi} dBm', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                onTap: () => _add(f.mac, found: f),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Obsługiwane są czujniki BTHome v2 (np. Shelly BLU, Xiaomi z oprogramowaniem pvvx/ATC w trybie BTHome). '
                'Szyfrowane wymagają klucza (bindkey) - z aplikacji producenta albo z ustawień oprogramowania czujnika. '
                'Własny czujnik btsensor nie potrzebuje klucza: paruje się z hubem po podłączeniu zasilania w czasie szukania.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dodanie czujnika: nazwa i (dla szyfrowanych) klucz; sparowany ([paired]) - sama nazwa, klucz zna hub.
class _BleAddDialog extends StatefulWidget {
  const _BleAddDialog({required this.mac, this.found, this.paired = false});

  final String mac;
  final BleFound? found;
  final bool paired;

  @override
  State<_BleAddDialog> createState() => _BleAddDialogState();
}

class _BleAddDialogState extends State<_BleAddDialog> {
  final _name = TextEditingController();
  final _key = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.found;
    final needsKey = !widget.paired && (f?.encrypted ?? false);
    final key = widget.paired ? '' : _key.text.trim();
    final ok = _name.text.trim().isNotEmpty && (key.isEmpty ? !needsKey : bleKeyPattern.hasMatch(key));
    return AlertDialog(
      title: Text(widget.paired ? 'Dodaj sparowany czujnik' : 'Dodaj czujnik'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.mac}${f == null || f.values.isEmpty ? '' : '\n${bleFoundSummary(f)}'}'),
            TextField(
              key: const Key('bleName'),
              controller: _name,
              maxLength: 32,
              decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'np. Salon, Okno kuchnia'),
              onChanged: (_) => setState(() {}),
            ),
            if (needsKey) BleKeyField(controller: _key, onChanged: () => setState(() {})),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('bleAddOk'),
          onPressed: ok
              ? () => Navigator.pop(context, <String, dynamic>{
                  'adapter': HubAdapter.ble.wire,
                  'deviceId': widget.mac,
                  'name': _name.text.trim(),
                  if (widget.paired) 'paired': true,
                  if (key.isNotEmpty) 'localKey': key.toLowerCase(),
                })
              : null,
          child: const Text('Dodaj'),
        ),
      ],
    );
  }
}

/// Poprawienie klucza czujnika Bluetooth (`error: "key"`): ten sam wpis (`id`), nowy `localKey`.
class BleKeyDialog extends StatefulWidget {
  const BleKeyDialog({super.key, required this.device});

  final HubChild device;

  @override
  State<BleKeyDialog> createState() => _BleKeyDialogState();
}

class _BleKeyDialogState extends State<BleKeyDialog> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final ok = bleKeyPattern.hasMatch(_key.text.trim());
    return AlertDialog(
      title: Text('Klucz: ${d.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.error == 'key')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Hub nie może odczytać pakietów czujnika - klucz jest zły albo go brak.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          BleKeyField(controller: _key, onChanged: () => setState(() {})),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('bleKeySave'),
          onPressed: ok ? () => Navigator.pop(context, _key.text.trim().toLowerCase()) : null,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}
