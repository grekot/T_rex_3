import 'package:flutter/services.dart';

/// Kanał do Androida (MainActivity.kt): katalog plików, zgoda na lokalizację, ekran.
class Urzadzenie {
  static const _kanal = MethodChannel('pl.grekot.mapychodzone/urzadzenie');

  /// Prywatny katalog aplikacji (filesDir).
  static Future<String> katalog() async => (await _kanal.invokeMethod<String>('katalog'))!;

  static Future<bool> maZgodeLokalizacji() async =>
      (await _kanal.invokeMethod<bool>('maZgodeLokalizacji')) ?? false;

  /// Pokazuje systemowe pytanie o lokalizację (jeśli trzeba). Zwraca, czy jest zgoda.
  static Future<bool> poprosOLokalizacje() async =>
      (await _kanal.invokeMethod<bool>('poprosOLokalizacje')) ?? false;

  static Future<void> ekranWlaczony(bool wlaczony) =>
      _kanal.invokeMethod<void>('ekranWlaczony', wlaczony);
}
