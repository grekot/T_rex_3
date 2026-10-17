import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as ink;

/// Pisanie palcem: każdy produkt piszesz osobno, aplikacja rozpoznaje go na bieżąco
/// (ML Kit Digital Ink, model polski, działa offline po jednorazowym pobraniu).
/// Zwraca listę rozpoznanych produktów.
class HandwritingScreen extends StatefulWidget {
  const HandwritingScreen({super.key});

  @override
  State<HandwritingScreen> createState() => _HandwritingScreenState();
}

enum _ModelState { checking, downloading, ready, failed }

class _HandwritingScreenState extends State<HandwritingScreen> {
  static const _language = 'pl';

  final _recognizer = ink.DigitalInkRecognizer(languageCode: _language);
  final _modelManager = ink.DigitalInkRecognizerModelManager();
  final _ink = ink.Ink();
  final List<List<Offset>> _strokes = [];
  final List<String> _collected = [];
  List<String> _candidates = [];
  int _chosen = 0;
  Size _area = Size.zero;
  Timer? _debounce;
  _ModelState _model = _ModelState.checking;

  @override
  void initState() {
    super.initState();
    _prepareModel();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recognizer.close();
    super.dispose();
  }

  Future<void> _prepareModel() async {
    try {
      if (await _modelManager.isModelDownloaded(_language)) {
        setState(() => _model = _ModelState.ready);
        return;
      }
      setState(() => _model = _ModelState.downloading);
      // Jednorazowo ok. 20 MB; pozwalamy też na danych komórkowych
      final ok = await _modelManager.downloadModel(_language, isWifiRequired: false);
      if (mounted) setState(() => _model = ok ? _ModelState.ready : _ModelState.failed);
    } catch (_) {
      if (mounted) setState(() => _model = _ModelState.failed);
    }
  }

  void _start(Offset p) {
    _debounce?.cancel();
    final t = DateTime.now().millisecondsSinceEpoch;
    setState(() => _strokes.add([p]));
    _ink.strokes.add(ink.Stroke()..points.add(ink.StrokePoint(x: p.dx, y: p.dy, t: t)));
  }

  void _move(Offset p) {
    if (_strokes.isEmpty) return;
    final t = DateTime.now().millisecondsSinceEpoch;
    setState(() => _strokes.last.add(p));
    _ink.strokes.last.points.add(ink.StrokePoint(x: p.dx, y: p.dy, t: t));
  }

  // Po każdej kresce (z małym opóźnieniem) pokazujemy, co rozpoznano
  void _end() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _recognize);
  }

  Future<void> _recognize() async {
    if (_ink.strokes.isEmpty || _model != _ModelState.ready) return;
    try {
      final result = await _recognizer.recognize(
        _ink,
        context: ink.DigitalInkRecognitionContext(
          writingArea: ink.WritingArea(width: _area.width, height: _area.height),
        ),
      );
      if (!mounted) return;
      setState(() {
        _candidates = result.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toSet().take(4).toList();
        _chosen = 0;
      });
    } catch (_) {}
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _strokes.clear();
      _ink.strokes.clear();
      _candidates = [];
    });
  }

  void _undoStroke() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
      _ink.strokes.removeLast();
      if (_strokes.isEmpty) _candidates = [];
    });
    if (_strokes.isNotEmpty) _end();
  }

  void _accept() {
    if (_candidates.isEmpty) return;
    setState(() => _collected.add(_candidates[_chosen]));
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Napisz palcem'),
        actions: [
          TextButton(
            onPressed: _collected.isEmpty ? null : () => Navigator.pop(context, List<String>.of(_collected)),
            child: Text('Gotowe (${_collected.length})'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zebrane produkty
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _collected.isEmpty
                ? Text('Napisz jeden produkt, sprawdź podpowiedź i stuknij „Dodaj”. Potem następny.',
                    style: theme.textTheme.bodySmall)
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < _collected.length; i++)
                        InputChip(
                          label: Text(_collected[i]),
                          onDeleted: () => setState(() => _collected.removeAt(i)),
                        ),
                    ],
                  ),
          ),
          // Rozpoznane warianty bieżącego słowa
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              height: 40,
              child: switch (_model) {
                _ModelState.checking => const Text('Przygotowanie…'),
                _ModelState.downloading => const Row(children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Expanded(child: Text('Pobieranie modelu pisma (jednorazowo, ok. 20 MB)…')),
                  ]),
                _ModelState.failed => Row(children: [
                    const Expanded(child: Text('Nie udało się pobrać modelu pisma. Sprawdź internet.')),
                    TextButton(onPressed: _prepareModel, child: const Text('Ponów')),
                  ]),
                _ModelState.ready => _candidates.isEmpty
                    ? Text('Pisz w polu poniżej…', style: TextStyle(color: theme.colorScheme.outline))
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < _candidates.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(_candidates[i]),
                                selected: i == _chosen,
                                onSelected: (_) => setState(() => _chosen = i),
                              ),
                            ),
                        ],
                      ),
              },
            ),
          ),
          // Pole do pisania
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _area = Size(constraints.maxWidth, constraints.maxHeight);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: GestureDetector(
                        onPanStart: (d) => _start(d.localPosition),
                        onPanUpdate: (d) => _move(d.localPosition),
                        onPanEnd: (_) => _end(),
                        child: CustomPaint(
                          painter: _InkPainter(_strokes, theme.colorScheme.onSurface),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  IconButton(tooltip: 'Cofnij kreskę', onPressed: _undoStroke, icon: const Icon(Icons.undo)),
                  IconButton(tooltip: 'Wyczyść', onPressed: _clear, icon: const Icon(Icons.delete_outline)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _candidates.isEmpty ? null : _accept,
                    icon: const Icon(Icons.add),
                    label: Text(_candidates.isEmpty ? 'Dodaj' : 'Dodaj „${_candidates[_chosen]}”'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes, this.color);

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 2.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
