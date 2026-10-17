import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../sorting.dart';
import 'parser.dart';

/// Dyktowanie produktów po polsku. Każda wypowiedź zakończona pauzą to kolejny produkt
/// (albo kilka: "mleko, chleb i masło"); po pauzie telefon sam słucha dalej.
/// Zwraca nazwy do dodania albo null, gdy anulowano.
Future<List<String>?> showDictationSheet(BuildContext context, {List<String> hints = const []}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DictationSheet(hints: hints),
  );
}

class _DictationSheet extends StatefulWidget {
  const _DictationSheet({required this.hints});

  /// Podpowiedzi dla rozpoznawania (nazwy produktów; Android 13+)
  final List<String> hints;

  @override
  State<_DictationSheet> createState() => _DictationSheetState();
}

class _DictationSheetState extends State<_DictationSheet> {
  final SpeechToText _stt = SpeechToText();
  final List<String> _items = [];
  String _partial = '';
  String? _error;
  String? _localeId;
  bool _ready = false;
  bool _listening = false;
  bool _closing = false;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closing = true;
    // SpeechToText to jeden obiekt na całą aplikację - odpinamy się od niego
    _stt.errorListener = null;
    _stt.statusListener = null;
    _stt.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    // initialize() ustawia słuchaczy tylko za pierwszym razem, więc podpinamy ich też ręcznie
    _stt.errorListener = _onError;
    _stt.statusListener = _onStatus;
    final ok = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Rozpoznawanie mowy jest niedostępne. Zezwól Zakupom na mikrofon '
          '(Ustawienia → Aplikacje → Zakupy → Uprawnienia) i sprawdź, czy jest aplikacja Google.');
      return;
    }
    final locales = await _stt.locales();
    if (!mounted) return;
    _localeId = locales.map((l) => l.localeId).where((id) => id.toLowerCase().startsWith('pl')).firstOrNull ?? 'pl_PL';
    _ready = true;
    _listen();
  }

  Future<void> _listen() async {
    if (!mounted || _closing || !_ready || _stt.isListening) return;
    setState(() {
      _error = null;
      _partial = '';
    });
    await _stt.listen(
      onResult: _onResult,
      onSoundLevelChange: (level) {
        if (mounted) setState(() => _level = level);
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
        contextualPhrases: widget.hints.take(100).toList(),
      ),
    );
  }

  void _addSpoken(String text) {
    for (final name in splitSpoken(text)) {
      if (!_items.any((i) => normalizeName(i) == normalizeName(name))) _items.add(name);
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    if (!result.finalResult) {
      setState(() => _partial = result.recognizedWords);
      return;
    }
    setState(() {
      _addSpoken(result.recognizedWords);
      _partial = '';
    });
    // Po zakończonej wypowiedzi słuchamy dalej - kolejny produkt
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_closing && _error == null) _listen();
    });
  }

  void _onStatus(String status) {
    if (!mounted) return;
    setState(() {
      _listening = status == SpeechToText.listeningStatus;
      if (!_listening) _level = 0;
    });
  }

  void _onError(SpeechRecognitionError error) {
    if (!mounted) return;
    final String? message = switch (error.errorMsg) {
      // Cisza - po prostu przestajemy słuchać, mikrofon można włączyć ponownie
      'error_no_match' || 'error_speech_timeout' => null,
      'error_network' || 'error_network_timeout' || 'error_server' || 'error_server_disconnected' =>
        'Brak internetu. Rozpoznawanie mowy go potrzebuje, chyba że masz pobrany polski '
            'pakiet offline (Ustawienia → Google → Rozpoznawanie mowy).',
      'error_permission' || 'error_insufficient_permissions' =>
        'Brak uprawnienia do mikrofonu (Ustawienia → Aplikacje → Zakupy → Uprawnienia).',
      'error_language_not_supported' || 'error_language_unavailable' =>
        'Telefon nie rozpoznaje mowy po polsku. Dodaj polski w ustawieniach rozpoznawania mowy Google.',
      'error_busy' || 'error_recognizer_busy' => 'Mikrofon jest zajęty – spróbuj za chwilę.',
      _ => 'Błąd rozpoznawania mowy (${error.errorMsg}).',
    };
    setState(() {
      _error = message;
      _listening = false;
      _level = 0;
    });
  }

  void _toggle() {
    if (_listening) {
      _stt.stop();
    } else {
      _listen();
    }
  }

  void _finish() {
    _closing = true;
    // Ostatnia wypowiedź mogła jeszcze nie zostać zatwierdzona
    if (_partial.isNotEmpty) _addSpoken(_partial);
    _stt.stop();
    Navigator.pop(context, List<String>.of(_items));
  }

  String get _status {
    if (_error != null) return _error!;
    if (!_ready) return 'Uruchamiam mikrofon…';
    if (_listening) return _partial.isEmpty ? 'Słucham…' : _partial;
    return _items.isEmpty ? 'Stuknij mikrofon i mów' : 'Stuknij mikrofon, żeby dodać więcej';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ring = 72 + _level.clamp(0.0, 10.0) * 3;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Dyktuj produkty', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Mów nazwy z krótką przerwą albo jednym ciągiem: „mleko, chleb i masło”.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 104,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _listening ? ring : 72,
                  height: _listening ? ring : 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening ? theme.colorScheme.primaryContainer : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: IconButton.filled(
                    iconSize: 36,
                    padding: const EdgeInsets.all(16),
                    tooltip: _listening ? 'Zatrzymaj' : 'Mów',
                    onPressed: _ready ? _toggle : null,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                  ),
                ),
              ),
            ),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: _error != null
                  ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)
                  : theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            if (_items.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final name in _items)
                        InputChip(
                          label: Text(name),
                          onDeleted: () => setState(() => _items.remove(name)),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _items.isEmpty && _partial.isEmpty ? null : _finish,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(_items.isEmpty ? 'Dodaj' : 'Dodaj (${_items.length})'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
