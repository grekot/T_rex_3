import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../data/watch_store.dart';
import '../models/dashboard.dart';
import '../models/home.dart';
import '../models/watch.dart';
import '../services.dart';
import 'dashboard_tiles.dart' show fallbackPoint;
import 'widget_editor.dart';
import 'widgets.dart';

/// „Zegarek” (pkt 13a): pulpit zegarka osobny od pulpitów telefonu, osobno dla każdego domu i zegarka.
/// Strony z tytułem, kafelki half / full / big, podgląd w kształcie i rozdzielczości zegarka.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.hub, this.store});

  final DeviceHub hub;

  /// Do testów; domyślnie z konta w [Services].
  final WatchStore? store;

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
    });
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
      messenger.showSnackBar(const SnackBar(content: Text('Zapisano. Zegarek pobierze pulpit przy otwarciu aplikacji.')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie zapisano: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _watchPicker(context, w),
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
