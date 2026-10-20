// Ekran główny: stan przeglądania galerii, pula zdjęć dla zegarka (okrągłe podglądy jak na zegarku),
// automatyka w tle (most dla zegarka + odświeżanie puli) i dziennik zapytań z aplikacji Zepp.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../background/auto_service.dart';
import '../bridge/bridge_server.dart';
import '../bridge/format.dart';
import '../media/gallery.dart';
import '../pool_controller.dart';
import '../select/store.dart';
import 'ai_settings_screen.dart';
import 'photo_sheet.dart';
import 'pick_screen.dart';
import 'settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.version});

  final String version;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _pool = PoolController();
  final List<BridgeRequest> _requests = [];
  String? _autoError;
  String? _selfCheck;
  bool _autoRunning = false;
  bool _autoRefreshing = false;
  AutoState _auto = const AutoState();
  bool _screenKeptOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _pool.addListener(_keepScreenWhileWorking);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _pool.removeListener(_keepScreenWhileWorking);
    _pool.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _start() async {
    initAutoService();
    await _pool.init(refreshNow: false);
    if (_pool.prefs.autoEnabled) await _setAuto(true, remember: false);
    await _readAuto();
    await _pool.refresh();
  }

  // Powrót do aplikacji: usługa w tle mogła w tym czasie odświeżyć pulę
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _readAuto();
      _pool.refresh();
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data['type']) {
      case 'request':
        setState(() => _requests.insert(0, BridgeRequest.fromJson(data)));
      case 'refreshing':
        setState(() => _autoRefreshing = true);
      case 'refreshed':
        _autoRefreshing = false;
        _readAuto();
        _pool.refresh();
      case 'error':
        setState(() => _autoError = data['message'] as String?);
    }
  }

  Future<void> _readAuto() async {
    final running = await autoServiceRunning();
    final state = await _pool.autoState();
    if (!mounted) return;
    setState(() {
      _autoRunning = running;
      _auto = state;
    });
  }

  Future<void> _setAuto(bool on, {bool remember = true}) async {
    setState(() => _autoError = null);
    if (remember) await _pool.setAutoEnabled(on);
    if (on) {
      final error = await startAutoService();
      if (error != null) _autoError = 'Nie udało się uruchomić usługi w tle: $error';
    } else {
      await stopAutoService();
    }
    await _readAuto();
  }

  // Ekran nie gaśnie, dopóki aplikacja pracuje na ekranie (analiza, ocena AI, kadrowanie) -
  // Android zamraża aplikacje w tle, więc praca by stanęła
  void _keepScreenWhileWorking() {
    final needed = _pool.busy;
    if (needed == _screenKeptOn) return;
    _screenKeptOn = needed;
    WakelockPlus.toggle(enable: needed);
  }

  Future<void> _checkServer() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$bridgePort/manifest.json'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final count = (jsonDecode(body)['photos'] as List).length;
      _selfCheck = 'OK: HTTP ${res.statusCode}, zdjęć na liście: $count';
    } catch (e) {
      _selfCheck = 'Błąd: $e';
    } finally {
      client.close(force: true);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pool,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('Zdjęcia ${widget.version}'),
          actions: [
            IconButton(
              tooltip: 'Ocena przez AI',
              icon: const Icon(Icons.auto_awesome),
              onPressed: _pool.busy ? null : _openAi,
            ),
            IconButton(
              tooltip: 'Dodaj zdjęcie ręcznie',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _pool.busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PickScreen(pool: _pool))),
            ),
            IconButton(
              tooltip: 'Ustawienia',
              icon: const Icon(Icons.tune),
              onPressed: _pool.busy ? null : () => showSettingsSheet(context, _pool),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _statusCard(context),
            if (_pool.pool.isNotEmpty) _poolGrid(context),
            _autoCard(context),
            _requestsCard(context),
          ],
        ),
      ),
    );
  }

  void _openAi() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiSettingsScreen(pool: _pool)));

  Widget _statusCard(BuildContext context) {
    final p = _pool;
    final text = Theme.of(context).textTheme;
    final working = p.busy;
    String line;
    switch (p.phase) {
      case PoolPhase.starting:
      case PoolPhase.scanning:
        line = 'Szukam zdjęć z aparatu z ostatnich ${p.prefs.days} dni...';
      case PoolPhase.analyzing:
        line = 'Analizuję nowe zdjęcia: ${p.done} z ${p.total}';
      case PoolPhase.rating:
        line = 'Gemini ocenia zdjęcia: ${p.done} z ${p.total}';
      case PoolPhase.memories:
        line = 'Szukam wspomnień w starszych zdjęciach: okres ${p.done + 1} z ${p.total}';
      case PoolPhase.preparing:
        line = 'Kadruję zdjęcia dla zegarka: ${p.done} z ${p.total}';
      case PoolPhase.noAccess:
        line = 'Brak dostępu do zdjęć – zezwól w ustawieniach aplikacji.';
      case PoolPhase.failed:
        line = 'Błąd: ${p.error}';
      case PoolPhase.ready:
        final memories = p.pool.where((i) => i.isMemory).length;
        line = 'Pula: ${p.pool.length} zdjęć – ${p.pool.length - memories} świeżych '
            '(ostatnie ${p.prefs.days} dni) i $memories wspomnień';
    }
    final rejected = p.rejectedCounts.entries.map((e) => '${e.key} ${e.value}').join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Najciekawsze zdjęcia', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(line),
            if (p.lockedOut && !working)
              Text('Pula odświeża się teraz w tle – wynik pojawi się sam.', style: text.bodySmall),
            if (working) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: p.total > 0 ? p.done / p.total : null),
              const SizedBox(height: 4),
              Text('Ekran nie zgaśnie, dopóki trwa praca – zostaw aplikację otwartą.', style: text.bodySmall),
            ],
            if (!working && p.phase == PoolPhase.ready && p.aiActive)
              Text('Ocenione przez AI: ${p.ratedCount} z ${p.scored.length}', style: text.bodySmall),
            if (!working && p.phase == PoolPhase.ready && rejected.isNotEmpty)
              Text('Pominięte: $rejected', style: text.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis),
            if (p.aiError != null)
              Text(p.aiError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!working && !p.aiActive)
              TextButton.icon(
                onPressed: _openAi,
                icon: const Icon(Icons.auto_awesome),
                label: Text(p.hasApiKey ? 'Ocena przez AI jest wyłączona' : 'Włącz ocenę przez AI (klucz Gemini)'),
              ),
            if (p.limited && !working)
              TextButton(
                onPressed: () async {
                  await pickMorePhotos();
                  await p.refresh();
                },
                child: const Text('Aplikacja widzi tylko wybrane zdjęcia – wybierz więcej'),
              ),
            if (p.phase == PoolPhase.noAccess)
              TextButton(onPressed: PhotoManager.openSetting, child: const Text('Otwórz ustawienia')),
            if (!working)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: p.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Odśwież'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _poolGrid(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.8,
          children: [
            for (final item in _pool.pool)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showPhotoSheet(context, _pool, item),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(child: ClipOval(child: Image.memory(item.png, fit: BoxFit.cover))),
                          if (_pool.pinned.contains(item.id))
                            const Positioned(right: 0, top: 0, child: Icon(Icons.push_pin, size: 20, color: Colors.orange)),
                          if (item.isMemory)
                            Positioned(
                              left: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                                child: Text('${item.taken.year}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.scored.tags.isEmpty ? formatDay(item.taken) : item.scored.tags.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _autoCard(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final small = Theme.of(context).textTheme.bodySmall;
    final last = _auto.lastRun;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Automatyka w tle', style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(_autoRunning
                  ? 'Zegarek sam dostaje zdjęcia, pula odświeża się co ${autoRefreshEvery.inHours} h'
                  : 'Wyłączona – zegarek nie dostanie nowych zdjęć'),
              value: _autoRunning,
              onChanged: (on) => _setAuto(on),
            ),
            if (_autoError != null) Text(_autoError!, style: TextStyle(color: error)),
            if (_autoRefreshing) Text('Pula odświeża się teraz w tle...', style: small),
            if (last != null)
              Text(
                'Ostatnio w tle: ${formatDateTime(last)} – '
                '${_auto.ok ? 'pula ${_auto.poolSize} zdjęć, nowe: ${_auto.newPhotos}' : 'błąd: ${_auto.error}'}',
                style: _auto.ok ? small : TextStyle(color: error),
              ),
            if (_autoRunning) ...[
              const SizedBox(height: 4),
              Text(
                'Most dla zegarka: http://127.0.0.1:$bridgePort (tylko ten telefon). '
                'Android pokazuje przy tym ciche powiadomienie – można je zwinąć w ustawieniach powiadomień.',
                style: small,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: _checkServer, child: const Text('Sprawdź most')),
                  OutlinedButton(
                    onPressed: _autoRefreshing || _pool.busy ? null : requestAutoRefresh,
                    child: const Text('Odśwież w tle teraz'),
                  ),
                ],
              ),
              if (_selfCheck != null) Text(_selfCheck!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _requestsCard(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('Zapytania z aplikacji Zepp (${_requests.length})'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_requests.isEmpty) const Text('Jeszcze nikt nie pytał.'),
          for (final r in _requests.take(30))
            Text(
              '${formatClock(r.at)}  ${r.method} ${r.path}  ${r.status}  ${formatBytes(r.bytes)}  ${formatDuration(r.took)}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
        ],
      ),
    );
  }
}
