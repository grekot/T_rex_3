import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/device_hub.dart';
import '../controllers/home_session.dart';
import '../data/device_store.dart';
import '../data/errors.dart';
import '../models/home.dart';
import 'account_menu.dart';
import 'widgets.dart';

/// „Domownicy” (pkt 12, tylko właściciel): lista, poziomy per urządzenie, zaproszenia, usuwanie.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.hub, required this.session});

  final DeviceHub hub;
  final HomeSession session;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late final Home _home = widget.session.current!;
  late final Stream<List<Member>> _members = widget.session.repo.members(_home.id);

  /// Zaproszenia utworzone w tej sesji (kodów nie da się wylistować z bazy).
  final _invites = <Invite>[];

  Future<void> _invite() async {
    final invite = await Navigator.of(context).push<Invite>(
      MaterialPageRoute(builder: (_) => InviteScreen(hub: widget.hub, session: widget.session)),
    );
    if (invite != null) setState(() => _invites.add(invite));
  }

  Future<void> _deleteInvite(Invite i) async {
    await widget.session.repo.deleteInvite(i.code);
    setState(() => _invites.remove(i));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Domownicy'), actions: [AccountMenu(session: widget.session)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        key: const Key('invite'),
        onPressed: _invite,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Zaproś'),
      ),
      body: StreamBuilder<List<Member>>(
        stream: _members,
        builder: (context, snap) {
          final members = snap.data ?? const <Member>[];
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (!snap.hasData) const LinearProgressIndicator(),
              for (final m in members)
                ListTile(
                  key: Key('member-${m.uid}'),
                  leading: CircleAvatar(child: Icon(m.role == MemberRole.owner ? Icons.star : Icons.person)),
                  title: Text(m.label),
                  subtitle: Text(m.role == MemberRole.owner ? 'właściciel · pełny dostęp' : m.email),
                  trailing: m.role == MemberRole.owner ? null : const Icon(Icons.chevron_right),
                  onTap: m.role == MemberRole.owner
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MemberAccessScreen(hub: widget.hub, session: widget.session, member: m),
                          ),
                        ),
                ),
              if (_invites.isNotEmpty) ...[
                const SectionHeader('Zaproszenia z tego telefonu'),
                for (final i in _invites)
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: SelectableText(i.code, style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.bold)),
                    subtitle: Text('ważne do ${_time(i.expiresAt)} · domyślnie ${i.access.all.label}'),
                    trailing: IconButton(
                      tooltip: 'Usuń zaproszenie',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteInvite(i),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _time(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

/// Poziomy jednego domownika (`homes/{h}/access/{uid}`) i usuwanie z domu.
class MemberAccessScreen extends StatefulWidget {
  const MemberAccessScreen({super.key, required this.hub, required this.session, required this.member});

  final DeviceHub hub;
  final HomeSession session;
  final Member member;

  @override
  State<MemberAccessScreen> createState() => _MemberAccessScreenState();
}

class _MemberAccessScreenState extends State<MemberAccessScreen> {
  HomeAccess? _access;
  bool _dirty = false;
  bool _saving = false;
  StreamSubscription<HomeAccess>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.session.repo.accessOf(widget.session.current!, widget.member.uid).listen((a) {
      if (!_dirty && mounted) setState(() => _access = a);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.session.repo.setAccess(widget.session.current!.id, widget.member.uid, _access!);
      _dirty = false;
      messenger.showSnackBar(
        const SnackBar(content: Text('Zapisano. Urządzenia odświeżają uprawnienia co 5 minut.')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie zapisano: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć ${widget.member.label} z domu?'),
        content: const Text(
          'Straci dostęp do urządzeń przez chmurę (urządzenia odświeżają uprawnienia co 5 minut). '
          'Tokeny jego telefonów usuń w ustawieniach urządzeń → Telefony.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.session.repo.removeMember(widget.session.current!.id, widget.member.uid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final a = _access;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.member.label),
        actions: [
          TextButton(
            key: const Key('saveAccess'),
            onPressed: _dirty && !_saving ? _save : null,
            child: const Text('Zapisz'),
          ),
        ],
      ),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                AccessEditor(
                  devices: widget.hub.devices,
                  value: a,
                  onChanged: (v) => setState(() {
                    _access = v;
                    _dirty = true;
                  }),
                ),
                const Divider(),
                ListTile(
                  key: const Key('removeMember'),
                  leading: Icon(Icons.person_remove, color: Theme.of(context).colorScheme.error),
                  title: const Text('Usuń z domu'),
                  onTap: _remove,
                ),
              ],
            ),
    );
  }
}

/// Nowe zaproszenie (pkt 12): poziomy dla dołączającego, potem kod do przekazania.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.hub, required this.session});

  final DeviceHub hub;
  final HomeSession session;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  HomeAccess _access = const HomeAccess(all: AccessLevel.control);
  Invite? _created;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = await widget.session.repo.createInvite(widget.session.current!.id, _access);
      setState(() => _created = invite);
    } on ThermostatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'Nie udało się: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final created = _created;
    return PopScope(
      canPop: created == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(created);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Zaproszenie')),
        body: created != null
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Kod zaproszenia', style: t.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  SelectableText(
                    created.code,
                    key: const Key('inviteCodeShown'),
                    textAlign: TextAlign.center,
                    style: t.displaySmall?.copyWith(letterSpacing: 6, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Przekaż kod domownikowi. W aplikacji HomeAutomation wybierze „Dołącz do domu” i wpisze go. '
                    'Kod jest ważny 24 godziny.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text:
                              'Zaproszenie do domu „${widget.session.current!.name}” w aplikacji HomeAutomation: '
                              'kod ${created.code} (ważny 24 h).',
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Skopiowano.')));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Kopiuj wiadomość'),
                  ),
                  TextButton(onPressed: () => Navigator.of(context).pop(created), child: const Text('Gotowe')),
                ],
              )
            : ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      'Ustal, co nowy domownik będzie mógł. Zaproszenie niesie tylko poziom domyślny - wyjątki dla '
                      'urządzeń aplikacja dopisze sama, gdy domownik dołączy (otwórz wtedy aplikację). '
                      'Najlepiej daj niższy poziom domyślny i wyższy dla wybranych urządzeń. Później zmienisz to w „Domownicy”.',
                    ),
                  ),
                  AccessEditor(devices: widget.hub.devices, value: _access, onChanged: (v) => setState(() => _access = v)),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      key: const Key('createInvite'),
                      onPressed: _busy ? null : _create,
                      child: const Text('Utwórz kod'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Edytor poziomów: `_all` (urządzenia bez osobnego wpisu, także nowe) + wyjątki per urządzenie.
class AccessEditor extends StatelessWidget {
  const AccessEditor({super.key, required this.devices, required this.value, required this.onChanged});

  final List<PairedDevice> devices;
  final HomeAccess value;
  final ValueChanged<HomeAccess> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Domyślnie (wszystkie urządzenia, także nowe)'),
        ListTile(
          title: const Text('Poziom domyślny'),
          trailing: _LevelDropdown(
            key: const Key('level-_all'),
            value: value.all,
            allowNone: true,
            onChanged: (l) => onChanged(value.copyWith(all: l)),
          ),
        ),
        if (devices.isNotEmpty) const SectionHeader('Wyjątki dla urządzeń'),
        for (final d in devices)
          ListTile(
            title: Text(d.name),
            subtitle: Text(d.type.label),
            trailing: _LevelDropdown(
              key: Key('level-${d.id}'),
              value: value.devices[d.id],
              // „brak dostępu” przy ogólnym `_all` odbiera to jedno urządzenie (pkt 12).
              allowNone: value.all != AccessLevel.none,
              defaultLabel: 'jak domyślnie',
              onChanged: (l) {
                final map = {...value.devices};
                if (l == null) {
                  map.remove(d.id);
                } else {
                  map[d.id] = l;
                }
                onChanged(value.copyWith(devices: map));
              },
            ),
          ),
      ],
    );
  }
}

class _LevelDropdown extends StatelessWidget {
  const _LevelDropdown({super.key, required this.value, required this.onChanged, this.allowNone = false, this.defaultLabel});

  final AccessLevel? value;
  final ValueChanged<AccessLevel?> onChanged;
  final bool allowNone;

  /// Z tym napisem: dodatkowa pozycja „null” (bez wyjątku).
  final String? defaultLabel;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<AccessLevel?>(
      value: value,
      items: [
        if (defaultLabel != null) DropdownMenuItem(value: null, child: Text(defaultLabel!)),
        if (allowNone) const DropdownMenuItem(value: AccessLevel.none, child: Text('brak dostępu')),
        for (final l in AccessLevel.grantable) DropdownMenuItem(value: l, child: Text(l.label)),
      ],
      onChanged: onChanged,
    );
  }
}
