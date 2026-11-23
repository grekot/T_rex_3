/// Dźwięk, wibracja, „ekran nie gaśnie” i prywatny katalog aplikacji
/// przez kanał `pl.grekot.trening/urzadzenie` (MainActivity.kt), bez wtyczek.
/// Błędy kanału są ciche: brak dźwięku nie może przerwać treningu (i testów).
library;

import 'package:flutter/services.dart';

class Urzadzenie {
  const Urzadzenie();

  static const _kanal = MethodChannel('pl.grekot.trening/urzadzenie');

  Future<T?> _wywolaj<T>(String metoda, [Object? argumenty]) async {
    try {
      return await _kanal.invokeMethod<T>(metoda, argumenty);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String?> katalog() => _wywolaj<String>('katalog');

  Future<void> ekranWlaczony(bool wlaczony) => _wywolaj<void>('ekranWlaczony', wlaczony);

  /// `typ`: `krotki`, `wysoki`, `potwierdzenie`.
  Future<void> ton(String typ, {int ms = 150}) => _wywolaj<void>('ton', {'typ': typ, 'ms': ms});

  Future<void> wibracja({int ms = 100}) => _wywolaj<void>('wibracja', {'ms': ms});
}
