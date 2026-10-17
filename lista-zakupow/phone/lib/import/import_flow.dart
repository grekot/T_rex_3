import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../repository.dart';
import 'ai_recognizer.dart';
import 'ai_text.dart';
import 'handwriting_screen.dart';
import 'parser.dart';
import 'products_pl.dart';
import 'review_screen.dart';

enum _Source { camera, gallery, handwriting, paste }

enum _Engine { ai, device }

// Zapamiętany wybór sposobu rozpoznawania zdjęć (na czas działania aplikacji)
_Engine _lastEngine = _Engine.ai;

/// "Dodaj z kartki": wybór źródła -> rozpoznanie -> ekran sprawdzenia -> dodanie do listy.
Future<void> startImport(
  BuildContext context, {
  required ShoppingRepository repo,
  required ShoppingList list,
  required List<ShoppingItem> currentItems,
}) async {
  final source = await showModalBottomSheet<_Source>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _SourceSheet(),
  );
  if (source == null || !context.mounted) return;

  List<String>? lines;
  switch (source) {
    case _Source.camera:
    case _Source.gallery:
      lines = await _recognizePhoto(context, source == _Source.camera ? ImageSource.camera : ImageSource.gallery);
    case _Source.handwriting:
      lines = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(builder: (_) => const HandwritingScreen()),
      );
    case _Source.paste:
      lines = await _askForText(context);
  }
  if (lines == null || !context.mounted) return;

  // Słownik autokorekty: produkty z moich list + typowe produkty
  List<String> history = const [];
  try {
    history = await repo.productHistory();
  } catch (_) {}
  if (!context.mounted) return;
  final candidates = planImport(lines, currentItems, Vocabulary(history, commonProducts));

  final added = await Navigator.push<int>(
    context,
    MaterialPageRoute(
      builder: (_) => ImportReviewScreen(repo: repo, list: list, candidates: candidates, currentItems: currentItems),
    ),
  );
  if (added != null && added > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dodano produktów: $added')));
  }
}

class _SourceSheet extends StatefulWidget {
  const _SourceSheet();

  @override
  State<_SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<_SourceSheet> {
  _Engine _engine = _lastEngine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Dodaj wiele produktów naraz', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<_Engine>(
              segments: const [
                ButtonSegment(value: _Engine.ai, icon: Icon(Icons.auto_awesome), label: Text('AI (Gemini)')),
                ButtonSegment(value: _Engine.device, icon: Icon(Icons.phone_android), label: Text('Na telefonie')),
              ],
              selected: {_engine},
              onSelectionChanged: (s) => setState(() => _engine = _lastEngine = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
            child: Text(
              _engine == _Engine.ai
                  ? 'Zdjęcia czyta Gemini – najlepsze dla trudnego pisma. Wymaga internetu; zdjęcie trafia do Google.'
                  : 'Zdjęcia czyta ML Kit na telefonie – offline, najlepiej przy wyraźnych literach.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Zrób zdjęcie kartki'),
            onTap: () => Navigator.pop(context, _Source.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Wybierz zdjęcie z galerii'),
            onTap: () => Navigator.pop(context, _Source.gallery),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.draw_outlined),
            title: const Text('Napisz palcem'),
            subtitle: const Text('Na telefonie, rozpoznaje każde pismo'),
            onTap: () => Navigator.pop(context, _Source.handwriting),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Wklej tekst'),
            subtitle: const Text('Np. skopiowany z Google Lens albo z wiadomości'),
            onTap: () => Navigator.pop(context, _Source.paste),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Zdjęcie -> linie tekstu, przez AI albo na telefonie (zależnie od wyboru).
/// Gdy AI zawiedzie, proponuje rozpoznanie tego samego zdjęcia na telefonie.
Future<List<String>?> _recognizePhoto(BuildContext context, ImageSource source) async {
  final engine = _lastEngine;
  final XFile? photo;
  try {
    // Gemini nie potrzebuje pełnej rozdzielczości - mniejsze zdjęcie = szybsza wysyłka
    photo = engine == _Engine.ai
        ? await ImagePicker().pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 85)
        : await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nie udało się otworzyć aparatu: $e')));
    }
    return null;
  }
  if (photo == null || !context.mounted) return null;

  if (engine == _Engine.ai) {
    try {
      final bytes = await photo.readAsBytes();
      if (!context.mounted) return null;
      return await _withProgress(context, 'Rozpoznawanie przez AI…', () => recognizeWithGemini(bytes, imageMimeType(photo!.path)));
    } on AiRecognitionException catch (e) {
      if (!context.mounted) return null;
      final fallback = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('AI nie odczytało zdjęcia'),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rozpoznaj na telefonie')),
          ],
        ),
      );
      if (fallback != true || !context.mounted) return null;
    }
  }
  return _recognizeOnDevice(context, photo.path);
}

/// ML Kit na telefonie, bez internetu. Linie w kolejności czytania.
Future<List<String>?> _recognizeOnDevice(BuildContext context, String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    return await _withProgress(context, 'Rozpoznawanie pisma…', () async {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      final lines = <TextLine>[for (final block in result.blocks) ...block.lines];
      // Od góry do dołu (linie w podobnej wysokości - od lewej)
      lines.sort((a, b) {
        final dy = a.boundingBox.center.dy - b.boundingBox.center.dy;
        if (dy.abs() > a.boundingBox.height / 2) return dy.sign.toInt();
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      });
      return lines.map((l) => l.text).toList();
    });
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd rozpoznawania: $e')));
    }
    return null;
  } finally {
    await recognizer.close();
  }
}

/// Okienko "proszę czekać" na czas zadania
Future<T> _withProgress<T>(BuildContext context, String text, Future<T> Function() task) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Wklejanie listy (np. tekst skopiowany z Google Lens)
Future<List<String>?> _askForText(BuildContext context) async {
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return null;
  final controller = TextEditingController(text: clip?.text ?? '');
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Wklej listę'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 6,
        maxLines: 12,
        decoration: const InputDecoration(
          hintText: 'Każdy produkt w osobnej linii albo po przecinku',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Dalej')),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty) return null;
  return [text];
}
