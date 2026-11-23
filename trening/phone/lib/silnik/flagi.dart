/// Flagi, którymi plan włącza i wyłącza ćwiczenia (`tylkoGdy`, `pominGdy`).
/// Nazwy muszą być w `znaneFlagi` (plan/model.dart).
library;

import '../plan/model.dart';
import 'daty.dart';

/// Gdzie kończy się ból. Kolejność ma znaczenie: im dalej, tym gorzej.
enum Zasieg { brak, posladek, udo, ponizejKolana }

/// Wynik testu kierunkowego.
enum WynikTestu { lepiej, bezZmian, gorzej }

/// Liczy flagi na dzień [dzis].
///
/// [zasiegi]: gdzie kończył się ból w kolejnych dniach (z oceny po treningu
/// i porannego check-inu; dla dnia bierzemy najgorszy wpis).
Set<String> obliczFlagi({
  required DateTime dzis,
  WynikTestu? test,
  Map<DateTime, Zasieg> zasiegi = const {},
  bool slizgiOdFizjo = false,
}) {
  final d = dzien(dzis);
  final f = <String>{};
  if (test != null) {
    f.add('testKierunkowyZrobiony');
    if (test != WynikTestu.gorzej) f.addAll(['wyprostNieSzkodzi', 'lezenieNaBrzuchuOk']);
    if (test == WynikTestu.lepiej) f.add('wyprostPomaga');
  }

  Zasieg? najgorszy(Iterable<MapEntry<DateTime, Zasieg>> wpisy) {
    Zasieg? z;
    for (final w in wpisy) {
      if (z == null || w.value.index > z.index) z = w.value;
    }
    return z;
  }

  bool wOknie(DateTime data, int odDni, int doDni) {
    final r = dniMiedzy(data, d);
    return r >= odDni && r <= doDni;
  }

  final ostatnie7 = najgorszy(zasiegi.entries.where((e) => wOknie(e.key, 0, 6)));
  if (ostatnie7 != null && ostatnie7.index >= Zasieg.udo.index) f.add('objawyUdoLubNizej');

  final dzisiaj = najgorszy(zasiegi.entries.where((e) => dzien(e.key) == d));
  final wczesniej = najgorszy(zasiegi.entries.where((e) => wOknie(e.key, 1, 7)));
  if (dzisiaj != null && dzisiaj.index > (wczesniej ?? Zasieg.brak).index) f.add('zasiegSchodziNizej');

  if (slizgiOdFizjo) f.add('slizgiOdFizjo');
  assert(f.every(znaneFlagi.contains));
  return f;
}

/// Czy ćwiczenie jest dziś w sesji: `tylkoGdy` = którakolwiek z flag, `pominGdy` = którakolwiek z flag.
bool cwiczenieAktywne(CwiczeniePlanu c, Set<String> flagi) {
  if (c.pominGdy.any(flagi.contains)) return false;
  if (c.tylkoGdy.isNotEmpty && !c.tylkoGdy.any(flagi.contains)) return false;
  return true;
}
