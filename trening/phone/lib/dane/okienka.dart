/// Stan okienek kalendarza „adwentowego” (plan aplikacji, sekcja 3.2).
library;

import '../silnik/daty.dart';
import '../silnik/kalendarz.dart';
import '../silnik/sygnalizacja.dart';
import 'stan.dart';

enum StanOkienka {
  /// Dziś, jeszcze nic nie zrobione.
  czeka,
  wykonane,

  /// Wersja na gorszy dzień albo przerwana sesja.
  skrocone,

  /// Data minęła, nic nie odznaczono.
  pominiete,
  wolne,

  /// Dzień obecnego etapu, który dopiero przyjdzie.
  przyszle,

  /// Dzień następnego etapu: czeka na kryteria.
  zablokowane,
}

class Okienko {
  Okienko({
    required this.dzien,
    required this.stan,
    required this.dzis,
    required this.sesja,
    this.zapis,
    this.test = false,
  });

  final DzienPlanu dzien;
  final StanOkienka stan;
  final bool dzis;

  /// Litera sesji: zrobiona (gdy jest zapis) albo zaplanowana.
  final String sesja;
  final ZapisTreningu? zapis;

  /// Znaczek 🧭: test kierunkowy zrobiony tego dnia albo (dziś) czeka na zrobienie.
  final bool test;

  DateTime get data => dzien.data;
  Strefa? get strefa => zapis?.ocena?.strefa;
  bool get odznaczone => stan == StanOkienka.wykonane || stan == StanOkienka.skrocone;
}

Okienko okienko(DzienPlanu d, Stan s, DateTime dzis) {
  final klucz = iso(d.data);
  final zapis = s.treningi[klucz];
  final r = dniMiedzy(d.data, dzis);
  final StanOkienka stan;
  if (zapis != null) {
    stan = zapis.stan == StanDnia.wykonane ? StanOkienka.wykonane : StanOkienka.skrocone;
  } else if (s.wolne.contains(klucz)) {
    stan = StanOkienka.wolne;
  } else if (r > 0) {
    stan = StanOkienka.pominiete;
  } else if (r == 0) {
    stan = StanOkienka.czeka;
  } else {
    stan = d.zablokowany ? StanOkienka.zablokowane : StanOkienka.przyszle;
  }
  final testZrobiony = s.testKierunkowy?.data;
  final test = testZrobiony != null
      ? dzien(testZrobiony) == d.data
      : r == 0 && d.zadania.contains('test-kierunkowy');
  return Okienko(dzien: d, stan: stan, dzis: r == 0, sesja: zapis?.sesja ?? d.sesja, zapis: zapis, test: test);
}

/// Ile treningów (pełnych i skróconych) w tygodniu Pn–Nd, w którym jest [dzis].
int treningiWTygodniu(Stan s, DateTime dzis) {
  final pn = dodajDni(dzien(dzis), 1 - dzis.weekday);
  var n = 0;
  for (var i = 0; i < 7; i++) {
    if (s.treningi.containsKey(iso(dodajDni(pn, i)))) n++;
  }
  return n;
}
