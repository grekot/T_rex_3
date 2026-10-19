// Ocena porcji zdjęć przez Gemini: miniatury → zapytanie → oceny (ponawianie przy limicie klucza).
import 'gemini_client.dart';
import 'ai_errors.dart';
import 'photo_rating.dart';

class PhotoRater {
  PhotoRater({required this.client, required this.preferences}) : hash = prefsHash(preferences);

  final GeminiClient client;
  final String preferences;
  final String hash;

  /// Oceny w kolejności [photos]; null = model pominął zdjęcie
  Future<List<PhotoRating?>> rateBatch(List<RatingInput> photos) async {
    final json = await withRetry(() => client.generateJson(
          system: ratingSystemPrompt,
          parts: ratingParts(photos, preferences),
          schema: ratingSchema,
        ));
    return parseRatings(json, photos.length, hash);
  }
}
