import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../controllers/home_session.dart';
import '../data/dashboard_store.dart';
import '../data/history.dart';
import '../data/notifications.dart';
import '../data/updates.dart';
import '../home_widgets/quick_tiles_screen.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/hub.dart';
import '../models/room.dart';
import '../models/scene.dart';
import '../services.dart';
import 'automations_screen.dart';
import 'dashboard_panel.dart';
import 'dashboard_summary.dart';
import 'dashboard_tiles.dart';
import 'devices_tab.dart';
import 'members_screen.dart';
import 'notifications_screen.dart';
import 'tile_settings.dart';
import 'updates_screen.dart';
import 'watch_screen.dart';
import 'widget_editor.dart';
import 'widgets.dart';

/// Ekran główny domu (pkt 13): u góry tylko zakładki pulpitów (przesuwanie palcem między nimi) i przycisk ☰
/// z panelem wysuwanym z góry (dom, urządzenia, domownicy, powiadomienia, zegarek, opcje pulpitu). Tryb edycji
/// (dodawanie widżetu w 3 krokach, przeciąganie, rozmiar, usuwanie, sceny); wspólne zmienia tylko właściciel.
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

  /// Strony pulpitów (przesuwanie palcem) i pasek zakładek.
  PageController? _pages;
  bool _animatingPage = false;
  final _tabsScroll = ScrollController();
  final _tabKeys = <String, GlobalKey>{};
  bool _tabsOverflow = false;

  /// Powiadomienia z domu (kropka na ☰, liczba w panelu).
  StreamSubscription<List<HubNotification>>? _notesSub;
  List<HubNotification> _notes = const [];
  int _seen = 0;

  /// Edytor: przewijanie przy krawędzi w trakcie przeciągania kafelka.
  final _scroll = ScrollController();
  final _editorKey = GlobalKey();
  bool _dragging = false;
  Timer? _autoScroll;
  double _scrollStep = 0;

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
    _roomsSub = services.rooms.watch().listen((r) {
      if (mounted) setState(() => _rooms = sortRooms(r));
    }, onError: (_) {});
    _sub = _store.watch(_homeId).listen((l) {
      if (mounted) setState(() => _list = l);
    }, onError: (_) {});
    _store.prefs(_homeId).then((p) {
      if (mounted) setState(() => _prefs = p);
    }, onError: (_) {});
    if (_notifications) {
      notificationsSeen(_homeId).then((s) {
        if (mounted) setState(() => _seen = s);
      });
      _notesSub = watchNotifications(services.cloud.store, _homeId).listen((l) {
        if (mounted) setState(() => _notes = l);
      }, onError: (_) {});
    }
  }

  bool get _notifications => _withAccount && Services.of(context).cloud.available && widget.session?.current != null;

  int get _unseen => _notes.where((n) => n.ts > _seen).length;

  @override
  void dispose() {
    _sub?.cancel();
    _roomsSub?.cancel();
    _notesSub?.cancel();
    _pages?.dispose();
    _tabsScroll.dispose();
    _autoScroll?.cancel();
    _scroll.dispose();
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
    final w = await Navigator.of(context).push<DashWidget>(
      MaterialPageRoute(
        builder: (_) => AddWidgetScreen(hub: widget.hub, grid: d.grid),
      ),
    );
    if (w != null) await _save(d.copyWith(widgets: [...d.widgets, w]));
  }

  /// Widoki pasujące do punktu kafelka (z `describe`, gdy urządzenie go podało).
  List<WidgetView> _viewsFor(DashWidget w, DeviceDescription? desc) {
    if (w.isScene ||
        const [
          WidgetView.group,
          WidgetView.weather,
          WidgetView.hub,
          WidgetView.schedule,
          WidgetView.valueList,
          WidgetView.gate,
          WidgetView.room,
        ].contains(w.view)) {
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
      rooms: _rooms,
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

  /// Siatka 2: przeciągnięty kafelek zajmuje miejsce tego, na który go upuszczono (i przechodzi do jego sekcji).
  Future<void> _drop(Dashboard d, String fromId, String toId) {
    final from = d.widgets.indexWhere((x) => x.id == fromId), to = d.widgets.indexWhere((x) => x.id == toId);
    final moved = d.widgets[from].patch({'section': d.widgets[to].section}).unpinned();
    final list = [...d.widgets]..[from] = moved;
    return _save(d.copyWith(widgets: reorder(list, from, to > from ? to + 1 : to)));
  }

  /// Siatka 4: upuszczony kafelek [id] przechodzi do [section]; cała sekcja przypięta tak, jak widać w podglądzie.
  Future<void> _arrange(Dashboard d, String id, String? section, Map<String, (int, int)> at) => _save(
    d.copyWith(
      widgets: [
        for (final w in d.widgets)
          if (at[w.id] case (final r, final c))
            (w.id == id ? w.patch({'section': section}) : w).pinnedAt(c, r)
          else
            w,
      ],
    ),
  );

  /// Przewijanie edytora, gdy przeciągany kafelek jest przy górnej albo dolnej krawędzi.
  void _autoScrollAt(Offset global) {
    final box = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    if (!_dragging || box == null) return _stopAutoScroll();
    final y = box.globalToLocal(global).dy;
    const edge = 72.0;
    _scrollStep = y < edge ? -12 : (y > box.size.height - edge ? 12 : 0);
    if (_scrollStep == 0) return _stopAutoScroll();
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      final to = (p.pixels + _scrollStep).clamp(p.minScrollExtent, p.maxScrollExtent);
      if (to != p.pixels) _scroll.jumpTo(to);
    });
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  void _endDrag() {
    _dragging = false;
    _stopAutoScroll();
  }

  /// Przycisk w rogu: kolejny rozmiar (siatka 2: 1×1 → 2×1 → 2×2; siatka 4: kolejny z [sizesFor] widoku).
  Future<void> _resize(Dashboard d, DashWidget w) {
    final DashWidget next;
    if (d.grid == 4) {
      final sizes = sizesFor(w.view);
      final i = sizes.indexWhere((s) => s.$1 == w.gridW && s.$2 == w.gridH);
      final (gw, gh) = sizes[(i + 1) % sizes.length];
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

  /// Wybór pulpitu z zakładki albo listy: strona przesuwa się do niego.
  void _select(String id) {
    final list = _list ?? const <Dashboard>[];
    final i = list.indexWhere((x) => x.id == id);
    setState(() {
      _selected = id;
      _editing = false;
    });
    _showTab(id);
    final p = _pages;
    if (i < 0 || p == null || !p.hasClients) return;
    _animatingPage = true;
    p
        .animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic)
        .whenComplete(() => _animatingPage = false);
  }

  /// Zakładka wybranego pulpitu na środku paska.
  void _showTab(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _tabKeys[id]?.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(c, alignment: 0.5, duration: const Duration(milliseconds: 250));
      }
    });
  }

  /// Po zmianie listy (nowy, usunięty pulpit) strona pokazuje [_current]; strzałka „wszystkie”, gdy zakładki się
  /// nie mieszczą.
  void _afterLayout(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = _pages;
      if (p != null && p.hasClients && !_animatingPage && p.page?.round() != index) p.jumpToPage(index);
      final over = _tabsScroll.hasClients && _tabsScroll.position.maxScrollExtent > 0;
      if (over != _tabsOverflow) setState(() => _tabsOverflow = over);
    });
  }

  Future<void> _openPanel() async {
    final d = _current;
    final hubs = widget.hub.hubs;
    final a = await showTopSheet<PanelAction>(
      context,
      builder: (_) => DashboardPanel(
        session: widget.session,
        dashboard: d,
        canEdit: d != null && _canEdit(d),
        owner: _owner,
        isDefault: d != null && d.id == _prefs.defaultDashboard,
        unseen: _unseen,
        notifications: _notifications,
        automations: hubs.isNotEmpty && hubs.first.canConfig,
        updates: !_withAccount || _owner,
        quickTiles: defaultTargetPlatform == TargetPlatform.android,
        dashboards: _list?.length ?? 0,
      ),
    );
    if (a == null || !mounted) return;
    final nav = Navigator.of(context);
    switch (a) {
      case PanelAction.devices:
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => DevicesTab(hub: widget.hub, session: widget.session),
          ),
        );
      case PanelAction.members:
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => MembersScreen(hub: widget.hub, session: widget.session!),
          ),
        );
      case PanelAction.notifications:
        await nav.push(MaterialPageRoute<void>(builder: (_) => NotificationsScreen(items: _notes)));
        final latest = _notes.isEmpty ? 0 : _notes.first.ts;
        await markNotificationsSeen(_homeId, latest);
        if (mounted) setState(() => _seen = latest);
      case PanelAction.watch:
        await nav.push(MaterialPageRoute<void>(builder: (_) => WatchScreen(hub: widget.hub)));
      case PanelAction.updates:
        await nav.push(MaterialPageRoute<void>(builder: (_) => UpdatesScreen(backend: DeviceHubUpdates(widget.hub))));
      case PanelAction.automations:
        if (hubs.isEmpty) return;
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => AutomationsScreen(hub: widget.hub, controller: hubs.first),
          ),
        );
      case PanelAction.quickTiles:
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => QuickTilesScreen(hub: widget.hub, session: widget.session, dashboards: _list ?? const []),
          ),
        );
      case PanelAction.edit:
        setState(() => _editing = true);
      case PanelAction.arrange:
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => DashboardsOrderScreen(
              dashboards: _list ?? const [],
              canEdit: _canEdit,
              defaultId: _prefs.defaultDashboard,
              onSave: _save,
              onDefault: (id) async {
                final p = HomePrefs(defaultDashboard: id);
                if (mounted) setState(() => _prefs = p);
                await _store.savePrefs(_homeId, p).catchError((_) {});
              },
            ),
          ),
        );
      case PanelAction.newDashboard:
        await _create();
      case PanelAction.newShared:
        await _create(scope: DashboardScope.shared);
      case PanelAction.rename ||
          PanelAction.section ||
          PanelAction.grid4 ||
          PanelAction.makeDefault ||
          PanelAction.copy ||
          PanelAction.delete:
        if (d == null) return;
        await _menu(switch (a) {
          PanelAction.makeDefault => 'default',
          _ => a.name,
        }, d);
    }
  }

  Future<void> _openAll() async {
    final id = await showTopSheet<String>(
      context,
      label: 'Wszystkie pulpity',
      builder: (_) =>
          AllDashboards(dashboards: _list ?? const [], current: _current?.id, defaultId: _prefs.defaultDashboard),
    );
    if (id != null && mounted) _select(id);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final d = _current;
    final index = list == null || d == null ? 0 : list.indexOf(d);
    if (list != null && list.isNotEmpty) {
      _pages ??= PageController(initialPage: index);
      _afterLayout(index);
    }
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) setState(() => _editing = false);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (d != null && _editing) _editBar(context, d) else _topBar(context, list ?? const [], d),
              Expanded(
                child: list == null
                    ? const Center(child: CircularProgressIndicator())
                    : d == null
                    ? _empty(context)
                    : PageView.builder(
                        key: const Key('dashboardPages'),
                        controller: _pages,
                        physics: _editing ? const NeverScrollableScrollPhysics() : null,
                        itemCount: list.length,
                        onPageChanged: (i) {
                          if (_animatingPage || i >= list.length) return;
                          setState(() => _selected = list[i].id);
                          _showTab(list[i].id);
                        },
                        itemBuilder: (context, i) =>
                            _editing && list[i].id == d.id ? _editor(context, list[i]) : _view(context, list[i]),
                      ),
              ),
            ],
          ),
        ),
        floatingActionButton: d != null && _editing
            ? FloatingActionButton.extended(
                heroTag: null,
                key: const Key('addWidget'),
                onPressed: () => _addWidget(d),
                icon: const Icon(Icons.add),
                label: const Text('Kafelek'),
              )
            : null,
      ),
    );
  }

  /// Zakładki pulpitów (przewijane), „wszystkie”, gdy się nie mieszczą, i ☰ z kropką nowych powiadomień.
  Widget _topBar(BuildContext context, List<Dashboard> list, Dashboard? d) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text('Pulpit', style: t.titleLarge),
                      )
                    : ShaderMask(
                        // Przygaszone krawędzie: widać, że zakładek jest więcej.
                        shaderCallback: (r) => LinearGradient(
                          colors: [
                            _tabsOverflow ? Colors.transparent : Colors.white,
                            Colors.white,
                            Colors.white,
                            _tabsOverflow ? Colors.transparent : Colors.white,
                          ],
                          stops: const [0, 0.06, 0.94, 1],
                        ).createShader(r),
                        blendMode: BlendMode.dstIn,
                        // Wszystkie zakładki zbudowane (nie ListView) - przewinięcie do wybranej działa zawsze.
                        child: SingleChildScrollView(
                          key: const Key('dashboardTabs'),
                          controller: _tabsScroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              for (final x in list)
                                Padding(
                                  key: _tabKeys.putIfAbsent(x.id, GlobalKey.new),
                                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                                  child: _DashTab(dashboard: x, selected: x.id == d?.id, onTap: () => _select(x.id)),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
              if (_tabsOverflow)
                IconButton(
                  key: const Key('allDashboards'),
                  tooltip: 'Wszystkie pulpity',
                  icon: const Icon(Icons.expand_more),
                  onPressed: _openAll,
                ),
              IconButton(
                key: const Key('panel'),
                tooltip: 'Panel: dom, urządzenia, opcje pulpitu',
                icon: Badge(smallSize: 9, isLabelVisible: _unseen > 0, child: const Icon(Icons.menu)),
                onPressed: _openPanel,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (list.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final x in list)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: x.id == d?.id ? 18 : 6,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      color: x.id == d?.id ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Pasek trybu edycji: nazwa pulpitu, opcje i „Gotowe”.
  Widget _editBar(BuildContext context, Dashboard d) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('EDYCJA', style: t.labelSmall?.copyWith(color: cs.primary, letterSpacing: 0.8)),
                  Text(
                    'Pulpit „${d.name}”',
                    style: t.titleMedium?.copyWith(color: cs.onSecondaryContainer),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: const Key('editMenu'),
              tooltip: 'Opcje pulpitu',
              onSelected: (a) => _menu(a, d),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                if (d.grid != 4) const PopupMenuItem(value: 'grid4', child: Text('Nowy układ (siatka 4 kolumn)')),
                const PopupMenuItem(value: 'section', child: Text('Nowa sekcja')),
                const PopupMenuItem(value: 'delete', child: Text('Usuń pulpit')),
              ],
            ),
            FilledButton(
              key: const Key('editDone'),
              onPressed: () => setState(() => _editing = false),
              child: const Text('Gotowe'),
            ),
          ],
        ),
      ),
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
                  builder: (w) => DashTile(widget: w, hub: widget.hub, history: _history, rooms: _rooms),
                ),
                const SizedBox(height: 4),
              ],
        ],
      ),
    );
  }

  /// Tryb edycji na siatce: te same kafelki co na pulpicie, dotyk - ustawienia, przytrzymanie - przeciąganie
  /// (siatka 4: pozostałe rozsuwają się na żywo), przycisk w rogu - rozmiar.
  Widget _editor(BuildContext context, Dashboard d) {
    final byId = {for (final w in d.widgets) w.id: w};
    return Listener(
      onPointerMove: (e) => _autoScrollAt(e.position),
      // Także gdy kafelek, z którego zaczęto, zniknął z listy przy przewijaniu (wtedy nie zgłosi końca).
      onPointerUp: (_) => _endDrag(),
      onPointerCancel: (_) => _endDrag(),
      child: _editorList(context, d, byId),
    );
  }

  Widget _editorList(BuildContext context, Dashboard d, Map<String, DashWidget> byId) {
    return ListView(
      key: _editorKey,
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            d.grid == 4
                ? 'Dotknij kafelka, aby go ustawić. Przytrzymaj i przeciągnij - pozostałe kafelki zrobią miejsce, '
                      'a obrys pokaże, gdzie stanie (także w innej sekcji). Przycisk w rogu zmienia rozmiar.'
                : 'Dotknij kafelka, aby go ustawić. Przytrzymaj i przeciągnij na inny kafelek, aby zająć jego miejsce. '
                      'Przycisk w rogu zmienia rozmiar.',
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
          const Padding(padding: EdgeInsets.all(24), child: Text('Dodaj pierwszy kafelek przyciskiem „Kafelek”.'))
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
                lookup: d.grid == 4 ? (id) => byId[id] : null,
                onArrange: d.grid == 4 ? (id, at) => _arrange(d, id, s?.id, at) : null,
                builder: (w) => EditableTile(
                  id: w.id,
                  onTap: () => _tileSettings(d, w),
                  onResize: () => _resize(d, w),
                  onDrop: d.grid == 4 ? null : (from) => _drop(d, from, w.id),
                  onDragging: (on) {
                    if (on) {
                      _dragging = true;
                    } else {
                      _endDrag();
                    }
                  },
                  child: DashTile(widget: w, hub: widget.hub, history: _history, rooms: _rooms),
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

/// Zakładka pulpitu w górnym pasku.
class _DashTab extends StatelessWidget {
  const _DashTab({required this.dashboard, required this.selected, required this.onTap});

  final Dashboard dashboard;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        key: Key('dashTab-${dashboard.id}'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dashboard.scope == DashboardScope.shared) ...[
                Icon(Icons.group_outlined, size: 16, color: style?.color),
                const SizedBox(width: 6),
              ],
              Text(dashboard.name, style: style),
            ],
          ),
        ),
      ),
    );
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
