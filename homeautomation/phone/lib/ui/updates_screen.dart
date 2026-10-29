import 'dart:async';

import 'package:flutter/material.dart';

import '../data/errors.dart';
import '../data/updates.dart';
import '../models/firmware.dart';
import 'app_icons.dart';
import 'widgets.dart';

/// „Aktualizacje” (pkt 3e, właściciel / `config`): manifest wydań porównany z wersjami urządzeń. Termostat, hub
/// i urządzenia z chmurą pobierają plik same (Set `firmwareUrl` + `firmwareSha256`); węzły huba aktualizuje hub
/// po kolei, po zatwierdzeniu zaznaczonych.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key, required this.backend, this.hubRefresh = const Duration(seconds: 15)});

  final UpdateBackend backend;

  /// Odświeżanie listy węzłów, gdy hub coś aktualizuje.
  final Duration hubRefresh;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  FirmwareManifest? _manifest;
  List<UpdateTarget> _targets = const [];
  List<HubUpdatesView> _hubs = const [];
  bool _loading = true;
  String? _error;
  final _runs = <String, UpdateProgress>{};
  final _subs = <String, StreamSubscription<UpdateProgress>>{};
  final _selected = <String, Set<String>>{};
  Timer? _hubTimer;

  UpdateBackend get b => widget.backend;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hubTimer?.cancel();
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await b.manifest();
      final results = await Future.wait([b.targets(), b.hubs()]);
      if (!mounted) return;
      setState(() {
        _manifest = m;
        _hubs = results[1] as List<HubUpdatesView>;
        // Węzły za hubem aktualizuje hub - nie pokazujemy ich drugi raz.
        final viaHub = {for (final h in _hubs) ...h.updates.devices.map((d) => d.id)};
        _targets = [
          for (final t in results[0] as List<UpdateTarget>)
            if (!viaHub.contains(t.id)) t,
        ];
      });
      _scheduleHubRefresh();
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Nie udało się sprawdzić aktualizacji: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleHubRefresh() {
    _hubTimer?.cancel();
    if (!_hubs.any((h) => h.updates.devices.any((d) => d.state.busy))) return;
    _hubTimer = Timer(widget.hubRefresh, () async {
      try {
        final hubs = await b.hubs();
        if (!mounted) return;
        setState(() => _hubs = hubs);
        _scheduleHubRefresh();
      } on Object {
        // następna próba przy odświeżeniu ekranu
      }
    });
  }

  /// [check] z dostępną wersją: instalujemy `check.step` (przy dwóch krokach - najpierw wersję pośrednią).
  Future<void> _update(UpdateTarget t, UpdateCheck check) async {
    final r = check.step!;
    final last = check.release!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Zaktualizować ${t.name}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wersja ${t.fw} → ${r.version}${r.date == null ? '' : ' (${r.date})'}'),
              if (check.twoSteps) ...[
                const SizedBox(height: 8),
                Text(
                  'To wersja pośrednia - do ${last.version} urządzenie dojdzie w dwóch krokach. Drugi zatwierdzisz '
                  'po zakończeniu pierwszego.',
                  key: const Key('updateTwoSteps'),
                ),
              ],
              if ((last.notes ?? r.notes) != null) ...[const SizedBox(height: 8), Text((last.notes ?? r.notes)!)],
              if (t.warning != null) ...[
                const SizedBox(height: 12),
                Text(
                  t.warning!,
                  key: const Key('updateWarning'),
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Urządzenie pobierze plik i zrestartuje się. Przez 10 min trwa okres próbny - jeśli nowa wersja '
                'będzie się zawieszać, urządzenie samo wróci do poprzedniej.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            key: const Key('updateConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aktualizuj'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _runs[t.id] = const UpdateProgress(UpdatePhase.sending));
    _subs[t.id] = b
        .update(t, r)
        .listen(
          (p) {
            if (!mounted) return;
            setState(() => _runs[t.id] = p);
            if (p.phase == UpdatePhase.done && check.twoSteps) _nextStep(t, last);
          },
          onError: (Object e) {
            if (mounted) setState(() => _runs[t.id] = UpdateProgress(UpdatePhase.failed, message: '$e'));
          },
        );
  }

  /// Po wersji pośredniej: lista od nowa (urządzenie ma nową `fw`), drugi krok do zatwierdzenia.
  Future<void> _nextStep(UpdateTarget t, FirmwareRelease last) async {
    await _load();
    if (!mounted) return;
    setState(() => _runs.remove(t.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${t.name}: pierwszy krok gotowy - zatwierdź aktualizację do ${last.version}.')),
    );
  }

  Future<void> _checkHub(HubUpdatesView h) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await b.checkHub(h.hubId);
      messenger.showSnackBar(SnackBar(content: Text('Hub ${h.hubName} sprawdza wydania…')));
      await Future<void>.delayed(const Duration(seconds: 3));
      final hubs = await b.hubs();
      if (mounted) setState(() => _hubs = hubs);
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie udało się: $e')));
    }
  }

  Future<void> _applyHub(HubUpdatesView h) async {
    final ids = (_selected[h.hubId] ?? const <String>{}).toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Zaktualizować ${ids.length} ${ids.length == 1 ? 'węzeł' : 'węzły'}?'),
        content: const Text(
          'Hub aktualizuje po kolei: najpierw jeden węzeł i obserwuje go 10 min, potem resztę. Nieudana '
          'aktualizacja zatrzymuje kolejkę. W czasie restartu węzła jego światła nie reagują przez kilkanaście sekund.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aktualizuj')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await b.applyHub(h.hubId, ids);
      _selected.remove(h.hubId);
      final hubs = await b.hubs();
      if (!mounted) return;
      setState(() => _hubs = hubs);
      _scheduleHubRefresh();
      messenger.showSnackBar(SnackBar(content: Text('Hub ${h.hubName} zaczął aktualizację.')));
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie udało się: $e')));
    }
  }

  String _date(DateTime d) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _targetTile(UpdateTarget t, FirmwareManifest m) {
    final check = checkUpdate(m, fw: t.fw, fwId: t.fwId);
    final r = check.release;
    final run = _runs[t.id];
    final cs = Theme.of(context).colorScheme;
    final status = switch (check.status) {
      UpdateStatus.unknown => 'Wersja ${t.fw ?? '?'} - firmware nie podaje wariantu (fwId), zaktualizuj go raz ręcznie',
      UpdateStatus.noRelease => 'Wersja ${t.fw} - brak wydań dla ${t.fwId}',
      UpdateStatus.upToDate => 'Wersja ${t.fw} - aktualna',
      UpdateStatus.available when check.twoSteps => 'Wersja ${t.fw} → ${r!.version} (najpierw ${check.step!.version})',
      UpdateStatus.available => 'Wersja ${t.fw} → ${r!.version}',
      UpdateStatus.needsIntermediate =>
        'Wersja ${t.fw} → ${r!.version}: najpierw potrzebna wersja ${r.minVersion}, której pliku nie ma na liście',
    };
    Widget? trailing;
    if (run != null && !run.finished) {
      trailing = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(value: run.percent == null ? null : run.percent! / 100, strokeWidth: 3),
      );
    } else if (check.status == UpdateStatus.upToDate || run?.phase == UpdatePhase.done) {
      trailing = Icon(Icons.check_circle_outline, color: cs.primary);
    } else if (check.canUpdate && t.blocked == null) {
      trailing = FilledButton.tonal(
        key: Key('update-${t.id}'),
        onPressed: () => _update(t, check),
        child: const Text('Aktualizuj'),
      );
    }
    return ListTile(
      key: Key('target-${t.id}'),
      leading: Icon(appIcon(deviceIconKey(t.type))!.icon),
      title: Text(t.name),
      isThreeLine: check.canUpdate && r?.notes != null || run != null || t.blocked != null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          if (check.canUpdate && r?.notes != null) Text(r!.notes!, style: Theme.of(context).textTheme.bodySmall),
          if (check.canUpdate && t.blocked != null) Text(t.blocked!, style: TextStyle(color: cs.error)),
          if (run != null)
            Text(
              run.label,
              key: Key('progress-${t.id}'),
              style: TextStyle(color: run.phase == UpdatePhase.failed ? cs.error : cs.primary),
            ),
        ],
      ),
      trailing: trailing,
    );
  }

  List<Widget> _hubSection(HubUpdatesView h) {
    final sel = _selected[h.hubId] ??= <String>{};
    final cs = Theme.of(context).colorScheme;
    final checked = h.updates.checked;
    return [
      SectionHeader('Węzły huba ${h.hubName}'),
      Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                checked == null
                    ? 'Hub jeszcze nie sprawdzał wydań'
                    : 'Hub sprawdził wydania ${_date(DateTime.fromMillisecondsSinceEpoch(checked * 1000))}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              key: Key('hubCheck-${h.hubId}'),
              onPressed: () => _checkHub(h),
              child: const Text('Sprawdź teraz'),
            ),
          ],
        ),
      ),
      if (h.updates.devices.isEmpty) const ListTile(title: Text('Hub nie ma własnych węzłów.')),
      for (final d in h.updates.devices) _hubEntry(h, d, sel, cs),
      if (h.updates.devices.any((d) => d.selectable))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            key: Key('hubApply-${h.hubId}'),
            onPressed: sel.isEmpty ? null : () => _applyHub(h),
            icon: const Icon(Icons.system_update_alt),
            label: Text('Aktualizuj zaznaczone (${sel.length})'),
          ),
        ),
    ];
  }

  Widget _hubEntry(HubUpdatesView h, HubUpdateEntry d, Set<String> sel, ColorScheme cs) {
    final name = h.names[d.id] ?? d.id;
    final version = d.hasUpdate
        ? '${d.current} → ${d.next}${d.twoSteps ? ' (potem ${d.available})' : ''}'
        : (d.current ?? '?');
    final notes = [
      if (d.state != HubUpdateState.idle) d.state.label,
      if (d.hasUpdate && !d.ready && !d.state.busy) 'hub jeszcze pobiera plik',
      ?d.errorLabel,
    ].join(' · ');
    final subtitle = Text(
      notes.isEmpty ? 'Wersja $version' : 'Wersja $version · $notes',
      style: d.state == HubUpdateState.failed ? TextStyle(color: cs.error) : null,
    );
    if (d.selectable) {
      return CheckboxListTile(
        key: Key('hubUpd-${d.id}'),
        title: Text(name),
        subtitle: subtitle,
        value: sel.contains(d.id),
        onChanged: (v) => setState(() => v == true ? sel.add(d.id) : sel.remove(d.id)),
      );
    }
    return ListTile(
      key: Key('hubUpd-${d.id}'),
      leading: d.state.busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(d.hasUpdate ? Icons.update : Icons.check_circle_outline),
      title: Text(name),
      subtitle: subtitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _manifest;
    final fetched = b.manifestFetchedAt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktualizacje'),
        actions: [
          IconButton(
            key: const Key('updatesRefresh'),
            tooltip: 'Sprawdź ponownie',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading && m == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && m == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, key: const Key('updatesError')),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'Lista wydań${m?.generated == null ? '' : ' z ${m!.generated!.split('T').first}'}'
                      '${fetched == null ? '' : ', pobrana ${_date(fetched)}'}. Każdą aktualizację zatwierdzasz tutaj.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SectionHeader('Urządzenia'),
                  if (_targets.isEmpty)
                    const ListTile(title: Text('Brak urządzeń, którymi możesz zarządzać.'))
                  else
                    for (final t in _targets) _targetTile(t, m!),
                  for (final h in _hubs) ..._hubSection(h),
                ],
              ),
            ),
    );
  }
}
