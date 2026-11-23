/// Rozpisanie sesji na fazy prowadzenia: przygotowanie do ćwiczenia, serie
/// powtórzeń, trzymania na czas, oddechy i przerwy (między powtórzeniami,
/// stronami, seriami i rundami). Zakresy z planu startują od dolnej granicy.
library;

import '../plan/atlas.dart';
import '../plan/model.dart';
import '../silnik/flagi.dart';

enum Strona { lewa, prawa }

extension NazwaStrony on Strona {
  String get nazwa => this == Strona.lewa ? 'lewa strona' : 'prawa strona';
}

/// Domyślne przerwy, gdy plan ich nie podaje (sekundy).
const przerwaMiedzySeriami = 15;
const przerwaMiedzyStronami = 5;
const przerwaMiedzyPowtorzeniami = 3;
const przerwaZmianaPozycji = 5;
const przerwaPoRundzie = 30;

/// Ćwiczenie w dzisiejszej sesji: dane z planu i atlasu.
class CwiczenieSesji {
  CwiczenieSesji({required this.krok, required this.cwiczenie, required this.atlas, required this.blok});

  final Krok krok;
  final CwiczeniePlanu cwiczenie;
  final AtlasCwiczenie? atlas;
  final int blok;

  String get id => cwiczenie.id;
  Rysunek? get rysunek => atlas?.rysunek(cwiczenie.wariant);

  /// Skrót techniki pod rysunkiem: wskazówki z planu, a gdy ich nie ma, pierwsze kroki „Ruch” z atlasu.
  List<String> get skrot {
    if (cwiczenie.wskazowki.isNotEmpty) return cwiczenie.wskazowki.take(3).toList();
    final ruch = atlas?.rodzaju('ruch').expand((s) => s.punkty).take(3).toList();
    return ruch ?? const [];
  }

  /// „Przerwij, jeśli” z atlasu (gdy ćwiczenie ma tę sekcję).
  String? get przerwijJesli {
    for (final s in atlas?.rodzaju('przerwijJesli') ?? const <SekcjaAtlasu>[]) {
      return s.tekst ?? s.punkty.join(' ');
    }
    return null;
  }
}

sealed class Faza {
  const Faza(this.cwiczenie);

  /// Indeks ćwiczenia w [Rozpiska.cwiczenia].
  final int cwiczenie;
}

/// Ekran „przygotuj się”: rysunek, opis, Start. Daje czas na zajęcie pozycji.
class FazaPrzygotowanie extends Faza {
  const FazaPrzygotowanie(super.cwiczenie);
}

/// Licznik powtórzeń; dalej po „Gotowe”.
class FazaPowtorzenia extends Faza {
  const FazaPowtorzenia(super.cwiczenie,
      {required this.cel, required this.zakres, required this.seria, required this.serii, this.strona,
      this.naZmiane = false, this.pauzaGoraS, this.tempo, this.opis});

  /// Np. „Wyprosty na dłoniach” w ćwiczeniu z kilku pozycji.
  final String? opis;
  final int cel;
  final Zakres zakres;
  final int seria;
  final int serii;
  final Strona? strona;

  /// Strony na zmianę: [cel] liczy powtórzenia obu stron razem.
  final bool naZmiane;
  final Zakres? pauzaGoraS;
  final Tempo? tempo;
}

/// Trzymanie na czas (rozciąganie, deska, powtórzenie z trzymaniem); samo przechodzi dalej.
class FazaTrzymanie extends Faza {
  const FazaTrzymanie(super.cwiczenie,
      {required this.sekundy, required this.zakres, required this.opis, required this.seria, required this.serii,
      this.strona});

  final int sekundy;
  final Zakres zakres;

  /// Np. „Powtórzenie 2/5”, „Sfinks”.
  final String opis;
  final int seria;
  final int serii;
  final Strona? strona;
}

/// Oddechy w tempie wdech/wydech; dalej po „Gotowe”.
class FazaOddechy extends Faza {
  const FazaOddechy(super.cwiczenie, {required this.cel, required this.zakres, required this.wdechS, required this.wydechS});

  final int cel;
  final Zakres zakres;
  final num wdechS;
  final num wydechS;
}

enum PowodPrzerwy { powtorzenie, strona, seria, pozycja, runda }

class FazaPrzerwa extends Faza {
  const FazaPrzerwa(super.cwiczenie, {required this.sekundy, required this.powod});

  final int sekundy;
  final PowodPrzerwy powod;
}

class PominieteCwiczenie {
  PominieteCwiczenie(this.cwiczenie, this.powod);

  final CwiczeniePlanu cwiczenie;
  final String powod;
}

class Rozpiska {
  Rozpiska({required this.sesja, required this.cwiczenia, required this.pominiete, required this.fazy});

  final Sesja sesja;
  final List<CwiczenieSesji> cwiczenia;

  /// Ćwiczenia, które dziś wypadają przez flagi (np. wyprosty przed testem kierunkowym).
  final List<PominieteCwiczenie> pominiete;
  final List<Faza> fazy;
}

String _powodPominiecia(CwiczeniePlanu c, Set<String> flagi) {
  if (c.pominGdy.contains('zasiegSchodziNizej') && flagi.contains('zasiegSchodziNizej')) {
    return 'Ból schodzi dziś niżej niż w ostatnich dniach.';
  }
  if (c.tylkoGdy.contains('wyprostNieSzkodzi')) {
    return flagi.contains('testKierunkowyZrobiony')
        ? 'Test kierunkowy: wyprost na razie Ci nie służy.'
        : 'Najpierw zrób test kierunkowy.';
  }
  return c.uwaga ?? 'Nie dziś.';
}

/// Rozpisuje [sesja] na fazy. [czesc]: numer części „dwóch krótszych wersji” (0 albo 1), null = całość.
Rozpiska rozpisz(Plan plan, Atlas atlas, Sesja sesja, Set<String> flagi, {int? czesc}) {
  var bloki = [for (var i = 0; i < sesja.bloki.length; i++) i];
  if (czesc != null) {
    final (od, do_) = sesja.krotszaWersja[czesc];
    bloki = [for (var i = od; i <= do_; i++) i];
  }

  final cwiczenia = <CwiczenieSesji>[];
  final pominiete = <PominieteCwiczenie>[];
  final fazy = <Faza>[];

  for (final b in bloki) {
    final blok = sesja.bloki[b];
    final indeksy = <int>[];
    for (final krok in blok.kroki) {
      final c = plan.cwiczenia[krok.cwiczenie]!;
      if (!cwiczenieAktywne(c, flagi)) {
        pominiete.add(PominieteCwiczenie(c, _powodPominiecia(c, flagi)));
        continue;
      }
      indeksy.add(cwiczenia.length);
      cwiczenia.add(CwiczenieSesji(krok: krok, cwiczenie: c, atlas: atlas.cwiczenia[c.atlasId], blok: b));
    }
    if (indeksy.isEmpty) continue;
    for (var runda = 1; runda <= blok.rundy; runda++) {
      for (final ci in indeksy) {
        if (runda == 1) fazy.add(FazaPrzygotowanie(ci));
        _rozpiszDawke(fazy, ci, cwiczenia[ci]);
        if (fazy.last is FazaPrzerwa) fazy.removeLast(); // bez przerwy po ostatniej serii
      }
      if (runda < blok.rundy) {
        final s = blok.przerwaPoRundzieS?.min.round() ?? przerwaPoRundzie;
        fazy.add(FazaPrzerwa(indeksy.first, sekundy: s, powod: PowodPrzerwy.runda));
      }
    }
  }
  return Rozpiska(sesja: sesja, cwiczenia: cwiczenia, pominiete: pominiete, fazy: fazy);
}

void _rozpiszDawke(List<Faza> f, int ci, CwiczenieSesji cs) {
  final d = cs.krok.dawka;
  final strony = (d.naStrone || cs.cwiczenie.naStrone) ? Strona.values : const <Strona?>[null];
  int s(Zakres z) => z.min.round();

  switch (d) {
    case Powtorzenia():
      final serii = s(d.serie);
      for (var seria = 1; seria <= serii; seria++) {
        if (d.trzymanieS != null) {
          // każde powtórzenie trzymane na czas (bird dog 8 s); na zmianę: L, P, L, P…
          final kolejnosc = d.naZmiane
              ? [for (var r = 1; r <= s(d.ile); r++) for (final st in strony) (r, st)]
              : [for (final st in strony) for (var r = 1; r <= s(d.ile); r++) (r, st)];
          for (final (i, (r, st)) in kolejnosc.indexed) {
            if (i > 0) {
              final zmiana = !d.naZmiane && st != kolejnosc[i - 1].$2;
              f.add(FazaPrzerwa(ci,
                  sekundy: zmiana ? przerwaMiedzyStronami : przerwaMiedzyPowtorzeniami,
                  powod: zmiana ? PowodPrzerwy.strona : PowodPrzerwy.powtorzenie));
            }
            f.add(FazaTrzymanie(ci,
                sekundy: s(d.trzymanieS!), zakres: d.trzymanieS!, opis: 'Powtórzenie $r/${s(d.ile)}',
                seria: seria, serii: serii, strona: st));
          }
        } else if (d.naZmiane) {
          f.add(FazaPowtorzenia(ci, cel: s(d.ile) * 2, zakres: d.ile, seria: seria, serii: serii, naZmiane: true,
              pauzaGoraS: d.pauzaGoraS));
        } else {
          for (final (i, st) in strony.indexed) {
            if (i > 0) f.add(FazaPrzerwa(ci, sekundy: przerwaMiedzyStronami, powod: PowodPrzerwy.strona));
            f.add(FazaPowtorzenia(ci, cel: s(d.ile), zakres: d.ile, seria: seria, serii: serii, strona: st,
                pauzaGoraS: d.pauzaGoraS, tempo: cs.krok.tempo));
          }
        }
        f.add(FazaPrzerwa(ci, sekundy: d.przerwaS?.min.round() ?? przerwaMiedzySeriami, powod: PowodPrzerwy.seria));
      }
    case Piramida():
      final serii = d.serie.length;
      for (final (i, ile) in d.serie.indexed) {
        for (final (k, st) in strony.indexed) {
          if (k > 0) f.add(FazaPrzerwa(ci, sekundy: przerwaMiedzyStronami, powod: PowodPrzerwy.strona));
          for (var r = 1; r <= ile; r++) {
            if (r > 1) f.add(FazaPrzerwa(ci, sekundy: przerwaMiedzyPowtorzeniami, powod: PowodPrzerwy.powtorzenie));
            f.add(FazaTrzymanie(ci,
                sekundy: s(d.trzymanieS), zakres: d.trzymanieS, opis: 'Powtórzenie $r/$ile',
                seria: i + 1, serii: serii, strona: st));
          }
        }
        f.add(FazaPrzerwa(ci, sekundy: d.przerwaS?.min.round() ?? przerwaMiedzySeriami, powod: PowodPrzerwy.seria));
      }
    case Trzymanie():
      final serii = s(d.serie);
      for (var seria = 1; seria <= serii; seria++) {
        for (final (k, st) in strony.indexed) {
          if (k > 0) f.add(FazaPrzerwa(ci, sekundy: przerwaMiedzyStronami, powod: PowodPrzerwy.strona));
          f.add(FazaTrzymanie(ci, sekundy: s(d.s), zakres: d.s, opis: 'Trzymaj', seria: seria, serii: serii, strona: st));
        }
        f.add(FazaPrzerwa(ci,
            sekundy: d.przerwaS?.min.round() ?? przerwaMiedzyStronami, powod: PowodPrzerwy.seria));
      }
    case Oddechy():
      f.add(FazaOddechy(ci, cel: s(d.ile), zakres: d.ile, wdechS: d.wdechS.max, wydechS: d.wydechS.max));
    case Pozycje():
      for (final (i, e) in d.etapy.indexed) {
        if (i > 0) f.add(FazaPrzerwa(ci, sekundy: przerwaZmianaPozycji, powod: PowodPrzerwy.pozycja));
        if (e.s != null) {
          f.add(FazaTrzymanie(ci, sekundy: s(e.s!), zakres: e.s!, opis: e.nazwa, seria: 1, serii: 1));
        } else {
          f.add(FazaPowtorzenia(ci, cel: e.powt!, zakres: Zakres.jeden(e.powt!), seria: 1, serii: 1,
              pauzaGoraS: e.pauzaGoraS, opis: e.nazwa));
        }
      }
  }
}
