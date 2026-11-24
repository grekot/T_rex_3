/// To, czego aplikacja potrzebuje od Androida, przez kanał
/// `pl.grekot.trening/urzadzenie` (MainActivity.kt), bez wtyczek: dźwięk, wibracja,
/// „ekran nie gaśnie”, prywatny katalog, przypomnienia, ustawienia systemu, 112.
/// Błędy kanału są ciche: brak dźwięku nie może przerwać treningu (i testów).
library;

import 'package:flutter/services.dart';

import 'przypomnienia/harmonogram.dart';

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

  /// Zastępuje wszystkie zaplanowane przypomnienia nową listą (alarmy przetrwają restart telefonu).
  Future<void> zaplanujPrzypomnienia(List<Przypomnienie> lista) =>
      _wywolaj<void>('zaplanujPrzypomnienia', [for (final p in lista) p.toJson()]);

  /// Jedno przypomnienie poza listą (nie znika przy jej odświeżeniu).
  Future<void> przypomnienieTestowe(Przypomnienie p) => _wywolaj<void>('przypomnienieTestowe', p.toJson());

  Future<bool> powiadomieniaWlaczone() async => await _wywolaj<bool>('powiadomieniaWlaczone') ?? false;

  /// Systemowe pytanie o zgodę na powiadomienia (Android 13+). Zwraca, czy są włączone.
  Future<bool> poprosOPowiadomienia() async => await _wywolaj<bool>('poprosOPowiadomienia') ?? false;

  Future<void> ustawieniaPowiadomien() => _wywolaj<void>('ustawieniaPowiadomien');

  Future<void> ustawieniaAplikacji() => _wywolaj<void>('ustawieniaAplikacji');

  /// Czy aplikacja jest zwolniona z oszczędzania baterii („Bez ograniczeń”).
  Future<bool> bateriaBezOgraniczen() async => await _wywolaj<bool>('bateriaBezOgraniczen') ?? false;

  /// Systemowe okno „Zezwolić na działanie w tle?”.
  Future<void> zwolnijZBaterii() => _wywolaj<void>('zwolnijZBaterii');

  /// Otwiera ekran wybierania numeru z wpisanym numerem; nie dzwoni sam.
  Future<void> zadzwon(String numer) => _wywolaj<void>('zadzwon', numer);
}
