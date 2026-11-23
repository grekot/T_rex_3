import 'package:flutter_test/flutter_test.dart';
import 'package:trening/plan/atlas.dart';

import '../tool/atlas_parser.dart';

const _probka = '''
# Atlas ćwiczeń

## Zasady wspólne dla wszystkich ćwiczeń

- **Oddech:** oddychaj normalnie.
- **Tempo:** powoli.

## Spis treści

1. [Deska](#deska-boczna)

---

# Rutyna „Kręgosłup 15 min”

<a id="deska-boczna"></a>
## 6. Deska boczna (na kolanach i na stopach)

**Wersja na kolanach (start)**

![Deska na kolanach](img/deska_boczna_kolana.jpg)

**Wersja na stopach**

![Deska na stopach](img/deska_boczna_stopy.jpg)

**Po co:** wzmacnia boczne mięśnie tułowia.

**Pozycja wyjściowa**
- Połóż się na boku.
- **Na kolanach:** kolana zgięte ok. 90°, stopy za sobą. Rysunek pokazuje kolana zgięte mniej, ale liczy się linia.
- **Na stopach:** nogi proste.

**Ruch**
1. Unieś biodra.
2. Utrzymaj zadany czas.

**Przerwij, jeśli:** ból schodzi do pośladka.

---

# W ciągu dnia

<a id="pozycje-do-spania"></a>
## 13. Pozycje do spania

![Pozycje](img/pozycje_do_spania.jpg)

- **Na plecach:** poduszka pod kolanami.

**Wstawanie z łóżka bez skłonu:**
1. Obróć się na bok.

Przez pierwszą godzinę unikaj skłonów.
''';

void main() {
  final json = parsujAtlas(_probka);
  final atlas = Atlas.zJson(json);

  test('zasady wspólne i grupy', () {
    expect(atlas.zasadyWspolne, ['**Oddech:** oddychaj normalnie.', '**Tempo:** powoli.']);
    expect(atlas.cwiczenia.keys, ['deska-boczna', 'pozycje-do-spania']);
    expect(atlas.cwiczenia['deska-boczna']!.grupa, 'Rutyna „Kręgosłup 15 min”');
    expect(atlas.cwiczenia['pozycje-do-spania']!.grupa, 'W ciągu dnia');
  });

  test('kilka rysunków: warianty, podpisy i uwaga przy właściwym wariancie', () {
    final d = atlas.cwiczenia['deska-boczna']!;
    expect(d.nazwa, 'Deska boczna (na kolanach i na stopach)');
    expect(d.rysunki.keys, ['kolana', 'stopy']);
    expect(d.rysunki['kolana']!.podpis, 'Wersja na kolanach (start)');
    expect(d.rysunki['kolana']!.uwaga, 'Rysunek pokazuje kolana zgięte mniej, ale liczy się linia.');
    expect(d.rysunki['stopy']!.uwaga, isNull);
    expect(d.rysunek('kolana')!.asset, 'assets/plan/img/deska_boczna_kolana.jpg');
  });

  test('sekcje: rodzaje, punkty, numeracja, tekst w linii', () {
    final s = atlas.cwiczenia['deska-boczna']!.sekcje;
    expect(s.map((e) => e.rodzaj), ['poCo', 'pozycja', 'ruch', 'przerwijJesli']);
    expect(s[0].tekst, 'wzmacnia boczne mięśnie tułowia.');
    expect(s[1].punkty, hasLength(3));
    expect(s[1].numerowane, isFalse);
    expect(s[2].punkty, ['Unieś biodra.', 'Utrzymaj zadany czas.']);
    expect(s[2].numerowane, isTrue);
    expect(s[3].tekst, 'ból schodzi do pośladka.');
  });

  test('pojedynczy rysunek ma pusty klucz, punkty bez nagłówka i akapit nie giną', () {
    final p = atlas.cwiczenia['pozycje-do-spania']!;
    expect(p.rysunki.keys, ['']);
    expect(p.sekcje.map((e) => (e.tytul, e.punkty.length, e.tekst)), [
      ('', 1, null),
      ('Wstawanie z łóżka bez skłonu', 1, null),
      ('', 0, 'Przez pierwszą godzinę unikaj skłonów.'),
    ]);
  });

  test('rodzaj sekcji po początku tytułu', () {
    expect(rodzajSekcji('Ruch: wersja łatwa (rysunek 2)'), 'ruch');
    expect(rodzajSekcji('Pozycja wyjściowa (rysunek 1)'), 'pozycja');
    expect(rodzajSekcji('Najczęstsze błędy (ważne dla pleców)'), 'bledy');
    expect(rodzajSekcji('Warunek'), 'kiedy');
    expect(rodzajSekcji('Zejście'), 'inne');
  });
}
