import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kanał do Androida (MainActivity.kt): katalog plików, zgoda na lokalizację, ekran.
/// W przeglądarce o lokalizację pyta sama przeglądarka (przy pierwszym użyciu przez mapę).
class Urzadzenie {
  static const _kanal = MethodChannel('pl.grekot.mapychodzone/urzadzenie');

  /// Prywatny katalog aplikacji (filesDir).
  static Future<String> katalog() async => (await _kanal.invokeMethod<String>('katalog'))!;

  static Future<bool> maZgodeLokalizacji() async =>
      !kIsWeb && ((await _kanal.invokeMethod<bool>('maZgodeLokalizacji')) ?? false);

  /// Pokazuje systemowe pytanie o lokalizację (jeśli trzeba). Zwraca, czy jest zgoda.
  static Future<bool> poprosOLokalizacje() async =>
      kIsWeb || ((await _kanal.invokeMethod<bool>('poprosOLokalizacje')) ?? false);

  static Future<void> ekranWlaczony(bool wlaczony) async {
    if (!kIsWeb) await _kanal.invokeMethod<void>('ekranWlaczony', wlaczony);
  }
}
