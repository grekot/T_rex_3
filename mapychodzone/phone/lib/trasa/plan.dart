import 'trasa.dart';

/// Rodzaj punktu planu trasy.
///
/// - [start] i [cel]: początek i koniec.
/// - [przystanek]: cel pośredni (np. schronisko). Trasa dzieli się na nim na odcinki,
///   a nawigacja (później) prowadzi do niego i podaje odległość.
/// - [przez]: punkt kształtujący trasę („idź tędy”). Trasa przez niego przechodzi,
///   ale nie jest celem: nie dzieli trasy i nawigacja go nie ogłasza.
enum RodzajPunktu { start, przez, przystanek, cel }

class PunktPlanu {
  const PunktPlanu(this.lon, this.lat, this.rodzaj, {this.nazwa});

  final double lon;
  final double lat;
  final RodzajPunktu rodzaj;

  /// Nazwa z mapy (np. „Schronisko PTTK na Turbaczu”), jeśli punkt leży przy nazwanym obiekcie.
  final String? nazwa;

  bool get jestCelem => rodzaj != RodzajPunktu.przez;

  PunktPlanu jako(RodzajPunktu r) => PunktPlanu(lon, lat, r, nazwa: nazwa);
}

/// Jak BRouter ma prowadzić trasę.
enum TrybTrasy {
  /// Trzyma się znakowanych szlaków; zejście ze szlaku kosztuje 6 razy więcej.
  szlakami('Szlakami', 5),

  /// Woli szlaki, ale skraca drogami leśnymi i ścieżkami (2 razy drożej poza szlakiem).
  szlakiISkroty('Szlaki i skróty', 1),

  /// Najkrótsza rozsądna trasa pieszo, bez premii za szlaki.
  najkrocej('Najkrócej', 0);

  const TrybTrasy(this.etykieta, this.preferencjaSzlakow);

  final String etykieta;

  /// Parametr `hiking_routes_preference` profilu BRoutera `hiking-mountain`:
  /// koszt odcinków poza szlakiem × (1 + wartość).
  final double preferencjaSzlakow;

  Map<String, String> get parametryBRoutera => {'hiking_routes_preference': '$preferencjaSzlakow'};
}

/// Kolejne punkty trasy. Niezmienny: każda operacja zwraca nowy plan.
class PlanTrasy {
  const PlanTrasy([this.punkty = const []]);

  final List<PunktPlanu> punkty;

  bool get pusty => punkty.isEmpty;
  int get dlugosc => punkty.length;

  /// Punkty, do których prowadzi nawigacja i na których dzielą się odcinki (bez startu).
  List<int> get indeksyCelow => [
        for (var i = 1; i < punkty.length; i++)
          if (punkty[i].jestCelem) i,
      ];

  /// Numer przystanku do podpisu na mapie (1, 2, …), null dla innych rodzajów.
  int? numerPrzystanku(int indeks) {
    if (punkty[indeks].rodzaj != RodzajPunktu.przystanek) return null;
    var n = 0;
    for (var i = 0; i <= indeks; i++) {
      if (punkty[i].rodzaj == RodzajPunktu.przystanek) n++;
    }
    return n;
  }

  /// Pierwszy punkt to start, drugi to cel. Dalsze dodawanie przedłuża trasę:
  /// dotychczasowy cel staje się przystankiem.
  PlanTrasy dodajNaKoncu(double lon, double lat, {String? nazwa}) {
    if (punkty.isEmpty) return PlanTrasy([PunktPlanu(lon, lat, RodzajPunktu.start, nazwa: nazwa)]);
    final nowe = [...punkty];
    if (nowe.length >= 2) nowe[nowe.length - 1] = nowe.last.jako(RodzajPunktu.przystanek);
    nowe.add(PunktPlanu(lon, lat, RodzajPunktu.cel, nazwa: nazwa));
    return PlanTrasy(nowe);
  }

  /// Wstawia punkt pośredni ([RodzajPunktu.przez] albo [RodzajPunktu.przystanek]) między
  /// punkty, gdzie najmniej wydłuża trasę. Gdy jest policzona [trasa], decyduje odcinek trasy
  /// najbliższy nowemu punktowi; bez niej – najmniejszy objazd w linii prostej.
  PlanTrasy wstaw(double lon, double lat, RodzajPunktu rodzaj, {String? nazwa, Trasa? trasa}) {
    assert(rodzaj == RodzajPunktu.przez || rodzaj == RodzajPunktu.przystanek);
    if (punkty.length < 2) return dodajNaKoncu(lon, lat, nazwa: nazwa);
    final miejsce = (trasa != null ? _miejscePoTrasie(lon, lat, trasa) : null) ?? _miejsceNajmniejszyObjazd(lon, lat);
    final nowe = [...punkty]..insert(miejsce, PunktPlanu(lon, lat, rodzaj, nazwa: nazwa));
    return PlanTrasy(nowe);
  }

  int _miejsceNajmniejszyObjazd(double lon, double lat) {
    var najlepsze = 1;
    var najmniej = double.infinity;
    for (var i = 0; i + 1 < punkty.length; i++) {
      final a = punkty[i], b = punkty[i + 1];
      final objazd = odlegloscM(a.lat, a.lon, lat, lon) + odlegloscM(lat, lon, b.lat, b.lon) - odlegloscM(a.lat, a.lon, b.lat, b.lon);
      if (objazd < najmniej) {
        najmniej = objazd;
        najlepsze = i + 1;
      }
    }
    return najlepsze;
  }

  int? _miejscePoTrasie(double lon, double lat, Trasa trasa) {
    if (trasa.punkty.isEmpty) return null;
    final indeksy = indeksyNaTrasie(trasa, punkty);
    if (indeksy == null) return null;
    var najblizszy = 0;
    var min = double.infinity;
    for (var j = 0; j < trasa.punkty.length; j++) {
      final p = trasa.punkty[j];
      final d = odlegloscM(p.lat, p.lon, lat, lon);
      if (d < min) {
        min = d;
        najblizszy = j;
      }
    }
    for (var i = 0; i + 1 < indeksy.length; i++) {
      if (najblizszy <= indeksy[i + 1]) return i + 1;
    }
    return punkty.length - 1;
  }

  PlanTrasy usun(int indeks) {
    final nowe = [...punkty]..removeAt(indeks);
    if (nowe.isEmpty) return const PlanTrasy();
    nowe[0] = nowe.first.jako(RodzajPunktu.start);
    if (nowe.length >= 2) nowe[nowe.length - 1] = nowe.last.jako(RodzajPunktu.cel);
    return PlanTrasy(nowe);
  }

  /// Zmiana punktu pośredniego między „przez” a „przystanek”. Start i cel zostają.
  PlanTrasy zmienRodzaj(int indeks, RodzajPunktu rodzaj) {
    if (indeks <= 0 || indeks >= punkty.length - 1) return this;
    final nowe = [...punkty];
    nowe[indeks] = nowe[indeks].jako(rodzaj);
    return PlanTrasy(nowe);
  }

  PlanTrasy cofnij() => punkty.isEmpty ? this : usun(punkty.length - 1);

  List<(double, double)> get wspolrzedne => [for (final p in punkty) (p.lon, p.lat)];
}

/// Indeksy punktów śladu, przez które trasa przechodzi przy kolejnych punktach planu.
///
/// BRouter przyciąga punkt do najbliższej drogi, więc ślad przechodzi zwykle kilka–kilkadziesiąt
/// metrów od niego. Szukamy po kolei, od miejsca poprzedniego punktu: pierwszy punkt śladu
/// niewiele dalej niż najbliższy (gdy trasa wraca tą samą drogą, bierzemy pierwsze przejście).
List<int>? indeksyNaTrasie(Trasa trasa, List<PunktPlanu> punkty) {
  final slad = trasa.punkty;
  if (slad.isEmpty || punkty.length < 2) return null;
  final wynik = <int>[];
  var od = 0;
  for (var i = 0; i < punkty.length; i++) {
    final p = punkty[i];
    if (i == punkty.length - 1) {
      wynik.add(slad.length - 1);
      break;
    }
    if (i == 0) {
      wynik.add(0);
      continue;
    }
    var min = double.infinity;
    final odl = List<double>.filled(slad.length, double.infinity);
    for (var j = od; j < slad.length; j++) {
      odl[j] = odlegloscM(slad[j].lat, slad[j].lon, p.lat, p.lon);
      if (odl[j] < min) min = odl[j];
    }
    var wybrany = od;
    for (var j = od; j < slad.length; j++) {
      if (odl[j] <= min + 15) {
        wybrany = j;
        break;
      }
    }
    wynik.add(wybrany);
    od = wybrany;
  }
  return wynik;
}

/// Odcinek trasy między kolejnymi celami (start → przystanek → … → cel).
class Odcinek {
  const Odcinek({
    required this.odIndeksu,
    required this.doIndeksu,
    required this.dlugosc,
    required this.podejscia,
    required this.zejscia,
    this.powrot = false,
  });

  /// Indeksy punktów planu na początku i końcu odcinka.
  final int odIndeksu;
  final int doIndeksu;
  final double dlugosc;
  final double podejscia;
  final double zejscia;

  /// Odcinek powrotu tą samą drogą (z celu do startu).
  final bool powrot;

  Duration get czas => czasPrzejscia(dlugoscM: dlugosc, podejsciaM: podejscia, zejsciaM: zejscia);
}

/// Dzieli trasę na odcinki na przystankach (punkty „przez” nie dzielą).
///
/// [trasa] to trasa „tam”. Przy [powrot] dochodzi jeden odcinek z celu z powrotem do startu
/// tą samą drogą (podejścia i zejścia liczone na odwróconym śladzie).
List<Odcinek> odcinki(Trasa trasa, PlanTrasy plan, {bool powrot = false}) {
  final indeksy = indeksyNaTrasie(trasa, plan.punkty);
  if (indeksy == null) return const [];
  final wynik = <Odcinek>[];
  var poczatek = 0;
  for (final k in plan.indeksyCelow) {
    final a = indeksy[poczatek], b = indeksy[k];
    final kawalek = trasa.punkty.sublist(a, b + 1);
    final (gora, dol) = sumaPrzewyzszen([
      for (final p in kawalek)
        if (p.wysokosc != null) p.wysokosc!,
    ]);
    wynik.add(Odcinek(
      odIndeksu: poczatek,
      doIndeksu: k,
      dlugosc: trasa.punkty[b].odStartu - trasa.punkty[a].odStartu,
      podejscia: gora,
      zejscia: dol,
    ));
    poczatek = k;
  }
  if (powrot && wynik.isNotEmpty) {
    final (gora, dol) = sumaPrzewyzszen([
      for (final p in trasa.punkty.reversed)
        if (p.wysokosc != null) p.wysokosc!,
    ]);
    wynik.add(Odcinek(
      odIndeksu: plan.dlugosc - 1,
      doIndeksu: 0,
      dlugosc: trasa.dlugosc,
      podejscia: gora,
      zejscia: dol,
      powrot: true,
    ));
  }
  return wynik;
}
