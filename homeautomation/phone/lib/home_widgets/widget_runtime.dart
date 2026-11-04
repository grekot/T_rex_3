import 'dart:async';
import 'dart:convert';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/home_widget.dart';
import '../models/scene.dart';
import 'widget_cells.dart';
import 'widget_chart.dart';

/// Tworzy [DeviceHub] domu widżetu; [wanted] - urządzenia, z którymi ma się łączyć.
typedef WidgetHubFactory = DeviceHub Function(HomeWidgetConfig config, Set<String> Function() wanted);

/// Serce usługi widżetów: trzyma połączenia z urządzeniami z widżetów (po jednym [DeviceHub] na dom), po każdej
/// zmianie stanu przekazuje kratki do [render], wykonuje dotknięcia. Przy zgaszonym ekranie rozłącza się.
class WidgetRuntime {
  WidgetRuntime({
    required this.hubFactory,
    required this.render,
    this.debounce = const Duration(milliseconds: 150),
    this.readyTimeout = const Duration(seconds: 8),
    this.messageTime = const Duration(seconds: 4),
    this.iconPng,
    this.chartLoader,
    this.chartRefresh = const Duration(minutes: 15),
  });

  /// Wykres pozycji `chart` (historia z chmury → obrazek); null = bez wykresów (testy bez nich).
  final Future<WidgetChart?> Function(DeviceHub hub, HomeWidgetItem item)? chartLoader;

  /// Co ile odświeżać wykresy (historia zapisuje się co 15 min).
  final Duration chartRefresh;
  final _charts = <String, ({WidgetChart? chart, DateTime at})>{};
  final _chartsLoading = <String>{};
  Timer? _chartTimer;

  /// Ikona z katalogu aplikacji jako PNG (base64) dla kratek z `iconKey`; null = tylko ikony zapasowe Androida.
  final Future<String?> Function(String key)? iconPng;
  final _icons = <String, String?>{};

  final WidgetHubFactory hubFactory;

  /// JSON `{"<id widżetu>": [kratki]}`.
  final void Function(String json) render;
  final Duration debounce;

  /// Ile czekać przy dotknięciu na połączenie (usługa mogła dopiero wystartować).
  final Duration readyTimeout;

  /// Jak długo widać komunikat po akcji.
  final Duration messageTime;

  List<HomeWidgetConfig> _configs = const [];
  final _hubs = <String, DeviceHub>{};
  final _overrides = <(int, int), ({String subtitle, bool? active})>{};
  final _overrideTimers = <(int, int), Timer>{};
  Timer? _renderTimer;
  String? _lastRender;
  String? _message;
  bool _paused = false;

  /// Połączenia, na których już pytaliśmy o `describe` dla czujnika / wykresu (raz na połączenie) i na których
  /// odpowiedź już przyszła.
  final _described = Expando<bool>();
  final _describeDone = Expando<bool>();

  /// Hub domu (testy).
  DeviceHub? hub(String homeId) => _hubs[homeId];

  /// Komunikat zamiast stanu, np. po wylogowaniu; połączenia zostają zamknięte.
  void showMessage(String? message) {
    _message = message;
    if (message != null) _closeHubs();
    _scheduleRender();
  }

  /// Nowa lista widżetów: domy bez widżetów są zamykane, reszta dostaje nowy zestaw urządzeń.
  void update(List<HomeWidgetConfig> configs) {
    _configs = configs;
    final homes = {for (final c in configs) c.homeId};
    for (final h in _hubs.keys.where((h) => !homes.contains(h)).toList()) {
      _closeHub(h);
    }
    if (!_paused && _message == null) _openHubs();
    for (final hub in _hubs.values) {
      hub.resync();
    }
    _syncChartTimer();
    _scheduleRender();
  }

  void _openHubs() {
    for (final config in _configs) {
      if (_hubs.containsKey(config.homeId)) continue;
      final h = config.homeId;
      final hub = hubFactory(config, () => _wanted(h));
      _hubs[h] = hub;
      hub
        ..addListener(_scheduleRender)
        ..start();
    }
  }

  void _closeHub(String homeId) {
    final hub = _hubs.remove(homeId);
    hub?.removeListener(_scheduleRender);
    hub?.dispose();
  }

  void _closeHubs() {
    for (final h in _hubs.keys.toList()) {
      _closeHub(h);
    }
  }

  /// Urządzenia widżetów domu; przy scenach także huby i urządzenia z akcji scen.
  Set<String> _wanted(String homeId) {
    final hub = _hubs[homeId];
    final items = [
      for (final c in _configs)
        if (c.homeId == homeId) ...c.items,
    ];
    final ids = <String>{for (final i in items) ?i.device};
    if (hub == null) return ids;
    if (items.any((i) => i.kind == HomeWidgetKind.scene)) {
      ids.addAll(hub.devices.where((d) => d.type == DeviceType.hub).map((d) => d.id));
      void add(Scene scene, int depth) {
        ids.addAll(scene.devices);
        if (depth >= 3) return;
        for (final a in scene.actions) {
          final inner = a.scene == null ? null : hub.scene(a.scene!);
          if (inner != null) add(inner, depth + 1);
        }
      }

      for (final i in items) {
        final scene = i.sceneId == null ? null : hub.scene(i.sceneId!);
        if (scene != null) add(scene, 0);
      }
    }
    return ids;
  }

  /// Ekran zgaszony - widżetów nie widać, więc bez połączeń i bez zużycia baterii.
  void pause() {
    _paused = true;
    _closeHubs();
    _syncChartTimer();
  }

  void resume() {
    _paused = false;
    if (_message == null) _openHubs();
    _syncChartTimer();
    _scheduleRender();
  }

  /// Zmiana sieci: dom ↔ poza domem. Kontrolery wybierają drogę od nowa.
  void networkChanged() {
    for (final hub in _hubs.values) {
      hub.refreshRoutes();
    }
  }

  void _scheduleRender() {
    _renderTimer?.cancel();
    _renderTimer = Timer(debounce, _render);
  }

  /// Czujnik pokazuje punkty z `describe` - pobieramy go raz na połączenie i rysujemy jeszcze raz.
  void _describeSensors(HomeWidgetConfig config, DeviceHub hub) {
    for (final item in config.items.where((i) => i.kind == HomeWidgetKind.sensor || i.kind == HomeWidgetKind.chart)) {
      final c = hub.controller(item.device!);
      final conn = c?.connection;
      if (c == null || conn == null || c.cachedDescription != null || _described[conn] == true) continue;
      _described[conn] = true;
      unawaited(
        c.description().then((d) {
          _describeDone[conn] = true;
          _scheduleRender();
        }, onError: (_) => _describeDone[conn] = true),
      );
    }
  }

  static String _chartKey(String homeId, HomeWidgetItem i) =>
      '$homeId|${i.device}|${i.point}|${i.look.range}|${i.look.bars}|${i.look.color}';

  /// Wykres pozycji: z pamięci, a gdy go nie ma albo jest starszy niż [chartRefresh] - wczytanie w tle (po
  /// `describe` urządzenia, żeby wiedzieć, które pole historii czytać) i ponowne rysowanie.
  WidgetChart? _chartFor(String homeId, DeviceHub hub, HomeWidgetItem item) {
    final load = chartLoader;
    if (load == null) return null;
    final key = _chartKey(homeId, item);
    final have = _charts[key];
    final fresh = have != null && DateTime.now().difference(have.at) < chartRefresh;
    if (!fresh && !_chartsLoading.contains(key)) {
      final conn = hub.controller(item.device!)?.connection;
      final described =
          conn != null && (hub.controller(item.device!)!.cachedDescription != null || _describeDone[conn] == true);
      if (described) {
        _chartsLoading.add(key);
        unawaited(
          load(hub, item)
              .then((c) => _charts[key] = (chart: c ?? have?.chart, at: DateTime.now()), onError: (_) => null)
              .whenComplete(() {
                _chartsLoading.remove(key);
                _scheduleRender();
              }),
        );
      }
    }
    return have?.chart;
  }

  /// Wykresy odświeżają się same co [chartRefresh], gdy są na widżetach (i ekran nie jest zgaszony).
  void _syncChartTimer() {
    final need = !_paused && _configs.any((c) => c.items.any((i) => i.kind == HomeWidgetKind.chart));
    if (!need) {
      _chartTimer?.cancel();
      _chartTimer = null;
    } else {
      _chartTimer ??= Timer.periodic(chartRefresh, (_) => _scheduleRender());
    }
  }

  void _render() {
    final out = <String, Object?>{};
    for (final config in _configs) {
      final hub = _hubs[config.homeId];
      if (hub != null && _message == null) _describeSensors(config, hub);
      out['${config.id}'] = [
        for (var i = 0; i < config.items.length; i++)
          if (_message != null)
            WidgetCell(title: 'HomeAutomation', subtitle: _message!, icon: 'lock', dimmed: true).toJson()
          else if (hub != null)
            _cellJson(
              _withOverride(
                config.id,
                i,
                widgetCell(
                  config.items[i],
                  hub,
                  chart: config.items[i].kind == HomeWidgetKind.chart
                      ? _chartFor(config.homeId, hub, config.items[i])
                      : null,
                ),
              ),
            ),
      ];
    }
    // Przy pauzie zostaje ostatni obraz; pusta lista kratek by go skasowała.
    out.removeWhere((_, cells) => (cells as List).isEmpty);
    final json = jsonEncode(out);
    if (json == _lastRender) return;
    _lastRender = json;
    render(json);
  }

  /// JSON kratki z obrazkiem ikony, gdy już narysowany (inaczej rysujemy w tle i rysujemy widżet jeszcze raz).
  Map<String, dynamic> _cellJson(WidgetCell cell) {
    final j = cell.toJson();
    final key = cell.iconKey, draw = iconPng;
    if (key == null || draw == null) return j;
    if (_icons.containsKey(key)) {
      if (_icons[key] case final png?) j['iconPng'] = png;
      return j;
    }
    _icons[key] = null; // w toku - jeden raz na klucz
    unawaited(
      draw(key).then((png) {
        _icons[key] = png;
        if (png != null) _scheduleRender();
      }, onError: (_) {}),
    );
    return j;
  }

  WidgetCell _withOverride(int id, int index, WidgetCell cell) {
    final o = _overrides[(id, index)];
    return o == null ? cell : cell.copyWith(subtitle: o.subtitle, active: o.active);
  }

  /// Chwilowy napis na kratce; z [hold] sam znika.
  void _override(int id, int index, String subtitle, {bool? active, bool hold = false}) {
    final key = (id, index);
    _overrideTimers.remove(key)?.cancel();
    _overrides[key] = (subtitle: subtitle, active: active);
    if (hold) _overrideTimers[key] = Timer(messageTime, () => _clearOverride(key));
    _scheduleRender();
  }

  void _clearOverride((int, int) key) {
    _overrideTimers.remove(key)?.cancel();
    _overrides.remove(key);
    _scheduleRender();
  }

  Future<void> _untilReady(bool Function() ready) async {
    final end = DateTime.now().add(readyTimeout);
    while (!ready() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Dotknięcie kratki [index] widżetu [id].
  Future<void> tap(int id, int index) async {
    final config = _configs.where((c) => c.id == id).firstOrNull;
    if (config == null || index >= config.items.length || _message != null) return;
    if (_paused) resume();
    final hub = _hubs[config.homeId];
    if (hub == null) return;
    final item = config.items[index];
    switch (item.kind) {
      case HomeWidgetKind.output when item.look.tap != 'open':
        await _tapOutput(hub, id, index, item);
      case HomeWidgetKind.output:
        break; // „Otwiera urządzenie” - otwiera aplikację po stronie Androida
      case HomeWidgetKind.scene:
        await _tapScene(hub, config.homeId, id, index, item);
      case HomeWidgetKind.thermostat || HomeWidgetKind.sensor || HomeWidgetKind.chart:
        break; // otwiera aplikację po stronie Androida
    }
  }

  Future<void> _tapOutput(DeviceHub hub, int id, int index, HomeWidgetItem item) async {
    _override(id, index, 'Wysyłanie…');
    await _untilReady(() => hub.controller(item.device!)?.phase != ConnectPhase.connecting && hub.loaded);
    final c = hub.controller(item.device!);
    if (c == null || c.stateJson == null) {
      _override(id, index, 'Brak kontaktu', hold: true);
      return;
    }
    if (!hub.accessFor(item.device!).canControl) {
      _override(id, index, 'Brak uprawnień', hold: true);
      return;
    }
    final p = (await c.description())?.point(item.point!);
    final set = p?.kind == PointKind.action ? p!.setFor(true) : outputToggle(item.point!, c.stateJson);
    if (p?.kind != PointKind.action) _override(id, index, 'Wysyłanie…', active: outputActiveAfter(set));
    final r = await c.sendJson(set);
    if (r.errors.isNotEmpty) {
      _override(id, index, describeErrors(r.errors), hold: true);
    } else {
      _clearOverride((id, index));
    }
  }

  Future<void> _tapScene(DeviceHub hub, String homeId, int id, int index, HomeWidgetItem item) async {
    _override(id, index, 'Uruchamianie…', active: true);
    await _untilReady(() {
      if (hub.scene(item.sceneId!) == null || !hub.loaded) return false;
      return _wanted(homeId).every((d) => hub.controller(d)?.phase != ConnectPhase.connecting);
    });
    final scene = hub.scene(item.sceneId!);
    if (scene == null) {
      _override(id, index, 'Niedostępna', active: false, hold: true);
      return;
    }
    final problems = await hub.runScene(scene);
    _override(id, index, problems.isEmpty ? 'Uruchomiona' : problems.first, active: false, hold: true);
  }

  void dispose() {
    _renderTimer?.cancel();
    _chartTimer?.cancel();
    for (final t in _overrideTimers.values) {
      t.cancel();
    }
    _closeHubs();
  }
}
