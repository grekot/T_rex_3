import 'package:flutter_test/flutter_test.dart';
import 'package:zakupy/import/ai_text.dart';

void main() {
  test('parseAiList: tablica JSON', () {
    expect(parseAiList('["Mleko 2 l", " Chleb ", "", "Masło"]'), ['Mleko 2 l', 'Chleb', 'Masło']);
  });

  test('parseAiList: blok ```json i obiekt z items', () {
    expect(parseAiList('```json\n["Jajka x10"]\n```'), ['Jajka x10']);
    expect(parseAiList('{"items": ["Ser", "Woda"]}'), ['Ser', 'Woda']);
  });

  test('parseAiList: zwykły tekst i puste odpowiedzi', () {
    expect(parseAiList('Mleko\nChleb\r\n\nMasło'), ['Mleko', 'Chleb', 'Masło']);
    expect(parseAiList('[]'), isEmpty);
    expect(parseAiList(''), isEmpty);
    expect(parseAiList(null), isEmpty);
  });

  test('friendlyAiError: typowe błędy', () {
    expect(
      friendlyAiError('Firebase AI Logic API has not been used in project 123 before or it is disabled.'),
      contains('AI Logic → Get started'),
    );
    expect(friendlyAiError('RESOURCE_EXHAUSTED: quota exceeded'), contains('limit'));
    expect(friendlyAiError('SocketException: Failed host lookup'), contains('internetem'));
    expect(friendlyAiError('Requests to this API are blocked. API_KEY_SERVICE_BLOCKED'), contains('Firebase AI Logic API'));
    expect(
      friendlyAiError('Requests to this API firebasevertexai.googleapis.com method x are blocked.'),
      contains('Dane logowania'),
      reason: 'zablokowany klucz, a nie wyłączone API',
    );
    expect(
      friendlyAiError('PERMISSION_DENIED: Firebase App Check token is invalid.'),
      contains('Unenforce'),
    );
    expect(friendlyAiError('coś dziwnego'), 'Błąd rozpoznawania przez AI: coś dziwnego');
  });

  test('chwilowe przeciążenie modelu', () {
    const msg = 'This model is currently experiencing high demand. Spikes in demand are usually temporary. '
        'Please try again later.';
    expect(isTransientAiError(msg), isTrue);
    expect(isTransientAiError('503 UNAVAILABLE'), isTrue);
    expect(isTransientAiError('PERMISSION_DENIED'), isFalse);
    expect(isTransientAiError('quota exceeded'), isFalse);
    expect(friendlyAiError(msg), contains('przeciążony'));
  });

  test('imageMimeType', () {
    expect(imageMimeType('/a/b/IMG_1.JPG'), 'image/jpeg');
    expect(imageMimeType('x.png'), 'image/png');
    expect(imageMimeType('x.webp'), 'image/webp');
    expect(imageMimeType('x.heic'), 'image/heic');
  });
}
