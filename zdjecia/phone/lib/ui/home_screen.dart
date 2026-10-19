// Ekran główny: stan przeglądania galerii, pula zdjęć dla zegarka (okrągłe podglądy jak na zegarku),
// udostępnianie zegarkowi i dziennik zapytań z aplikacji Zepp.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../bridge/bridge_server.dart';
import '../bridge/format.dart';
import '../media/gallery.dart';
import '../pool_controller.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  final _server = BridgeServer();
  late final PoolController _pool = PoolController(_server);
  late final StreamSubscription<BridgeRequest> _requestsSub;
  final List<BridgeRequest> _requests = [];
  String? _serverError;
  String? _selfCheck;

  @override
  void initState() {
    super.initState();
    _requestsSub = _server.requests.listen((r) => setState(() => _requests.insert(0, r)));
    WidgetsBinding.instance.addPostFrameCallback((_) => _pool.init());
  }

  @override
  void dispose() {
    _requestsSub.cancel();
    _pool.dispose();
    _server.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _toggleServer(bool on) async {
    setState(() => _serverError = null);
    if (on) {
      try {
        await _server.start();
        // Telefon nie może zasnąć - Android zamraża aplikacje w tle i serwer przestałby odpowiadać
        await WakelockPlus.enable();
      } on SocketException catch (e) {
        _serverError = 'Nie mogę otworzyć portu $bridgePort: ${e.message}';
      }
    } else {
      await _server.stop();
      await WakelockPlus.disable();
    }
    setState(() {});
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
            _serverCard(context),
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
      case PoolPhase.preparing:
        line = 'Kadruję zdjęcia dla zegarka: ${p.done} z ${p.total}';
      case PoolPhase.noAccess:
        line = 'Brak dostępu do zdjęć – zezwól w ustawieniach aplikacji.';
      case PoolPhase.failed:
        line = 'Błąd: ${p.error}';
      case PoolPhase.ready:
        line = 'Pula: ${p.pool.length} zdjęć wybranych z ${p.scored.length} '
            '(ostatnie ${p.prefs.days} dni)';
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
            if (working) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: p.total > 0 ? p.done / p.total : null),
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

  Widget _serverCard(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Udostępnij zegarkowi', style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(_server.running ? 'Działa: http://127.0.0.1:$bridgePort (tylko ten telefon)' : 'Wyłączone'),
              value: _server.running,
              onChanged: _toggleServer,
            ),
            if (_serverError != null) Text(_serverError!, style: TextStyle(color: error)),
            if (_server.running && _pool.pool.isEmpty)
              Text('Pula jest pusta – zegarek nic nie dostanie.', style: TextStyle(color: error)),
            if (_server.running) ...[
              const Text(
                'Teraz na zegarku otwórz Zdjęcia i naciśnij „Pobierz z telefonu”. '
                'Nie zamykaj tej aplikacji – ekran telefonu nie zgaśnie, dopóki udostępnianie działa.',
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _checkServer, child: const Text('Sprawdź serwer')),
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
