// Ekran główny bez dolnego paska: panel wysuwany z góry (przycisk ☰) z wyborem domu, skrótami (urządzenia,
// domownicy, powiadomienia, zegarek, aktualizacje, automatyki) i opcjami bieżącego pulpitu; lista wszystkich
// pulpitów, gdy zakładki się nie mieszczą; kolejność i nazwy pulpitów.

import 'package:flutter/material.dart';

import '../controllers/home_session.dart';
import '../models/dashboard.dart';
import 'account_menu.dart';
import 'widgets.dart';

/// Arkusz wysuwany z góry ekranu (zamyka go dotknięcie obok, „wstecz” albo przesunięcie w górę).
Future<T?> showTopSheet<T>(BuildContext context, {required WidgetBuilder builder, String label = 'Panel'}) {
  final cs = Theme.of(context).colorScheme;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -300) Navigator.of(ctx).maybePop();
        },
        child: Material(
          color: cs.surfaceContainerHigh,
          elevation: 6,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            bottom: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
              child: builder(ctx),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  );
}

/// Co wybrano w panelu (wykonuje ekran pulpitu, już po zamknięciu panelu).
enum PanelAction {
  devices,
  members,
  notifications,
  watch,
  updates,
  automations,
  edit,
  newDashboard,
  newShared,
  arrange,
  rename,
  section,
  grid4,
  makeDefault,
  copy,
  delete,
}

/// Zawartość panelu ☰.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.session,
    required this.dashboard,
    required this.canEdit,
    required this.owner,
    required this.isDefault,
    this.unseen = 0,
    this.notifications = false,
    this.automations = false,
    this.updates = false,
    this.dashboards = 0,
  });

  final HomeSession? session;
  final Dashboard? dashboard;
  final bool canEdit;
  final bool owner;
  final bool isDefault;

  /// Nieprzeczytane powiadomienia z domu.
  final int unseen;

  /// Skróty, które mają sens w tym domu.
  final bool notifications;
  final bool automations;
  final bool updates;

  /// Ile jest pulpitów (kolejność - od dwóch).
  final int dashboards;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final withAccount = session != null;
    final d = dashboard;
    void pick(PanelAction a) => Navigator.of(context).pop(a);
    final shortcuts = [
      _Shortcut(
        key: const Key('panel-devices'),
        icon: Icons.devices_other_outlined,
        label: 'Urządzenia',
        onTap: () => pick(PanelAction.devices),
      ),
      if (owner)
        _Shortcut(
          key: const Key('panel-members'),
          icon: Icons.group_outlined,
          label: 'Domownicy',
          onTap: () => pick(PanelAction.members),
        ),
      if (notifications)
        _Shortcut(
          key: const Key('panel-notifications'),
          icon: Icons.notifications_outlined,
          label: 'Powiadomienia',
          badge: unseen,
          onTap: () => pick(PanelAction.notifications),
        ),
      if (withAccount)
        _Shortcut(
          key: const Key('panel-watch'),
          icon: Icons.watch_outlined,
          label: 'Zegarek',
          onTap: () => pick(PanelAction.watch),
        ),
      if (updates)
        _Shortcut(
          key: const Key('panel-updates'),
          icon: Icons.system_update_alt,
          label: 'Aktualizacje',
          onTap: () => pick(PanelAction.updates),
        ),
      if (automations)
        _Shortcut(
          key: const Key('panel-automations'),
          icon: Icons.auto_mode,
          label: 'Automatyki',
          onTap: () => pick(PanelAction.automations),
        ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.home_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  session?.current?.name ?? 'Dom w telefonie',
                  style: t.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (withAccount) AccountMenu(session: session),
              IconButton(
                key: const Key('panel-close'),
                tooltip: 'Zamknij',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.35,
            children: shortcuts,
          ),
          if (d != null) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('Ten pulpit: ${d.name}', style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ),
                PopupMenuButton<PanelAction>(
                  key: const Key('dashboardMenu'),
                  tooltip: 'Więcej opcji pulpitu',
                  onSelected: pick,
                  itemBuilder: (_) => [
                    if (canEdit) const PopupMenuItem(value: PanelAction.rename, child: Text('Zmień nazwę')),
                    if (canEdit && d.grid != 4)
                      const PopupMenuItem(value: PanelAction.grid4, child: Text('Nowy układ (siatka 4 kolumn)')),
                    if (canEdit) const PopupMenuItem(value: PanelAction.section, child: Text('Nowa sekcja')),
                    if (!isDefault)
                      const PopupMenuItem(value: PanelAction.makeDefault, child: Text('Otwieraj na starcie')),
                    if (d.scope == DashboardScope.shared)
                      const PopupMenuItem(value: PanelAction.copy, child: Text('Kopiuj do moich')),
                    if (canEdit) const PopupMenuItem(value: PanelAction.delete, child: Text('Usuń pulpit')),
                  ],
                ),
              ],
            ),
            if (canEdit)
              ListTile(
                key: const Key('editDashboard'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edytuj kafelki i układ'),
                onTap: () => pick(PanelAction.edit),
              ),
          ],
          ListTile(
            key: const Key('panel-new'),
            leading: const Icon(Icons.add),
            title: const Text('Nowy pulpit'),
            onTap: () => pick(PanelAction.newDashboard),
          ),
          if (owner)
            ListTile(
              key: const Key('panel-newShared'),
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Nowy wspólny pulpit'),
              onTap: () => pick(PanelAction.newShared),
            ),
          if (dashboards > 1)
            ListTile(
              key: const Key('panel-arrange'),
              leading: const Icon(Icons.low_priority),
              title: const Text('Kolejność i nazwy pulpitów'),
              onTap: () => pick(PanelAction.arrange),
            ),
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({super.key, required this.icon, required this.label, required this.onTap, this.badge = 0});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Wszystkie pulpity w dwóch kolumnach (gdy zakładki się nie mieszczą); zwraca wybrany id.
class AllDashboards extends StatelessWidget {
  const AllDashboards({super.key, required this.dashboards, required this.current, this.defaultId});

  final List<Dashboard> dashboards;
  final String? current;
  final String? defaultId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text('Wszystkie pulpity', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.4,
            children: [
              for (final x in dashboards)
                Material(
                  color: x.id == current ? cs.secondaryContainer : cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: Key('allDash-${x.id}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).pop(x.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          if (x.id == defaultId) ...[
                            Icon(Icons.star, size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                          ],
                          if (x.scope == DashboardScope.shared) ...[
                            Icon(Icons.group_outlined, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (dashboards.any((x) => x.id == defaultId || x.scope == DashboardScope.shared))
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.star, size: 14, color: cs.primary),
                    const Text('otwierany na starcie'),
                    Icon(Icons.group_outlined, size: 14, color: cs.onSurfaceVariant),
                    const Text('wspólny'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kolejność i nazwy pulpitów (w obrębie prywatnych i wspólnych), pulpit otwierany na starcie.
class DashboardsOrderScreen extends StatefulWidget {
  const DashboardsOrderScreen({
    super.key,
    required this.dashboards,
    required this.canEdit,
    required this.onSave,
    required this.onDefault,
    this.defaultId,
  });

  final List<Dashboard> dashboards;
  final bool Function(Dashboard d) canEdit;
  final Future<void> Function(Dashboard d) onSave;
  final Future<void> Function(String id) onDefault;
  final String? defaultId;

  @override
  State<DashboardsOrderScreen> createState() => _DashboardsOrderScreenState();
}

class _DashboardsOrderScreenState extends State<DashboardsOrderScreen> {
  late List<Dashboard> _list = [...widget.dashboards];
  late String? _default = widget.defaultId;

  List<Dashboard> _scope(DashboardScope s) => [
    for (final d in _list)
      if (d.scope == s) d,
  ];

  /// Przesunięcie w obrębie swojej grupy; nowe `order` = pozycja w grupie (zapis tylko zmienionych).
  Future<void> _move(Dashboard d, int by) async {
    final group = _scope(d.scope);
    final i = group.indexWhere((x) => x.id == d.id);
    final to = i + by;
    if (to < 0 || to >= group.length) return;
    group.insert(to, group.removeAt(i));
    final changed = <Dashboard>[];
    for (final (k, x) in group.indexed) {
      if (x.order != k) changed.add(x.copyWith(order: k));
    }
    setState(() {
      final byId = {for (final x in changed) x.id: x};
      final others = [
        for (final x in _list)
          if (x.scope != d.scope) x,
      ];
      final moved = [for (final x in group) byId[x.id] ?? x];
      _list = d.scope == DashboardScope.private ? [...moved, ...others] : [...others, ...moved];
    });
    for (final x in changed) {
      await widget.onSave(x);
    }
  }

  Future<void> _rename(Dashboard d) async {
    final name = await showTextInputDialog(context, title: 'Nazwa pulpitu', initial: d.name, maxLength: 24);
    if (name == null || name.trim().isEmpty) return;
    final r = d.copyWith(name: name.trim());
    setState(() => _list = [for (final x in _list) x.id == d.id && x.scope == d.scope ? r : x]);
    await widget.onSave(r);
  }

  Future<void> _makeDefault(Dashboard d) async {
    setState(() => _default = d.id);
    await widget.onDefault(d.id);
  }

  Widget _row(Dashboard d, int i, int n) {
    final editable = widget.canEdit(d);
    return ListTile(
      key: Key('order-${d.id}'),
      leading: IconButton(
        key: Key('orderDefault-${d.id}'),
        tooltip: d.id == _default ? 'Otwierany na starcie' : 'Otwieraj na starcie',
        icon: Icon(d.id == _default ? Icons.star : Icons.star_border),
        onPressed: () => _makeDefault(d),
      ),
      title: Text(d.name),
      onTap: editable ? () => _rename(d) : null,
      trailing: editable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('orderUp-${d.id}'),
                  tooltip: 'Wyżej',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: i == 0 ? null : () => _move(d, -1),
                ),
                IconButton(
                  key: Key('orderDown-${d.id}'),
                  tooltip: 'Niżej',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: i == n - 1 ? null : () => _move(d, 1),
                ),
              ],
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = _scope(DashboardScope.private), shared = _scope(DashboardScope.shared);
    return Scaffold(
      appBar: AppBar(title: const Text('Kolejność i nazwy pulpitów')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Dotknij nazwy, aby ją zmienić. Gwiazdka - pulpit otwierany na starcie.'),
          ),
          if (mine.isNotEmpty) ...[
            const SectionHeader('Moje pulpity'),
            for (final (i, d) in mine.indexed) _row(d, i, mine.length),
          ],
          if (shared.isNotEmpty) ...[
            const SectionHeader('Wspólne pulpity domu'),
            for (final (i, d) in shared.indexed) _row(d, i, shared.length),
          ],
        ],
      ),
    );
  }
}
