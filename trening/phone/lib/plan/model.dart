/// Plan treningowy jako dane (`assets/plan/plan.json`): ćwiczenia z dawkami,
/// sesje, etapy z harmonogramem i kryteriami przejścia, teksty bezpieczeństwa.
/// Technika i rysunki są w atlasie (`atlas.dart`); identyfikator ćwiczenia to
/// kotwica atlasu, a wariant rysunku idzie po ukośniku: `deska-boczna/kolana`.
library;

import 'json.dart';

export 'json.dart' show BladPlanu, Zakres;

const planFormat = 'trening-plan/1';

/// Flagi, którymi plan włącza i wyłącza ćwiczenia (`tylkoGdy`, `pominGdy`).
/// Liczy je `silnik/flagi.dart`; plan nie może używać innych nazw.
const znaneFlagi = {
  'testKierunkowyZrobiony', // test kierunkowy ma wynik
  'wyprostNieSzkodzi', // test zrobiony i nie wypadł „gorzej”
  'wyprostPomaga', // test wypadł „lepiej”
  'lezenieNaBrzuchuOk', // jak wyprostNieSzkodzi (Y/T leżąc, pozycja do spania)
  'objawyUdoLubNizej', // w ostatnich 7 dniach ból schodził na udo lub niżej
  'zasiegSchodziNizej', // dziś ból schodzi niżej niż w poprzednich 7 dniach
  'slizgiOdFizjo', // fizjoterapeuta zalecił ślizgi nerwu (ustawienie)
};

/// Metryki, z których aplikacja sama sprawdza kryteria przejścia.
const znaneMetryki = {'bolRano', 'dniZasiegPosladekLubNizej', 'dniBezCzerwonejIZasieguBrak'};

/// Dni tygodnia w harmonogramie → DateTime.weekday.
const dniTygodnia = {'pn': 1, 'wt': 2, 'sr': 3, 'czw': 4, 'pt': 5, 'sob': 6, 'nd': 7};

// ---------------------------------------------------------------- ćwiczenia

class CwiczeniePlanu {
  CwiczeniePlanu({
    required this.id,
    required this.nazwa,
    this.jak,
    this.wskazowki = const [],
    this.naStrone = false,
    this.sprzet = const [],
    this.tylkoGdy = const [],
    this.pominGdy = const [],
    this.ostrzezenie,
    this.uwaga,
  });

  final String id;
  final String nazwa;

  /// „Jak wykonać” z tabeli planu.
  final String? jak;
  final List<String> wskazowki;
  final bool naStrone;
  final List<String> sprzet;
  /// Ćwiczenie jest w sesji tylko wtedy, gdy spełniona jest **którakolwiek** z tych flag.
  final List<String> tylkoGdy;

  /// Ćwiczenie wypada z sesji, gdy spełniona jest **którakolwiek** z tych flag.
  final List<String> pominGdy;
  final String? ostrzezenie;

  /// Uwaga z planu przy ćwiczeniu, np. kiedy je pominąć.
  final String? uwaga;

  /// Kotwica w atlasie: część identyfikatora przed ukośnikiem.
  String get atlasId => id.split('/').first;

  /// Wariant rysunku: część po ukośniku (pusta, gdy brak).
  String get wariant => id.contains('/') ? id.substring(id.indexOf('/') + 1) : '';

  static CwiczeniePlanu zJson(String id, Object? json) {
    final o = Odczyt(json, 'cwiczenia.$id', dozwolone: {
      'nazwa', 'jak', 'wskazowki', 'naStrone', 'sprzet', 'tylkoGdy', 'pominGdy', 'ostrzezenie', 'uwaga', //
    });
    return CwiczeniePlanu(
      id: id,
      nazwa: o.tekst('nazwa'),
      jak: o.tekstOpcja('jak'),
      wskazowki: o.teksty('wskazowki'),
      naStrone: o.flaga('naStrone'),
      sprzet: o.teksty('sprzet'),
      tylkoGdy: o.teksty('tylkoGdy'),
      pominGdy: o.teksty('pominGdy'),
      ostrzezenie: o.tekstOpcja('ostrzezenie'),
      uwaga: o.tekstOpcja('uwaga'),
    );
  }
}

// ---------------------------------------------------------------- dawki

/// Dawka kroku. Każdy typ ma swój widok w prowadzeniu treningu.
sealed class Dawka {
  const Dawka({required this.naStrone});

  final bool naStrone;

  static Dawka zJson(Object? json, String sciezka) {
    final typ = Odczyt(json, sciezka).m['typ'];
    switch (typ) {
      case 'powtorzenia':
        final o = Odczyt(json, sciezka,
            dozwolone: {'typ', 'serie', 'ile', 'naStrone', 'naZmiane', 'pauzaGoraS', 'trzymanieS', 'przerwaS'});
        final naZmiane = o.flaga('naZmiane');
        if (naZmiane && !o.flaga('naStrone')) throw BladPlanu(o.p('naZmiane'), 'naZmiane wymaga naStrone');
        return Powtorzenia(
          serie: o.zakresOpcja('serie') ?? const Zakres.jeden(1),
          ile: o.zakres('ile'),
          naStrone: o.flaga('naStrone'),
          naZmiane: naZmiane,
          pauzaGoraS: o.zakresOpcja('pauzaGoraS'),
          trzymanieS: o.zakresOpcja('trzymanieS'),
          przerwaS: o.zakresOpcja('przerwaS'),
        );
      case 'piramida':
        final o = Odczyt(json, sciezka, dozwolone: {'typ', 'serie', 'trzymanieS', 'przerwaS', 'naStrone'});
        final serie = o.lista('serie', wymagane: true);
        if (serie.isEmpty || serie.any((e) => e is! int || e < 1)) {
          throw BladPlanu(o.p('serie'), 'oczekiwano listy liczb powtórzeń, np. [5, 3, 1]');
        }
        return Piramida(
          serie: serie.cast<int>(),
          trzymanieS: o.zakres('trzymanieS'),
          przerwaS: o.zakresOpcja('przerwaS'),
          naStrone: o.flaga('naStrone'),
        );
      case 'trzymanie':
        final o = Odczyt(json, sciezka, dozwolone: {'typ', 'serie', 's', 'naStrone', 'przerwaS'});
        return Trzymanie(
          serie: o.zakresOpcja('serie') ?? const Zakres.jeden(1),
          s: o.zakres('s'),
          naStrone: o.flaga('naStrone'),
          przerwaS: o.zakresOpcja('przerwaS'),
        );
      case 'oddechy':
        final o = Odczyt(json, sciezka, dozwolone: {'typ', 'ile', 'wdechS', 'wydechS'});
        return Oddechy(ile: o.zakres('ile'), wdechS: o.zakres('wdechS'), wydechS: o.zakres('wydechS'));
      case 'pozycje':
        final o = Odczyt(json, sciezka, dozwolone: {'typ', 'etapy'});
        final etapy = o.lista('etapy', wymagane: true);
        if (etapy.isEmpty) throw BladPlanu(o.p('etapy'), 'pusta lista');
        return Pozycje(etapy: [
          for (var i = 0; i < etapy.length; i++) EtapPozycji.zJson(etapy[i], o.p('etapy[$i]')),
        ]);
      default:
        throw BladPlanu('$sciezka.typ', 'nieznany typ dawki: $typ');
    }
  }
}

/// Powtórzenia w seriach, np. mostek 2 × 10 z 2 s pauzy u góry,
/// bird dog 2 × 6 na stronę z trzymaniem 8 s.
class Powtorzenia extends Dawka {
  const Powtorzenia({
    required this.serie,
    required this.ile,
    super.naStrone = false,
    this.naZmiane = false,
    this.pauzaGoraS,
    this.trzymanieS,
    this.przerwaS,
  });

  final Zakres serie;

  /// Powtórzeń w serii (na stronę, gdy [naStrone]).
  final Zakres ile;

  /// Strony na zmianę w jednej serii (bird dog, dead bug), a nie najpierw cała lewa, potem prawa.
  final bool naZmiane;
  final Zakres? pauzaGoraS;

  /// Trzymanie każdego powtórzenia (bird dog 8 s): wtedy prowadzi timer.
  final Zakres? trzymanieS;
  final Zakres? przerwaS;
}

/// Piramida McGilla: 5, potem 3, potem 1 powtórzenie, każde trzymane 8–10 s.
class Piramida extends Dawka {
  const Piramida({required this.serie, required this.trzymanieS, this.przerwaS, super.naStrone = false});

  final List<int> serie;
  final Zakres trzymanieS;
  final Zakres? przerwaS;
}

/// Trzymanie na czas: rozciąganie 2 × 30–45 s, skręt 2–3 × 20–30 s, deska 20–30 s.
class Trzymanie extends Dawka {
  const Trzymanie({required this.serie, required this.s, super.naStrone = false, this.przerwaS});

  final Zakres serie;
  final Zakres s;
  final Zakres? przerwaS;
}

/// Oddechy z tempem wdechu i wydechu (90/90: 6–8 oddechów, wdech 3–4 s, wydech 5–6 s).
class Oddechy extends Dawka {
  const Oddechy({required this.ile, required this.wdechS, required this.wydechS}) : super(naStrone: false);

  final Zakres ile;
  final Zakres wdechS;
  final Zakres wydechS;
}

/// Kolejne pozycje z czasem albo powtórzeniami (sfinks 1–2 min, potem 10 wyprostów).
class Pozycje extends Dawka {
  const Pozycje({required this.etapy}) : super(naStrone: false);

  final List<EtapPozycji> etapy;
}

class EtapPozycji {
  EtapPozycji({required this.nazwa, this.s, this.powt, this.pauzaGoraS});

  final String nazwa;
  final Zakres? s;
  final int? powt;
  final Zakres? pauzaGoraS;

  static EtapPozycji zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka, dozwolone: {'nazwa', 's', 'powt', 'pauzaGoraS'});
    final e = EtapPozycji(
      nazwa: o.tekst('nazwa'),
      s: o.zakresOpcja('s'),
      powt: o.calkowitaOpcja('powt'),
      pauzaGoraS: o.zakresOpcja('pauzaGoraS'),
    );
    if ((e.s == null) == (e.powt == null)) throw BladPlanu(sciezka, 'podaj albo „s”, albo „powt”');
    return e;
  }
}

class Tempo {
  Tempo({required this.dolS, required this.goraS});

  final Zakres dolS;
  final Zakres goraS;
}

// ---------------------------------------------------------------- sesje

class Krok {
  Krok({required this.cwiczenie, required this.dawka, this.tempo, this.uwaga});

  final String cwiczenie;
  final Dawka dawka;
  final Tempo? tempo;
  final String? uwaga;

  static Krok zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka, dozwolone: {'c', 'dawka', 'tempo', 'uwaga'});
    Tempo? tempo;
    if (o.ma('tempo')) {
      final t = Odczyt(o.m['tempo'], o.p('tempo'), dozwolone: {'dolS', 'goraS'});
      tempo = Tempo(dolS: t.zakres('dolS'), goraS: t.zakres('goraS'));
    }
    return Krok(
      cwiczenie: o.tekst('c'),
      dawka: Dawka.zJson(o.m['dawka'], o.p('dawka')),
      tempo: tempo,
      uwaga: o.tekstOpcja('uwaga'),
    );
  }
}

enum TypBloku { kolejno, superseria }

class Blok {
  Blok({this.nazwa, required this.typ, required this.rundy, this.przerwaPoRundzieS, required this.kroki});

  final String? nazwa;
  final TypBloku typ;
  final int rundy;
  final Zakres? przerwaPoRundzieS;
  final List<Krok> kroki;

  static Blok zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka, dozwolone: {'nazwa', 'typ', 'rundy', 'przerwaPoRundzieS', 'kroki'});
    final typ = switch (o.m['typ'] ?? 'kolejno') {
      'kolejno' => TypBloku.kolejno,
      'superseria' => TypBloku.superseria,
      final t => throw BladPlanu(o.p('typ'), 'nieznany typ bloku: $t'),
    };
    final kroki = o.lista('kroki', wymagane: true);
    if (kroki.isEmpty) throw BladPlanu(o.p('kroki'), 'blok bez kroków');
    return Blok(
      nazwa: o.tekstOpcja('nazwa'),
      typ: typ,
      rundy: o.calkowitaOpcja('rundy') ?? 1,
      przerwaPoRundzieS: o.zakresOpcja('przerwaPoRundzieS'),
      kroki: [for (var i = 0; i < kroki.length; i++) Krok.zJson(kroki[i], o.p('kroki[$i]'))],
    );
  }
}

class Sesja {
  Sesja({
    required this.id,
    required this.nazwa,
    this.minuty,
    this.opis,
    this.wkrotce = false,
    this.krotszaWersja = const [],
    required this.bloki,
  });

  final String id;
  final String nazwa;
  final int? minuty;
  final String? opis;

  /// Sesja zapowiedziana: jest w harmonogramie, ale treść dojdzie w kolejnej wersji.
  final bool wkrotce;

  /// Podział na „dwie krótsze wersje” na gorszy dzień: zakresy numerów bloków [od, do].
  final List<(int, int)> krotszaWersja;
  final List<Blok> bloki;

  static Sesja zJson(String id, Object? json) {
    final o = Odczyt(json, 'sesje.$id',
        dozwolone: {'nazwa', 'minuty', 'opis', 'wkrotce', 'krotszaWersja', 'bloki'});
    final wkrotce = o.flaga('wkrotce');
    final bloki = o.lista('bloki');
    if (!wkrotce && bloki.isEmpty) throw BladPlanu(o.p('bloki'), 'sesja bez bloków (albo „wkrotce”: true)');
    final czesci = <(int, int)>[];
    for (final c in o.lista('krotszaWersja')) {
      if (c is List && c.length == 2 && c[0] is int && c[1] is int) {
        czesci.add((c[0] as int, c[1] as int));
      } else {
        throw BladPlanu(o.p('krotszaWersja'), 'oczekiwano par [od, do]');
      }
    }
    return Sesja(
      id: id,
      nazwa: o.tekst('nazwa'),
      minuty: o.calkowitaOpcja('minuty'),
      opis: o.tekstOpcja('opis'),
      wkrotce: wkrotce,
      krotszaWersja: czesci,
      bloki: [for (var i = 0; i < bloki.length; i++) Blok.zJson(bloki[i], o.p('bloki[$i]'))],
    );
  }
}

// ---------------------------------------------------------------- etapy

class Zadanie {
  Zadanie({
    required this.id,
    required this.nazwa,
    this.opis,
    this.tygodnie,
    this.coDni,
    this.odDnia = 1,
    this.opcjonalne = false,
  });

  final String id;
  final String nazwa;
  final String? opis;

  /// Tygodnie etapu, w których zadanie jest aktualne (koniec null = do końca etapu).
  final (int, int?)? tygodnie;

  /// Co ile dni etapu (np. drążek co 3 dni), licząc od dnia [odDnia].
  final int? coDni;
  final int odDnia;
  final bool opcjonalne;

  static Zadanie zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka,
        dozwolone: {'id', 'nazwa', 'opis', 'tygodnie', 'coDni', 'odDnia', 'opcjonalne'});
    return Zadanie(
      id: o.tekst('id'),
      nazwa: o.tekst('nazwa'),
      opis: o.tekstOpcja('opis'),
      tygodnie: o.ma('tygodnie') ? _tygodnie(o.m['tygodnie'], o.p('tygodnie')) : null,
      coDni: o.calkowitaOpcja('coDni'),
      odDnia: o.calkowitaOpcja('odDnia') ?? 1,
      opcjonalne: o.flaga('opcjonalne'),
    );
  }
}

(int, int?) _tygodnie(Object? v, String sciezka) {
  if (v is List && v.length == 2 && v[0] is int && (v[1] == null || v[1] is int)) {
    return (v[0] as int, v[1] as int?);
  }
  throw BladPlanu(sciezka, 'oczekiwano [od, do] albo [od, null]');
}

class CelSpaceru {
  CelSpaceru({required this.tygodnie, required this.tekst, this.minuty, this.kroki});

  final (int, int?) tygodnie;
  final String tekst;
  final Zakres? minuty;
  final Zakres? kroki;

  static CelSpaceru zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka, dozwolone: {'tygodnie', 'tekst', 'minuty', 'kroki'});
    return CelSpaceru(
      tygodnie: _tygodnie(o.m['tygodnie'], o.p('tygodnie')),
      tekst: o.tekst('tekst'),
      minuty: o.zakresOpcja('minuty'),
      kroki: o.zakresOpcja('kroki'),
    );
  }
}

class KryteriumAuto {
  KryteriumAuto({required this.metryka, required this.parametry});

  final String metryka;
  final Map<String, Object?> parametry;
}

class Kryterium {
  Kryterium({required this.id, required this.tekst, this.auto});

  final String id;
  final String tekst;

  /// Gdy jest: aplikacja sprawdza kryterium sama z danych; inaczej potwierdzasz ręcznie.
  final KryteriumAuto? auto;

  static Kryterium zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka, dozwolone: {'id', 'tekst', 'auto'});
    KryteriumAuto? auto;
    if (o.ma('auto')) {
      final a = Odczyt(o.m['auto'], o.p('auto'));
      final metryka = a.tekst('metryka');
      if (!znaneMetryki.contains(metryka)) throw BladPlanu(a.p('metryka'), 'nieznana metryka $metryka');
      auto = KryteriumAuto(metryka: metryka, parametry: Map.of(a.m)..remove('metryka'));
    }
    return Kryterium(id: o.tekst('id'), tekst: o.tekst('tekst'), auto: auto);
  }
}

class Etap {
  Etap({
    required this.nr,
    required this.nazwa,
    required this.cel,
    required this.minDni,
    required this.harmonogram,
    this.sprzet = const [],
    this.zadania = const [],
    this.spacer = const [],
    this.kryteria = const [],
  });

  final int nr;
  final String nazwa;
  final String cel;

  /// Najkrótszy czas etapu; potem przejście tylko po spełnieniu kryteriów.
  final int minDni;

  /// DateTime.weekday (1 = poniedziałek) → identyfikator sesji.
  final Map<int, String> harmonogram;
  final List<String> sprzet;
  final List<Zadanie> zadania;
  final List<CelSpaceru> spacer;

  /// Kryteria przejścia do następnego etapu.
  final List<Kryterium> kryteria;

  static Etap zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka, dozwolone: {
      'nr', 'nazwa', 'cel', 'minDni', 'harmonogram', 'sprzet', 'zadania', 'spacer', 'kryteria', //
    });
    final h = Odczyt(o.m['harmonogram'], o.p('harmonogram'), dozwolone: dniTygodnia.keys.toSet());
    final harmonogram = <int, String>{};
    for (final MapEntry(key: dzien, value: nr) in dniTygodnia.entries) {
      harmonogram[nr] = h.tekst(dzien);
    }
    return Etap(
      nr: o.calkowita('nr'),
      nazwa: o.tekst('nazwa'),
      cel: o.tekst('cel'),
      minDni: o.calkowita('minDni'),
      harmonogram: harmonogram,
      sprzet: o.teksty('sprzet'),
      zadania: [
        for (final (i, z) in o.lista('zadania').indexed) Zadanie.zJson(z, o.p('zadania[$i]')),
      ],
      spacer: [
        for (final (i, s) in o.lista('spacer').indexed) CelSpaceru.zJson(s, o.p('spacer[$i]')),
      ],
      kryteria: [
        for (final (i, k) in o.lista('kryteria').indexed) Kryterium.zJson(k, o.p('kryteria[$i]')),
      ],
    );
  }
}

// ---------------------------------------------------------------- test kierunkowy i teksty

class KrokTestu {
  KrokTestu({required this.typ, required this.nazwa, required this.opis, this.s, this.powt, this.pauzaGoraS});

  /// `ocena` (gdzie i jak mocno boli), `pozycja` (timer), `powtorzenia` (licznik), `marsz` (timer).
  final String typ;
  final String nazwa;
  final String opis;
  final Zakres? s;
  final int? powt;
  final Zakres? pauzaGoraS;

  static KrokTestu zJson(Object? json, String sciezka) {
    final o = Odczyt(json, sciezka, dozwolone: {'typ', 'nazwa', 'opis', 's', 'powt', 'pauzaGoraS'});
    final typ = o.tekst('typ');
    if (!{'ocena', 'pozycja', 'powtorzenia', 'marsz'}.contains(typ)) {
      throw BladPlanu(o.p('typ'), 'nieznany typ kroku testu: $typ');
    }
    return KrokTestu(
      typ: typ,
      nazwa: o.tekst('nazwa'),
      opis: o.tekst('opis'),
      s: o.zakresOpcja('s'),
      powt: o.calkowitaOpcja('powt'),
      pauzaGoraS: o.zakresOpcja('pauzaGoraS'),
    );
  }
}

class WynikTestuOpis {
  WynikTestuOpis({required this.wynik, required this.gdy, required this.znaczenie, required this.coRobisz});

  final String wynik;

  /// Co obserwujesz po teście, np. „Palenie w krzyżu zmalało”.
  final String gdy;
  final String znaczenie;
  final String coRobisz;
}

class TestKierunkowy {
  TestKierunkowy({required this.cel, required this.kiedy, required this.kroki, required this.wyniki, this.wskazowka});

  final String cel;
  final String kiedy;
  final List<KrokTestu> kroki;

  /// `lepiej`, `bezZmian`, `gorzej`.
  final Map<String, WynikTestuOpis> wyniki;
  final String? wskazowka;

  static TestKierunkowy zJson(Object? json) {
    final o = Odczyt(json, 'testKierunkowy', dozwolone: {'cel', 'kiedy', 'kroki', 'wyniki', 'wskazowka'});
    final wyniki = <String, WynikTestuOpis>{};
    final w = Odczyt(o.m['wyniki'], o.p('wyniki'), dozwolone: {'lepiej', 'bezZmian', 'gorzej'});
    for (final k in ['lepiej', 'bezZmian', 'gorzej']) {
      final r = Odczyt(w.m[k], w.p(k), dozwolone: {'gdy', 'znaczenie', 'coRobisz'});
      wyniki[k] = WynikTestuOpis(
        wynik: k,
        gdy: r.tekst('gdy'),
        znaczenie: r.tekst('znaczenie'),
        coRobisz: r.tekst('coRobisz'),
      );
    }
    return TestKierunkowy(
      cel: o.tekst('cel'),
      kiedy: o.tekst('kiedy'),
      kroki: [for (final (i, k) in o.lista('kroki', wymagane: true).indexed) KrokTestu.zJson(k, o.p('kroki[$i]'))],
      wyniki: wyniki,
      wskazowka: o.tekstOpcja('wskazowka'),
    );
  }
}

class StrefaOpis {
  StrefaOpis({required this.strefa, required this.bol, required this.coRobisz});

  final String strefa;
  final String bol;
  final String coRobisz;
}

class TekstyPlanu {
  TekstyPlanu({
    required this.czerwoneFlagi,
    required this.kiedyDoSpecjalisty,
    required this.gdyBolWraca,
    required this.czegoUnikac,
    required this.czegoUnikacTygodnie,
    required this.centralizacja,
    required this.sygnalizacja,
  });

  final List<String> czerwoneFlagi;
  final List<String> kiedyDoSpecjalisty;
  final List<String> gdyBolWraca;
  final List<String> czegoUnikac;
  final Zakres czegoUnikacTygodnie;
  final List<String> centralizacja;

  /// `zielona`, `zolta`, `czerwona` → opis strefy z planu.
  final Map<String, StrefaOpis> sygnalizacja;

  static TekstyPlanu zJson(Object? json) {
    final o = Odczyt(json, 'teksty', dozwolone: {
      'czerwoneFlagi', 'kiedyDoSpecjalisty', 'gdyBolWraca', 'czegoUnikac', 'czegoUnikacTygodnie', //
      'centralizacja', 'sygnalizacja',
    });
    final s = Odczyt(o.m['sygnalizacja'], o.p('sygnalizacja'), dozwolone: {'zielona', 'zolta', 'czerwona'});
    return TekstyPlanu(
      czerwoneFlagi: o.teksty('czerwoneFlagi', wymagane: true),
      kiedyDoSpecjalisty: o.teksty('kiedyDoSpecjalisty', wymagane: true),
      gdyBolWraca: o.teksty('gdyBolWraca', wymagane: true),
      czegoUnikac: o.teksty('czegoUnikac', wymagane: true),
      czegoUnikacTygodnie: o.zakres('czegoUnikacTygodnie'),
      centralizacja: o.teksty('centralizacja', wymagane: true),
      sygnalizacja: {
        for (final k in ['zielona', 'zolta', 'czerwona'])
          k: () {
            final r = Odczyt(s.m[k], s.p(k), dozwolone: {'bol', 'coRobisz'});
            return StrefaOpis(strefa: k, bol: r.tekst('bol'), coRobisz: r.tekst('coRobisz'));
          }(),
      },
    );
  }
}

// ---------------------------------------------------------------- plan

class Plan {
  Plan({
    required this.id,
    required this.wersja,
    required this.tytul,
    required this.zastrzezenie,
    required this.minDniPoCofnieciu,
    required this.cwiczenia,
    required this.sesje,
    required this.etapy,
    required this.testKierunkowy,
    required this.teksty,
  });

  final String id;
  final String wersja;
  final String tytul;
  final String zastrzezenie;

  /// Najkrótszy czas etapu po cofnięciu (🔴), gdy plan nie mówi inaczej.
  final int minDniPoCofnieciu;
  final Map<String, CwiczeniePlanu> cwiczenia;
  final Map<String, Sesja> sesje;
  final List<Etap> etapy;
  final TestKierunkowy testKierunkowy;
  final TekstyPlanu teksty;

  Etap etap(int nr) => etapy.firstWhere((e) => e.nr == nr);

  factory Plan.zJson(Object? json) {
    final o = Odczyt(json, 'plan', dozwolone: {
      'format', 'id', 'wersja', 'tytul', 'zastrzezenie', 'minDniPoCofnieciu', 'cwiczenia', 'sesje', //
      'etapy', 'testKierunkowy', 'teksty',
    });
    if (o.tekst('format') != planFormat) throw BladPlanu(o.p('format'), 'oczekiwano $planFormat');
    final etapy = [
      for (final (i, e) in o.lista('etapy', wymagane: true).indexed) Etap.zJson(e, o.p('etapy[$i]')),
    ];
    for (var i = 0; i < etapy.length; i++) {
      if (etapy[i].nr != i + 1) throw BladPlanu(o.p('etapy[$i].nr'), 'etapy mają być numerowane 1, 2, 3…');
    }
    return Plan(
      id: o.tekst('id'),
      wersja: o.tekst('wersja'),
      tytul: o.tekst('tytul'),
      zastrzezenie: o.tekst('zastrzezenie'),
      minDniPoCofnieciu: o.calkowita('minDniPoCofnieciu'),
      cwiczenia: {
        for (final MapEntry(:key, :value) in o.obiekt('cwiczenia').entries) key: CwiczeniePlanu.zJson(key, value),
      },
      sesje: {for (final MapEntry(:key, :value) in o.obiekt('sesje').entries) key: Sesja.zJson(key, value)},
      etapy: etapy,
      testKierunkowy: TestKierunkowy.zJson(o.m['testKierunkowy']),
      teksty: TekstyPlanu.zJson(o.m['teksty']),
    );
  }
}
