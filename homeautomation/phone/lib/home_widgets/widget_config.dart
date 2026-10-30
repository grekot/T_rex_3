import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../controllers/device_hub.dart';
import '../data/cloud_access.dart';
import '../data/home_repository.dart';
import '../data/home_widget_store.dart';
import '../firebase_options.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/home_widget.dart';
import '../services.dart';
import '../ui/dashboard_tiles.dart' show channelName;
import 'widget_cells.dart';

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
  });

  final DeviceHub hub;
  final bool multi;
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

  Widget _tile(HomeWidgetItem item, String title, {String? subtitle, required IconData icon}) => ListTile(
    key: Key('widget-item-${item.device ?? ''}-${item.point ?? item.sceneId ?? ''}'),
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: Icon(_chosen.contains(item) ? Icons.check_circle : Icons.radio_button_unchecked),
    onTap: () => _flip(item),
  );

  List<Widget> _deviceTiles(DeviceHub hub) {
    final out = <Widget>[];
    for (final d in hub.devices) {
      final c = hub.controller(d.id);
      if (d.type == DeviceType.thermostat) {
        out.add(_tile(HomeWidgetItem.thermostat(d.id), c?.device.name ?? d.name, icon: Icons.thermostat));
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
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.hub,
      builder: (context, _) {
        final hub = widget.hub;
        final devices = _deviceTiles(hub);
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
