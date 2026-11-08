import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/errors.dart';
import '../data/hub_api.dart';
import '../data/watch_store.dart';
import '../models/dashboard.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import '../models/remote.dart';
import '../models/watch.dart';
import '../services.dart';
import 'dashboard_tiles.dart' show fallbackPoint;
import 'widget_editor.dart';
import 'widgets.dart';

/// „Zegarek” (pkt 13a): pulpit zegarka osobny od pulpitów telefonu, osobno dla każdego domu i zegarka.
/// Strony z tytułem, kafelki half / full / big, podgląd w kształcie i rozdzielczości zegarka.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.hub, this.store, this.hubApi});

  final DeviceHub hub;

  /// Do testów; domyślnie z konta w [Services].
  final WatchStore? store;

  /// Do testów; domyślnie API huba domu w sieci domowej.
  final HubApi? hubApi;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  WatchStore? _store;
  StreamSubscription<List<WatchInfo>>? _sub;
  List<WatchInfo> _registered = const [];
  WatchInfo? _watch;
  List<WatchPage> _pages = const [];
  bool _loading = false;
  bool _dirty = false;
  bool _saving = false;
  bool _exists = false;

  /// Połączenie zegarka z hubem przez Bluetooth (pkt 15.1) i urządzenia, które hub zna (null = nie wiadomo).
  WatchBleLink? _ble;
  Set<String>? _hubDevices;
  bool _bleBusy = false;

  DeviceHub get hub => widget.hub;
  String get _homeId => hub.homeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store != null) return;
    final cloud = Services.of(context).cloud;
    final store = widget.store ?? (cloud.uid == null ? null : WatchStore(cloud.store, cloud.uid!));
    _store = store;
    _sub = store?.watches().listen((list) {
      if (!mounted) return;
      setState(() => _registered = list);
      if (_watch == null) _select(list.firstOrNull ?? builtInWatches.first);
    }, onError: (_) {
      if (mounted && _watch == null) _select(builtInWatches.first);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _select(WatchInfo w) async {
    setState(() {
      _watch = w;
      _loading = true;
      _dirty = false;
      _ble = w.ble?.homeId == _homeId ? w.ble : null;
    });
    unawaited(_loadHubDevices());
    WatchDashboard? d;
    try {
      d = await _store?.load(_homeId, w.id);
    } on Object {
      d = null;
    }
    if (!mounted || _watch?.id != w.id) return;
    setState(() {
      _exists = d != null;
      _pages = d?.pages ?? [const WatchPage(title: 'Dom')];
      _loading = false;
    });
  }

  void _change(List<WatchPage> pages) => setState(() {
    _pages = pages;
    _dirty = true;
  });

  void _changePage(int i, WatchPage p) => _change([for (final (j, x) in _pages.indexed) j == i ? p : x]);

  Future<void> _save() async {
    final w = _watch, store = _store;
    if (w == null || store == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.save(_homeId, w, WatchDashboard(pages: _pages));
      setState(() {
        _dirty = false;
        _exists = true;
      });
      final link = _ble;
      if (link != null) await _syncRemote(link, w);
      final missing = link == null ? const <String>[] : _notInHub(link.hub);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            missing.isEmpty
                ? 'Zapisano. Zegarek pobierze pulpit przy otwarciu aplikacji.'
                : 'Zapisano. Hub nie zna: ${missing.join(', ')} - przez Bluetooth zegarek nimi nie steruje.',
          ),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie zapisano: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Bluetooth bez telefonu (pkt 15.1)

  /// Hub domu z połączeniem w sieci domowej (rejestracja idzie wprost do huba, tokenem tej osoby).
  DeviceController<Object?, Object?>? get _hubController => hub.hubs.firstOrNull;

  HubApi? get _hubApi {
    if (widget.hubApi != null) return widget.hubApi;
    final local = _hubController?.localApi;
    return local == null ? null : HubApi(local);
  }

  Future<void> _loadHubDevices() async {
    final api = _hubApi;
    if (api == null) return;
    try {
      final list = await api.devices();
      if (mounted) setState(() => _hubDevices = {for (final c in list) c.id});
    } on Object {
      // Bez listy - ostrzeżenie wg `via` z bazy.
    }
  }

  /// Urządzenia kafelków zegarka, których hub [hubId] nie zna (polecenia z Bluetooth by nie przeszły).
  List<String> _notInHub(String hubId) {
    final ids = <String>{
      for (final p in _pages)
        for (final t in p.tiles)
          if (t.view != WatchView.scene && t.device != null && t.device != hubId) t.device!,
    };
    final known = _hubDevices;
    return [
      for (final id in ids)
        if (known != null ? !known.contains(id) : hub.device(id)?.via != hubId) hub.device(id)?.name ?? id,
    ];
  }

  /// Lista punktów z pulpitu do `homes/{h}/remotes/{id}` (`cfgVer` + 1, najmniej [minVer]) i - w sieci domowej -
  /// do huba (`PUT`: tylko `points`, `cfgVer`, `name`; treść do 4 kB, dłuższa lista - hub pobiera ją z chmury po `reload`).
  Future<void> _syncRemote(WatchBleLink link, WatchInfo w, {int minVer = 0}) async {
    final store = _store!;
    final cloudVer = asIntOrNull((await store.loadRemote(_homeId, link.id))?['cfgVer'], 'cfgVer') ?? 0;
    final ver = math.max(minVer, cloudVer + 1);
    final doc = remoteDoc(
      ownerUid: store.uid,
      name: w.name,
      hub: link.hub,
      cfgVer: ver,
      points: watchRemotePoints(_pages, link.hub),
    );
    await store.saveRemote(_homeId, link.id, doc);
    final api = _hubApi;
    if (api == null) return;
    final local = <String, dynamic>{'name': doc['name'], 'cfgVer': ver, 'points': doc['points']};
    var sent = false;
    if (utf8.encode(jsonEncode(local)).length <= maxRemotePutBytes) {
      try {
        await api.putRemote(link.id, local);
        sent = true;
      } on ThermostatException {
        // Starszy hub albo chwilowy błąd - niżej `reload`.
      }
    }
    if (!sent) {
      final c = _hubController;
      if (c != null && c.canConfig) await c.sendJson({'reload': true});
    }
  }

  Future<void> _pair(WatchInfo w) async {
    final api = _hubApi, hubId = _hubController?.device.id, store = _store;
    if (api == null || hubId == null || store == null) return;
    setState(() => _bleBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await api.registerRemote(watchId: w.id, name: w.name);
      final link = WatchBleLink(homeId: _homeId, hub: hubId, id: r.id, slot: r.slot, key: r.key);
      await store.saveBle(w.id, link);
      // Ponowna rejestracja = nowy klucz i licznik; lista punktów co najmniej z wersją huba.
      await _syncRemote(link, w, minVer: r.cfgVer);
      if (!mounted) return;
      setState(() => _ble = link);
      messenger.showSnackBar(
        const SnackBar(content: Text('Połączono. Zegarek pobierze klucz przy otwarciu aplikacji „Dom”.')),
      );
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie połączono: ${e.message}')));
    } finally {
      if (mounted) setState(() => _bleBusy = false);
    }
  }

  Future<void> _unpair(WatchInfo w) async {
    final link = _ble, store = _store;
    if (link == null || store == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Odłączyć zegarek od huba?'),
        content: const Text('Klucz przestanie działać - zegarek będzie sterował domem tylko przez telefon i chmurę.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            key: const Key('watchBleUnlinkOk'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Odłącz'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bleBusy = true);
    try {
      await _hubApi?.deleteRemote(link.id);
    } on ThermostatException {
      // Poza domem - hub unieważni klucz, gdy zobaczy, że wpisu w chmurze już nie ma.
    }
    await store.saveRemote(_homeId, link.id, null);
    await store.saveBle(w.id, null);
    if (mounted) {
      setState(() {
        _ble = null;
        _bleBusy = false;
      });
    }
  }

  Widget _bleSection(BuildContext context, WatchInfo w) {
    final cs = Theme.of(context).colorScheme;
    final link = _ble;
    final hubC = _hubController;
    final String? why = !w.canPair
        ? 'Najpierw otwórz aplikację „Dom” na zegarku, żeby się zgłosił.'
        : hubC == null
        ? 'W domu nie ma huba.'
        : _hubApi == null
        ? 'Połącz w sieci domowej - rejestracja idzie wprost do huba.'
        : !hub.accessFor(hubC.device.id).canControl
        ? 'Potrzebny poziom sterowania huba.'
        : null;
    final missing = link != null ? _notInHub(link.hub) : (hubC == null ? const <String>[] : _notInHub(hubC.device.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Bluetooth (bez telefonu)'),
        if (link != null)
          ListTile(
            key: const Key('watchBleLinked'),
            leading: const Icon(Icons.bluetooth_connected),
            title: Text('Połączony z hubem ${hub.device(link.hub)?.name ?? link.hub}'),
            subtitle: Text(
              'Zegarek steruje domem przez węzeł Bluetooth, także bez telefonu. Lista kafelków trafia do huba przy '
              'zapisie pulpitu (slot ${link.slot}).',
            ),
            trailing: TextButton(
              key: const Key('watchBleUnlink'),
              onPressed: _bleBusy ? null : () => _unpair(w),
              child: const Text('Odłącz'),
            ),
          )
        else
          ListTile(
            key: const Key('watchBle'),
            leading: const Icon(Icons.bluetooth),
            title: const Text('Połącz zegarek z hubem (Bluetooth)'),
            subtitle: Text(why ?? 'Zegarek będzie sterował domem przez węzeł btnode, także bez telefonu i internetu.'),
            trailing: _bleBusy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator()) : null,
            enabled: why == null && !_bleBusy,
            onTap: () => _pair(w),
          ),
        if (missing.isNotEmpty && (link != null || why == null))
          Padding(
            key: const Key('watchBleMissing'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Hub nie zna: ${missing.join(', ')}. Przez Bluetooth zegarek nimi nie steruje - dodaj je do huba '
              '(np. termostat w ustawieniach „Przypisz do huba”).',
              style: TextStyle(color: cs.error),
            ),
          ),
      ],
    );
  }

  Future<void> _remove() async {
    final w = _watch, store = _store;
    if (w == null || store == null) return;
    await store.remove(_homeId, w.id);
    if (!mounted) return;
    setState(() {
      _exists = false;
      _dirty = false;
      _pages = [const WatchPage(title: 'Dom')];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Usunięto. Zegarek pokaże listę urządzeń, do których masz dostęp.')),
    );
  }

  Future<void> _addTile(int page) async {
    final w = await Navigator.of(
      context,
    ).push<DashWidget>(MaterialPageRoute(builder: (_) => AddWidgetScreen(hub: hub, forWatch: true)));
    if (w == null) return;
    final view = WatchView.fromWire(w.view.wire);
    final tile = WatchTile(
      id: newLocalId('t'),
      view: view,
      size: WatchTileSize.defaultFor(view),
      device: w.device,
      point: w.point,
      label: w.label,
      sceneId: w.sceneId,
    );
    _changePage(page, _pages[page].copyWith(tiles: [..._pages[page].tiles, tile]));
  }

  Future<void> _tileMenu(int page, WatchTile t, String action) async {
    final tiles = _pages[page].tiles;
    List<WatchTile> replaced(WatchTile n) => [for (final x in tiles) x.id == t.id ? n : x];
    switch (action) {
      case 'label':
        final label = await showTextInputDialog(context, title: 'Podpis', initial: t.label ?? '', maxLength: 16);
        if (label == null) return;
        _changePage(
          page,
          _pages[page].copyWith(
            tiles: replaced(label.trim().isEmpty ? t.copyWith(clearLabel: true) : t.copyWith(label: label.trim())),
          ),
        );
      case 'delete':
        _changePage(page, _pages[page].copyWith(tiles: [...tiles.where((x) => x.id != t.id)]));
      case final String a when a.startsWith('move:'):
        final to = int.parse(a.substring(5));
        final pages = [..._pages];
        pages[page] = pages[page].copyWith(tiles: [...tiles.where((x) => x.id != t.id)]);
        pages[to] = pages[to].copyWith(tiles: [...pages[to].tiles, t]);
        _change(pages);
      default:
        _changePage(page, _pages[page].copyWith(tiles: replaced(t.copyWith(size: WatchTileSize.fromWire(action)))));
    }
  }

  Future<void> _pageMenu(int i, String action) async {
    switch (action) {
      case 'rename':
        final title = await showTextInputDialog(context, title: 'Tytuł strony', initial: _pages[i].title, maxLength: 16);
        if (title != null) _changePage(i, _pages[i].copyWith(title: title.trim()));
      case 'up' || 'down':
        final to = action == 'up' ? i - 1 : i + 2;
        if (to < 0 || to > _pages.length) return;
        _change(reorder(_pages, i, to));
      case 'delete':
        _change([..._pages]..removeAt(i));
    }
  }

  String _tileTitle(WatchTile t) {
    if (t.label != null) return t.label!;
    if (t.view == WatchView.scene) return hub.scene(t.sceneId ?? '')?.name ?? 'Scena';
    final name = hub.device(t.device ?? '')?.name ?? t.device ?? '?';
    if (t.view == WatchView.thermostat || t.point == null) return name;
    return '$name · ${fallbackPoint(t.point!).name}';
  }

  @override
  Widget build(BuildContext context) {
    final w = _watch;
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Pulpit zegarka'),
          actions: [
            TextButton(
              key: const Key('watchSave'),
              onPressed: _dirty && !_saving && w != null ? _save : null,
              child: const Text('Zapisz'),
            ),
          ],
        ),
        body: _store == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Pulpit zegarka wymaga konta - zegarek łączy się tylko przez chmurę.'),
                ),
              )
            : w == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: listPadding(context, const EdgeInsets.only(bottom: 32)),
                children: [
                  _watchPicker(context, w),
                  _bleSection(context, w),
                  if (_loading)
                    const LinearProgressIndicator()
                  else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: WatchPreview(watch: w, pages: _pages, hub: hub)),
                    ),
                    Text(
                      'Podgląd przewiniesz palcem jak na zegarku. Kafelki urządzeń bez dostępu zegarek pomija.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final (i, page) in _pages.indexed) _pageEditor(context, i, page),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton.icon(
                        key: const Key('watchAddPage'),
                        onPressed: () => _change([..._pages, const WatchPage(title: 'Strona')]),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Nowa strona'),
                      ),
                    ),
                    if (_exists)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: TextButton(
                          onPressed: _remove,
                          child: const Text('Usuń pulpit zegarka (pokaże listę urządzeń)'),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _watchPicker(BuildContext context, WatchInfo w) {
    final all = [
      ..._registered,
      for (final b in builtInWatches)
        if (!_registered.any((r) => r.id == b.id)) b,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(w.shape == WatchShape.round ? Icons.watch_outlined : Icons.crop_portrait),
          title: DropdownButton<String>(
            key: const Key('watchPicker'),
            isExpanded: true,
            value: w.id,
            items: [
              for (final x in all)
                DropdownMenuItem(
                  value: x.id,
                  child: Text(x.registered ? x.name : '${x.name} (model)', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) async {
              if (id == null || id == w.id) return;
              if (_dirty && !await _confirmDiscard()) return;
              await _select(all.firstWhere((x) => x.id == id));
            },
          ),
          subtitle: Text(w.resolution),
        ),
        if (_registered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Żaden zegarek się jeszcze nie zgłosił - otwórz aplikację „Dom” na zegarku (zalogowaną tym kontem). '
              'Do tego czasu możesz ułożyć pulpit dla wybranego modelu.',
            ),
          ),
      ],
    );
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Porzucić zmiany?'),
          content: const Text('Pulpit tego zegarka nie został zapisany.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Porzuć')),
          ],
        ),
      ) ==
      true;

  Widget _pageEditor(BuildContext context, int i, WatchPage page) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: Key('watchPage-$i'),
          title: Text(page.title.isEmpty ? 'Strona ${i + 1} (bez tytułu)' : page.title,
              style: Theme.of(context).textTheme.titleMedium),
          trailing: PopupMenuButton<String>(
            onSelected: (a) => _pageMenu(i, a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Tytuł')),
              if (i > 0) const PopupMenuItem(value: 'up', child: Text('Wyżej')),
              if (i < _pages.length - 1) const PopupMenuItem(value: 'down', child: Text('Niżej')),
              const PopupMenuItem(value: 'delete', child: Text('Usuń stronę')),
            ],
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (a, b) => _changePage(i, page.copyWith(tiles: reorder(page.tiles, a, b))),
          children: [
            for (final (j, t) in page.tiles.indexed)
              ListTile(
                key: ValueKey(t.id),
                dense: true,
                leading: ReorderableDragStartListener(index: j, child: const Icon(Icons.drag_handle)),
                title: Text(_tileTitle(t)),
                subtitle: Text('${t.view.label} · ${t.size.label}'),
                trailing: PopupMenuButton<String>(
                  key: Key('watchTileMenu-${t.id}'),
                  onSelected: (a) => _tileMenu(i, t, a),
                  itemBuilder: (_) => [
                    for (final s in WatchTileSize.values)
                      CheckedPopupMenuItem(value: s.wire, checked: t.size == s, child: Text('Rozmiar: ${s.label}')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'label', child: Text('Podpis')),
                    for (final (k, p) in _pages.indexed)
                      if (k != i)
                        PopupMenuItem(value: 'move:$k', child: Text('Przenieś na: ${p.title.isEmpty ? 'stronę ${k + 1}' : p.title}')),
                    const PopupMenuItem(value: 'delete', child: Text('Usuń')),
                  ],
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: TextButton.icon(
              key: Key('watchAddTile-$i'),
              onPressed: () => _addTile(i),
              icon: const Icon(Icons.add),
              label: const Text('Kafelek'),
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}

/// Podgląd ekranu zegarka: ten sam układ co na zegarku (`layoutWatchPages`), przeskalowany,
/// przycięty do koła albo prostokąta, przewijany palcem; wartości na żywo z urządzeń.
class WatchPreview extends StatelessWidget {
  const WatchPreview({super.key, required this.watch, required this.pages, required this.hub, this.size = 280});

  final WatchInfo watch;
  final List<WatchPage> pages;
  final DeviceHub hub;

  /// Szerokość podglądu w px telefonu.
  final double size;

  @override
  Widget build(BuildContext context) {
    final layout = layoutWatchPages(pages, watch.width, watch.height, watch.shape);
    final k = size / watch.width;
    final round = watch.shape == WatchShape.round;
    final screen = SizedBox(
      width: watch.width * k,
      height: watch.height * k,
      child: ColoredBox(
        color: Colors.black,
        child: SingleChildScrollView(
          key: const Key('watchPreview'),
          child: SizedBox(
            width: watch.width * k,
            height: layout.height * k,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 30 * k,
                  child: Text(
                    hub.home?.name ?? 'Dom',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 26 * k),
                  ),
                ),
                for (final b in layout.blocks)
                  Positioned(
                    left: b.x * k,
                    top: b.y * k,
                    width: b.w * k,
                    height: b.h * k,
                    child: b.tile == null
                        ? Center(
                            child: Text(
                              b.header!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white70, fontSize: 24 * k),
                            ),
                          )
                        : _PreviewTile(tile: b.tile!, hub: hub, k: k),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(36 * k),
        border: Border.all(color: Colors.grey.shade600, width: 6),
      ),
      child: round ? ClipOval(child: screen) : ClipRRect(borderRadius: BorderRadius.circular(36 * k), child: screen),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.tile, required this.hub, required this.k});

  final WatchTile tile;
  final DeviceHub hub;
  final double k;

  @override
  Widget build(BuildContext context) {
    final t = tile;
    final device = t.device == null ? null : hub.device(t.device!);
    final level = t.device == null ? AccessLevel.control : hub.accessFor(t.device!);
    final state = t.device == null ? null : hub.controller(t.device!)?.stateJson;
    final hidden = t.view != WatchView.scene && (device == null || level == AccessLevel.none);
    final scene = t.sceneId == null ? null : hub.scene(t.sceneId!);
    final title =
        t.label ??
        (t.view == WatchView.scene
            ? scene?.name ?? 'Scena'
            : t.view == WatchView.thermostat || t.point == null
            ? device?.name ?? '?'
            : fallbackPoint(t.point!).name);
    final p = fallbackPoint(t.point ?? (t.view == WatchView.thermostat ? 'temp' : ''));
    final value = switch (t.view) {
      WatchView.scene => '▶',
      WatchView.toggle => p.valueIn(state) == true ? 'wł.' : 'wył.',
      WatchView.status => p.valueIn(state) == true ? '●' : '○',
      WatchView.thermostat => '${p.format(p.valueIn(state))} → ${fallbackPoint('target').format(state?['target'])}',
      WatchView.stepper => '−  ${p.format(p.valueIn(state))}  +',
      WatchView.value => p.format(p.valueIn(state)),
    };
    final accent = t.view == WatchView.scene ? const Color(0xFF7048E8) : const Color(0xFF2B2B2B);
    return Opacity(
      opacity: hidden ? 0.3 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20 * k)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 8 * k),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: 20 * k),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  hidden ? 'pominięty' : value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (t.size == WatchTileSize.big ? 44 : 30) * k,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
