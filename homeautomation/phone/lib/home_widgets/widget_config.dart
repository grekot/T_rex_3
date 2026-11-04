import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/cloud_access.dart';
import '../data/home_repository.dart';
import '../data/home_widget_store.dart';
import '../firebase_options.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/home_widget.dart';
import '../services.dart';
import '../ui/dashboard_tiles.dart' show channelName, fallbackPoint;
import 'widget_cells.dart';
import 'widget_look.dart';

const _channel = MethodChannel('pl.grekot.homeautomation/widget_config');

/// Uruchamiane przez WidgetConfigActivity.kt przy dodawaniu albo zmianie widżetu na ekranie telefonu.
Future<void> runHomeWidgetConfig() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (firebaseConfigured && Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions);
  final args = await _channel.invokeMapMethod<String, Object?>('args') ?? const {};
  final id = args['id'] as int? ?? 0;
  final multi = args['multi'] == true;
  final cloud = firebaseConfigured ? FirebaseCloudAccess(firebaseOptions) : NoCloudAccess();
  runApp(
    Services.production(
      cloud: cloud,
      child: MaterialApp(
        title: 'Widżet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFFE8590C), useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFFE8590C),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        locale: const Locale('pl', 'PL'),
        supportedLocales: const [Locale('pl', 'PL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: _ConfigRoot(widgetId: id, multi: multi),
      ),
    ),
  );
}

/// Dom widżetu: z konta albo „w telefonie”, przy kilku domach wybór w pasku.
class _ConfigRoot extends StatefulWidget {
  const _ConfigRoot({required this.widgetId, required this.multi});

  final int widgetId;
  final bool multi;

  @override
  State<_ConfigRoot> createState() => _ConfigRootState();
}

class _ConfigRootState extends State<_ConfigRoot> {
  final _store = HomeWidgetStore();
  HomeWidgetConfig? _existing;
  List<Home> _homes = const [];
  Home? _home;
  DeviceHub? _hub;

  /// Pulpity domu - pozycje „Z pulpitu”.
  List<Dashboard> _dashboards = const [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _error == null) unawaited(_load());
  }

  Future<void> _load() async {
    final cloud = Services.of(context).cloud;
    _existing = (await _store.load()).where((c) => c.id == widget.widgetId).firstOrNull;
    try {
      if (firebaseConfigured) {
        final uid = cloud.uid;
        if (uid == null) {
          setState(() {
            _loading = false;
            _error = 'Najpierw zaloguj się w aplikacji HomeAutomation.';
          });
          return;
        }
        _homes = await HomeRepository(store: cloud.store, uid: uid).myHomes();
        if (_homes.isEmpty) {
          setState(() {
            _loading = false;
            _error = 'Najpierw załóż dom w aplikacji HomeAutomation.';
          });
          return;
        }
        _select(_homes.where((h) => h.id == _existing?.homeId).firstOrNull ?? _homes.first);
      } else {
        _select(null);
      }
      setState(() => _loading = false);
    } on Object {
      setState(() {
        _loading = false;
        _error = 'Nie udało się pobrać domów. Sprawdź połączenie z internetem.';
      });
    }
  }

  void _select(Home? home) {
    final services = Services.of(context);
    services.cloud
      ..homeId = home?.id
      ..homeOwnerUid = home?.ownerUid;
    _hub?.dispose();
    _home = home;
    _dashboards = const [];
    final dashboards = services.dashboards.watch(home?.id ?? HomeWidgetConfig.localHome).first;
    dashboards.timeout(const Duration(seconds: 8)).then((l) {
      if (mounted && _home?.id == home?.id) setState(() => _dashboards = l);
    }, onError: (_) {});
    _hub = DeviceHub(
      store: services.store,
      manager: services.manager,
      cloud: services.cloud,
      home: home,
      sceneStore: services.scenes,
    )..start();
  }

  Future<void> _save(List<HomeWidgetItem> items) async {
    await _store.save(
      HomeWidgetConfig(
        id: widget.widgetId,
        homeId: _home?.id ?? HomeWidgetConfig.localHome,
        homeName: _home?.name ?? '',
        ownerUid: _home?.ownerUid ?? '',
        items: items,
      ),
    );
    await _channel.invokeMethod<void>('done');
  }

  @override
  void dispose() {
    _hub?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hub = _hub;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (hub == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Widżet')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(_error ?? 'Brak domu', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return HomeWidgetConfigScreen(
      key: ValueKey(_home?.id),
      hub: hub,
      multi: widget.multi,
      dashboards: _dashboards,
      initial: _existing?.homeId == (_home?.id ?? HomeWidgetConfig.localHome) ? _existing!.items : const [],
      onSave: _save,
      homeSwitcher: _homes.length < 2
          ? null
          : DropdownButton<Home>(
              value: _home,
              underline: const SizedBox(),
              items: [for (final h in _homes) DropdownMenuItem(value: h, child: Text(h.name))],
              onChanged: (h) => setState(() => _select(h)),
            ),
    );
  }
}

/// Wybór pozycji widżetu: jedna kratka albo do [HomeWidgetConfig.maxItems] w widżecie „Kilka pozycji”.
class HomeWidgetConfigScreen extends StatefulWidget {
  const HomeWidgetConfigScreen({
    super.key,
    required this.hub,
    required this.multi,
    required this.onSave,
    this.initial = const [],
    this.homeSwitcher,
    this.dashboards = const [],
  });

  final DeviceHub hub;
  final bool multi;

  /// Pulpity domu: kafelek pulpitu jako gotowa pozycja (podpis, ikona, kolor, wartości).
  final List<Dashboard> dashboards;
  final List<HomeWidgetItem> initial;
  final Future<void> Function(List<HomeWidgetItem> items) onSave;
  final Widget? homeSwitcher;

  @override
  State<HomeWidgetConfigScreen> createState() => _HomeWidgetConfigScreenState();
}

class _HomeWidgetConfigScreenState extends State<HomeWidgetConfigScreen> {
  late final List<HomeWidgetItem> _chosen = [...widget.initial];

  void _flip(HomeWidgetItem item) {
    setState(() {
      if (_chosen.remove(item)) return;
      if (!widget.multi) _chosen.clear();
      if (_chosen.length < HomeWidgetConfig.maxItems) _chosen.add(item);
    });
  }

  /// Pozycja z kafelka pulpitu: zastępuje tę samą (z nowym wyglądem), drugi raz ten sam kafelek - usuwa.
  void _fromTile(HomeWidgetItem item) {
    setState(() {
      final i = _chosen.indexOf(item);
      if (i >= 0) {
        if (_chosen[i].look == item.look) {
          _chosen.removeAt(i);
        } else {
          _chosen[i] = item;
        }
        return;
      }
      if (!widget.multi) _chosen.clear();
      if (_chosen.length < HomeWidgetConfig.maxItems) _chosen.add(item);
    });
  }

  /// „Wygląd” wybranej pozycji.
  Future<void> _editLook(HomeWidgetItem item) async {
    final i = _chosen.indexOf(item);
    if (i < 0) return;
    final r = await Navigator.of(context).push<HomeWidgetItem>(
      MaterialPageRoute(
        builder: (_) => WidgetLookScreen(item: _chosen[i], hub: widget.hub),
      ),
    );
    if (r != null && mounted) setState(() => _chosen[i] = r);
  }

  static String _keyOf(HomeWidgetItem item) => item.kind == HomeWidgetKind.chart
      ? '${item.device}-chart:${item.point}'
      : '${item.device ?? ''}-${item.point ?? item.sceneId ?? ''}';

  /// Urządzenia, o których `describe` już pytaliśmy (wykresy - punkty z polem `history`).
  final _asked = <String>{};

  void _describeAll(DeviceHub hub) {
    for (final d in hub.devices) {
      final c = hub.controller(d.id);
      if (c == null || c.connection == null || c.cachedDescription != null || !_asked.add(d.id)) continue;
      unawaited(c.description().then((_) => mounted ? setState(() {}) : null, onError: (_) => null));
    }
  }

  /// Punkty z historią (pkt 8.1) do wykresu; bez opisu - temperatura termostatu.
  static List<DataPoint> _historyPoints(DeviceType type, DeviceController<Object?, Object?>? c) {
    final desc = c?.cachedDescription;
    if (desc != null) {
      return [
        for (final p in desc.points)
          if (p.history != null) p,
      ];
    }
    return type == DeviceType.thermostat ? [fallbackPoint('temp')] : const [];
  }

  Widget _tile(HomeWidgetItem item, String title, {String? subtitle, required IconData icon}) {
    final i = _chosen.indexOf(item);
    final chosen = i >= 0 ? _chosen[i] : null;
    return ListTile(
      key: Key('widget-item-${_keyOf(item)}'),
      leading: Icon(icon),
      title: Text(chosen?.look.label ?? title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chosen != null)
            IconButton(
              key: Key('widget-look-${_keyOf(item)}'),
              tooltip: 'Wygląd',
              icon: const Icon(Icons.tune),
              onPressed: () => _editLook(item),
            ),
          Icon(chosen != null ? Icons.check_circle : Icons.radio_button_unchecked),
        ],
      ),
      onTap: () => _flip(item),
    );
  }

  /// Kafelki pulpitów, które mają odpowiednik w widżecie.
  List<Widget> _tileItems(DeviceHub hub) => [
    for (final d in widget.dashboards)
      for (final w in d.widgets)
        if (itemFromTile(w, hub) case final item?)
          ListTile(
            key: Key('widget-tile-${w.id}'),
            leading: const Icon(Icons.dashboard_outlined),
            title: Text(tileTitle(w, hub)),
            subtitle: Text('${d.name} · ${w.view.label}'),
            trailing: Icon(
              _chosen.any((x) => x == item && x.look == item.look) ? Icons.check_circle : Icons.radio_button_unchecked,
            ),
            onTap: () => _fromTile(item),
          ),
  ];

  List<Widget> _deviceTiles(DeviceHub hub) {
    final out = <Widget>[];
    for (final d in hub.devices) {
      final c = hub.controller(d.id);
      if (d.type == DeviceType.thermostat) {
        out.add(_tile(HomeWidgetItem.thermostat(d.id), c?.device.name ?? d.name, icon: Icons.thermostat));
      } else if (d.type == DeviceType.sensor) {
        out.add(_sensorTile(d.id, c?.device.name ?? d.name, c));
      } else if (d.type.isLight) {
        final n = channelCount(c?.stateJson);
        final name = c?.device.name ?? d.name;
        out.add(
          _tile(
            HomeWidgetItem.output(d.id, 'on'),
            name,
            subtitle: n > 1 ? 'Wszystkie wyjścia' : null,
            icon: Icons.lightbulb_outline,
          ),
        );
        if (n > 1) {
          for (var i = 1; i <= n; i++) {
            out.add(
              _tile(
                HomeWidgetItem.output(d.id, 'on$i'),
                channelName(c, null, 'on$i'),
                subtitle: name,
                icon: Icons.lightbulb_outline,
              ),
            );
          }
        }
        // Węzeł z czujnikiem temperatury / wilgotności (np. switch4 z DHT).
        if (canShowAsSensor(d.type, c?.stateJson)) out.add(_sensorTile(d.id, name, c));
      }
      // Wykresy punktów z historią (stan, np. grzanie - od razu słupki z czasem włączenia).
      for (final p in _historyPoints(d.type, c)) {
        out.add(
          _tile(
            HomeWidgetItem.chart(
              d.id,
              p.key,
              look: p.kind == PointKind.status ? const WidgetItemLook(bars: true) : const WidgetItemLook(),
            ),
            'Wykres: ${p.name}',
            subtitle: c?.device.name ?? d.name,
            icon: Icons.show_chart,
          ),
        );
      }
    }
    return out;
  }

  /// „Czujnik”: podgląd wartości, które pokaże kratka.
  Widget _sensorTile(String id, String name, DeviceController<Object?, Object?>? c) {
    final values = c == null ? const <String>[] : sensorValues(c);
    return _tile(
      HomeWidgetItem.sensor(id),
      name,
      subtitle: values.isEmpty ? 'Czujnik' : 'Czujnik · ${values.join(' · ')}',
      icon: Icons.sensors,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.hub,
      builder: (context, _) {
        final hub = widget.hub;
        _describeAll(hub);
        final devices = _deviceTiles(hub);
        final tiles = _tileItems(hub);
        final title = widget.multi ? 'Pozycje (${_chosen.length} z ${HomeWidgetConfig.maxItems})' : 'Co pokazać';
        return Scaffold(
          appBar: AppBar(title: Text(title), actions: [?widget.homeSwitcher]),
          body: ListView(
            children: [
              if (devices.isEmpty && hub.scenes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    hub.loaded && !hub.cloudLoading ? 'Brak urządzeń i scen w tym domu.' : 'Wczytywanie…',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (devices.isNotEmpty) const ListTile(dense: true, title: Text('Urządzenia')),
              ...devices,
              if (hub.scenes.isNotEmpty) const ListTile(dense: true, title: Text('Sceny')),
              for (final s in hub.scenes) _tile(HomeWidgetItem.scene(s.id), s.name, icon: Icons.auto_awesome),
              if (tiles.isNotEmpty) ...[
                const ListTile(
                  dense: true,
                  title: Text('Z pulpitu'),
                  subtitle: Text('Podpis, ikona, kolor i wartości jak na kafelku (kopia - zmienisz w „Wygląd”)'),
                ),
                ...tiles,
              ],
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                key: const Key('widget-save'),
                onPressed: _chosen.isEmpty ? null : () => widget.onSave(_chosen),
                child: const Text('Dodaj widżet'),
              ),
            ),
          ),
        );
      },
    );
  }
}
