/// Kalendarz „adwentowy”: okienko na każdy dzień od startu planu.
///
/// Etapy zmieniają się według kryteriów, nie kalendarza. Przeszłość wynika
/// z historii etapów (kiedy który się zaczął), a przyszłość jest prognozą:
/// bieżący etap trwa co najmniej swoje minimum, a kolejne etapy są zablokowane
/// do czasu spełnienia kryteriów. Gdy etap się wydłuża, cały blok kolejnych
/// etapów przesuwa się, a siatka rośnie ponad 84 dni.
library;

import '../plan/model.dart';
import 'daty.dart';

/// Wpis historii: od dnia [od] obowiązuje etap [nr] (też po cofnięciu).
class WpisEtapu {
  WpisEtapu(this.nr, DateTime od) : od = dzien(od);

  final int nr;
  final DateTime od;

  @override
  String toString() => 'etap $nr od ${iso(od)}';
}

class DzienPlanu {
  DzienPlanu({
    required this.data,
    required this.nr,
    required this.etap,
    required this.tydzienEtapu,
    required this.dzienEtapu,
    required this.sesja,
    required this.zablokowany,
    required this.zadania,
  });

  final DateTime data;

  /// Numer dnia planu, od 1.
  final int nr;
  final int etap;

  /// Tydzień i dzień liczone od początku etapu (od 1): treść zależna od
  /// „tygodni planu” jest liczona od startu etapu, nie od startu planu.
  final int tydzienEtapu;
  final int dzienEtapu;
  final String sesja;

  /// Dzień etapu, do którego jeszcze nie przeszedłeś (czeka na kryteria).
  final bool zablokowany;

  /// Identyfikatory zadań dodatkowych na ten dzień (test kierunkowy, drążek…).
  final List<String> zadania;
}

/// Odcinek prognozy: etap [nr] od [od]; [prognoza] = jeszcze nie rozpoczęty.
class _Odcinek {
  _Odcinek(this.nr, this.od, {required this.prognoza});

  final int nr;
  final DateTime od;
  final bool prognoza;
}

class Kalendarz {
  Kalendarz._(this.start, this.dni, this.koniecMinimum);

  final DateTime start;
  final List<DzienPlanu> dni;

  /// Najwcześniejszy dzień, w którym bieżący etap może się skończyć (null w ostatnim etapie).
  final DateTime? koniecMinimum;

  DzienPlanu? naDzien(DateTime d) {
    final i = dniMiedzy(start, d);
    return i >= 0 && i < dni.length ? dni[i] : null;
  }

  /// Ile dni pokazuje siatka: co najmniej 84, więcej, gdy etap się wydłużył.
  int get dlugosc => dni.length;

  /// Wylicza kalendarz od [start] do końca minimum ostatniego etapu.
  ///
  /// [historia] to kolejne wejścia w etapy (pierwszy wpis to etap 1 w dniu startu;
  /// pusta historia = tylko etap 1 od startu). [dzis] rozdziela przeszłość od prognozy.
  static Kalendarz wylicz(Plan plan, DateTime start, List<WpisEtapu> historia, DateTime dzis) {
    final s = dzien(start);
    final d = dzien(dzis).isBefore(s) ? s : dzien(dzis);
    final wpisy = historia.isEmpty ? [WpisEtapu(1, s)] : ([...historia]..sort((a, b) => a.od.compareTo(b.od)));
    if (wpisy.first.nr != 1 || wpisy.first.od != s) {
      throw ArgumentError('historia musi zaczynać się od etapu 1 w dniu startu');
    }

    // odcinki, które już się zaczęły (do dziś włącznie)
    final odcinki = [
      for (final w in wpisy)
        if (!w.od.isAfter(d)) _Odcinek(w.nr, w.od, prognoza: false),
    ];
    final biezacy = odcinki.last;
    final poprzedni = odcinki.length > 1 ? odcinki[odcinki.length - 2] : null;
    final cofniety = poprzedni != null && biezacy.nr < poprzedni.nr;
    final minimum = cofniety ? plan.minDniPoCofnieciu : plan.etap(biezacy.nr).minDni;
    final koniecMin = dodajDni(biezacy.od, minimum);

    // prognoza: następny etap najwcześniej po minimum, ale nie wcześniej niż jutro
    var od = koniecMin.isAfter(d) ? koniecMin : dodajDni(d, 1);
    for (var nr = biezacy.nr + 1; nr <= plan.etapy.length; nr++) {
      odcinki.add(_Odcinek(nr, od, prognoza: true));
      od = dodajDni(od, plan.etap(nr).minDni);
    }
    // siatka kończy się z minimum ostatniego etapu (prognozowanego albo bieżącego)
    final ostatni = odcinki.last;
    final koniec = dodajDni(ostatni.od, plan.etap(ostatni.nr).minDni);
    final dlugosc = [dniMiedzy(s, koniec), 84, dniMiedzy(s, d) + 1].reduce((a, b) => a > b ? a : b);

    final dni = <DzienPlanu>[];
    var o = 0;
    for (var i = 0; i < dlugosc; i++) {
      final data = dodajDni(s, i);
      while (o + 1 < odcinki.length && !odcinki[o + 1].od.isAfter(data)) {
        o++;
      }
      final odc = odcinki[o];
      final etap = plan.etap(odc.nr);
      final dzienEtapu = dniMiedzy(odc.od, data) + 1;
      final tydzien = (dzienEtapu - 1) ~/ 7 + 1;
      dni.add(DzienPlanu(
        data: data,
        nr: i + 1,
        etap: odc.nr,
        tydzienEtapu: tydzien,
        dzienEtapu: dzienEtapu,
        sesja: etap.harmonogram[data.weekday]!,
        zablokowany: odc.prognoza,
        zadania: [
          for (final z in etap.zadania)
            if (_zadanieWDniu(z, tydzien, dzienEtapu)) z.id,
        ],
      ));
    }
    final ostatniEtap = biezacy.nr == plan.etapy.length;
    return Kalendarz._(s, dni, ostatniEtap ? null : koniecMin);
  }
}

bool _zadanieWDniu(Zadanie z, int tydzien, int dzienEtapu) {
  final t = z.tygodnie;
  if (t != null && (tydzien < t.$1 || (t.$2 != null && tydzien > t.$2!))) return false;
  final co = z.coDni;
  if (co != null) return dzienEtapu >= z.odDnia && (dzienEtapu - z.odDnia) % co == 0;
  return true;
}

/// Cel spaceru na dzień etapu (tydzień liczony od startu etapu).
CelSpaceru? celSpaceru(Etap etap, int tydzienEtapu) {
  for (final c in etap.spacer) {
    final (od, do_) = c.tygodnie;
    if (tydzienEtapu >= od && (do_ == null || tydzienEtapu <= do_)) return c;
  }
  return null;
}
