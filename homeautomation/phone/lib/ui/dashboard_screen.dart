import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../controllers/home_session.dart';
import '../data/dashboard_store.dart';
import '../data/history.dart';
import '../models/dashboard.dart';
import '../models/device_type.dart';
import '../models/scene.dart';
import '../services.dart';
import 'account_menu.dart';
import 'dashboard_tiles.dart';
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
      _history = (device, field) => loadHistory(cloud.store, homeId: home, deviceId: device, field: field);
    }
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

  Future<void> _create({DashboardScope scope = DashboardScope.private, List<DashWidget> widgets = const []}) async {
    final name = await showTextInputDialog(
      context,
      title: scope == DashboardScope.shared ? 'Nowy wspólny pulpit' : 'Nowy pulpit',
      initial: (_list?.isEmpty ?? true) ? 'Dom' : '',
      maxLength: 24,
      fieldKey: const Key('dashboardName'),
    );
    if (name == null || !mounted) return;
    final d = Dashboard(id: newLocalId('d'), name: name, scope: scope, order: _nextOrder(scope), widgets: widgets);
    await _save(d);
    setState(() {
      _selected = d.id;
      _editing = widgets.isEmpty;
    });
  }

  /// Pulpit startowy z urządzeń, do których mam dostęp: termostaty jako „termostat”, światła jako przełącznik.
  List<DashWidget> _starterWidgets() => [
    for (final d in widget.hub.devices)
      if (widget.hub.accessFor(d.id).canView)
        if (d.type == DeviceType.thermostat)
          DashWidget(id: newLocalId('w${d.id.hashCode}'), view: WidgetView.thermostat, size: WidgetSize.s2x1, device: d.id)
        else if (d.type.isLight)
          DashWidget(id: newLocalId('w${d.id.hashCode}'), view: WidgetView.toggle, device: d.id, point: 'on', label: d.name),
  ];

  Future<void> _menu(String action, Dashboard d) async {
    switch (action) {
      case 'new':
        await _create();
      case 'newShared':
        await _create(scope: DashboardScope.shared);
      case 'rename':
        final name = await showTextInputDialog(context, title: 'Nazwa pulpitu', initial: d.name, maxLength: 24);
        if (name != null) await _save(d.copyWith(name: name));
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
            content: d.scope == DashboardScope.shared ? const Text('To wspólny pulpit - zniknie u wszystkich domowników.') : null,
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

  Future<void> _editWidget(Dashboard d, DashWidget w, String action) async {
    List<DashWidget> replace(DashWidget n) => [for (final x in d.widgets) x.id == w.id ? n : x];
    switch (action) {
      case 'label':
        final label = await showTextInputDialog(context, title: 'Podpis', initial: w.label ?? '', maxLength: 24);
        if (label == null) return;
        await _save(
          d.copyWith(
            widgets: replace(
              DashWidget(
                id: w.id,
                view: w.view,
                size: w.size,
                device: w.device,
                point: w.point,
                label: label.trim().isEmpty ? null : label.trim(),
                sceneId: w.sceneId,
              ),
            ),
          ),
        );
      case 'scene':
        final scene = widget.hub.scene(w.sceneId ?? '');
        await Navigator.of(
          context,
        ).push<Scene>(MaterialPageRoute(builder: (_) => SceneEditorScreen(hub: widget.hub, initial: scene)));
      case 'delete':
        await _save(d.copyWith(widgets: [...d.widgets.where((x) => x.id != w.id)]));
      default:
        final size = WidgetSize.fromWire(action);
        await _save(d.copyWith(widgets: replace(w.copyWith(size: size))));
    }
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
                if (d.id != _prefs.defaultDashboard)
                  const PopupMenuItem(value: 'default', child: Text('Otwieraj na starcie')),
                if (d.scope == DashboardScope.shared)
                  const PopupMenuItem(value: 'copy', child: Text('Kopiuj do moich')),
                if (_canEdit(d)) const PopupMenuItem(value: 'delete', child: Text('Usuń pulpit')),
              ],
            ),
          if (_withAccount)
            IconButton(
              key: const Key('watchDashboard'),
              tooltip: 'Pulpit zegarka',
              icon: const Icon(Icons.watch_outlined),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(hub: widget.hub))),
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
            onPressed: widget.hub.devices.isEmpty ? null : () => _create(widgets: _starterWidgets()),
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
                    TextButton(
                      onPressed: () => setState(() => _editing = true),
                      child: const Text('Dodaj widżety'),
                    ),
                ],
              ),
            )
          else
            DashGrid(
              widgets: d.widgets,
              builder: (w) => DashTile(widget: w, hub: widget.hub, history: _history),
            ),
        ],
      ),
    );
  }

  Widget _editor(BuildContext context, Dashboard d) {
    return ReorderableListView(
      padding: const EdgeInsets.only(bottom: 96),
      buildDefaultDragHandles: false,
      header: const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('Przeciągnij za uchwyt, aby zmienić kolejność. Menu przy widżecie: rozmiar, podpis, usunięcie.'),
      ),
      onReorder: (a, b) => _save(d.copyWith(widgets: reorder(d.widgets, a, b))),
      children: [
        for (final (i, w) in d.widgets.indexed)
          ListTile(
            key: ValueKey(w.id),
            leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
            title: Text(_widgetTitle(w)),
            subtitle: Text(
              [
                if (!w.isScene) widget.hub.device(w.device ?? '')?.name ?? 'urządzenie niedostępne',
                w.view.label,
                w.size.wire.replaceAll('x', '×'),
              ].join(' · '),
            ),
            trailing: PopupMenuButton<String>(
              key: Key('widgetMenu-${w.id}'),
              onSelected: (a) => _editWidget(d, w, a),
              itemBuilder: (_) => [
                for (final s in WidgetSize.values)
                  CheckedPopupMenuItem(
                    value: s.wire,
                    checked: w.size == s,
                    child: Text('Rozmiar ${s.wire.replaceAll('x', '×')}'),
                  ),
                const PopupMenuDivider(),
                if (w.isScene && widget.hub.canEditShared && widget.hub.scene(w.sceneId ?? '') != null)
                  const PopupMenuItem(value: 'scene', child: Text('Edytuj scenę')),
                const PopupMenuItem(value: 'label', child: Text('Podpis')),
                const PopupMenuItem(value: 'delete', child: Text('Usuń')),
              ],
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
