import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../controllers/home_session.dart';
import '../data/dashboard_store.dart';
import '../data/history.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/room.dart';
import '../models/scene.dart';
import '../services.dart';
import 'account_menu.dart';
import 'dashboard_summary.dart';
import 'dashboard_tiles.dart';
import 'notifications_screen.dart';
import 'tile_settings.dart';
import 'watch_screen.dart';
import 'widget_editor.dart';
import 'widgets.dart';

/// Zakładka „Pulpit” (pkt 13): pulpity prywatne i wspólne domu, tryb edycji (dodawanie widżetu
/// w 3 krokach, przeciąganie, rozmiar, usuwanie, sceny). Wspólne zmienia tylko właściciel.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.hub, this.session});

  final DeviceHub hub;
  final HomeSession? session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DashboardStore _store;
  StreamSubscription<List<Dashboard>>? _sub;
  List<Dashboard>? _list;
  HomePrefs _prefs = const HomePrefs();
  String? _selected;
  bool _editing = false;
  HistorySource? _history;

  /// Pokoje domu - sekcje pulpitu startowego.
  List<Room> _rooms = const [];
  StreamSubscription<List<Room>>? _roomsSub;

  /// Bez konta - jeden dom „w telefonie”.
  String get _homeId => widget.session?.current?.id ?? 'local';
  bool get _owner => widget.session?.isOwner ?? false;
  bool get _withAccount => widget.session != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final services = Services.of(context);
    _store = services.dashboards;
    if (_withAccount && services.cloud.available) {
      final cloud = services.cloud;
      final home = _homeId;
      _history = (device, field, {int hours = 24}) =>
          loadHistory(cloud.store, homeId: home, deviceId: device, field: field, hours: hours);
    }
    _roomsSub = services.rooms.watch().listen((r) => _rooms = sortRooms(r), onError: (_) {});
    _sub = _store.watch(_homeId).listen((l) {
      if (mounted) setState(() => _list = l);
    }, onError: (_) {});
    _store.prefs(_homeId).then((p) {
      if (mounted) setState(() => _prefs = p);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _roomsSub?.cancel();
    super.dispose();
  }

  Dashboard? get _current {
    final l = _list;
    if (l == null || l.isEmpty) return null;
    return l.where((d) => d.id == _selected).firstOrNull ??
        l.where((d) => d.id == _prefs.defaultDashboard).firstOrNull ??
        l.first;
  }

  bool _canEdit(Dashboard d) => d.scope == DashboardScope.private || _owner;

  Future<void> _save(Dashboard d) async {
    // Od razu na ekranie; magazyn i tak przyśle nową listę.
    setState(() => _list = sortDashboards([...?_list?.where((x) => x.id != d.id || x.scope != d.scope), d]));
    try {
      await _store.save(_homeId, d);
    } on Object catch (e) {
      if (mounted) _snack('Nie zapisano pulpitu: $e');
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  int _nextOrder(DashboardScope scope) =>
      (_list ?? const <Dashboard>[]).where((d) => d.scope == scope).fold(-1, (m, d) => d.order > m ? d.order : m) + 1;

  Future<void> _create({
    DashboardScope scope = DashboardScope.private,
    List<DashWidget> widgets = const [],
    List<DashSection> sections = const [],
  }) async {
    final name = await showTextInputDialog(
      context,
      title: scope == DashboardScope.shared ? 'Nowy wspólny pulpit' : 'Nowy pulpit',
      initial: (_list?.isEmpty ?? true) ? 'Dom' : '',
      maxLength: 24,
      fieldKey: const Key('dashboardName'),
    );
    if (name == null || !mounted) return;
    final d = Dashboard(
      id: newLocalId('d'),
      name: name,
      scope: scope,
      order: _nextOrder(scope),
      widgets: widgets,
      grid: 4,
      sections: sections,
    );
    await _save(d);
    setState(() {
      _selected = d.id;
      _editing = widgets.isEmpty;
    });
  }

  /// Pulpit startowy z urządzeń, do których mam dostęp (siatka 4, pkt 13.1): sekcja na pokój, termostaty 4×2,
  /// węzły wielokanałowe 4×2 (wszystkie wyjścia), pozostałe światła 2×1.
  Future<void> _createStarter() async {
    final rooms = _rooms;
    final roomOf = {
      for (final r in rooms)
        for (final id in r.devices) id: r.id,
    };
    final sections = [
      for (final r in rooms)
        if (r.devices.any((id) => widget.hub.device(id) != null))
          DashSection(id: 's${r.id}', title: r.name, room: r.id),
    ];
    final devices = [
      for (final d in widget.hub.devices)
        if (widget.hub.accessFor(d.id).canView && (d.type == DeviceType.thermostat || d.type.isLight)) d,
    ];
    // Kolejność: jak w pokojach, potem reszta.
    final order = [for (final r in rooms) ...r.devices];
    devices.sort((a, b) {
      final ia = order.indexOf(a.id), ib = order.indexOf(b.id);
      return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
    });
    final widgets = [
      for (final d in devices)
        () {
          final multi = (widget.hub.controller(d.id)?.stateJson?['channels'] as num? ?? 1) > 1;
          final base = d.type == DeviceType.thermostat
              ? DashWidget(
                  id: newLocalId('w${d.id.hashCode}'),
                  view: WidgetView.thermostat,
                  size: WidgetSize.s2x1,
                  device: d.id,
                )
              : DashWidget(
                  id: newLocalId('w${d.id.hashCode}'),
                  view: WidgetView.toggle,
                  device: d.id,
                  point: 'on',
                  label: d.name,
                );
          final sized = d.type == DeviceType.thermostat || multi ? base.resized(4, 2) : base.resized(2, 1);
          final room = roomOf[d.id];
          return room == null ? sized : sized.patch({'section': 's$room'});
        }(),
    ];
    if (!mounted) return;
    await _create(widgets: widgets, sections: sections);
  }

  Future<void> _menu(String action, Dashboard d) async {
    switch (action) {
      case 'new':
        await _create();
      case 'newShared':
        await _create(scope: DashboardScope.shared);
      case 'rename':
        final name = await showTextInputDialog(context, title: 'Nazwa pulpitu', initial: d.name, maxLength: 24);
        if (name != null) await _save(d.copyWith(name: name));
      case 'grid4':
        await _save(d.toGrid4());
        if (mounted) _snack('Pulpit ma teraz siatkę 4 kolumn - rozmiary kafelków zmienisz w edycji.');
      case 'section':
        await _addSection(d);
      case 'default':
        final p = HomePrefs(defaultDashboard: d.id);
        setState(() => _prefs = p);
        await _store.savePrefs(_homeId, p).catchError((_) {});
        if (mounted) _snack('„${d.name}” otwiera się na starcie.');
      case 'copy':
        final copy = d.copyWith(
          id: newLocalId('d'),
          name: '${d.name} (moja)',
          scope: DashboardScope.private,
          order: _nextOrder(DashboardScope.private),
        );
        await _save(copy);
        setState(() => _selected = copy.id);
        if (mounted) _snack('Skopiowano do Twoich pulpitów.');
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Usunąć pulpit „${d.name}”?'),
            content: d.scope == DashboardScope.shared
                ? const Text('To wspólny pulpit - zniknie u wszystkich domowników.')
                : null,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
            ],
          ),
        );
        if (ok != true) return;
        setState(() {
          _list = _list?.where((x) => !(x.id == d.id && x.scope == d.scope)).toList();
          _selected = null;
          _editing = false;
        });
        await _store.remove(_homeId, d).catchError((Object e) {
          if (mounted) _snack('Nie usunięto: $e');
        });
    }
  }

  Future<void> _addWidget(Dashboard d) async {
    final w = await Navigator.of(
      context,
    ).push<DashWidget>(MaterialPageRoute(builder: (_) => AddWidgetScreen(hub: widget.hub)));
    if (w != null) await _save(d.copyWith(widgets: [...d.widgets, w]));
  }

  /// Widoki pasujące do punktu kafelka (z `describe`, gdy urządzenie go podało).
  List<WidgetView> _viewsFor(DashWidget w, DeviceDescription? desc) {
    if (w.isScene || w.view == WidgetView.group || w.view == WidgetView.weather || w.view == WidgetView.hub) {
      return [w.view];
    }
    if (w.view == WidgetView.thermostat && w.point == null) return const [WidgetView.thermostat];
    final p = desc?.point(w.point ?? '') ?? fallbackPoint(w.point ?? '');
    final views = viewsFor(p);
    return views.contains(w.view) ? views : [w.view, ...views];
  }

  /// Arkusz ustawień kafelka (podgląd, podpis, ikona, rozmiar, wygląd, przesunięcie, duplikat, usunięcie).
  Future<void> _tileSettings(Dashboard d, DashWidget w) async {
    final c = widget.hub.controller(w.device ?? '');
    final desc = await c?.description().catchError((_) => null);
    if (!mounted) return;
    final groupOptions = w.view == WidgetView.group ? await groupCandidates(widget.hub) : const <GroupCandidate>[];
    if (!mounted) return;
    final views = _viewsFor(w, desc);
    final channels = c?.stateJson?['channels'];
    final i = d.widgets.indexWhere((x) => x.id == w.id);
    final scene = w.isScene ? widget.hub.scene(w.sceneId ?? '') : null;
    final r = await showTileSettings(
      context,
      widget: w,
      hub: widget.hub,
      views: views,
      defaultTitle: _widgetTitle(w.copyWith(clearLabel: true)),
      history: _history,
      canEditScene: scene != null && widget.hub.canEditShared,
      first: i == 0,
      last: i == d.widgets.length - 1,
      grid: d.grid,
      sections: d.sections,
      points: desc?.points ?? [if (w.point != null) fallbackPoint(w.point!)],
      channels: channels is int ? channels : 1,
      groupOptions: groupOptions,
    );
    if (!mounted || r == null) return;
    final list = [...d.widgets];
    switch (r) {
      case TileUpdated u:
        list[i] = u.widget;
      case TileDeleted():
        list.removeAt(i);
      case TileDuplicated():
        list.insert(i + 1, w.copyWith(id: newLocalId('w')));
      case TileMoved m:
        final to = (i + m.by).clamp(0, list.length - 1);
        list.insert(to, list.removeAt(i));
      case TileEditScene():
        await Navigator.of(context).push<Scene>(
          MaterialPageRoute(
            builder: (_) => SceneEditorScreen(hub: widget.hub, initial: scene),
          ),
        );
        return;
    }
    await _save(d.copyWith(widgets: list));
  }

  /// Przeciągnięty kafelek zajmuje miejsce tego, na który go upuszczono (i przechodzi do jego sekcji).
  Future<void> _drop(Dashboard d, String fromId, String toId) {
    final from = d.widgets.indexWhere((x) => x.id == fromId), to = d.widgets.indexWhere((x) => x.id == toId);
    final moved = d.widgets[from].patch({'section': d.widgets[to].section});
    final list = [...d.widgets]..[from] = moved;
    return _save(d.copyWith(widgets: reorder(list, from, to > from ? to + 1 : to)));
  }

  /// Przycisk w rogu: kolejny rozmiar (siatka 2: 1×1 → 2×1 → 2×2; siatka 4: kolejny z [grid4Sizes]).
  Future<void> _resize(Dashboard d, DashWidget w) {
    final DashWidget next;
    if (d.grid == 4) {
      final i = grid4Sizes.indexWhere((s) => s.$1 == w.gridW && s.$2 == w.gridH);
      final (gw, gh) = grid4Sizes[(i + 1) % grid4Sizes.length];
      next = w.resized(gw, gh);
    } else {
      next = w.copyWith(size: WidgetSize.values[(w.size.index + 1) % WidgetSize.values.length]);
    }
    return _save(d.copyWith(widgets: [for (final x in d.widgets) x.id == w.id ? next : x]));
  }

  Future<void> _addSection(Dashboard d) async {
    final title = await showTextInputDialog(context, title: 'Nowa sekcja', initial: '', maxLength: 24);
    if (title == null || title.trim().isEmpty) return;
    await _save(
      d.copyWith(
        sections: [
          ...d.sections,
          DashSection(id: newLocalId('s'), title: title.trim()),
        ],
      ),
    );
  }

  Future<void> _sectionMenu(Dashboard d, DashSection s, String action) async {
    final i = d.sections.indexWhere((x) => x.id == s.id);
    switch (action) {
      case 'rename':
        final title = await showTextInputDialog(context, title: 'Nazwa sekcji', initial: s.title, maxLength: 24);
        if (title == null || title.trim().isEmpty) return;
        await _save(
          d.copyWith(
            sections: [...d.sections]..[i] = DashSection(id: s.id, title: title.trim(), room: s.room),
          ),
        );
      case 'up' || 'down':
        final to = (i + (action == 'up' ? -1 : 1)).clamp(0, d.sections.length - 1);
        final list = [...d.sections];
        list.insert(to, list.removeAt(i));
        await _save(d.copyWith(sections: list));
      case 'delete':
        // Kafelki zostają, bez sekcji.
        await _save(
          d.copyWith(
            sections: [...d.sections]..removeAt(i),
            widgets: [
              for (final w in d.widgets) w.section == s.id ? w.patch({'section': null}) : w,
            ],
          ),
        );
    }
  }

  /// Kafelki bez sekcji (także z nieznaną sekcją), potem sekcje w kolejności.
  List<(DashSection?, List<DashWidget>)> _grouped(Dashboard d) {
    final ids = {for (final s in d.sections) s.id};
    return [
      (
        null,
        [
          for (final w in d.widgets)
            if (!ids.contains(w.section)) w,
        ],
      ),
      for (final s in d.sections)
        (
          s,
          [
            for (final w in d.widgets)
              if (w.section == s.id) w,
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final d = _current;
    return Scaffold(
      appBar: AppBar(
        title: list == null || list.length < 2 || d == null
            ? Text(d?.name ?? 'Pulpit')
            : PopupMenuButton<String>(
                key: const Key('dashboardPicker'),
                tooltip: 'Wybierz pulpit',
                onSelected: (id) => setState(() {
                  _selected = id;
                  _editing = false;
                }),
                itemBuilder: (_) => [
                  for (final x in list)
                    PopupMenuItem(
                      value: x.id,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(x.scope == DashboardScope.shared ? Icons.group : Icons.person),
                        title: Text(x.name),
                        trailing: x.id == _prefs.defaultDashboard ? const Icon(Icons.star, size: 18) : null,
                      ),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(d.name, overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
        actions: [
          if (d != null && _canEdit(d))
            IconButton(
              key: const Key('editDashboard'),
              tooltip: _editing ? 'Gotowe' : 'Edytuj pulpit',
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
              onPressed: () => setState(() => _editing = !_editing),
            ),
          if (d != null)
            PopupMenuButton<String>(
              key: const Key('dashboardMenu'),
              onSelected: (a) => _menu(a, d),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'new', child: Text('Nowy pulpit')),
                if (_owner) const PopupMenuItem(value: 'newShared', child: Text('Nowy wspólny pulpit')),
                if (_canEdit(d)) const PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                if (_canEdit(d) && d.grid != 4)
                  const PopupMenuItem(value: 'grid4', child: Text('Nowy układ (siatka 4 kolumn)')),
                if (_canEdit(d)) const PopupMenuItem(value: 'section', child: Text('Nowa sekcja')),
                if (d.id != _prefs.defaultDashboard)
                  const PopupMenuItem(value: 'default', child: Text('Otwieraj na starcie')),
                if (d.scope == DashboardScope.shared)
                  const PopupMenuItem(value: 'copy', child: Text('Kopiuj do moich')),
                if (_canEdit(d)) const PopupMenuItem(value: 'delete', child: Text('Usuń pulpit')),
              ],
            ),
          if (_withAccount && Services.of(context).cloud.available && widget.session?.current != null)
            NotificationsButton(store: Services.of(context).cloud.store, homeId: widget.session!.current!.id),
          if (_withAccount)
            IconButton(
              key: const Key('watchDashboard'),
              tooltip: 'Pulpit zegarka',
              icon: const Icon(Icons.watch_outlined),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(hub: widget.hub))),
            ),
          if (_withAccount) AccountMenu(session: widget.session),
        ],
      ),
      floatingActionButton: d != null && _editing
          ? FloatingActionButton.extended(
              heroTag: null,
              key: const Key('addWidget'),
              onPressed: () => _addWidget(d),
              icon: const Icon(Icons.add),
              label: const Text('Widżet'),
            )
          : null,
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : d == null
          ? _empty(context)
          : _editing
          ? _editor(context, d)
          : _view(context, d),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dashboard_customize_outlined, size: 56),
          const SizedBox(height: 12),
          const Text('Nie masz jeszcze pulpitu.', textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'Pulpit to Twoje skróty: wartości, przełączniki, wykresy i sceny z różnych urządzeń.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('starterDashboard'),
            onPressed: widget.hub.devices.isEmpty ? null : _createStarter,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Utwórz z moich urządzeń'),
          ),
          TextButton(key: const Key('emptyDashboard'), onPressed: _create, child: const Text('Pusty pulpit')),
        ],
      ),
    ),
  );

  Widget _view(BuildContext context, Dashboard d) {
    return RefreshIndicator(
      onRefresh: widget.hub.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          DashSummary(hub: widget.hub),
          if (d.scope == DashboardScope.shared && !_owner)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Wspólny pulpit domu - zmienia go właściciel. „Kopiuj do moich”, aby ułożyć po swojemu.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (d.widgets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text('Pulpit jest pusty.'),
                  if (_canEdit(d))
                    TextButton(onPressed: () => setState(() => _editing = true), child: const Text('Dodaj widżety')),
                ],
              ),
            )
          else
            for (final (s, list) in _grouped(d))
              if (s != null || list.isNotEmpty) ...[
                if (s != null) _SectionHeader(title: s.title, count: list.length),
                DashGrid(
                  grid: d.grid,
                  widgets: list,
                  builder: (w) => DashTile(widget: w, hub: widget.hub, history: _history),
                ),
                const SizedBox(height: 4),
              ],
        ],
      ),
    );
  }

  /// Tryb edycji na siatce: te same kafelki co na pulpicie, dotyk - ustawienia, przytrzymanie - przeciąganie,
  /// przycisk w rogu - rozmiar.
  Widget _editor(BuildContext context, Dashboard d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Dotknij kafelka, aby go ustawić. Przytrzymaj i przeciągnij, aby przenieść. Przycisk w rogu zmienia rozmiar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (d.grid != 4)
          Card(
            child: ListTile(
              key: const Key('toGrid4'),
              leading: const Icon(Icons.grid_view),
              title: const Text('Nowy układ: siatka 4 kolumn'),
              subtitle: const Text(
                'Niskie kafelki, paski 4×1, sekcje - wygląd obecnych kafelków prawie się nie zmieni.',
              ),
              onTap: () => _save(d.toGrid4()),
            ),
          ),
        if (d.widgets.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('Dodaj pierwszy kafelek przyciskiem „Widżet”.'))
        else
          for (final (s, list) in _grouped(d))
            if (s != null || list.isNotEmpty) ...[
              if (s != null)
                _SectionHeader(
                  title: s.title,
                  count: list.length,
                  menu: PopupMenuButton<String>(
                    key: Key('sectionMenu-${s.id}'),
                    onSelected: (a) => _sectionMenu(d, s, a),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                      PopupMenuItem(value: 'up', child: Text('Wyżej')),
                      PopupMenuItem(value: 'down', child: Text('Niżej')),
                      PopupMenuItem(value: 'delete', child: Text('Usuń sekcję (kafelki zostają)')),
                    ],
                  ),
                ),
              DashGrid(
                grid: d.grid,
                widgets: list,
                builder: (w) => EditableTile(
                  id: w.id,
                  onTap: () => _tileSettings(d, w),
                  onResize: () => _resize(d, w),
                  onDrop: (from) => _drop(d, from, w.id),
                  child: DashTile(widget: w, hub: widget.hub, history: _history),
                ),
              ),
              const SizedBox(height: 4),
            ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            key: const Key('addSection'),
            onPressed: () => _addSection(d),
            icon: const Icon(Icons.view_agenda_outlined),
            label: const Text('Nowa sekcja'),
          ),
        ),
      ],
    );
  }

  String _widgetTitle(DashWidget w) {
    if (w.label != null) return w.label!;
    if (w.isScene) return widget.hub.scene(w.sceneId ?? '')?.name ?? 'Scena';
    if (w.view == WidgetView.thermostat) return widget.hub.device(w.device ?? '')?.name ?? 'Termostat';
    return fallbackPoint(w.point ?? '').name;
  }
}

/// Nagłówek sekcji pulpitu (pkt 13.1).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, this.menu});

  final String title;
  final int count;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(
            '$count ${count == 1 ? 'kafelek' : (count > 1 && count < 5 ? 'kafelki' : 'kafelków')}',
            style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          ?menu,
        ],
      ),
    );
  }
}
