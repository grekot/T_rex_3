import 'package:flutter/material.dart';

import '../data/device_store.dart';
import '../data/errors.dart';
import '../data/pc_token.dart';
import '../models/home.dart';
import '../services.dart';
import 'qr_scan_screen.dart';

/// „Wyślij token do komputera” (pkt 2a): skan kodu z `tools/pair_pc.py`, potem wybór urządzeń.
Future<void> sendTokenToComputer(BuildContext context, {bool camera = true}) async {
  final qr = await Navigator.of(context).push<Object>(
    MaterialPageRoute(
      builder: (_) => QrScanScreen(
        camera: camera,
        parse: PcTokenQr.parse,
        title: 'Kod z komputera',
        hint: 'Na komputerze uruchom „python tools/pair_pc.py” i zeskanuj kod z przeglądarki (ważny 5 minut).',
      ),
    ),
  );
  if (qr is! PcTokenQr || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PcTokenScreen(qr: qr)));
}

/// Wybór urządzeń (tylko te, w których telefon ma `config` i zna adres) i wysłanie ich tokenów na komputer.
class PcTokenScreen extends StatefulWidget {
  const PcTokenScreen({super.key, required this.qr});

  final PcTokenQr qr;

  @override
  State<PcTokenScreen> createState() => _PcTokenScreenState();
}

class _PcTokenScreenState extends State<PcTokenScreen> {
  late Future<List<PairedDevice>> _devices;
  final _chosen = <String>{};
  bool _busy = false;
  String? _error;
  PcTokenResult? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devices = Services.of(context).store.devices().then((l) => [
      for (final d in l)
        if (d.access == AccessLevel.config && d.lastEndpoint != null) d,
    ]);
  }

  Future<void> _send(List<PairedDevice> all) async {
    final store = Services.of(context).store;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await sendTokensToPc(widget.qr, [for (final d in all) if (_chosen.contains(d.id)) d], store.token);
      setState(() => _result = r);
    } on ThermostatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text('Token dla: ${widget.qr.name}')),
      body: FutureBuilder<List<PairedDevice>>(
        future: _devices,
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          if (r != null) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Icon(Icons.check_circle, size: 56, color: cs.primary),
                const SizedBox(height: 8),
                Text(
                  'Komputer zapisał tokeny: ${r.saved.length}',
                  key: const Key('pcSaved'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final id in r.saved) ListTile(dense: true, leading: const Icon(Icons.computer), title: Text(id)),
                for (final e in r.failed.entries)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.error_outline, color: cs.error),
                    title: Text(e.key),
                    subtitle: Text(e.value),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Teraz na komputerze działa tools/ota.py <id> <plik.bin>. Token komputera widać i usuwa się '
                  'w ustawieniach urządzenia → Telefony.',
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Gotowe')),
              ],
            );
          }
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Każde wybrane urządzenie wystawi komputerowi własny token „pełny dostęp” (do aktualizacji '
                  'i testów). Wysyłka idzie tylko w sieci domowej.',
                ),
              ),
              if (all.isEmpty)
                const ListTile(title: Text('Brak urządzeń, w których ten telefon ma pełny dostęp.')),
              for (final d in all)
                CheckboxListTile(
                  key: Key('pc-${d.id}'),
                  value: _chosen.contains(d.id),
                  title: Text(d.name),
                  subtitle: Text('${d.type.label} · ${d.lastEndpoint!.display}'),
                  onChanged: (v) => setState(() => v == true ? _chosen.add(d.id) : _chosen.remove(d.id)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, key: const Key('pcError'), style: TextStyle(color: cs.error)),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const Key('pcSend'),
                  onPressed: _chosen.isEmpty || _busy ? null : () => _send(all),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Wyślij (${_chosen.length})'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
