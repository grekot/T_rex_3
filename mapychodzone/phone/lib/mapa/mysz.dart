/// Mysz na mapie w przeglądarce (web/index.html): aplikacja podaje stronie prostokąty swoich
/// paneli i przycisków (oraz czy jest otwarte okno nad całą mapą). Nad nimi kółko przewija panel,
/// a nie przybliża mapy, i prawy przycisk nie przesuwa mapy. W telefonie nic nie robi.
library;

export 'mysz_brak.dart' if (dart.library.js_interop) 'mysz_www.dart';
