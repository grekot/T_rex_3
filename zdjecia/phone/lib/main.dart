// Zdjęcia - etap próbny: 3 ostatnie zdjęcia z galerii jako PNG 480×480 udostępnione zegarkowi pod 127.0.0.1.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'bridge/bridge_server.dart';
import 'bridge/format.dart';
import 'bridge/gallery.dart';

// Wersję ustawia CI z tagu (--dart-define=APP_VERSION), lokalny build pokazuje „dev”
const _version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

void main() => runApp(const ZdjeciaApp());

class ZdjeciaApp extends StatelessWidget {
  const ZdjeciaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zdjęcia',
      theme: ThemeData(
        colorSchemeSeed: Colors.orange,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _server = BridgeServer();
  late final StreamSubscription<BridgeRequest> _requestsSub;
  final List<BridgeRequest> _requests = [];
  GalleryLoad? _load;
  int _count = 3;
  bool _loading = false;
  String? _error;
  String? _selfCheck;

  @override
  void initState() {
    super.initState();
    _requestsSub = _server.requests.listen((r) => setState(() => _requests.insert(0, r)));
    // Od razu po otwarciu: zdjęcia gotowe, wystarczy włączyć udostępnianie
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPhotos());
  }

  List<PreparedPhoto> get _photos => _load?.photos ?? const [];

  @override
  void dispose() {
    _requestsSub.cancel();
    _server.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = await loadLatestPhotos(_count);
      _server.photos = [for (final p in load.photos) p.photo];
      setState(() => _load = load);
    } catch (e) {
      setState(() => _error = 'Nie udało się przygotować zdjęć: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleServer(bool on) async {
    setState(() => _error = null);
    if (on) {
      if (_photos.isEmpty) await _loadPhotos();
      try {
        await _server.start();
        // Telefon nie może zasnąć - Android zamraża aplikacje w tle i serwer przestałby odpowiadać
        await WakelockPlus.enable();
      } on SocketException catch (e) {
        _error = 'Nie mogę otworzyć portu $bridgePort: ${e.message}';
      }
    } else {
      await _server.stop();
      await WakelockPlus.disable();
    }
    setState(() {});
  }

  // Ten sam adres, który odpytuje aplikacja Zepp - sprawdza, czy serwer w ogóle odpowiada
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Zdjęcia na zegarek – próba $_version')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            ),
          _photosCard(text),
          _serverCard(text),
          _requestsCard(text),
        ],
      ),
    );
  }

  Widget _photosCard(TextTheme text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Zdjęcia do wysłania', style: text.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 3, label: Text('3')),
                    ButtonSegment(value: 5, label: Text('5')),
                    ButtonSegment(value: 10, label: Text('10')),
                  ],
                  selected: {_count},
                  onSelectionChanged: (s) => setState(() => _count = s.first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _loading ? null : _loadPhotos,
                    child: Text(_loading ? 'Przygotowuję...' : 'Weź ostatnie'),
                  ),
                ),
              ],
            ),
            if (_load != null) ...[
              const SizedBox(height: 8),
              Text(accessSummary(_load!)),
              if (!_load!.hasAccess)
                TextButton(onPressed: PhotoManager.openSetting, child: const Text('Otwórz ustawienia')),
              if (_load!.limited)
                TextButton(
                  onPressed: () async {
                    await pickMorePhotos();
                    await _loadPhotos();
                  },
                  child: const Text('Wybierz więcej zdjęć'),
                ),
              for (final problem in _load!.problems)
                Text(problem, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            for (final p in _photos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipOval(child: Image.memory(p.photo.png, width: 56, height: 56)),
                title: Text(formatDateTime(p.photo.taken)),
                subtitle: Text(
                  'PNG ${formatBytes(p.photo.png.length)} · ${p.source} ${formatBytes(p.sourceBytes)}'
                  ' · ${formatDuration(p.took)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _serverCard(TextTheme text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('2. Udostępnij zegarkowi', style: text.titleMedium),
              subtitle: Text(_server.running
                  ? 'Działa: http://127.0.0.1:$bridgePort (tylko ten telefon)'
                  : 'Wyłączone'),
              value: _server.running,
              onChanged: _toggleServer,
            ),
            if (_server.running && _photos.isEmpty)
              Text(
                'Lista zdjęć jest pusta – zegarek nic nie dostanie. Sprawdź punkt 1.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_server.running) ...[
              const Text(
                'Teraz na zegarku otwórz Zdjęcia i naciśnij „Pobierz z telefonu”. '
                'Nie zamykaj tej aplikacji – ekran telefonu nie zgaśnie, dopóki serwer działa.',
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

  Widget _requestsCard(TextTheme text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('3. Zapytania z aplikacji Zepp', style: text.titleMedium),
            const SizedBox(height: 8),
            if (_requests.isEmpty)
              const Text(
                'Jeszcze nikt nie pytał. Jeśli zegarek pokazuje błąd, a tu nic się nie pojawia, '
                'to aplikacja Zepp nie dociera do 127.0.0.1.',
              ),
            for (final r in _requests.take(30))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${formatClock(r.at)}  ${r.method} ${r.path}  ${r.status}  '
                  '${formatBytes(r.bytes)}  ${formatDuration(r.took)}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
