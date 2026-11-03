// Bramka Bluetooth (węzeł `btnode`, ARCHITEKTURA pkt 4.9): stan obu układów i urządzenia, które hub obsługuje przez
// nią - czujniki z `via` = ta bramka (`GET hub/api/devices`), zegarki i piloty (`GET hub/api/remotes`), słyszane
// niedodane czujniki (`GET hub/api/ble/seen`).

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/errors.dart';
import '../data/hub_api.dart';
import '../models/hub.dart';
import '../models/json_utils.dart';
import '../models/remote.dart';
import '../services.dart';
import 'device_tiles.dart';
import 'format.dart';
import 'hub_ble_screen.dart';
import 'widgets.dart';

/// `1 połączenie`, `3 połączenia`, `5 połączeń`.
String plPlural(int n, String one, String few, String many) {
  if (n == 1) return '$n $one';
  final d = n % 10, t = n % 100;
  return d >= 2 && d <= 4 && (t < 12 || t > 14) ? '$n $few' : '$n $many';
}

/// Siła sygnału Bluetooth po polsku.
String rssiText(int rssi) => rssi >= -65
    ? 'bardzo dobry sygnał'
    : rssi >= -75
    ? 'dobry sygnał'
    : rssi >= -85
    ? 'słaby sygnał'
    : 'bardzo słaby sygnał';

IconData rssiIcon(int? rssi) => rssi == null
    ? Icons.signal_cellular_off_outlined
    : rssi >= -65
    ? Icons.signal_cellular_alt
    : rssi >= -75
    ? Icons.signal_cellular_alt_2_bar
    : rssi >= -85
    ? Icons.signal_cellular_alt_1_bar
    : Icons.signal_cellular_0_bar;

int? _int(Object? v) => v is num ? v.toInt() : null;

/// Jedna linijka na kafelek: `3 połączenia · szuka czujników`, „Układ Bluetooth nie odpowiada”.
String btnodeSummary(Json s) {
  if (s['bleOk'] == false) return 'Układ Bluetooth nie odpowiada';
  final conns = _int(s['bleConns']) ?? 0;
  return [
    'Bramka Bluetooth',
    if (conns > 0) plPlural(conns, 'połączenie', 'połączenia', 'połączeń'),
    if (s['scanAll'] == true) 'szuka czujników',
  ].join(' · ');
}

/// Urządzenia, które hub obsługuje przez bramkę [nodeId].
typedef BtNodeDevices = ({List<HubChild> sensors, List<HubRemote>? remotes, BleNode? node, List<BleFound>? found});

/// Ze wspólnych list huba - tylko to, co idzie przez [nodeId] (czujnik słyszany przez kilka bramek: przy tej
/// z najlepszym sygnałem).
BtNodeDevices btnodeDevices(String nodeId, List<HubChild> children, List<HubRemote>? remotes, BleSeen? seen) => (
  sensors: [
    for (final c in children)
      if (c.adapter == HubAdapter.ble && c.state['via'] == nodeId) c,
  ],
  remotes: remotes == null
      ? null
      : [
          for (final r in remotes)
            if (r.via == nodeId) r,
        ],
  node: seen?.nodes.where((n) => n.id == nodeId).firstOrNull,
  found: seen?.found.where((f) => f.via == nodeId).toList(),
);

/// Sekcje ekranu bramki: „Bramka”, „Czujniki przez tę bramkę”, „Zegarki i piloty”.
class BtNodeSection extends StatefulWidget {
  const BtNodeSection({super.key, required this.controller, this.hub, this.hubApi, this.refresh});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub? hub;

  /// Do testów: API huba zamiast tego z połączonego huba w [hub].
  final HubApi? hubApi;

  /// Co ile odświeżać listy z huba (null = 15 s).
  final Duration? refresh;

  @override
  State<BtNodeSection> createState() => _BtNodeSectionState();
}

class _BtNodeSectionState extends State<BtNodeSection> {
  DeviceController<Object?, Object?> get c => widget.controller;
  BtNodeDevices? _devices;
  String? _error;
  bool _loading = false;
  Timer? _timer;

  /// Hub, do którego bramka należy (`via`), inaczej pierwszy z połączeniem lokalnym.
  DeviceController<Object?, Object?>? get _hubController {
    final hubs = widget.hub?.hubs ?? const [];
    return hubs.where((h) => h.device.id == c.device.via && h.localApi != null).firstOrNull ??
        hubs.where((h) => h.localApi != null).firstOrNull;
  }

  HubApi? get _api {
    if (widget.hubApi != null) return widget.hubApi;
    final local = _hubController?.localApi;
    return local == null ? null : HubApi(local);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(widget.refresh ?? const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null || _loading) return;
    _loading = true;
    try {
      // Listy zegarków i „słyszanych” - starszy hub albo token bez `config` ich nie da; czujniki i tak pokażemy.
      final results = await Future.wait<Object?>([
        api.devices(),
        api.remotes().then<Object?>((r) => r, onError: (_) => null),
        api.bleSeen().then<Object?>((r) => r, onError: (_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _error = null;
        _devices = btnodeDevices(
          c.device.id,
          results[0]! as List<HubChild>,
          results[1] as List<HubRemote>?,
          results[2] as BleSeen?,
        );
      });
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _loading = false;
    }
  }

  Future<void> _search() async {
    final api = _api;
    if (api == null) return;
    final cloud = Services.of(context).cloud;
    final hubId = _hubController?.device.id ?? c.device.via ?? '';
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            HubBleScreen(api: api, canLink: cloud.available && cloud.isHomeOwner && cloud.homeId != null, hubId: hubId),
      ),
    );
    if (added == true) {
      unawaited(widget.hub?.load());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = c.stateJson ?? const <String, dynamic>{};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_status(context, s), ..._lists(context)]);
  }

  Widget _status(BuildContext context, Json s) {
    final cs = Theme.of(context).colorScheme;
    final ok = s['bleOk'] == true;
    final conns = _int(s['bleConns']) ?? 0;
    final adv = _int(s['advPerMin']);
    final fw = _int(s['bleFw']);
    final up = _int(s['bleUptime']);
    final crc = _int(s['linkCrcErrors']) ?? 0;
    final node = _devices?.node;
    return Card(
      key: const Key('btnodeStatus'),
      child: Column(
        children: [
          ListTile(
            key: const Key('btnodeBle'),
            leading: Icon(ok ? Icons.bluetooth : Icons.bluetooth_disabled, color: ok ? null : cs.error),
            title: Text(ok ? 'Układ Bluetooth działa' : 'Układ Bluetooth nie odpowiada'),
            subtitle: Text(
              ok
                  ? [if (fw != null) 'wersja $fw', if (up != null && up > 0) 'działa od ${fmtUptime(up)}'].join(' · ')
                  : 'Bramka nie dostaje od niego danych - sprawdź zasilanie i przewody między płytkami.',
            ),
          ),
          ListTile(
            key: const Key('btnodeConns'),
            leading: const Icon(Icons.watch_outlined),
            title: Text(
              conns == 0 ? 'Brak połączeń Bluetooth' : plPlural(conns, 'połączenie', 'połączenia', 'połączeń'),
            ),
            subtitle: const Text('Zegarki i piloty połączone teraz z bramką'),
          ),
          if (adv != null)
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text('$adv rozgłoszeń na minutę'),
              subtitle: const Text('Tyle pakietów od czujników Bluetooth słyszy bramka'),
            ),
          if (s['scanAll'] == true)
            const ListTile(
              key: Key('btnodeScanning'),
              leading: Icon(Icons.radar),
              title: Text('Trwa szukanie nowych czujników'),
              subtitle: Text('Włącza je hub na 2 minuty („Dodaj czujnik Bluetooth”).'),
            ),
          if (node != null)
            ListTile(
              key: const Key('btnodeHubLink'),
              leading: Icon(node.online ? Icons.device_hub : Icons.link_off, color: node.online ? null : cs.error),
              title: Text(node.online ? 'Hub odbiera dane z bramki' : 'Hub nie dostaje danych z bramki'),
              subtitle: Text(
                [
                  if (node.age != null) 'ostatnie ${fmtAge(node.age!)}',
                  if (node.received != null) plPlural(node.received!, 'komunikat', 'komunikaty', 'komunikatów'),
                  if ((node.lost ?? 0) > 0) 'zgubione ${node.lost}',
                ].join(' · '),
              ),
            ),
          if (crc > 0)
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: cs.error),
              title: Text('Błędy łącza między układami: $crc'),
              subtitle: const Text('Pojedyncze nie szkodzą; jeśli rosną - sprawdź przewody UART.'),
            ),
        ],
      ),
    );
  }

  List<Widget> _lists(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final api = _api;
    final d = _devices;
    final header = Row(
      children: [
        const Expanded(child: SectionHeader('Czujniki przez tę bramkę')),
        if (api != null)
          IconButton(
            key: const Key('btnodeRefresh'),
            tooltip: 'Odśwież',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
      ],
    );
    if (api == null) {
      return [
        header,
        const Padding(
          key: Key('btnodeNoHub'),
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Listę urządzeń bramki zna hub - widać ją w sieci domowej, gdy telefon jest sparowany z hubem.'),
        ),
      ];
    }
    if (d == null) {
      return [
        header,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: cs.error)),
          )
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ];
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final found = d.found ?? const <BleFound>[];
    return [
      header,
      Card(
        child: Column(
          children: [
            if (d.sensors.isEmpty)
              const ListTile(
                key: Key('btnodeNoSensors'),
                title: Text('Hub nie słyszy przez tę bramkę żadnego dodanego czujnika.'),
              ),
            for (final x in d.sensors) _sensorTile(context, x),
            if (found.isNotEmpty)
              ListTile(
                key: const Key('btnodeFound'),
                leading: const Icon(Icons.add_circle_outline),
                title: Text(
                  'W zasięgu: ${plPlural(found.length, 'nowy czujnik', 'nowe czujniki', 'nowych czujników')}',
                ),
                subtitle: const Text('Słyszane, a jeszcze niedodane do huba'),
                onTap: _search,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: TextButton.icon(
                  key: const Key('btnodeSearch'),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Dodaj czujnik Bluetooth'),
                  onPressed: _search,
                ),
              ),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Czujnik słyszany przez kilka bramek jest na liście tej, która słyszy go najlepiej.',
          style: TextStyle(fontSize: 12),
        ),
      ),
      if (d.remotes != null) ...[
        const SectionHeader('Zegarki i piloty'),
        Card(
          child: Column(
            children: [
              if (d.remotes!.isEmpty)
                const ListTile(
                  key: Key('btnodeNoRemotes'),
                  title: Text('Żaden zegarek ani pilot nie łączył się jeszcze przez tę bramkę.'),
                ),
              for (final r in d.remotes!)
                ListTile(
                  key: Key('btnodeRemote-${r.id}'),
                  leading: Icon(r.kind == 'watch' ? Icons.watch_outlined : Icons.settings_remote_outlined),
                  title: Text(r.label),
                  subtitle: Text(
                    [
                      r.kind == 'watch' ? 'zegarek' : 'pilot',
                      r.lastUsed == null ? 'jeszcze nieużywany' : 'ostatnio ${fmtAge(now - r.lastUsed!)}',
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _sensorTile(BuildContext context, HubChild x) {
    final rssi = _int(x.state['rssi']);
    final ctrl = widget.hub?.controller(x.id);
    final values = [
      for (final k in const ['temp', 'hum', 'battery'])
        if (x.state[k] != null) bleValueText(k, x.state[k]),
    ];
    return ListTile(
      key: Key('btnodeSensor-${x.id}'),
      leading: Icon(rssiIcon(rssi)),
      title: Text(x.label),
      subtitle: Text(
        [
          if (!x.online) 'niedostępny${x.error == null || x.error == 'offline' ? '' : ' (${x.error})'}',
          ...values,
          if (rssi != null) '${rssiText(rssi)} ($rssi dBm)',
        ].join(' · '),
      ),
      trailing: ctrl == null ? null : const Icon(Icons.chevron_right),
      onTap: ctrl == null ? null : () => openDevice(context, ctrl, hub: widget.hub),
    );
  }
}
