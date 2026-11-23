/// Maszyna prowadzenia treningu: która faza trwa, ile zostało, liczniki,
/// pauza, „Boli: pomiń”. Czas liczy od zegara (znacznik startu fazy), a nie
/// z „tyknięć”, więc powrót do aplikacji po chwili nie rozjeżdża odliczania.
/// Zegar i sygnały są wstrzykiwane, żeby dało się to przetestować bez czekania.
library;

import 'package:flutter/foundation.dart';

import 'rozpiska.dart';

/// Sygnały dźwiękowe i wibracje; implementacja w `sygnaly_urzadzenia.dart`.
abstract class Sygnaly {
  const Sygnaly();

  void startTrzymania() {}
  void odliczanie(int sekund) {}
  void koniecTrzymania() {}
  void zmianaStrony() {}
  void koniecPrzerwy() {}
  void celOsiagniety() {}
  void koniecTreningu() {}
}

class BrakSygnalow extends Sygnaly {
  const BrakSygnalow();
}

class WynikPrzebiegu {
  WynikPrzebiegu({
    required this.start,
    required this.koniec,
    required this.wykonane,
    required this.pominiete,
    required this.bolesne,
    required this.ukonczony,
  });

  final DateTime start;
  final DateTime koniec;
  final List<String> wykonane;
  final List<String> pominiete;
  final List<String> bolesne;

  /// Sesja przeszła do końca (z pominięciami albo bez); false = przerwana wcześniej.
  final bool ukonczony;
}

class Przebieg extends ChangeNotifier {
  Przebieg(this.rozpiska, {DateTime Function()? zegar, this.sygnaly = const BrakSygnalow()})
      : _zegar = zegar ?? DateTime.now {
    start = _zegar();
    if (rozpiska.fazy.isEmpty) {
      _koniec = true;
      _koniecCzas = start;
    } else {
      _wejdz(0);
    }
  }

  final Rozpiska rozpiska;
  final Sygnaly sygnaly;
  final DateTime Function() _zegar;
  late final DateTime start;

  int _i = 0;
  bool _koniec = false;
  DateTime? _koniecCzas;
  DateTime _startFazy = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _pauzy = Duration.zero;
  DateTime? _pauzaOd;
  int _licznik = 0;
  int _dodatkowe = 0;
  int _ostatnieOdliczanie = -1;
  bool _celZgloszony = false;

  /// Indeksy ćwiczeń pominiętych w trakcie (i te, przy których bolało).
  final Set<int> _pominiete = {};
  final Set<int> _bolesne = {};

  int get indeks => _i;
  bool get koniec => _koniec;
  bool get pauza => _pauzaOd != null;
  Faza get faza => rozpiska.fazy[_i];
  CwiczenieSesji get cwiczenie => rozpiska.cwiczenia[faza.cwiczenie];

  /// Powtórzenia odliczone ręcznie albo oddechy policzone z tempa.
  int get licznik => _licznik;
  double get postep => rozpiska.fazy.isEmpty ? 1 : (_koniec ? 1 : _i / rozpiska.fazy.length);

  Duration get uplynelo {
    final teraz = _pauzaOd ?? _zegar();
    final d = teraz.difference(_startFazy) - _pauzy;
    return d.isNegative ? Duration.zero : d;
  }

  /// Długość fazy z czasem (trzymanie, przerwa), z dodanymi sekundami; null dla pozostałych.
  int? get sekundyFazy => switch (faza) {
        FazaTrzymanie(:final sekundy) || FazaPrzerwa(:final sekundy) => sekundy + _dodatkowe,
        _ => null,
      };

  /// Pełne sekundy do końca fazy z czasem (zaokrąglone w górę).
  int? get pozostalo {
    final s = sekundyFazy;
    if (s == null) return null;
    final ms = s * 1000 - uplynelo.inMilliseconds;
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  /// Oddechy: czy trwa teraz wdech (do animacji koła).
  bool get wdech {
    final f = faza;
    if (f is! FazaOddechy) return false;
    final cykl = ((f.wdechS + f.wydechS) * 1000).round();
    return uplynelo.inMilliseconds % cykl < f.wdechS * 1000;
  }

  /// Kolejne ćwiczenie (inne niż bieżące, niepominięte) do podpisu „Dalej: …”.
  CwiczenieSesji? get nastepneCwiczenie {
    if (_koniec) return null;
    final biezace = faza.cwiczenie;
    for (var j = _i + 1; j < rozpiska.fazy.length; j++) {
      final c = rozpiska.fazy[j].cwiczenie;
      if (c != biezace && !_pominiete.contains(c)) return rozpiska.cwiczenia[c];
    }
    return null;
  }

  void tick() {
    if (_koniec || pauza) return;
    final f = faza;
    switch (f) {
      case FazaTrzymanie() || FazaPrzerwa():
        final zostalo = pozostalo!;
        if (zostalo >= 1 && zostalo <= 3 && zostalo != _ostatnieOdliczanie) {
          _ostatnieOdliczanie = zostalo;
          sygnaly.odliczanie(zostalo);
        }
        if (zostalo == 0) {
          f is FazaTrzymanie ? sygnaly.koniecTrzymania() : sygnaly.koniecPrzerwy();
          _nastepna();
        }
      case FazaOddechy():
        final cykl = ((f.wdechS + f.wydechS) * 1000).round();
        final n = uplynelo.inMilliseconds ~/ cykl;
        if (n != _licznik) {
          _licznik = n;
          if (_licznik >= f.cel && !_celZgloszony) {
            _celZgloszony = true;
            sygnaly.celOsiagniety();
          }
        }
      case FazaPrzygotowanie() || FazaPowtorzenia():
        break;
    }
    notifyListeners();
  }

  /// Start / Gotowe / pomiń odliczanie: następna faza.
  void dalej() {
    if (_koniec) return;
    if (pauza) wznow();
    _nastepna();
    notifyListeners();
  }

  void plusJeden() => _zmienLicznik(1);
  void minusJeden() => _zmienLicznik(-1);

  void _zmienLicznik(int o) {
    final f = faza;
    if (f is! FazaPowtorzenia) return;
    _licznik = (_licznik + o).clamp(0, 999);
    if (_licznik >= f.cel && !_celZgloszony) {
      _celZgloszony = true;
      sygnaly.celOsiagniety();
    }
    notifyListeners();
  }

  /// „+5 s” przy trzymaniu albo przerwie.
  void dodajSekundy(int s) {
    if (sekundyFazy == null) return;
    _dodatkowe += s;
    _ostatnieOdliczanie = -1;
    notifyListeners();
  }

  void pauzuj() {
    if (_koniec || pauza) return;
    _pauzaOd = _zegar();
    notifyListeners();
  }

  void wznow() {
    final od = _pauzaOd;
    if (od == null) return;
    _pauzy += _zegar().difference(od);
    _pauzaOd = null;
    notifyListeners();
  }

  /// Pomija bieżące ćwiczenie do końca sesji (także w kolejnych rundach).
  /// [boli]: „Boli: pomiń”, zapisywane do oceny po treningu.
  void pominCwiczenie({bool boli = false}) {
    if (_koniec) return;
    final c = faza.cwiczenie;
    _pominiete.add(c);
    if (boli) _bolesne.add(c);
    if (pauza) wznow();
    _nastepna();
    notifyListeners();
  }

  /// Kończy przed czasem (wyjście z treningu).
  void zakonczTeraz() {
    if (_koniec) return;
    _koniec = true;
    _koniecCzas = _zegar();
    notifyListeners();
  }

  WynikPrzebiegu wynik() {
    final ostatniaFaza = <int, int>{};
    for (final (j, f) in rozpiska.fazy.indexed) {
      ostatniaFaza[f.cwiczenie] = j;
    }
    final ukonczony = _koniec && _i >= rozpiska.fazy.length;
    final wykonane = <String>[];
    final pominiete = <String>[];
    for (final (c, cs) in rozpiska.cwiczenia.indexed) {
      if (_pominiete.contains(c)) {
        pominiete.add(cs.id);
      } else if (ukonczony || (ostatniaFaza[c] ?? -1) < _i) {
        wykonane.add(cs.id);
      }
    }
    return WynikPrzebiegu(
      start: start,
      koniec: _koniecCzas ?? _zegar(),
      wykonane: wykonane,
      pominiete: pominiete,
      bolesne: [for (final c in _bolesne) rozpiska.cwiczenia[c].id],
      ukonczony: ukonczony,
    );
  }

  void _nastepna() {
    var j = _i + 1;
    while (j < rozpiska.fazy.length && _pominiete.contains(rozpiska.fazy[j].cwiczenie)) {
      j++;
    }
    if (j >= rozpiska.fazy.length) {
      _i = rozpiska.fazy.length;
      _koniec = true;
      _koniecCzas = _zegar();
      sygnaly.koniecTreningu();
      return;
    }
    _wejdz(j);
  }

  void _wejdz(int j) {
    _i = j;
    _startFazy = _zegar();
    _pauzy = Duration.zero;
    _pauzaOd = null;
    _licznik = 0;
    _dodatkowe = 0;
    _ostatnieOdliczanie = -1;
    _celZgloszony = false;
    final f = rozpiska.fazy[j];
    if (f is FazaTrzymanie) sygnaly.startTrzymania();
    if (f is FazaPrzerwa && f.powod == PowodPrzerwy.strona) sygnaly.zmianaStrony();
  }
}
