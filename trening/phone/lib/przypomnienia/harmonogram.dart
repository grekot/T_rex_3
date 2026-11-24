/// Przypomnienia: ustawienia i wyliczanie, kiedy co ma przyjść.
///
/// Czysta logika bez Fluttera. Android dostaje gotową listę (id, czas, kanał,
/// tytuł, treść) i ustawia z niej alarmy (Przypomnienia.kt). Listę liczymy na
/// nowo po każdej zmianie stanu i przy każdym otwarciu aplikacji, więc
/// przypomnienie o treningu znika, gdy trening jest już zrobiony.
///
/// Czasy są w czasie lokalnym telefonu (zmiana czasu letniego liczy się sama).
library;

/// Dni tygodnia jak w `DateTime.weekday`: 1 = poniedziałek … 7 = niedziela.
const dniRobocze = {1, 2, 3, 4, 5};

class UstawieniaPrzypomnien {
  UstawieniaPrzypomnien({
    this.trening = true,
    this.treningMin = 19 * 60,
    this.drugie = false,
    this.przerwy = true,
    this.przerwyCo = 40,
    this.przerwyOd = 8 * 60,
    this.przerwyDo = 16 * 60,
    Set<int>? przerwyDni,
    this.wyprosty = false,
    this.wyprostyCoH = 3,
  }) : przerwyDni = przerwyDni ?? {...dniRobocze};

  /// Trening codziennie o [treningMin] (minuty od północy), opcjonalnie drugie o 20:30.
  bool trening;
  int treningMin;
  bool drugie;

  /// Przerwy w siedzeniu co [przerwyCo] min od [przerwyOd] do [przerwyDo] w [przerwyDni].
  bool przerwy;
  int przerwyCo;
  int przerwyOd;
  int przerwyDo;
  final Set<int> przerwyDni;

  /// Wyprosty w leżeniu co [wyprostyCoH] h (tylko po dobrym teście kierunkowym).
  bool wyprosty;
  int wyprostyCoH;

  static const drugieMin = 20 * 60 + 30;

  /// Interwał przerw w dzień, gdy „pali dziś w krzyżu” (plan: co 20–30 min).
  static const przerwyCoGdyPali = 25;
  static const wyprostyOd = 8 * 60;
  static const wyprostyDo = 20 * 60;

  Map<String, Object?> toJson() => {
        'trening': {'wl': trening, 'godz': godzina(treningMin), 'drugie': drugie},
        'przerwy': {
          'wl': przerwy,
          'coMin': przerwyCo,
          'od': godzina(przerwyOd),
          'do': godzina(przerwyDo),
          'dni': przerwyDni.toList()..sort(),
        },
        'wyprosty': {'wl': wyprosty, 'coH': wyprostyCoH},
      };

  static UstawieniaPrzypomnien zJson(Map<String, Object?> j) {
    Map<String, Object?> m(String k) => ((j[k] as Map?) ?? const {}).cast<String, Object?>();
    final t = m('trening'), p = m('przerwy'), w = m('wyprosty');
    final d = UstawieniaPrzypomnien();
    return UstawieniaPrzypomnien(
      trening: t['wl'] as bool? ?? d.trening,
      treningMin: minuty(t['godz'] as String?) ?? d.treningMin,
      drugie: t['drugie'] as bool? ?? d.drugie,
      przerwy: p['wl'] as bool? ?? d.przerwy,
      przerwyCo: p['coMin'] as int? ?? d.przerwyCo,
      przerwyOd: minuty(p['od'] as String?) ?? d.przerwyOd,
      przerwyDo: minuty(p['do'] as String?) ?? d.przerwyDo,
      przerwyDni: (p['dni'] as List?)?.cast<int>().toSet(),
      wyprosty: w['wl'] as bool? ?? d.wyprosty,
      wyprostyCoH: w['coH'] as int? ?? d.wyprostyCoH,
    );
  }
}

/// `19:00`
String godzina(int minuty) => '${minuty ~/ 60}:${(minuty % 60).toString().padLeft(2, '0')}';

int? minuty(String? hhmm) {
  if (hhmm == null) return null;
  final [h, m] = hhmm.split(':');
  return int.parse(h) * 60 + int.parse(m);
}

class Przypomnienie {
  const Przypomnienie({
    required this.id,
    required this.kiedy,
    required this.kanal,
    required this.tytul,
    required this.tresc,
  });

  final int id;

  /// Czas lokalny.
  final DateTime kiedy;

  /// Kanał powiadomień Androida: `trening`, `przerwy`, `wyprosty`.
  final String kanal;
  final String tytul;
  final String tresc;

  Map<String, Object?> toJson() => {
        'id': id,
        'czas': kiedy.millisecondsSinceEpoch,
        'kanal': kanal,
        'tytul': tytul,
        'tresc': tresc,
      };

  @override
  String toString() => '$id $kanal $kiedy: $tytul · $tresc';
}

/// Na ile dni naprzód planujemy (lista odnawia się przy każdym otwarciu aplikacji).
const dniTreningu = 14;
const dniPrzerw = 7;
const idTestowe = 9000;

/// Wylicza przypomnienia od chwili [teraz] (czas lokalny).
///
/// [bezTreningu]: dzień, w którym przypomnienie o treningu jest zbędne
/// (trening już zrobiony albo dzień wolny). [opisTreningu]: treść, np.
/// „Kręgosłup 15 min (ok. 15 min)”. [paliDzis]: włączony przełącznik „Pali dziś
/// w krzyżu” (przerwy co 25 min do końca dnia). [wyprostyDozwolone]: test
/// kierunkowy wypadł dobrze, więc wolno przypominać o wyprostach.
List<Przypomnienie> harmonogramPrzypomnien({
  required UstawieniaPrzypomnien u,
  required DateTime teraz,
  required bool Function(DateTime dzien) bezTreningu,
  required String Function(DateTime dzien) opisTreningu,
  bool paliDzis = false,
  bool wyprostyDozwolone = false,
}) {
  final wynik = <Przypomnienie>[];
  DateTime o(DateTime d, int min) => DateTime(d.year, d.month, d.day, min ~/ 60, min % 60);

  for (var i = 0; i < dniTreningu; i++) {
    final d = DateTime(teraz.year, teraz.month, teraz.day + i);

    if (u.trening && !bezTreningu(d)) {
      final opis = opisTreningu(d);
      for (final (n, min, tytul) in [
        (0, u.treningMin, 'Trening'),
        if (u.drugie && UstawieniaPrzypomnien.drugieMin > u.treningMin)
          (1, UstawieniaPrzypomnien.drugieMin, 'Trening: jeszcze zdążysz'),
      ]) {
        final kiedy = o(d, min);
        if (kiedy.isAfter(teraz)) {
          wynik.add(Przypomnienie(id: 1000 + n * 100 + i, kiedy: kiedy, kanal: 'trening', tytul: tytul, tresc: opis));
        }
      }
    }

    if (i >= dniPrzerw) continue;

    if (u.przerwy && u.przerwyDni.contains(d.weekday)) {
      final pali = paliDzis && i == 0;
      final co = pali ? UstawieniaPrzypomnien.przerwyCoGdyPali : u.przerwyCo;
      final tresc = wyprostyDozwolone
          ? 'Wstań na 1–2 min, przejdź się · 5–10 wyprostów w staniu'
          : 'Wstań na 1–2 min, przejdź się, napij się wody';
      var k = 0;
      // gdy pali: od teraz co 25 min; zwykle: pierwsza przerwa po interwale od początku pracy
      var min = pali ? teraz.hour * 60 + teraz.minute + co : u.przerwyOd + co;
      if (pali && min < u.przerwyOd + co) min = u.przerwyOd + co;
      for (; min <= u.przerwyDo && k < 99; min += co) {
        final kiedy = o(d, min);
        if (!kiedy.isAfter(teraz)) continue;
        wynik.add(Przypomnienie(id: 2000 + i * 100 + k++, kiedy: kiedy, kanal: 'przerwy', tytul: 'Przerwa', tresc: tresc));
      }
    }

    if (u.wyprosty && wyprostyDozwolone) {
      var k = 0;
      for (var min = UstawieniaPrzypomnien.wyprostyOd + u.wyprostyCoH * 60;
          min <= UstawieniaPrzypomnien.wyprostyDo;
          min += u.wyprostyCoH * 60) {
        final kiedy = o(d, min);
        if (!kiedy.isAfter(teraz)) continue;
        wynik.add(Przypomnienie(
          id: 3000 + i * 100 + k++,
          kiedy: kiedy,
          kanal: 'wyprosty',
          tytul: 'Wyprosty',
          tresc: '10 wyprostów w leżeniu, jeśli przynoszą ulgę',
        ));
      }
    }
  }
  wynik.sort((a, b) => a.kiedy.compareTo(b.kiedy));
  return wynik;
}

/// Jednorazowe przypomnienie do sprawdzenia, czy powiadomienia docierają (też na zegarek).
Przypomnienie przypomnienieTestowe(DateTime teraz) => Przypomnienie(
      id: idTestowe,
      kiedy: teraz.add(const Duration(minutes: 1)),
      kanal: 'trening',
      tytul: 'Test przypomnienia',
      tresc: 'Działa. Tak będą wyglądać przypomnienia o treningu.',
    );
