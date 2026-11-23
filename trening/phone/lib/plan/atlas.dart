/// Atlas ćwiczeń (`assets/plan/atlas.json`): technika i rysunki.
/// Plik generuje `tool/atlas_do_json.dart` z `cwiczenia/atlas_cwiczen.md`.
library;

import 'json.dart';

const atlasFormat = 'trening-atlas/1';

/// Rodzaje sekcji opisu, w kolejności, w jakiej atlas zwykle je podaje.
const rodzajeSekcji = {
  'poCo', 'pozycja', 'ruch', 'gdzieCzujesz', 'bledy', 'latwiej', 'trudniej', //
  'przerwijJesli', 'kiedy', 'inne',
};

class Rysunek {
  Rysunek({required this.plik, required this.opis, this.podpis, this.uwaga});

  /// Ścieżka względem `assets/plan/`, np. `img/bird_dog.jpg`.
  final String plik;
  final String opis;

  /// Podpis wariantu, np. „Wersja na kolanach (start)”.
  final String? podpis;

  /// Gdy rysunek odbiega od opisu: obowiązuje opis, a to zdanie pokazujemy pod rysunkiem.
  final String? uwaga;

  String get asset => 'assets/plan/$plik';
}

class SekcjaAtlasu {
  SekcjaAtlasu({
    required this.rodzaj,
    required this.tytul,
    this.tekst,
    this.punkty = const [],
    this.numerowane = false,
  });

  final String rodzaj;
  final String tytul;
  final String? tekst;
  final List<String> punkty;
  final bool numerowane;
}

class AtlasCwiczenie {
  AtlasCwiczenie({
    required this.id,
    required this.nazwa,
    required this.grupa,
    required this.rysunki,
    required this.sekcje,
  });

  final String id;
  final String nazwa;
  final String? grupa;

  /// Klucz wariantu → rysunek. Jeden rysunek ma klucz pusty.
  final Map<String, Rysunek> rysunki;
  final List<SekcjaAtlasu> sekcje;

  Rysunek? rysunek(String wariant) => rysunki[wariant] ?? (rysunki.length == 1 ? rysunki.values.first : null);

  Iterable<SekcjaAtlasu> rodzaju(String rodzaj) => sekcje.where((s) => s.rodzaj == rodzaj);
}

class Atlas {
  Atlas({required this.zasadyWspolne, required this.cwiczenia});

  final List<String> zasadyWspolne;
  final Map<String, AtlasCwiczenie> cwiczenia;

  factory Atlas.zJson(Object? json) {
    final o = Odczyt(json, 'atlas', dozwolone: {'format', 'zrodlo', 'zasadyWspolne', 'cwiczenia'});
    if (o.tekst('format') != atlasFormat) {
      throw BladPlanu(o.p('format'), 'oczekiwano $atlasFormat');
    }
    final cw = <String, AtlasCwiczenie>{};
    o.obiekt('cwiczenia').forEach((id, v) {
      final c = Odczyt(v, 'atlas.$id', dozwolone: {'nazwa', 'grupa', 'rysunki', 'sekcje'});
      final rysunki = <String, Rysunek>{};
      c.obiekt('rysunki').forEach((klucz, r) {
        final rr = Odczyt(r, c.p('rysunki.$klucz'), dozwolone: {'plik', 'opis', 'podpis', 'uwaga'});
        rysunki[klucz] = Rysunek(
          plik: rr.tekst('plik'),
          opis: rr.tekst('opis'),
          podpis: rr.tekstOpcja('podpis'),
          uwaga: rr.tekstOpcja('uwaga'),
        );
      });
      final sekcje = <SekcjaAtlasu>[];
      final lista = c.lista('sekcje', wymagane: true);
      for (var i = 0; i < lista.length; i++) {
        final s = Odczyt(lista[i], c.p('sekcje[$i]'),
            dozwolone: {'rodzaj', 'tytul', 'tekst', 'punkty', 'numerowane'});
        final rodzaj = s.tekst('rodzaj');
        if (!rodzajeSekcji.contains(rodzaj)) throw BladPlanu(s.p('rodzaj'), 'nieznany rodzaj $rodzaj');
        sekcje.add(SekcjaAtlasu(
          rodzaj: rodzaj,
          tytul: s.m['tytul'] as String? ?? '',
          tekst: s.tekstOpcja('tekst'),
          punkty: s.teksty('punkty'),
          numerowane: s.flaga('numerowane'),
        ));
      }
      cw[id] = AtlasCwiczenie(
        id: id,
        nazwa: c.tekst('nazwa'),
        grupa: c.tekstOpcja('grupa'),
        rysunki: rysunki,
        sekcje: sekcje,
      );
    });
    return Atlas(zasadyWspolne: o.teksty('zasadyWspolne'), cwiczenia: cw);
  }
}
