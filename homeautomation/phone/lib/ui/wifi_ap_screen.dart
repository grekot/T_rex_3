// Punkt sieci mesh urządzenia (kontrakt pkt 9.6): skan punktów tej sieci, przypięcie albo „Automatycznie”.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../models/wifi_ap.dart';
import 'widgets.dart';

/// „Punkt WiFi”: lista punktów (MAC, dBm, kanał) z bieżącym i przypiętym; wybór = przypięcie, „Automatycznie” = bez.
class WifiApScreen extends StatefulWidget {
  const WifiApScreen({
    super.key,
    required this.deviceName,
    required this.load,
    required this.scan,
    required this.pin,
    this.pollEvery = const Duration(seconds: 1),
    this.pollMax = 10,
  });

  WifiApScreen.forController(DeviceController<Object?, Object?> c, {Key? key})
    : this(
        key: key,
        deviceName: c.device.name,
        load: () async => c.localApi!.wifiAp(),
        scan: () => c.localApi!.wifiScan(),
        pin: (b) => c.localApi!.wifiPin(b),
      );

  final String deviceName;
  final Future<WifiApStatus?> Function() load;
  final Future<void> Function() scan;
  final Future<void> Function(String? bssid) pin;
  final Duration pollEvery;
  final int pollMax;

  @override
  State<WifiApScreen> createState() => _WifiApScreenState();
}

class _WifiApScreenState extends State<WifiApScreen> {
  WifiApStatus? _st;
  bool _busy = false, _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final st = await widget.load();
      if (!mounted) return;
      setState(() {
        _st = st;
        _error = st == null ? 'To urządzenie nie obsługuje wyboru punktu WiFi (zaktualizuj firmware).' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await widget.scan();
      // Wynik w GET /api/wifi (scan.state done), łącze urządzenia stoi ok. 2 s
      for (var i = 0; i < widget.pollMax; i++) {
        await Future<void>.delayed(widget.pollEvery);
        if (!mounted) return;
        final st = await widget.load().catchError((_) => _st);
        if (!mounted) return;
        setState(() => _st = st ?? _st);
        if (st != null && !st.scanning) break;
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pin(String? bssid) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pin(bssid);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _modeText(WifiApStatus st) => switch (st.mode) {
    'pinned' => 'Przypięty punkt ${st.pinned}.',
    'connecting' => 'Łączenie z przypiętym punktem ${st.pinned}…',
    'fallback' =>
      'Przypięty punkt ${st.pinned} jest niedostępny albo czeka na przerwę (np. radio gra) - urządzenie korzysta '
          'z najsilniejszego punktu i wróci do przypiętego najwcześniej po 30 min.',
    _ => 'Automatycznie: urządzenie łączy się z najsilniejszym punktem sieci.',
  };

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final aps = st?.aps ?? const <WifiAp>[];
    // Bieżący i przypięty na liście nawet bez skanu
    final rows = [
      ...aps,
      if (st?.bssid != null && !aps.any((a) => a.bssid == st!.bssid))
        WifiAp(bssid: st!.bssid!, rssi: st.rssi ?? 0, channel: st.channel ?? 0),
      if (st?.pinned != null && st!.pinned != st.bssid && !aps.any((a) => a.bssid == st.pinned))
        WifiAp(bssid: st.pinned!, rssi: 0, channel: 0),
    ];
    final busy = _busy || _scanning;
    return Scaffold(
      appBar: AppBar(title: const Text('Punkt WiFi')),
      body: st == null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: _error == null ? const Center(child: CircularProgressIndicator()) : Text(_error!),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${widget.deviceName} w sieci „${st.ssid}”'
                  '${st.rssi != null ? ': ${st.rssi} dBm, kanał ${st.channel}' : ''}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(_modeText(st), key: const Key('wifiApMode')),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      key: const Key('wifiApError'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    key: const Key('wifiApScan'),
                    icon: _scanning
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find),
                    label: Text(_scanning ? 'Skanowanie…' : 'Szukaj punktów'),
                    onPressed: busy ? null : _scan,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Skan przerywa łącze urządzenia na 2-3 s. Wybór punktu przypina urządzenie do niego; gdy punkt '
                  'zniknie, urządzenie samo połączy się z najsilniejszym.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SectionHeader('Punkty sieci'),
                RadioGroup<String?>(
                  groupValue: st.pinned,
                  onChanged: (v) {
                    if (!busy && v != st.pinned) _pin(v);
                  },
                  child: Column(
                    children: [
                      const RadioListTile<String?>(
                        key: Key('wifiApAuto'),
                        contentPadding: EdgeInsets.zero,
                        value: null,
                        title: Text('Automatycznie (najsilniejszy)'),
                      ),
                      for (final a in rows)
                        RadioListTile<String?>(
                          key: Key('wifiAp-${a.bssid}'),
                          contentPadding: EdgeInsets.zero,
                          value: a.bssid,
                          title: Text(a.bssid, style: const TextStyle(fontFamily: 'monospace')),
                          subtitle: Text(
                            [
                              if (a.rssi != 0) '${a.rssi} dBm (${wifiSignalText(a.rssi)})',
                              if (a.channel != 0) 'kanał ${a.channel}',
                              if (a.bssid == st.bssid) 'połączony teraz',
                              if (a.bssid == st.pinned) 'przypięty',
                              if (a.rssi == 0 && a.bssid != st.bssid) 'nie widać w ostatnim skanie',
                            ].join(' · '),
                          ),
                          secondary: Icon(a.bssid == st.bssid ? Icons.wifi : Icons.wifi_outlined),
                        ),
                    ],
                  ),
                ),
                if (aps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      st.scanState == 'error'
                          ? 'Skan się nie udał - spróbuj ponownie.'
                          : 'Naciśnij „Szukaj punktów”, żeby zobaczyć wszystkie punkty tej sieci.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Który to Deco? Adresy MAC punktów widać w aplikacji Deco (Deco → urządzenie → informacje). '
                  'Adres radia 2,4 GHz bywa inny od MAC-a z aplikacji na ostatnim bajcie (np. …:3A:F0 i …:3A:F1).',
                  key: const Key('wifiApHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
