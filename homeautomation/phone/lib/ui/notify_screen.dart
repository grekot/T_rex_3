import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/device_controller.dart';
import '../controllers/field_errors.dart';
import '../data/links.dart';
import '../models/json_utils.dart';
import '../models/notify.dart';
import '../models/set_values.dart';

/// Powiadomienia z urządzenia przez ntfy (kontrakt pkt 3d): urządzenie samo wysyła alarm (awaria czujnika,
/// mróz, nieudana aktualizacja, akcje automatyk huba), telefon subskrybuje temat w aplikacji ntfy.
/// Zmiany - poziom `config`, w sieci domowej (Config czytany z `GET /api/config`).
class NotifyScreen extends StatefulWidget {
  const NotifyScreen({
    super.key,
    required this.deviceName,
    required this.loadConfig,
    required this.send,
    this.openUrl = openExternalUrl,
  });

  NotifyScreen.forController(DeviceController<Object?, Object?> c, {Key? key})
    : this(key: key, deviceName: c.device.name, loadConfig: c.localApi!.configJson, send: c.sendJson);

  final String deviceName;
  final Future<Json> Function() loadConfig;
  final Future<SetResult> Function(Json values) send;
  final OpenUrl openUrl;

  @override
  State<NotifyScreen> createState() => _NotifyScreenState();
}

class _NotifyScreenState extends State<NotifyScreen> {
  NotifyConfig? _config;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = NotifyConfig.fromConfig(await widget.loadConfig());
      if (mounted) {
        setState(() {
          _config = c;
          _loaded = true;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = 'Nie udało się odczytać ustawień: $e';
        });
      }
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  /// Wysyła Set i odświeża Config; zwraca true, gdy bez błędów.
  Future<bool> _set(NotifySet s) async {
    setState(() => _busy = true);
    try {
      final r = await widget.send(s.toJson());
      if (r.errors.isNotEmpty) {
        _snack(describeErrors(r.errors));
        return false;
      }
      final fresh = r.configJson == null ? null : NotifyConfig.fromConfig(r.configJson!);
      if (fresh != null) {
        setState(() => _config = fresh);
      } else {
        await _load();
      }
      return true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _subscribe(NotifyConfig c) async {
    if (await widget.openUrl(c.subscribeUri)) return;
    if (await widget.openUrl(c.webUri)) return;
    await Clipboard.setData(ClipboardData(text: c.webUri.toString()));
    if (mounted) _snack('Nie ma aplikacji ntfy - zainstaluj ją. Adres tematu skopiowano.');
  }

  Future<void> _newTopic() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nowy temat?'),
        content: const Text(
          'Urządzenie wylosuje nowy temat. Dotychczasowe subskrypcje przestaną dostawać powiadomienia - '
          'każdy telefon musi zasubskrybować nowy temat.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zmień temat')),
        ],
      ),
    );
    if (ok == true && await _set(const NotifySet(topic: '')) && mounted) _snack('Nowy temat zapisany.');
  }

  Future<void> _server(NotifyConfig c) async {
    final r = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => _ServerDialog(config: c),
    );
    if (r == null) return;
    final (server, token) = r;
    if (await _set(NotifySet(server: server, token: token)) && mounted) _snack('Zapisano.');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('Powiadomienia')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
          : c == null
          ? const Padding(
              key: Key('notifyUnsupported'),
              padding: EdgeInsets.all(24),
              child: Text(
                'To urządzenie nie wysyła powiadomień - jego firmware jest starszy. Zaktualizuj firmware '
                'i wróć tutaj.',
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '${widget.deviceName} sam wyśle alarm na telefon przez aplikację ntfy - od razu, nawet gdy '
                    'HomeAutomation śpi: awaria czujnika, temperatura blisko ochrony przed mrozem, nieudana '
                    'aktualizacja i powrót do normy.',
                  ),
                ),
                SwitchListTile(
                  key: const Key('notifyEnabled'),
                  title: const Text('Wysyłaj powiadomienia'),
                  value: c.enabled,
                  onChanged: _busy ? null : (v) => _set(NotifySet(enabled: v)),
                ),
                ListTile(
                  title: const Text('Temat'),
                  subtitle: SelectableText(c.topic, key: const Key('notifyTopic'), style: t.titleMedium),
                  trailing: IconButton(
                    tooltip: 'Kopiuj adres',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: c.webUri.toString()));
                      if (context.mounted) _snack('Skopiowano ${c.webUri}');
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Kto zna temat, dostaje te powiadomienia - podawaj go tylko domownikom.',
                    style: t.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: FilledButton.icon(
                    key: const Key('notifySubscribe'),
                    onPressed: () => _subscribe(c),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Subskrybuj w ntfy'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: OutlinedButton.icon(
                    key: const Key('notifyTest'),
                    onPressed: _busy || !c.enabled
                        ? null
                        : () async {
                            if (await _set(const NotifySet(test: true)) && mounted) {
                              _snack('Wysłano próbne powiadomienie.');
                            }
                          },
                    icon: const Icon(Icons.send_outlined),
                    label: Text(c.enabled ? 'Wyślij próbne' : 'Wyślij próbne (włącz powiadomienia)'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'W aplikacji ntfy włącz dla tego tematu priorytet „pilne”, żeby alarm dzwonił także w trybie '
                    'nie przeszkadzać (Android: ustawienia subskrypcji).',
                    style: t.bodySmall,
                  ),
                ),
                const Divider(height: 32),
                ListTile(
                  key: const Key('notifyNewTopic'),
                  leading: const Icon(Icons.autorenew),
                  title: const Text('Nowy temat'),
                  subtitle: const Text('Gdy temat trafił do kogoś niepowołanego'),
                  enabled: !_busy,
                  onTap: _newTopic,
                ),
                ListTile(
                  key: const Key('notifyServer'),
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Serwer i token'),
                  subtitle: Text(
                    '${c.customServer ? c.server : 'ntfy.sh (domyślny)'}'
                    '${c.tokenSet ? ' · token zapisany' : ''}',
                  ),
                  enabled: !_busy,
                  onTap: () => _server(c),
                ),
              ],
            ),
    );
  }
}

/// Własny serwer ntfy i token dostępu: `''` serwera = domyślny, `''` tokenu = usuń, null tokenu = bez zmian.
class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.config});

  final NotifyConfig config;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _server = TextEditingController(text: widget.config.customServer ? widget.config.server : '');
  final _token = TextEditingController();
  bool _removeToken = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _token.dispose();
    super.dispose();
  }

  void _ok() {
    final server = _server.text.trim();
    if (server.isNotEmpty && !server.startsWith('https://')) {
      setState(() => _error = 'Adres serwera musi zaczynać się od https://');
      return;
    }
    if (_token.text.length > 128) {
      setState(() => _error = 'Token może mieć najwyżej 128 znaków.');
      return;
    }
    final token = _removeToken ? '' : (_token.text.isEmpty ? null : _token.text);
    Navigator.pop(context, (server, token));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Serwer ntfy'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('ntfyServer'),
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Adres (puste = ntfy.sh)',
              hintText: 'https://ntfy.example.pl',
            ),
          ),
          TextField(
            key: const Key('ntfyToken'),
            controller: _token,
            obscureText: true,
            autocorrect: false,
            enabled: !_removeToken,
            decoration: InputDecoration(
              labelText: widget.config.tokenSet ? 'Nowy token (puste = bez zmian)' : 'Token dostępu (opcjonalnie)',
            ),
          ),
          if (widget.config.tokenSet)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Usuń zapisany token'),
              value: _removeToken,
              onChanged: (v) => setState(() => _removeToken = v ?? false),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
      FilledButton(key: const Key('ntfySave'), onPressed: _ok, child: const Text('Zapisz')),
    ],
  );
}
