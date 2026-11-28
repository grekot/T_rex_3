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

  /// Najkrótsza trasa pieszo: bez premii za szlaki i bez kary za trudność ścieżki
  /// (w profilu ścieżka T3 kosztuje 2,56 razy więcej, więc trasa omijała skróty na szczyt).
  najkrocej('Najkrócej', 0, bezKaryZaTrudnosc: true),

  /// Na przełaj, po azymucie: bez BRoutera, z modelu terenu i przeszkód OSM (trasa/na_przelaj.dart).
  azymut('Azymut', -1);

  /// Czy trasę liczy BRouter (po drogach i ścieżkach z mapy).
  bool get poDrogach => this != azymut;

  const TrybTrasy(this.etykieta, this.preferencjaSzlakow, {this.bezKaryZaTrudnosc = false});

  final String etykieta;

  /// Parametr `hiking_routes_preference` profilu BRoutera `hiking-mountain`:
  /// koszt odcinków poza szlakiem × (1 + wartość).
  final double preferencjaSzlakow;

  /// Najwyższy dozwolony stopień trudności ścieżki (profil domyślnie: 3, czyli T4+ zakazane).
  static const limitTrudnosci = 6;

  /// Zeruje kary profilu za ścieżki trudniejsze lub łatwiejsze od T1 (`SAC_K1`, `SAC_K2`).
  final bool bezKaryZaTrudnosc;

  Map<String, String> get parametryBRoutera => {
    'hiking_routes_preference': '$preferencjaSzlakow',
    // szlaki T4–T6 dozwolone (decyzja 27.11; Tatry: Orla Perć, Rysy), aplikacja ostrzega
    'SAC_scale_limit': '$limitTrudnosci',
    if (bezKaryZaTrudnosc) ...{'SAC_K1': '0', 'SAC_K2': '0'},
  };
}

/// Opcja „unikaj stromych podejść”: każdy metr podejścia ponad nachylenie 15 % kosztuje
/// jak 120 m marszu po płaskim. Zejścia bez dodatkowego kosztu. Sprawdzone na trasach
/// w Beskidzie Wyspowym i Gorcach: największe nachylenie na 100 m spada z ok. 35–45 % do ok. 22–29 %.
const parametryUnikaniaStromych = {
  'consider_elevation': '1',
  'uphillcutoffvalue': '15',
  'uphillcostvalue': '120',
  'downhillcostvalue': '0',
};

/// Wszystkie parametry profilu BRoutera dla wybranego trybu i opcji.
Map<String, String> parametryTrasy(TrybTrasy tryb, {bool unikajStromych = false}) => {
  ...tryb.parametryBRoutera,
  if (unikajStromych) ...parametryUnikaniaStromych,
};

/// Tryby, które trzeba policzyć dla wybranego trybu; aplikacja bierze najkrótszy wynik.
///
/// Bez unikania stromych wystarcza sam wybrany tryb. Z unikaniem kara za strome podejścia
/// waży więcej niż długość: Szlakami nie zejdzie ze szlaku (poza nim 6 razy drożej), więc
/// zostaje przy stromym szlaku, a Najkrócej znajdzie łagodny, ale dłuższy objazd.
/// Przykład (Modyń od północy): Szlakami 1,88 km, Najkrócej 2,44 km. Dlatego tryb mniej
/// przywiązany do szlaków porównuje się z bardziej przywiązanymi: Najkrócej nigdy nie jest
/// dłuższa od Ze skrótami i Szlakami, a Ze skrótami od Szlakami.
List<TrybTrasy> trybyDoPorownania(TrybTrasy tryb, {bool unikajStromych = false}) => [
  tryb,
  if (unikajStromych)
    for (final t in TrybTrasy.values)
      if (t.preferencjaSzlakow > tryb.preferencjaSzlakow) t,
];

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

  /// Wstawia punkt pośredni ([RodzajPunktu.przez] albo [RodzajPunktu.przystanek]) między te dwa
  /// sąsiednie punkty, przy których najmniej wydłuża trasę w linii prostej
  /// (odl(A, nowy) + odl(nowy, B) − odl(A, B)), jak w OsmAnd.
  ///
  /// Wcześniej decydował najbliższy kawałek policzonej trasy, ale przy kilku punktach „przez”
  /// trasa ma zakręty i odnogi do poprzednich punktów, więc najbliższy kawałek należał często do
  /// innego odcinka: punkty ustawiały się w złej kolejności i trasa chodziła tam i z powrotem
  /// (Kotówka → Ćwilin, 28.11: 3,66 km zamiast 2,87 km, test w plan_test.dart).
  PlanTrasy wstaw(double lon, double lat, RodzajPunktu rodzaj, {String? nazwa}) {
    assert(rodzaj == RodzajPunktu.przez || rodzaj == RodzajPunktu.przystanek);
    if (punkty.length < 2) return dodajNaKoncu(lon, lat, nazwa: nazwa);
    final nowe = [...punkty]..insert(_miejsceNajmniejszyObjazd(lon, lat), PunktPlanu(lon, lat, rodzaj, nazwa: nazwa));
    return PlanTrasy(nowe);
  }

  int _miejsceNajmniejszyObjazd(double lon, double lat) {
    var najlepsze = 1;
    var najmniej = double.infinity;
    for (var i = 0; i + 1 < punkty.length; i++) {
      final a = punkty[i], b = punkty[i + 1];
      final objazd =
          odlegloscM(a.lat, a.lon, lat, lon) +
          odlegloscM(lat, lon, b.lat, b.lon) -
          odlegloscM(a.lat, a.lon, b.lat, b.lon);
      if (objazd < najmniej) {
        najmniej = objazd;
        najlepsze = i + 1;
      }
    }
    return najlepsze;
  }

  /// Przenosi punkt z miejsca [z] na miejsce [na] (indeks po przeniesieniu). Pierwszy punkt jest
  /// zawsze startem, ostatni celem; dawny start albo cel w środku listy zostaje przystankiem
  /// (był celem, więc dalej dzieli trasę), a punkty „przez” i przystanki zachowują rodzaj.
  PlanTrasy zmienKolejnosc(int z, int na) {
    if (z == na || z < 0 || na < 0 || z >= punkty.length || na >= punkty.length) return this;
    final nowe = [...punkty];
    nowe.insert(na, nowe.removeAt(z));
    for (var i = 0; i < nowe.length; i++) {
      final p = nowe[i];
      final rodzaj = i == 0
          ? RodzajPunktu.start
          : i == nowe.length - 1
          ? RodzajPunktu.cel
          : (p.rodzaj == RodzajPunktu.start || p.rodzaj == RodzajPunktu.cel)
          ? RodzajPunktu.przystanek
          : p.rodzaj;
      if (rodzaj != p.rodzaj) nowe[i] = p.jako(rodzaj);
    }
    return PlanTrasy(nowe);
  }

  PlanTrasy usun(int indeks) {
    final nowe = [...punkty]..removeAt(indeks);
    if (nowe.isEmpty) return const PlanTrasy();
    nowe[0] = nowe.first.jako(RodzajPunktu.start);
    if (nowe.length >= 2) nowe[nowe.length - 1] = nowe.last.jako(RodzajPunktu.cel);
    return PlanTrasy(nowe);
  }

  /// Przesuwa punkt w nowe miejsce. Rodzaj zostaje, nazwa jest z nowego miejsca (albo żadna).
  PlanTrasy przesun(int indeks, double lon, double lat, {String? nazwa}) {
    if (indeks < 0 || indeks >= punkty.length) return this;
    final nowe = [...punkty];
    nowe[indeks] = PunktPlanu(lon, lat, punkty[indeks].rodzaj, nazwa: nazwa);
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
    wynik.add(
      Odcinek(
        odIndeksu: poczatek,
        doIndeksu: k,
        dlugosc: trasa.punkty[b].odStartu - trasa.punkty[a].odStartu,
        podejscia: gora,
        zejscia: dol,
      ),
    );
    poczatek = k;
  }
  if (powrot && wynik.isNotEmpty) {
    final (gora, dol) = sumaPrzewyzszen([
      for (final p in trasa.punkty.reversed)
        if (p.wysokosc != null) p.wysokosc!,
    ]);
    wynik.add(
      Odcinek(
        odIndeksu: plan.dlugosc - 1,
        doIndeksu: 0,
        dlugosc: trasa.dlugosc,
        podejscia: gora,
        zejscia: dol,
        powrot: true,
      ),
    );
  }
  return wynik;
}
