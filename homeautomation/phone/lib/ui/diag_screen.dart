// Diagnostyka urządzenia (kontrakt pkt 3c): stan (restarty i ich przyczyny, pamięć, aktualizacje, ostatnie błędy,
// awarie ze zrzutem) i dziennik (`GET /api/log`, tylko w domu). Każde urządzenie z lib/HomeNode: hub, węzły, termostat.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/errors.dart';
import '../data/local_api.dart';
import '../models/diag.dart';
import '../models/json_utils.dart';
import 'format.dart';
import 'widgets.dart';

/// `12,3 kB`.
String fmtBytes(int? b) => b == null
    ? '—'
    : b >= 1024 * 1024
    ? '${fmtNumber(b / 1024 / 1024)} MB'
    : '${fmtNumber(b / 1024)} kB';

class DiagScreen extends StatefulWidget {
  const DiagScreen({super.key, required this.name, this.api, this.cloudDiag});

  final String name;

  /// W domu: `GET /api/diag`, `/api/log`, `DELETE /api/coredump`.
  final LocalApi? api;

  /// Poza domem: kopia `homes/{h}/devices/{id}/diag` (zapis przy starcie i co 15 min); null = bez chmury.
  final Future<Json?> Function()? cloudDiag;

  @override
  State<DiagScreen> createState() => _DiagScreenState();
}

class _DiagScreenState extends State<DiagScreen> {
  Future<DeviceDiag?>? _diag;
  Future<String>? _log;
  final _filter = TextEditingController();
  final _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _filter.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      final api = widget.api;
      _diag = api != null
          ? api.diag().then(DeviceDiag.fromJson)
          : widget.cloudDiag == null
          ? Future.value(null)
          : widget.cloudDiag!().then((j) => j == null ? null : DeviceDiag.fromJson(j));
      _log = api?.log(timeout: const Duration(seconds: 10));
    });
    // Dziennik: od razu na koniec (najnowsze wiersze).
    unawaited(
      _log?.then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        });
      }, onError: (_) {}),
    );
  }

  Future<void> _deleteDump() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć zrzut awarii?'),
        content: const Text(
          'Zniknie pełny zrzut z pamięci urządzenia i lista ostatnich awarii. Zrób to, gdy już go nie potrzebujesz '
          '(np. po rozkodowaniu na komputerze).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            key: const Key('diagDeleteOk'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api!.deleteCoreDump();
      messenger.showSnackBar(const SnackBar(content: Text('Usunięto zrzut awarii.')));
      _reload();
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.api != null;
    return DefaultTabController(
      length: local ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Diagnostyka · ${widget.name}'),
          actions: [
            IconButton(
              key: const Key('diagRefresh'),
              tooltip: 'Odśwież',
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(key: Key('diagTabState'), text: 'Stan'),
              if (local) const Tab(key: Key('diagTabLog'), text: 'Dziennik'),
            ],
          ),
        ),
        body: TabBarView(children: [_stateTab(context), if (local) _logTab(context)]),
      ),
    );
  }

  Widget _stateTab(BuildContext context) => FutureBuilder<DeviceDiag?>(
    future: _diag,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      final d = snap.data;
      if (snap.hasError || d == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              snap.error is ThermostatException
                  ? (snap.error! as ThermostatException).message
                  : widget.api == null && widget.cloudDiag == null
                  ? 'Diagnostyka jest dostępna w sieci domowej albo przez chmurę.'
                  : 'Urządzenie nie podało diagnostyki.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return _DiagView(diag: d, local: widget.api != null, onDeleteDump: widget.api == null ? null : _deleteDump);
    },
  );

  Widget _logTab(BuildContext context) => FutureBuilder<String>(
    future: _log,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) {
        final e = snap.error;
        return Center(child: Text(e is ThermostatException ? e.message : 'Nie udało się pobrać dziennika.'));
      }
      final all = (snap.data ?? '').split('\n').where((l) => l.trim().isNotEmpty).toList();
      final q = _filter.text.trim().toLowerCase();
      final lines = q.isEmpty ? all : all.where((l) => l.toLowerCase().contains(q)).toList();
      final t = Theme.of(context).textTheme;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('diagLogFilter'),
                    controller: _filter,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Szukaj w dzienniku (np. chmura, błąd, WiFi)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  key: const Key('diagLogCopy'),
                  tooltip: 'Kopiuj',
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Skopiowano ${lines.length} ${lines.length == 1 ? 'wiersz' : 'wierszy'}.'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                q.isEmpty
                    ? '${all.length} wierszy od ostatniego restartu urządzenia (najnowsze na dole)'
                    : '${lines.length} z ${all.length} wierszy',
                key: const Key('diagLogCount'),
                style: t.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('diagLog'),
              controller: _logScroll,
              padding: listPadding(context, const EdgeInsets.fromLTRB(12, 0, 12, 24)),
              itemCount: lines.length,
              itemBuilder: (context, i) {
                final l = lines[i];
                final bad = RegExp(r'błąd|BLAD|nieudan|error|fail|panic|wdt', caseSensitive: false).hasMatch(l);
                return SelectableText(
                  l,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: bad ? Theme.of(context).colorScheme.error : null,
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

class _DiagView extends StatelessWidget {
  const _DiagView({required this.diag, required this.local, this.onDeleteDump});

  final DeviceDiag diag;
  final bool local;
  final VoidCallback? onDeleteDump;

  @override
  Widget build(BuildContext context) {
    final d = diag;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget row(String label, String value, {Key? key, bool bad = false}) => ListTile(
      key: key,
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(color: bad ? cs.error : null, fontWeight: bad ? FontWeight.w600 : null),
      ),
    );
    final guard = d.guard;
    return ListView(
      padding: listPadding(context, const EdgeInsets.only(bottom: 24)),
      children: [
        if (!local)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Kopia z chmury (zapis przy starcie i co 15 min). Dziennik - tylko w sieci domowej.'),
          ),
        const SectionHeader('Praca'),
        row('Wersja', d.fw ?? '—'),
        row('Działa od', d.uptime == null ? '—' : fmtUptime(d.uptime!), key: const Key('diagUptime')),
        row(
          'Ostatni restart',
          resetReasonText(d.resetReason),
          key: const Key('diagReset'),
          bad: resetIsFault(d.resetReason),
        ),
        const SectionHeader('Restarty od pierwszego uruchomienia'),
        row('Uruchomienia', '${d.boots ?? '—'}'),
        row('Zawieszenia (watchdog)', '${d.wdtResets}', bad: d.wdtResets > 0),
        row('Awarie programu', '${d.panics}', bad: d.panics > 0),
        row('Spadki napięcia', '${d.brownouts}', bad: d.brownouts > 0),
        if (d.guardRestarts > 0)
          ListTile(
            key: const Key('diagGuard'),
            dense: true,
            title: const Text('Restarty strażnika łącza'),
            subtitle: guard == null
                ? null
                : Text(
                    [
                      if (guard.at != null) 'ostatni ${_when(guard.at!)}',
                      if (guard.why.isNotEmpty) guard.why,
                    ].join(' · '),
                  ),
            trailing: Text(
              '${d.guardRestarts}',
              style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
            ),
          ),
        const SectionHeader('Pamięć'),
        row('Wolna', fmtBytes(d.heapFree)),
        row('Najmniej od startu', fmtBytes(d.heapMin), bad: (d.heapMin ?? 1 << 30) < 20 * 1024),
        row('Największy wolny blok', fmtBytes(d.heapMaxBlock), bad: (d.heapMaxBlock ?? 1 << 30) < 8 * 1024),
        if (d.psramFree != null) row('PSRAM wolna', fmtBytes(d.psramFree)),
        const SectionHeader('Aktualizacje'),
        row('Partycja', d.otaPartition ?? '—'),
        if (d.otaTrial) row('Nowa wersja', 'na próbę (powrót przy awarii)'),
        row(
          'Powroty do poprzedniej wersji',
          d.rolledBackFrom == null ? '${d.rollbacks}' : '${d.rollbacks} (ostatnio z ${d.rolledBackFrom})',
          bad: d.rollbacks > 0,
        ),
        SectionHeader('Ostatnie błędy (${d.errors.length})'),
        if (d.errors.isEmpty)
          const ListTile(dense: true, title: Text('Brak błędów od startu.'))
        else
          for (final e in d.errors.reversed)
            ListTile(
              dense: true,
              leading: Icon(Icons.error_outline, color: cs.error),
              title: Text(e.msg),
              subtitle: Text(
                [
                  if (d.uptime != null && d.uptime! >= e.t) fmtAge(d.uptime! - e.t) else '${fmtUptime(e.t)} po starcie',
                  if (e.n > 1) '${e.n}× pod rząd',
                ].join(' · '),
              ),
            ),
        SectionHeader('Awarie ze zrzutem (${d.crashes.length})'),
        if (d.crashes.isEmpty)
          const ListTile(dense: true, title: Text('Brak zapisanych awarii.'))
        else
          for (final c in d.crashes.reversed)
            ListTile(
              dense: true,
              leading: Icon(Icons.bug_report_outlined, color: cs.error),
              title: Text('${c.boot == null ? '' : 'Start ${c.boot}: '}${resetReasonText(c.reason)}'),
              subtitle: Text(
                [
                  if (c.task != null) 'zadanie ${c.task}',
                  if (c.pc != null) 'adres ${c.pc}',
                  if (c.elf != null && c.elf != d.elf) 'inna wersja programu',
                ].join(' · '),
              ),
            ),
        if (d.coreDump || d.crashes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              d.coreDump
                  ? 'Pełny zrzut leży w pamięci urządzenia. Rozkodujesz go na komputerze: '
                        'python tools/coredump.py <id urządzenia>.'
                  : 'Pełnego zrzutu już nie ma - zostało podsumowanie.',
              style: t.bodySmall,
            ),
          ),
        if (onDeleteDump != null && (d.coreDump || d.crashes.isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              key: const Key('diagDeleteDump'),
              onPressed: onDeleteDump,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Usuń zrzut i listę awarii'),
            ),
          ),
      ],
    );
  }

  static String _when(DateTime at) {
    final s = DateTime.now().difference(at).inSeconds;
    return s < 0 ? 'przed chwilą' : fmtAge(s);
  }
}
