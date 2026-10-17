import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import 'ai_text.dart';

class AiRecognitionException implements Exception {
  AiRecognitionException(this.message);

  /// Komunikat dla użytkownika (po polsku)
  final String message;

  @override
  String toString() => message;
}

/// Zdjęcie listy -> produkty, przez Gemini (Firebase AI Logic, Gemini Developer API).
/// Klucz API nie jest w aplikacji - obsługuje go Firebase na podstawie konfiguracji projektu.
/// Przy chwilowym przeciążeniu: ponowienie, a potem lżejszy model zapasowy.
Future<List<String>> recognizeWithGemini(Uint8List bytes, String mimeType) async {
  final attempts = [geminiModel, geminiModel, geminiFallbackModel];
  String lastError = '';
  for (var i = 0; i < attempts.length; i++) {
    if (i > 0) await Future<void>.delayed(Duration(milliseconds: 1200 * i));
    try {
      return await _ask(attempts[i], bytes, mimeType);
    } on FirebaseAIException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = e.toString();
    }
    if (!isTransientAiError(lastError)) break;
  }
  throw AiRecognitionException(friendlyAiError(lastError));
}

Future<List<String>> _ask(String modelName, Uint8List bytes, String mimeType) async {
  final model = FirebaseAI.googleAI().generativeModel(
    model: modelName,
    generationConfig: GenerationConfig(
      temperature: 0,
      responseMimeType: 'application/json',
      responseSchema: Schema.array(items: Schema.string()),
    ),
  );
  final response = await model
      .generateContent([
        Content.multi([TextPart(aiPrompt), InlineDataPart(mimeType, bytes)]),
      ])
      .timeout(const Duration(seconds: 60));
  return parseAiList(response.text);
}
