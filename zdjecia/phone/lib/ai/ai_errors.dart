// Błędy zapytań do AI z komunikatami po polsku i ponawianie przejściowych błędów
// (jak w aplikacji EscapeRoom).
import 'dart:convert';

enum AiErrorKind { noApiKey, unauthorized, rateLimited, refusal, truncated, badJson, network, timeout, server, badRequest, unknown }

class AiException implements Exception {
  AiException(this.kind, this.message, {this.statusCode, this.body});

  final AiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? body;

  bool get isRetryable =>
      kind == AiErrorKind.rateLimited ||
      kind == AiErrorKind.server ||
      kind == AiErrorKind.network ||
      kind == AiErrorKind.timeout;

  String get userMessage => switch (kind) {
        AiErrorKind.noApiKey => 'Brak klucza Gemini. Wpisz go w ustawieniach AI.',
        AiErrorKind.unauthorized => 'Klucz Gemini został odrzucony. Sprawdź go w ustawieniach AI.',
        AiErrorKind.rateLimited => 'Wyczerpany limit zapytań klucza. Reszta zdjęć zostanie oceniona przy następnym odświeżeniu.',
        AiErrorKind.refusal => 'Model odmówił oceny tej porcji zdjęć.',
        AiErrorKind.truncated => 'Odpowiedź modelu została ucięta.',
        AiErrorKind.badJson => 'Model zwrócił niepoprawne dane.',
        AiErrorKind.network => 'Brak połączenia z internetem.',
        AiErrorKind.timeout => 'Serwer AI nie odpowiedział na czas.',
        AiErrorKind.server => 'Serwer AI zgłosił błąd. Spróbuj za chwilę.',
        AiErrorKind.badRequest => 'Serwer AI odrzucił zapytanie: $message',
        AiErrorKind.unknown => 'Nieoczekiwany błąd AI: $message',
      };

  @override
  String toString() => 'AiException(${kind.name}${statusCode != null ? ' $statusCode' : ''}): $message';
}

/// Ponawia przejściowe błędy z rosnącą przerwą (limit darmowego klucza zwykle mija po kilkunastu sekundach).
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int attempts = 4,
  Duration firstDelay = const Duration(seconds: 5),
  Future<void> Function(Duration) wait = Future<void>.delayed,
}) async {
  var delay = firstDelay;
  for (var i = 1;; i++) {
    try {
      return await fn();
    } on AiException catch (e) {
      if (!e.isRetryable || i >= attempts) rethrow;
      await wait(delay);
      delay *= 2;
    }
  }
}

/// Obiekt JSON z odpowiedzi modelu (także gdy owinął go w ```json).
Map<String, dynamic> parseJsonObject(String text) {
  var t = text.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
  final m = fence.firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  try {
    final v = jsonDecode(t);
    if (v is Map) return v.cast<String, dynamic>();
  } on FormatException {
    // niżej szukamy obiektu w tekście
  }
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final v = jsonDecode(t.substring(start, end + 1));
      if (v is Map) return v.cast<String, dynamic>();
    } on FormatException catch (e) {
      throw AiException(AiErrorKind.badJson, 'Niepoprawny JSON: ${e.message}', body: text);
    }
  }
  throw AiException(AiErrorKind.badJson, 'Brak obiektu JSON w odpowiedzi.', body: text);
}
