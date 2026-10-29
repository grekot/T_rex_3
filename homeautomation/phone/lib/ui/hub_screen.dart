import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../data/cloud_access.dart';
import '../data/device_store.dart';
import '../data/errors.dart';
import '../data/hub_api.dart';
import '../data/local_api.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/hub.dart';
import '../models/json_utils.dart';
import '../models/thermostat_config.dart';
import '../services.dart';
import 'automations_screen.dart';
import 'device_admin_section.dart';
import 'widget_editor.dart';
import 'widgets.dart';

/// Hub (pkt 11): stan, urządzenia podrzędne, automatyki, sceny, położenie domu i czas, ustawienia wspólne
/// (chmura, telefony, firmware, WiFi).
class HubScreen extends StatefulWidget {
  const HubScreen({super.key, required this.controller, required this.hub});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub hub;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  DeviceController<Object?, Object?> get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (c.connection == null) c.connect();
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _rename() async {
    final name = await showTextInputDialog(context, title: 'Nazwa huba', initial: c.device.name, maxLength: 32);
    if (name == null || !mounted) return;
    final r = await c.sendJson({'name': name});
    if (mounted) showSaveResult(context, r.errors, describeErrors);
  }

  /// Położenie domu - wschód i zachód słońca w automatykach (Set `location`).
  Future<void> _location(Json? current) async {
    // Podpowiedź z ustawień pogody termostatu.
    String? lat = current?['lat']?.toString(), lon = current?['lon']?.toString();
    if (lat == null) {
      for (final t in widget.hub.devices.where((d) => d.type == DeviceType.thermostat)) {
        final cfg = widget.hub.controller(t.id)?.config;
        if (cfg is ThermostatConfig && cfg.weather.lat.isNotEmpty) {
          lat = cfg.weather.lat;
          lon = cfg.weather.lon;
          break;
        }
      }
    }
    final r = await showDialog<(double, double)>(
      context: context,
      builder: (_) => _LocationDialog(lat: lat ?? '', lon: lon ?? ''),
    );
    if (r == null || !mounted) return;
    final res = await c.sendJson({
      'location': {'lat': r.$1, 'lon': r.$2},
    });
    if (mounted) showSaveResult(context, res.errors, describeErrors);
  }

  Future<void> _setTime() async {
    final api = c.localApi;
    if (api == null) return;
    try {
      await HubApi(api).setTime(DateTime.now());
      _snack('Ustawiono czas huba z telefonu.');
    } on ThermostatException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.stateJson;
        final cfg = c.config is Map ? (c.config! as Map).cast<String, dynamic>() : null;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.device.name),
            actions: [
              if (s != null && c.canConfig)
                IconButton(tooltip: 'Zmień nazwę', icon: const Icon(Icons.edit), onPressed: _rename),
            ],
          ),
          body: switch (c.phase) {
            ConnectPhase.connecting => ConnectingView(step: c.step),
            _ when s == null => FailedView(
              message: c.error ?? 'Nie udało się połączyć z hubem.',
              needsPairing: c.needsPairing,
              onRetry: c.connect,
              onPair: c.connect,
            ),
            _ => RefreshIndicator(onRefresh: c.connect, child: _body(context, s, cfg)),
          },
        );
      },
    );
  }

  Widget _body(BuildContext context, Json s, Json? cfg) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final location = asObjectOrNull(cfg?['location'], 'location');
    final lastRun = asObjectOrNull(s['lastRun'], 'lastRun');
    final link = switch (s['link']) {
      'ethernet' => 'Ethernet',
      'wifi' => 'WiFi',
      _ => 'brak sieci',
    };
    final local = c.isLocal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        RouteChip(controller: c),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Urządzenia: ${s['online'] ?? 0} z ${s['devices'] ?? 0} dostępne', style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Sceny: ${s['scenes'] ?? 0} · automatyki: ${s['automations'] ?? 0}'
                  '${(s['running'] as num? ?? 0) > 0 ? ' · trwa: ${s['running']}' : ''}',
                ),
                Text('Łącze: $link · chmura: ${s['cloud'] == true ? 'połączona' : 'niepołączona'}'),
                if (lastRun != null)
                  Text(
                    'Ostatnio: ${lastRun['kind'] == 'scene' ? 'scena' : 'automatyka'} ${lastRun['id']}'
                    '${lastRun['ok'] == false ? ' (błąd)' : ''}',
                  ),
              ],
            ),
          ),
        ),
        if (s['timeKnown'] == false)
          Card(
            color: cs.errorContainer,
            child: ListTile(
              key: const Key('hubTimeUnknown'),
              leading: Icon(Icons.schedule, color: cs.onErrorContainer),
              title: Text('Hub nie zna czasu', style: TextStyle(color: cs.onErrorContainer)),
              subtitle: Text(
                'Automatyki o godzinie i od słońca czekają. Hub weźmie czas z internetu, RTC albo termostatu.',
                style: TextStyle(color: cs.onErrorContainer),
              ),
              trailing: local && c.canConfig ? TextButton(onPressed: _setTime, child: const Text('Z telefonu')) : null,
            ),
          ),
        const SectionHeader('Hub'),
        ListTile(
          key: const Key('hubDevices'),
          leading: const Icon(Icons.device_hub),
          title: const Text('Urządzenia huba'),
          subtitle: Text(local ? 'Shelly, Sonoff, Tasmota, własne węzły' : 'Dodawanie i usuwanie w sieci domowej'),
          enabled: local,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HubDevicesScreen(controller: c, hub: widget.hub),
            ),
          ),
        ),
        ListTile(
          key: const Key('hubAutomations'),
          leading: const Icon(Icons.auto_mode),
          title: const Text('Automatyki'),
          subtitle: const Text('Godzina, słońce, stan urządzeń, przyciski - działają w hubie, także bez internetu'),
          enabled: c.canConfig,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AutomationsScreen(hub: widget.hub, controller: c),
            ),
          ),
        ),
        ListTile(
          key: const Key('hubScenes'),
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Sceny'),
          subtitle: const Text('Wykonuje je hub (całe, z przerwami)'),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScenePickerScreen(hub: widget.hub))),
        ),
        ListTile(
          key: const Key('hubLocation'),
          leading: const Icon(Icons.place_outlined),
          title: const Text('Położenie domu'),
          subtitle: Text(
            location == null
                ? 'Nieustawione - potrzebne do wschodu i zachodu słońca'
                : '${location['lat']}, ${location['lon']}',
          ),
          enabled: c.canConfig,
          onTap: () => _location(location),
        ),
        DeviceAdminSection(
          controller: c,
          cloudLinked: s['cloud'] == true,
          uptime: s['uptime'] is num ? (s['uptime'] as num).toInt() : null,
        ),
      ],
    );
  }
}

class _LocationDialog extends StatefulWidget {
  const _LocationDialog({required this.lat, required this.lon});

  final String lat;
  final String lon;

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  late final _lat = TextEditingController(text: widget.lat);
  late final _lon = TextEditingController(text: widget.lon);

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c, double max) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v == null || v.abs() > max ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final lat = _parse(_lat, 90), lon = _parse(_lon, 180);
    return AlertDialog(
      title: const Text('Położenie domu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('lat'),
            controller: _lat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Szerokość (np. 49.894)'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const Key('lon'),
            controller: _lon,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Długość (np. 20.609)'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('locationOk'),
          onPressed: lat == null || lon == null ? null : () => Navigator.pop(context, (lat, lon)),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

/// Urządzenia huba (pkt 11): lista z `GET /api/devices`, sterowanie, „Do chmury” (`deviceIndex/{id}/via`),
/// usuwanie, wykrywanie i dodawanie. Tylko w sieci domowej.
class HubDevicesScreen extends StatefulWidget {
  const HubDevicesScreen({super.key, required this.controller, required this.hub});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub hub;

  @override
  State<HubDevicesScreen> createState() => _HubDevicesScreenState();
}

class _HubDevicesScreenState extends State<HubDevicesScreen> {
  late final HubApi? _api = widget.controller.localApi == null ? null : HubApi(widget.controller.localApi!);
  Future<List<HubChild>>? _load;

  String get _hubId => widget.controller.device.id;

  @override
  void initState() {
    super.initState();
    _load = _api?.devices();
  }

  void _reload() => setState(() {
    _load = _api?.devices();
  });

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  /// Własny węzeł ma nazwę w swoim Config - hub w `GET /api/devices` podaje tę z chwili przypisania, więc
  /// bierzemy bieżącą znaną aplikacji (inaczej po zmianie nazwy trzeba by przypisywać od nowa).
  String _name(HubChild d) => (d.adapter == HubAdapter.ownNode ? widget.hub.device(d.id)?.name : null) ?? d.label;

  CloudAccess get _cloud => Services.of(context).cloud;

  bool get _canLink => _cloud.available && _cloud.isHomeOwner && _cloud.homeId != null;

  /// Właściciel: wpis `deviceIndex/{id}` z `via` - od tego hub pisze lustro i bierze polecenia z chmury.
  Future<void> _link(HubChild d) async {
    final type = d.type;
    if (type == null) {
      _snack('Hub jeszcze sprawdza typ urządzenia - spróbuj za chwilę.');
      return;
    }
    try {
      await writeDeviceIndex(_cloud.store, _cloud.homeId!, d.id, DeviceType.fromWire(type), _name(d), via: _hubId);
      _snack('Zapisano. Hub połączy „${_name(d)}” z chmurą w ciągu 5 minut.');
      await widget.hub.load();
    } on Object catch (e) {
      _snack('Nie zapisano: $e');
    }
  }

  Future<void> _delete(HubChild d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć „${_name(d)}” z huba?'),
        content: const Text('Hub przestanie nim sterować, a automatyki z tym urządzeniem przestaną działać.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api!.deleteDevice(d.id);
      // Wpisy w bazie usuwa aplikacja (pkt 11).
      if (_canLink) {
        final h = _cloud.homeId!;
        await _cloud.store.write('homes/$h/deviceIndex/${d.id}', null).catchError((_) {});
        await _cloud.store.write('homes/$h/devices/${d.id}', null).catchError((_) {});
      }
      _reload();
      unawaited(widget.hub.load());
    } on ThermostatException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _toggle(HubChild d, bool on) async {
    try {
      final r = await _api!.setDevice(d.id, {'on': on});
      if (r.pending) {
        _snack('Urządzenie odpowie za chwilę.');
      } else if (r.errors.isNotEmpty) {
        _snack(describeErrors(r.errors));
      }
      _reload();
    } on ThermostatException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _discover() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HubDiscoverScreen(api: _api!, canLink: _canLink, hubId: _hubId),
      ),
    );
    if (added == true) {
      _reload();
      unawaited(widget.hub.load());
    }
  }

  String _error(String e) => switch (e) {
    'offline' => 'niedostępne',
    'unauthorized' => 'zły token',
    'password' => 'złe hasło',
    'not_gen2' => 'stary Shelly (Gen1) - nieobsługiwany',
    _ => e,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Urządzenia huba'),
        actions: [IconButton(tooltip: 'Odśwież', icon: const Icon(Icons.refresh), onPressed: _reload)],
      ),
      floatingActionButton: _api == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('hubDiscover'),
              heroTag: null,
              onPressed: _discover,
              icon: const Icon(Icons.search),
              label: const Text('Szukaj w sieci'),
            ),
      body: _api == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Urządzenia huba dodaje się i usuwa w sieci domowej.'),
              ),
            )
          : FutureBuilder<List<HubChild>>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  final e = snap.error;
                  return Center(child: Text(e is ThermostatException ? e.message : '$e'));
                }
                final list = snap.data;
                if (list == null) return const Center(child: CircularProgressIndicator());
                return ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Własne węzły przypisuje się w ich ustawieniach („Przypisz do huba”). '
                        'Obce (Shelly, Sonoff DIY, Tasmota) - „Szukaj w sieci”. Adresy urządzeń najlepiej '
                        'zarezerwować w routerze (hub nie śledzi zmian adresu).',
                      ),
                    ),
                    if (list.isEmpty) const ListTile(title: Text('Hub nie ma jeszcze urządzeń.')),
                    for (final d in list)
                      ListTile(
                        key: Key('hubChild-${d.id}'),
                        leading: Icon(
                          d.type == 'sensor' ? Icons.sensors : Icons.lightbulb_outline,
                          color: d.online ? null : cs.outline,
                        ),
                        title: Text(_name(d)),
                        subtitle: Text(
                          [
                            d.adapter.label,
                            d.host,
                            if (d.model != null) d.model!,
                            d.online ? 'dostępne' : 'niedostępne',
                            if (d.error != null) _error(d.error!),
                            if (!d.mirror) 'tylko automatyki' else if (d.linked) 'w chmurze' else 'tylko w domu',
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (d.online && (d.type == 'switch' || d.type == 'dimmer'))
                              Switch(
                                key: Key('hubChildSwitch-${d.id}'),
                                value: d.state['on'] == true,
                                onChanged: (v) => _toggle(d, v),
                              ),
                            PopupMenuButton<String>(
                              onSelected: (a) => a == 'link' ? _link(d) : _delete(d),
                              itemBuilder: (_) => [
                                if (d.mirror && !d.linked && _canLink)
                                  const PopupMenuItem(value: 'link', child: Text('Do chmury')),
                                const PopupMenuItem(value: 'delete', child: Text('Usuń z huba')),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// Wykrywanie (`GET /api/discover`: skan ~10 s w tle, odpytywanie co 1 s) i dodawanie znalezionych.
class HubDiscoverScreen extends StatefulWidget {
  const HubDiscoverScreen({
    super.key,
    required this.api,
    required this.canLink,
    required this.hubId,
    this.interval = const Duration(seconds: 1),
  });

  final HubApi api;
  final bool canLink;
  final String hubId;
  final Duration interval;

  @override
  State<HubDiscoverScreen> createState() => _HubDiscoverScreenState();
}

class _HubDiscoverScreenState extends State<HubDiscoverScreen> {
  HubDiscovery? _result;
  String? _error;
  Timer? _timer;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final r = await widget.api.discover();
      if (!mounted) return;
      setState(() {
        _result = r;
        _error = null;
      });
      if (r.scanning) _timer = Timer(widget.interval, _poll);
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add(HubFound f) async {
    if (f.adapter == HubAdapter.tuya) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tuya hub obsłuży w kolejnej wersji. Można ją przeflashować na Tasmotę.')),
      );
      return;
    }
    final req = await showDialog<Json>(
      context: context,
      builder: (_) => _AddDeviceDialog(found: f),
    );
    if (req == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final cloud = Services.of(context).cloud;
    try {
      final id = await widget.api.addDevice(req);
      _added = true;
      // Właściciel od razu wpisuje urządzenie do chmury, gdy typ jest znany (pkt 11).
      final type = f.type;
      if (widget.canLink && type != null) {
        await writeDeviceIndex(
          cloud.store,
          cloud.homeId!,
          id,
          DeviceType.fromWire(type),
          (req['name'] as String?) ?? id,
          via: widget.hubId,
        );
      }
      messenger.showSnackBar(SnackBar(content: Text('Dodano ${req['name'] ?? id}.')));
      setState(
        () => _result = _result == null
            ? null
            : HubDiscovery(scanning: _result!.scanning, age: _result!.age, found: [..._result!.found]..remove(f)),
      );
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_added);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Szukaj w sieci')),
        body: ListView(
          children: [
            if (r == null || r.scanning) const LinearProgressIndicator(),
            ListTile(
              title: Text(
                _error ??
                    (r == null || r.scanning
                        ? 'Hub szuka urządzeń w sieci (ok. 10 s)…'
                        : 'Znalezione, jeszcze niedodane: ${r.found.length}'),
              ),
              trailing: r != null && !r.scanning
                  ? TextButton(onPressed: _poll, child: const Text('Jeszcze raz'))
                  : null,
            ),
            for (final f in r?.found ?? const <HubFound>[])
              ListTile(
                key: Key('found-${f.host}'),
                leading: const Icon(Icons.add_circle_outline),
                title: Text(f.id ?? f.host),
                subtitle: Text([f.adapter.label, f.host, ?f.model, ?f.type].join(' · ')),
                onTap: () => _add(f),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog({required this.found});

  final HubFound found;

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _channel = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.found;
    final channel = int.tryParse(_channel.text);
    return AlertDialog(
      title: Text('Dodaj ${f.model ?? f.adapter.label}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${f.adapter.label} · ${f.host}'),
            TextField(
              key: const Key('addName'),
              controller: _name,
              maxLength: 32,
              decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'np. Taras'),
            ),
            if (f.adapter.hasPassword)
              TextField(
                key: const Key('addPassword'),
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Hasło urządzenia (gdy ustawione)'),
              ),
            if (f.adapter != HubAdapter.ownNode)
              TextField(
                key: const Key('addChannel'),
                controller: _channel,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Kanał (wielokanałowe, 0-7, opcjonalnie)'),
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('addOk'),
          onPressed: () => Navigator.pop(context, <String, dynamic>{
            'adapter': f.adapter.wire,
            'host': f.host,
            'id': ?f.id,
            'type': ?f.type,
            if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
            if (_password.text.isNotEmpty) 'password': _password.text,
            if (channel != null && channel >= 0 && channel <= 7) 'channel': channel,
          }),
          child: const Text('Dodaj'),
        ),
      ],
    );
  }
}

/// „Przypisz do huba” (ARCHITEKTURA pkt 4.4): węzeł wystawia hubowi własny token (`POST /api/clients`),
/// hub dostaje go w `POST /api/devices` (`ownNode`), właściciel wpisuje `deviceIndex/{id}` z `via`.
/// Termostat: token `control` i bez lustra - tylko do automatyk. Ekran pokazuje, do którego huba urządzenie
/// już należy (`GET /api/devices` każdego sparowanego huba), i pozwala je odłączyć albo przypisać ponownie.
class AssignToHubScreen extends StatefulWidget {
  const AssignToHubScreen({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<AssignToHubScreen> createState() => _AssignToHubScreenState();
}

/// Hub sparowany z telefonem i to urządzenie w nim (null = nieprzypisane albo hub niedostępny).
typedef _HubEntry = ({PairedDevice hub, HubApi? api, HubChild? child, String? error});

class _AssignToHubScreenState extends State<AssignToHubScreen> {
  Future<List<_HubEntry>>? _hubs;
  PairedDevice? _hub;
  bool _busy = false;
  String? _error;

  DeviceController<Object?, Object?> get c => widget.controller;
  bool get _thermostat => c.device.type == DeviceType.thermostat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hubs ??= _load();
  }

  Future<List<_HubEntry>> _load() async {
    final store = Services.of(context).store;
    final hubs = [
      for (final d in await store.devices())
        if (d.type == DeviceType.hub && d.lastEndpoint != null) d,
    ];
    final entries = await Future.wait(
      hubs.map((h) async {
        final token = await store.token(h.id);
        if (token == null) return (hub: h, api: null, child: null, error: 'telefon nie jest sparowany z hubem');
        final api = HubApi(LocalApi(h.lastEndpoint!, token: token, timeout: const Duration(seconds: 3)));
        try {
          final child = (await api.devices()).where((x) => x.id == c.device.id).firstOrNull;
          return (hub: h, api: api, child: child, error: null);
        } on ThermostatException catch (e) {
          return (hub: h, api: api, child: null, error: e.message);
        }
      }),
    );
    final assigned = entries.where((e) => e.child != null).firstOrNull;
    if (mounted && _hub == null) {
      setState(() => _hub = assigned?.hub ?? (entries.length == 1 ? entries.first.hub : null));
    }
    return entries;
  }

  void _reload() {
    setState(() {
      _hubs = _load();
    });
  }

  /// Tokeny „hub” u węzła (poprzednie przypisania) - żeby ponowne przypisanie nie mnożyło tokenów.
  Future<void> _removeHubTokens() async {
    try {
      for (final p in await c.phones()) {
        if (p.name == 'hub') await c.removePhone(p.id);
      }
    } on ThermostatException {
      // stary token zostanie; usuniesz go w „Telefony”
    }
  }

  Future<void> _assign(_HubEntry e) async {
    final host = c.device.lastEndpoint?.host;
    if (host == null || !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
      setState(() => _error = 'Hub potrzebuje adresu IPv4 urządzenia - połącz się z nim w sieci domowej.');
      return;
    }
    final api = e.api;
    if (api == null) {
      setState(() => _error = 'Ten telefon nie jest sparowany z hubem ${e.hub.name}.');
      return;
    }
    final cloud = Services.of(context).cloud;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _removeHubTokens();
      final t = await c.createToken('hub', _thermostat ? AccessLevel.control : AccessLevel.config);
      await api.addDevice({
        'adapter': 'ownNode',
        'id': c.device.id,
        'host': host,
        'token': t.token,
        'type': c.device.type.wire,
        'name': c.device.name,
        if (_thermostat) 'mirror': false,
      });
      if (!_thermostat && cloud.available && cloud.isHomeOwner && cloud.homeId != null) {
        await writeDeviceIndex(cloud.store, cloud.homeId!, c.device.id, c.device.type, c.device.name, via: e.hub.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _thermostat ? 'Hub widzi termostat - można go używać w automatykach.' : 'Przypisano do huba ${e.hub.name}.',
          ),
        ),
      );
      _reload();
    } on ThermostatException catch (err) {
      setState(() => _error = err.message);
    } on Object catch (err) {
      setState(() => _error = 'Nie udało się: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unassign(_HubEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Odłączyć od huba ${e.hub.name}?'),
        content: const Text(
          'Hub przestanie zbierać stan tego urządzenia i używać go w automatykach; spoza domu nie będzie '
          'przez hub dostępne. W domu działa dalej normalnie.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Odłącz')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cloud = Services.of(context).cloud;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await e.api!.deleteDevice(c.device.id);
      await _removeHubTokens();
      if (cloud.available && cloud.isHomeOwner && cloud.homeId != null) {
        await cloud.store.write('homes/${cloud.homeId}/deviceIndex/${c.device.id}/via', null).catchError((_) {});
      }
      _reload();
    } on ThermostatException catch (err) {
      setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Przypisz do huba'),
        actions: [IconButton(tooltip: 'Odśwież', icon: const Icon(Icons.refresh), onPressed: _reload)],
      ),
      body: FutureBuilder<List<_HubEntry>>(
        future: _hubs,
        builder: (context, snap) {
          final hubs = snap.data;
          if (hubs == null) return const Center(child: CircularProgressIndicator());
          final assigned = hubs.where((e) => e.child != null).firstOrNull;
          final selected = hubs.where((e) => e.hub.id == _hub?.id).firstOrNull;
          final child = assigned?.child;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (assigned != null && child != null)
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    key: const Key('assignedTo'),
                    leading: Icon(Icons.check_circle, color: cs.onPrimaryContainer),
                    title: Text(
                      'Przypisane do huba ${assigned.hub.name}',
                      style: TextStyle(color: cs.onPrimaryContainer),
                    ),
                    subtitle: Text(
                      [
                        child.online
                            ? 'hub widzi urządzenie'
                            : 'hub nie widzi urządzenia${child.error == null ? '' : ' (${child.error})'}',
                        if (!child.mirror)
                          'tylko automatyki'
                        else if (child.linked)
                          'w chmurze przez hub'
                        else
                          'jeszcze bez chmury (hub łączy co 5 min, gdy sam jest w chmurze)',
                      ].join(' · '),
                      style: TextStyle(color: cs.onPrimaryContainer),
                    ),
                  ),
                )
              else
                Text(
                  _thermostat
                      ? 'Hub dostanie od termostatu token „sterowanie” i będzie mógł używać go w automatykach '
                            '(np. „wszyscy wyszli → eko”). Termostat dalej sam łączy się z chmurą.'
                      : 'Hub dostanie od ${c.device.name} własny token, będzie zbierał jego stan (także dla '
                            'automatyk) i przekaże go do chmury - spoza domu sterujesz nim przez hub.',
                ),
              const SizedBox(height: 16),
              if (hubs.isEmpty) const Text('Ten telefon nie jest sparowany z żadnym hubem w sieci domowej.'),
              RadioGroup<String>(
                groupValue: _hub?.id,
                onChanged: (id) => setState(() => _hub = hubs.firstWhere((e) => e.hub.id == id).hub),
                child: Column(
                  children: [
                    for (final e in hubs)
                      RadioListTile<String>(
                        key: Key('assignHub-${e.hub.id}'),
                        value: e.hub.id,
                        title: Text(e.child != null ? '${e.hub.name} (przypisane)' : e.hub.name),
                        subtitle: Text(e.error ?? e.hub.lastEndpoint!.display),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('assignError'),
                    style: TextStyle(color: cs.error),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('assignGo'),
                onPressed: selected == null || _busy ? null : () => _assign(selected),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(selected?.child != null ? 'Przypisz ponownie (nowy token)' : 'Przypisz'),
              ),
              if (assigned != null)
                TextButton(
                  key: const Key('unassign'),
                  onPressed: _busy ? null : () => _unassign(assigned),
                  child: Text('Odłącz od huba ${assigned.hub.name}'),
                ),
            ],
          );
        },
      ),
    );
  }
}
