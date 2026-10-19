// Klucz Gemini (Google AI Studio) tylko w zaszyfrowanym magazynie Androida (Keystore),
// nigdy w plikach ani w APK - APK leży publicznie w wydaniach na GitHubie.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyStore {
  KeyStore({FlutterSecureStorage? storage}) : _s = storage ?? const FlutterSecureStorage();

  static const _kGemini = 'gemini_api_key';

  final FlutterSecureStorage _s;

  Future<String> gemini() async => (await _s.read(key: _kGemini)) ?? '';

  Future<void> setGemini(String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      await _s.delete(key: _kGemini);
    } else {
      await _s.write(key: _kGemini, value: v);
    }
  }
}
