import 'dart:convert';

/// Czyste funkcje dla rozpoznawania przez AI (testowane bez sieci).

/// Model Gemini: stabilny, bez wymogu płatnego planu Firebase, dostępny co najmniej do 05.2027
const geminiModel = 'gemini-3.5-flash';

/// Zapasowy, lżejszy model - gdy główny jest chwilowo przeciążony ("high demand")
const geminiFallbackModel = 'gemini-3.5-flash-lite';

/// Czy błąd jest chwilowy (przeciążenie modelu) - wtedy warto ponowić albo zmienić model
bool isTransientAiError(String message) {
  final m = message.toLowerCase();
  return m.contains('high demand') ||
      m.contains('overloaded') ||
      m.contains('unavailable') ||
      m.contains('503') ||
      m.contains('internal error') ||
      (m.contains('internal') && m.contains('try again'));
}

const aiPrompt = '''Na zdjęciu jest lista zakupów, zwykle napisana odręcznie po polsku.
Odczytaj ją i zwróć wyłącznie produkty, w kolejności z kartki.
Zasady:
- każdy produkt osobno; jeśli w jednej linii jest kilka produktów (np. po przecinku), rozdziel je,
- zachowaj ilości i dopiski, np. "Mleko 2 l", "Jajka x10", "Ser żółty (plastry)",
- popraw oczywiste literówki i dodaj polskie znaki, ale nie zamieniaj produktów na inne,
- pomiń numerację, punktory, pozycje skreślone, nagłówki, daty i podpisy,
- gdy pozycja jest słabo czytelna, podaj najbardziej prawdopodobne odczytanie,
- jeśli na zdjęciu nie ma listy zakupów, zwróć pustą listę.''';

/// Odpowiedź modelu -> lista produktów. Oczekujemy tablicy JSON, ale radzimy sobie też
/// z blokiem ```json ...``` albo zwykłym tekstem linia po linii.
List<String> parseAiList(String? text) {
  if (text == null) return const [];
  var t = text.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
  final m = fence.firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  if (t.isEmpty) return const [];
  try {
    final decoded = jsonDecode(t);
    if (decoded is List) {
      return decoded.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
  } catch (_) {
    // nie JSON - traktujemy jak zwykły tekst
  }
  return t.split(RegExp(r'[\r\n]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// Zrozumiały komunikat zamiast technicznego błędu Firebase / Gemini
String friendlyAiError(String message) {
  final m = message.toLowerCase();
  // App Check: aplikacja z pliku APK (spoza Google Play) nie przejdzie atestacji
  if (m.contains('app check') || m.contains('appcheck') || m.contains('attestation')) {
    return 'Firebase wymaga App Check dla AI. W konsoli Firebase: Security → App Check → APIs → '
        'Firebase AI Logic → Unenforce (na darmowym planie Spark nie grozi to kosztami).';
  }
  // Zablokowany klucz - jego komunikat też zawiera nazwę API AI Logic
  if (m.contains('api_key_service_blocked') || m.contains('api key not valid') || m.contains('are blocked')) {
    return 'Klucz Firebase nie ma dostępu do AI Logic. W Google Cloud → Dane logowania '
        'dopisz „Firebase AI Logic API” do dozwolonych interfejsów klucza Android.';
  }
  if (m.contains('has not been used') ||
      m.contains('is disabled') ||
      m.contains('not enabled') ||
      m.contains('firebasevertexai') ||
      m.contains('firebase ai logic') ||
      m.contains('generativelanguage')) {
    return 'Rozpoznawanie przez AI nie jest jeszcze włączone. W konsoli Firebase: '
        'AI Logic → Get started → Gemini Developer API.';
  }
  if (isTransientAiError(message)) {
    return 'Gemini jest chwilowo przeciążony. Spróbuj za chwilę albo użyj rozpoznawania na telefonie.';
  }
  if (m.contains('quota') || m.contains('resource_exhausted') || m.contains('429') || m.contains('rate')) {
    return 'Wyczerpany limit zapytań do AI. Spróbuj za chwilę albo użyj rozpoznawania na telefonie.';
  }
  if (m.contains('location') && m.contains('not supported')) {
    return 'Gemini nie jest dostępny w tym regionie.';
  }
  if (m.contains('socket') || m.contains('network') || m.contains('failed host lookup') || m.contains('timeout')) {
    return 'Brak połączenia z internetem. Spróbuj ponownie albo użyj rozpoznawania na telefonie.';
  }
  return 'Błąd rozpoznawania przez AI: $message';
}

/// Typ obrazu po rozszerzeniu pliku (Gemini potrzebuje mime type)
String imageMimeType(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  if (p.endsWith('.heic') || p.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}
