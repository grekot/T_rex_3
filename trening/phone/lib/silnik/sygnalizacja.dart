/// Sygnalizacja świetlna (plan aplikacji, sekcja 5.3): strefa bólu po treningu
/// i rano. Aplikacja tylko podpowiada; przy niejasnych danych wybiera
/// ostrożniejszą strefę.
library;

import 'daty.dart';
import 'flagi.dart';

enum Strefa { zielona, zolta, czerwona }

/// Ocena bólu: po treningu, rano albo przy „zrobiłem bez aplikacji”.
class OcenaBolu {
  const OcenaBolu({required this.bol, required this.zasieg, this.mrowienie = false});

  /// Ból w krzyżu 0–10.
  final int bol;
  final Zasieg zasieg;

  /// Mrowienie albo drętwienie.
  final bool mrowienie;

  /// Ból poniżej kolana albo mrowienie: gdy się utrzymuje, plan każe iść do specjalisty.
  bool get objawyNerwowe => mrowienie || zasieg == Zasieg.ponizejKolana;
}

class WynikSygnalizacji {
  const WynikSygnalizacji({
    required this.strefa,
    this.schodziNizej = false,
    this.cofaSie = false,
    this.pytajOFlagi = false,
    this.objawyNerwowe = false,
  });

  final Strefa strefa;

  /// Zasięg niżej niż najgorszy z ostatnich 7 dni (bez historii: udo lub niżej).
  final bool schodziNizej;

  /// Zasięg cofa się w stronę kręgosłupa (centralizacja): dobry znak.
  final bool cofaSie;

  /// Ból ≥ 5 albo zasięg udo lub niżej: zapytać o czerwone flagi.
  final bool pytajOFlagi;
  final bool objawyNerwowe;
}

/// Strefa dla oceny [o].
///
/// [odniesienie]: najgorszy zasięg z 7 dni przed oceną (null = brak danych).
/// [minelo]: odpowiedź z porannego check-inu, czy ból po treningu minął w 24 h
/// (null = jeszcze nie wiadomo).
WynikSygnalizacji ocenStrefe(OcenaBolu o, {Zasieg? odniesienie, bool? minelo}) {
  final schodziNizej =
      odniesienie == null ? o.zasieg.index >= Zasieg.udo.index : o.zasieg.index > odniesienie.index;
  final cofaSie = odniesienie != null && o.zasieg.index < odniesienie.index;
  final Strefa strefa;
  if (o.bol >= 5 || minelo == false || schodziNizej || o.objawyNerwowe) {
    strefa = Strefa.czerwona;
  } else if (o.bol >= 3 || o.zasieg == Zasieg.udo) {
    strefa = Strefa.zolta;
  } else {
    strefa = Strefa.zielona;
  }
  return WynikSygnalizacji(
    strefa: strefa,
    schodziNizej: schodziNizej,
    cofaSie: cofaSie,
    pytajOFlagi: o.bol >= 5 || o.zasieg.index >= Zasieg.udo.index,
    objawyNerwowe: o.objawyNerwowe,
  );
}

/// Najgorszy zasięg w dniach od `dzis - doDni` do `dzis - odDni` (włącznie).
Zasieg? najgorszyZasieg(Map<DateTime, Zasieg> zasiegi, DateTime dzis, {int odDni = 1, int doDni = 7}) {
  Zasieg? z;
  for (final MapEntry(:key, :value) in zasiegi.entries) {
    final r = dniMiedzy(key, dzis);
    if (r < odDni || r > doDni) continue;
    if (z == null || value.index > z.index) z = value;
  }
  return z;
}
