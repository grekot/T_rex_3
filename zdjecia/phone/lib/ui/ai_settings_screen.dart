// Ustawienia oceny przez AI: klucz Gemini z Google AI Studio (jak w EscapeRoom), model
// i preferencje właściciela dopisywane do polecenia.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/gemini_client.dart';
import '../pool_controller.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, required this.pool});

  final PoolController pool;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _key = TextEditingController();
  final _prefs = TextEditingController();
  late bool _enabled = widget.pool.prefs.aiEnabled;
  late String _model = widget.pool.prefs.aiModel;
  List<String> _models = const [];
  bool _showKey = false;
  bool _checking = false;
  String? _check;

  @override
  void initState() {
    super.initState();
    _prefs.text = widget.pool.prefs.preferences;
    widget.pool.apiKey().then((k) {
      if (!mounted) return;
      _key.text = k;
      if (k.isNotEmpty) _loadModels();
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _prefs.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final models = await widget.pool.aiModels(_key.text);
      if (mounted) setState(() => _models = models);
    } catch (_) {
      // lista jest tylko podpowiedzią - zostaje model domyślny
    }
  }

  Future<void> _testKey() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    final error = await widget.pool.testAi(_key.text, _model);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _check = error ?? 'Klucz i model działają.';
    });
    if (error == null) _loadModels();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _key.text = data!.text!.trim());
  }

  Future<void> _save() async {
    Navigator.pop(context);
    await widget.pool.setAi(enabled: _enabled, key: _key.text, model: _model, preferences: _prefs.text);
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final models = {..._models, _model, defaultGeminiModel}.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Ocena przez AI')),
      body: ListView(
        padding: const EdgeInsets.all(16) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wybieraj zdjęcia z pomocą Gemini'),
            subtitle: const Text('Bez AI zostaje sama punktacja na telefonie.'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Klucz API Gemini (AIza…)',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(tooltip: 'Wklej', icon: const Icon(Icons.content_paste), onPressed: _paste),
                  IconButton(
                    tooltip: _showKey ? 'Ukryj' : 'Pokaż',
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Klucz utworzysz w Google AI Studio: aistudio.google.com/apikey (może być ten sam co w EscapeRoom). '
            'Zostaje tylko na tym telefonie, w zaszyfrowanym magazynie Androida.',
            style: small,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _model,
            decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
            items: [for (final m in models) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (v) => setState(() => _model = v ?? _model),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(onPressed: _checking ? null : _testKey, child: const Text('Sprawdź klucz')),
              const SizedBox(width: 12),
              if (_checking) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              if (_check != null) Expanded(child: Text(_check!)),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _prefs,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Co lubię / czego nie chcę',
              hintText: 'np. dzieci, rodzina, wycieczki, góry i przyroda, pies; '
                  'bez jedzenia, samochodów, zdjęć z pracy i sprzętu',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text('Zmiana preferencji albo modelu = zdjęcia zostaną ocenione od nowa.', style: small),
          const SizedBox(height: 16),
          Text(
            'Do Gemini trafiają miniatury 512 px. Przy kluczu bez włączonych płatności w AI Studio Google może '
            'używać przesłanych treści do ulepszania swoich usług; z płatnościami - nie.',
            style: small,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Zapisz i oceń zdjęcia')),
        ],
      ),
    );
  }
}
