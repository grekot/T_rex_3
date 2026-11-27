/// Drobne ustawienia zapamiętywane w przeglądarce (localStorage), np. ostatnio oglądany region.
/// W telefonie nic nie robi: tam pamięta [Magazyn] (plik aktywny.txt).
library;

export 'pamiec_brak.dart' if (dart.library.js_interop) 'pamiec_www.dart';
