/// Sprawdzenie odwołań między plan.json a atlas.json: każde ćwiczenie ma opis
/// i rysunek w atlasie, każdy krok wskazuje istniejące ćwiczenie, harmonogramy
/// wskazują istniejące sesje, flagi są znane. Zwraca listę problemów (pusta = OK).
library;

import 'atlas.dart';
import 'model.dart';

List<String> sprawdzPlan(Plan plan, Atlas atlas) {
  final bledy = <String>[];

  for (final c in plan.cwiczenia.values) {
    final a = atlas.cwiczenia[c.atlasId];
    if (a == null) {
      bledy.add('ćwiczenie ${c.id}: brak kotwicy „${c.atlasId}” w atlasie');
    } else if (a.rysunek(c.wariant) == null) {
      bledy.add('ćwiczenie ${c.id}: atlas nie ma rysunku wariantu „${c.wariant}” '
          '(są: ${a.rysunki.keys.map((k) => k.isEmpty ? '(domyślny)' : k).join(', ')})');
    }
    for (final f in [...c.tylkoGdy, ...c.pominGdy]) {
      if (!znaneFlagi.contains(f)) bledy.add('ćwiczenie ${c.id}: nieznana flaga „$f”');
    }
  }

  for (final s in plan.sesje.values) {
    for (final (b, blok) in s.bloki.indexed) {
      for (final krok in blok.kroki) {
        if (!plan.cwiczenia.containsKey(krok.cwiczenie)) {
          bledy.add('sesja ${s.id}, blok ${b + 1}: nieznane ćwiczenie „${krok.cwiczenie}”');
        }
      }
    }
    for (final (od, do_) in s.krotszaWersja) {
      if (od < 0 || do_ >= s.bloki.length || od > do_) {
        bledy.add('sesja ${s.id}: krotszaWersja [$od, $do_] poza blokami 0–${s.bloki.length - 1}');
      }
    }
  }

  for (final e in plan.etapy) {
    for (final MapEntry(key: dzien, value: sesja) in e.harmonogram.entries) {
      if (!plan.sesje.containsKey(sesja)) bledy.add('etap ${e.nr}, dzień $dzien: nieznana sesja „$sesja”');
    }
    final ids = <String>{};
    for (final z in e.zadania) {
      if (!ids.add(z.id)) bledy.add('etap ${e.nr}: powtórzone zadanie „${z.id}”');
    }
    for (final k in e.kryteria) {
      if (!ids.add(k.id)) bledy.add('etap ${e.nr}: powtórzony identyfikator kryterium „${k.id}”');
    }
    if (e.nr < plan.etapy.length && e.kryteria.isEmpty) {
      bledy.add('etap ${e.nr}: brak kryteriów przejścia do etapu ${e.nr + 1}');
    }
  }

  // etap 1 musi być kompletny od pierwszego wydania: żadnych zapowiedzi
  for (final sesja in plan.etapy.first.harmonogram.values.toSet()) {
    if (plan.sesje[sesja]?.wkrotce ?? false) bledy.add('etap 1 używa zapowiedzianej sesji „$sesja”');
  }

  return bledy;
}
