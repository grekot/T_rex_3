import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../dane/katalog.dart';
import '../dane/magazyn.dart';
import '../dane/zrodlo.dart';
import '../konto/konto.dart';
import '../konto/trasy_w_chmurze.dart';
import '../konto/zapisana_trasa.dart';
import '../pamiec/pamiec.dart';
import '../mapa/mysz.dart';
import '../mapa/punkty_nazwane.dart';
import '../mapa/styl.dart';
import '../teren/model_terenu.dart';
import '../teren/pmtiles.dart';
import '../trasa/brouter.dart';
import '../trasa/na_przelaj.dart';
import '../trasa/plan.dart';
import '../trasa/trasa.dart';
import '../urzadzenie.dart';
import 'ekran_moich_tras.dart';
import 'ekran_regionow.dart';
import 'o_aplikacji.dart';
import 'panel_trasy.dart';

const _kolorTrasy = '#d81b60';
const _pustyGeojson = <String, dynamic>{'type': 'FeatureCollection', 'features': <dynamic>[]};

/// Mapa offline regionu z planowaniem trasy.
///
/// Przytrzymanie palca (w przeglądarce kliknięcie lewym przyciskiem): w tym miejscu pojawia się
/// kółko i menu z rodzajem punktu – start, cel, punkt „przez” (prowadź tędy), przystanek (cel
/// pośredni) albo nowy cel. W przeglądarce prawy przycisk przesuwa mapę (web/index.html).
/// Punkty trasy: lista w panelu albo dotknięcie punktu – zmiana rodzaju, usunięcie
/// albo „postaw w nowym miejscu” (następne dotknięcie mapy przenosi punkt).
/// BRouter liczy trasę (w telefonie offline, w przeglądarce przez brouter.de) w wybranym trybie (szlakami, ze skrótami, najkrócej),
/// opcjonalnie omijając strome podejścia.
/// Po zalogowaniu trasę można zapisać na koncie i otworzyć w telefonie albo w przeglądarce („Moje trasy”).
class EkranMapy extends StatefulWidget {
  const EkranMapy({super.key, required this.dane, required this.katalog, required this.region, this.otworz});

  final ZrodloDanych dane;
  final Katalog katalog;
  final RegionPaczki region;

  /// Zapisana trasa do pokazania od razu (otwarta z „Moich tras” w innym regionie).
  final ZapisanaTrasa? otworz;

  @override
  State<EkranMapy> createState() => _EkranMapyState();
}

class _EkranMapyState extends State<EkranMapy> {
  MapLibreMapController? _mapa;
  String? _styl;
  String? _bladStylu;
  bool _stylGotowy = false;
  bool _lokalizacja = false;
  bool _sledzi = false;
  PunktyNazwane? _nazwane;

  PlanTrasy _plan = const PlanTrasy();
  TrybTrasy _tryb = TrybTrasy.szlakami;
  bool _powrot = false;
  bool _unikajStromych = false;

  /// Punkt planu czekający na nowe miejsce (następne dotknięcie albo przytrzymanie mapy).
  int? _przenoszony;
  bool _rysujePunkty = false;
  bool _punktyDoOdswiezenia = false;

  /// Trasa „tam” z BRoutera; pokazywana [_trasa] to ona albo ona z powrotem.
  Trasa? _trasaTam;
  Trasa? _trasa;
  List<Odcinek> _odcinki = const [];
  bool _liczy = false;
  String? _bladTrasy;
  int _numerObliczenia = 0;

  /// Trasa z konta, którą teraz pokazujemy i zmieniamy („Zapisz zmiany” ją nadpisze).
  ZapisanaTrasa? _zapisana;

  /// Kamera ma objąć całą trasę, gdy mapa będzie gotowa.
  bool _dopasujKamere = false;

  /// Panel trasy zwinięty do jednego paska (cała mapa widoczna).
  bool _panelZwiniety = false;

  /// Punkt planu wskazany kursorem na liście punktów (podświetlony na mapie).
  int? _podswietlony;

  final _kluczPanelu = GlobalKey();
  final _kluczMenu = GlobalKey();
  final _kluczPozycji = GlobalKey();
  final _kluczPodpowiedzi = GlobalKey();
  TrasyWChmurze? _repo;

  @override
  void initState() {
    super.initState();
    if (widget.otworz case final t?) {
      _wczytajZapisana(t);
      _dopasujKamere = true;
    }
    _wczytajStyl();
    _wczytajPunkty();
    // w przeglądarce pytanie o lokalizację dopiero po dotknięciu „moja pozycja”
    if (!kIsWeb) _zapytajOLokalizacje();
  }

  Future<void> _wczytajStyl() async {
    try {
      final d = widget.dane;
      final szablon = await d.tekst(widget.katalog.styl.plik);
      final punkty = widget.region.punkty;
      setState(() {
        _styl = przygotujStyl(
          szablon,
          paczka: d.adres(widget.region.mapa.plik),
          szlaki: d.adres(widget.region.szlaki.plik),
          punkty: punkty == null ? null : d.adres(punkty.plik),
          poziomice: switch (widget.region.poziomice) {
            final p? => d.adres(p.plik),
            null => null,
          },
          teren: switch (widget.region.teren) {
            final p? => d.adres(p.plik),
            null => null,
          },
          glify: d.adresGlifow,
          sprite: d.adresSprite,
        );
      });
    } on Object catch (e) {
      setState(() => _bladStylu = 'Nie udało się wczytać stylu mapy: $e');
    }
  }

  Future<void> _wczytajPunkty() async {
    final p = widget.region.punkty;
    if (p == null) return;
    try {
      final tekst = await widget.dane.tekst(p.plik);
      _nazwane = PunktyNazwane.zGeojson(tekst);
    } on Object {
      // bez nazw przystanki dostaną tylko numery
    }
  }

  Future<void> _zapytajOLokalizacje() async {
    final zgoda = await Urzadzenie.poprosOLokalizacje();
    if (mounted) setState(() => _lokalizacja = zgoda);
  }

  Future<void> _poZaladowaniuStylu() async {
    final c = _mapa;
    if (c == null) return;
    await c.addGeoJsonSource('trasa', _pustyGeojson);
    await c.addLineLayer(
      'trasa',
      'trasa-obrys',
      const LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: 8,
        lineOpacity: 0.9,
        lineJoin: 'round',
        lineCap: 'round',
      ),
      enableInteraction: false,
    );
    await c.addLineLayer(
      'trasa',
      'trasa-linia',
      const LineLayerProperties(lineColor: _kolorTrasy, lineWidth: 5, lineJoin: 'round', lineCap: 'round'),
      enableInteraction: false,
    );
    // pod punktami: obwódka punktu wskazanego na liście
    await c.addGeoJsonSource('punkt-podswietlony', _pustyGeojson);
    await c.addCircleLayer(
      'punkt-podswietlony',
      'punkt-podswietlony-kolo',
      const CircleLayerProperties(
        circleRadius: 17,
        circleColor: '#ffd600',
        circleOpacity: 0.55,
        circleStrokeColor: '#ff6f00',
        circleStrokeWidth: 3,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource('punkty-trasy', _pustyGeojson);
    await c.addCircleLayer(
      'punkty-trasy',
      'punkty-trasy-kolka',
      const CircleLayerProperties(
        circleRadius: [
          'match',
          ['get', 'r'],
          'przez',
          5.5,
          8.5,
        ],
        circleColor: [
          'match',
          ['get', 'r'],
          'start',
          '#2e7d32',
          'cel',
          '#c62828',
          '#ffffff',
        ],
        circleStrokeColor: [
          'match',
          ['get', 'r'],
          'przystanek',
          _kolorTrasy,
          'przez',
          '#555555',
          '#ffffff',
        ],
        circleStrokeWidth: 3,
      ),
      enableInteraction: false,
    );
    await c.addSymbolLayer(
      'punkty-trasy',
      'punkty-trasy-numery',
      const SymbolLayerProperties(
        textField: ['get', 'nr'],
        textFont: ['NotoSans-Medium'],
        textSize: 11,
        textColor: _kolorTrasy,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    // na wierzchu: kółko w miejscu przytrzymania palca (kliknięcia), zanim wybierze się rodzaj punktu
    await c.addGeoJsonSource('punkt-kandydat', _pustyGeojson);
    await c.addCircleLayer(
      'punkt-kandydat',
      'punkt-kandydat-kolo',
      const CircleLayerProperties(
        circleRadius: 9,
        circleColor: '#ffffff',
        circleOpacity: 0.85,
        circleStrokeColor: _kolorTrasy,
        circleStrokeWidth: 3,
      ),
      enableInteraction: false,
    );
    setState(() => _stylGotowy = true);
    await _odswiezWarstwy();
    if (_dopasujKamere) await _pokazCalaTrase();
  }

  Map<String, dynamic> get _punktyGeojson {
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final (i, p) in _plan.punkty.indexed)
          {
            'type': 'Feature',
            'id': 'p$i',
            'properties': <String, dynamic>{'r': p.rodzaj.name, 'nr': _plan.numerPrzystanku(i)?.toString() ?? ''},
            'geometry': {
              'type': 'Point',
              'coordinates': [p.lon, p.lat],
            },
          },
      ],
    };
  }

  /// Rysuje punkty planu. Gdy rysowanie jeszcze trwa, zapamiętujemy tylko, że trzeba
  /// narysować jeszcze raz (zmiany mogą przychodzić szybciej, niż mapa nadąża).
  Future<void> _odswiezPunkty() async {
    final c = _mapa;
    if (c == null || !_stylGotowy) return;
    if (_rysujePunkty) {
      _punktyDoOdswiezenia = true;
      return;
    }
    _rysujePunkty = true;
    try {
      do {
        _punktyDoOdswiezenia = false;
        await c.setGeoJsonSource('punkty-trasy', _punktyGeojson);
      } while (_punktyDoOdswiezenia);
    } finally {
      _rysujePunkty = false;
    }
  }

  Future<void> _odswiezWarstwy() async {
    final c = _mapa;
    if (c == null || !_stylGotowy) return;
    await _odswiezPunkty();
    await c.setGeoJsonSource('trasa', _trasa?.geojson ?? _pustyGeojson);
  }

  /// Stawia przenoszony punkt [i] w miejscu [p] (przyciąga się do nazwanego obiektu w pobliżu).
  void _postawPunkt(int i, LatLng p) {
    setState(() => _przenoszony = null);
    if (!widget.region.zawiera(p.longitude, p.latitude)) {
      _komunikat('Ten punkt leży poza pobranym regionem.');
      return;
    }
    if (i >= _plan.dlugosc) return;
    final (x, y, nazwa) = _przyciagnij(p);
    _ustawPlan(_plan.przesun(i, x, y, nazwa: nazwa));
  }

  void _przenies(int i) => setState(() => _przenoszony = i);

  /// Przy nazwanym obiekcie (np. schronisku) punkt trafia dokładnie w niego i dostaje jego nazwę.
  (double, double, String?) _przyciagnij(LatLng p) {
    final obiekt = _nazwane?.najblizszy(p.longitude, p.latitude);
    return obiekt == null ? (p.longitude, p.latitude, null) : (obiekt.lon, obiekt.lat, obiekt.opis);
  }

  void _ustawPlan(PlanTrasy plan) {
    setState(() {
      _plan = plan;
      _przenoszony = null;
      _bladTrasy = null;
      if (plan.dlugosc < 2) {
        _trasaTam = null;
        _trasa = null;
        _odcinki = const [];
      }
    });
    _przelicz();
  }

  /// W przeglądarce mapa (element HTML pod Flutterem) dostaje też kliknięcia w panel, przyciski
  /// i menu. Dlatego każde dotknięcie nakładki zapisuje czas, a mapa ignoruje kliknięcia
  /// tuż po nim (zdarzenie „click” przychodzi po puszczeniu przycisku, „dblclick” po drugim).
  DateTime _dotykNakladki = DateTime(2000);

  /// Ile okien (arkuszy, dialogów, ekranów) leży teraz nad mapą. Licznik, nie flaga: pozycja menu
  /// zamyka arkusz i od razu otwiera następne okno, a arkusz kończy się dopiero po chwili.
  int _otwarteOkna = 0;

  bool get _klikDlaNakladki =>
      _otwarteOkna > 0 || DateTime.now().difference(_dotykNakladki) < const Duration(milliseconds: 500);

  Widget _nakladka(GlobalKey klucz, Widget child) =>
      Listener(key: klucz, onPointerDown: (_) => _dotykNakladki = DateTime.now(), child: child);

  /// Ostatnio wysłane stronie położenie nakładek (przeglądarka), żeby nie wysyłać tego samego.
  String _wyslaneNakladki = '';

  Rect? _prostokat(GlobalKey klucz) {
    final box = klucz.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Mówi stronie (web/index.html), gdzie są panel i przyciski oraz czy okno zakrywa mapę:
  /// tam kółko i prawy przycisk nie działają na mapę.
  void _odswiezNakladki() {
    if (!kIsWeb || !mounted) return;
    final prostokaty = [
      for (final k in [_kluczPanelu, _kluczMenu, _kluczPozycji, _kluczPodpowiedzi]) ?_prostokat(k),
    ];
    final okno = _otwarteOkna > 0;
    final opis = '$okno $prostokaty';
    if (opis == _wyslaneNakladki) return;
    _wyslaneNakladki = opis;
    ustawNakladki(prostokaty, okno: okno);
  }

  Future<T> _okno<T>(Future<T> Function() otworz) async {
    _otwarteOkna++;
    _odswiezNakladki();
    try {
      return await otworz();
    } finally {
      // kliknięcie, które zamknęło okno, dociera do mapy chwilę później
      _otwarteOkna--;
      _dotykNakladki = DateTime.now();
      _odswiezNakladki();
    }
  }

  Future<T?> _arkusz<T>(WidgetBuilder builder) =>
      _okno(() => showModalBottomSheet<T>(context: context, builder: builder));

  /// Przytrzymanie palca (telefon): kółko w tym miejscu i menu z rodzajem punktu, jak kliknięcie w przeglądarce.
  Future<void> _przytrzymanie(Point<double> ekran, LatLng p) async {
    if (_klikDlaNakladki) return;
    if (_przenoszony case final i?) return _postawPunkt(i, p);
    HapticFeedback.mediumImpact();
    await _menuMapy(ekran, p);
  }

  /// Dodaje punkt wybranego rodzaju: start, cel (przedłuża trasę), przez, przystanek
  /// albo „nowyStart” (start przeniesiony w to miejsce).
  void _dodajPunkt(String? wybor, double x, double y, String? nazwa) {
    if (wybor == null) return;
    _ustawPlan(switch (wybor) {
      'przez' => _plan.wstaw(x, y, RodzajPunktu.przez, nazwa: nazwa, trasa: _trasaTam),
      'przystanek' => _plan.wstaw(x, y, RodzajPunktu.przystanek, nazwa: nazwa, trasa: _trasaTam),
      'nowyStart' => _plan.przesun(0, x, y, nazwa: nazwa),
      _ => _plan.dodajNaKoncu(x, y, nazwa: nazwa),
    });
  }

  /// Punkt planu pod miejscem kliknięcia (do ok. 28 px), jeśli jest.
  Future<int?> _punktPod(Point<double> ekran) async {
    final c = _mapa;
    if (c == null || _plan.pusty) return null;
    final naEkranie = await c.toScreenLocationBatch([for (final q in _plan.punkty) LatLng(q.lat, q.lon)]);
    if (!mounted) return null;
    final prog = 28 * MediaQuery.devicePixelRatioOf(context);
    int? trafiony;
    var najblizej = double.infinity;
    for (final (i, q) in naEkranie.indexed) {
      final d = sqrt(pow(q.x - ekran.x, 2) + pow(q.y - ekran.y, 2));
      if (d < prog && d < najblizej) {
        najblizej = d;
        trafiony = i;
      }
    }
    return trafiony;
  }

  /// Dotknięcie mapy: stawia przenoszony punkt, a jeśli blisko punktu trasy – menu tego punktu.
  /// W przeglądarce kliknięcie w puste miejsce otwiera menu „jaki punkt postawić”.
  Future<void> _klikniecie(Point<double> ekran, LatLng p) async {
    if (_klikDlaNakladki) return;
    if (_przenoszony case final i?) return _postawPunkt(i, p);
    final trafiony = await _punktPod(ekran);
    if (!mounted) return;
    if (trafiony != null) return _menuPunktu(trafiony);
    if (kIsWeb) await _menuMapy(ekran, p);
  }

  /// Kółko w miejscu, gdzie stanie nowy punkt (null = schowaj).
  Future<void> _pokazKandydata((double, double)? miejsce) async {
    final c = _mapa;
    if (c == null || !_stylGotowy) return;
    await c.setGeoJsonSource(
      'punkt-kandydat',
      miejsce == null
          ? _pustyGeojson
          : {
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [miejsce.$1, miejsce.$2],
                  },
                },
              ],
            },
    );
  }

  /// Menu podręczne w miejscu kliknięcia (przeglądarka) albo przytrzymania palca (telefon):
  /// najpierw kółko w tym miejscu (przyciągnięte do nazwanego obiektu), potem rodzaj punktu.
  Future<void> _menuMapy(Point<double> ekran, LatLng p) async {
    if (!widget.region.zawiera(p.longitude, p.latitude)) {
      _komunikat('Ten punkt leży poza regionem mapy.');
      return;
    }
    final (x, y, nazwa) = _przyciagnij(p);
    await _pokazKandydata((x, y));
    if (!mounted) return;
    final opcje = <(String, IconData, String)>[
      if (_plan.pusty) ('cel', Icons.trip_origin, 'Start trasy'),
      if (_plan.dlugosc == 1) ...[
        ('cel', Icons.place_outlined, 'Cel trasy'),
        ('nowyStart', Icons.trip_origin, 'Przenieś start tutaj'),
      ],
      if (_plan.dlugosc >= 2) ...[
        ('przez', Icons.alt_route, 'Prowadź tędy'),
        ('przystanek', Icons.flag_outlined, 'Przystanek po drodze'),
        ('cel', Icons.add_location_alt_outlined, 'Nowy cel – przedłuż trasę'),
      ],
    ];
    final rozmiar = MediaQuery.sizeOf(context);
    // w telefonie mapa podaje piksele fizyczne, w przeglądarce logiczne
    final skala = kIsWeb ? 1.0 : MediaQuery.devicePixelRatioOf(context);
    final ex = ekran.x / skala, ey = ekran.y / skala;
    final wybor = await _okno(
      () => showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(ex, ey, rozmiar.width - ex, rozmiar.height - ey),
        items: [
          if (nazwa != null)
            PopupMenuItem<String>(enabled: false, child: Text(nazwa, style: Theme.of(context).textTheme.titleSmall)),
          for (final (wartosc, ikona, tekst) in opcje)
            PopupMenuItem<String>(
              value: wartosc,
              child: Row(children: [Icon(ikona, size: 20), const SizedBox(width: 12), Text(tekst)]),
            ),
        ],
      ),
    );
    if (!mounted) return;
    await _pokazKandydata(null);
    _dodajPunkt(wybor, x, y, nazwa);
  }

  /// Wskazanie punktu na liście: podświetla go na mapie, a gdy jest poza widokiem (albo pod
  /// panelem) – przesuwa mapę tak, żeby był widać.
  Future<void> _podswietl(int? i) async {
    if (_podswietlony == i) return;
    _podswietlony = i;
    final c = _mapa;
    if (c == null || !_stylGotowy) return;
    final punkt = (i == null || i >= _plan.dlugosc) ? null : _plan.punkty[i];
    await c.setGeoJsonSource(
      'punkt-podswietlony',
      punkt == null
          ? _pustyGeojson
          : {
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [punkt.lon, punkt.lat],
                  },
                },
              ],
            },
    );
    if (punkt == null || !mounted || _podswietlony != i) return;
    // w telefonie współrzędne ekranu są w pikselach fizycznych, w przeglądarce w logicznych
    final skala = kIsWeb ? 1.0 : MediaQuery.devicePixelRatioOf(context);
    final naEkranie = await c.toScreenLocation(LatLng(punkt.lat, punkt.lon));
    if (!mounted || _podswietlony != i) return;
    final rozmiar = MediaQuery.sizeOf(context);
    final panel = _kluczPanelu.currentContext?.findRenderObject();
    final gora = 72.0;
    final dol = rozmiar.height - (panel is RenderBox && panel.hasSize ? panel.size.height : 0) - 8;
    const margines = 40.0;
    final x = naEkranie.x / skala, y = naEkranie.y / skala;
    if (x >= margines && x <= rozmiar.width - margines && y >= gora && y <= dol - margines) return;
    // przesunięcie: punkt na środek widocznej części mapy (nad panelem)
    final dx = x - rozmiar.width / 2, dy = y - (gora + dol) / 2;
    final srodek = await c.toLatLng(Point((rozmiar.width / 2 + dx) * skala, (rozmiar.height / 2 + dy) * skala));
    if (!mounted || _podswietlony != i) return;
    await c.animateCamera(CameraUpdate.newLatLng(srodek), duration: const Duration(milliseconds: 300));
  }

  Future<void> _menuPunktu(int i) async {
    final p = _plan.punkty[i];
    final posredni = i > 0 && i < _plan.dlugosc - 1;
    final wybor = await _arkusz<String>(
      (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(nazwaPunktu(_plan, i, powrot: _powrot), style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: const Text('Postaw w nowym miejscu'),
              subtitle: const Text('Potem dotknij mapy tam, gdzie ma być punkt.'),
              onTap: () => Navigator.pop(ctx, 'przenies'),
            ),
            if (posredni && p.rodzaj == RodzajPunktu.przez)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Zmień na przystanek'),
                onTap: () => Navigator.pop(ctx, 'przystanek'),
              ),
            if (posredni && p.rodzaj == RodzajPunktu.przystanek)
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: const Text('Zmień na „prowadź tędy”'),
                subtitle: const Text('Bez przystanku i odliczania'),
                onTap: () => Navigator.pop(ctx, 'przez'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Usuń punkt'),
              onTap: () => Navigator.pop(ctx, 'usun'),
            ),
          ],
        ),
      ),
    );
    switch (wybor) {
      case 'przystanek':
        _ustawPlan(_plan.zmienRodzaj(i, RodzajPunktu.przystanek));
      case 'przez':
        _ustawPlan(_plan.zmienRodzaj(i, RodzajPunktu.przez));
      case 'przenies':
        _przenies(i);
      case 'usun':
        _ustawPlan(_plan.usun(i));
    }
  }

  void _wyczysc() {
    _numerObliczenia++;
    setState(() {
      _plan = const PlanTrasy();
      _przenoszony = null;
      _trasaTam = null;
      _trasa = null;
      _odcinki = const [];
      _bladTrasy = null;
      _liczy = false;
      _zapisana = null;
    });
    _odswiezWarstwy();
  }

  /// Powrót nie wymaga ponownego liczenia: to ten sam ślad w odwrotnej kolejności.
  void _zmienPowrot(bool powrot) {
    setState(() {
      _powrot = powrot;
      _ustawTrase(_trasaTam);
    });
    _odswiezWarstwy();
  }

  void _ustawTrase(Trasa? tam) {
    _trasaTam = tam;
    _trasa = tam == null ? null : (_powrot ? tam.zPowrotem() : tam);
    _odcinki = tam == null ? const [] : odcinki(tam, _plan, powrot: _powrot);
  }

  void _zmienTryb(TrybTrasy tryb) {
    setState(() => _tryb = tryb);
    _przelicz();
  }

  void _zmienUnikanieStromych(bool unikaj) {
    setState(() => _unikajStromych = unikaj);
    _przelicz();
  }

  /// Model terenu i przeszkody regionu do trasy na przełaj (wczytywane przy pierwszym użyciu).
  ModelTerenu? _model;
  Przeszkody? _przeszkody;

  Future<Trasa> _trasaNaPrzelaj(List<(double, double)> punkty) async {
    final r = widget.region;
    final teren = r.teren;
    if (teren == null) {
      throw BladPrzelaju('Ten region nie ma jeszcze modelu terenu. Zaktualizuj go w „Regionach map”.');
    }
    final d = widget.dane;
    _model ??= ModelTerenu(PMTiles((od, dl) => d.zakres(teren.plik, od, dl)));
    if (_przeszkody == null) {
      final p = r.przeszkody;
      _przeszkody = p == null ? Przeszkody.pusty : Przeszkody.zGeojson(await d.tekst(p.plik));
    }
    return trasaNaPrzelaj(
      punkty,
      model: _model!,
      przeszkody: _przeszkody!,
      ustawienia: _unikajStromych ? const UstawieniaPrzelaju.lagodnie() : const UstawieniaPrzelaju(),
    );
  }

  Future<void> _przelicz() async {
    final numer = ++_numerObliczenia;
    await _odswiezWarstwy();
    if (_plan.dlugosc < 2) return;
    setState(() => _liczy = true);
    final plan = _plan;
    try {
      final trasa = _tryb.poDrogach
          ? await widget.dane.trasownik.oblicz(plan.wspolrzedne, tryb: _tryb, unikajStromych: _unikajStromych)
          : await _trasaNaPrzelaj(plan.wspolrzedne);
      if (numer != _numerObliczenia || !mounted) return;
      setState(() {
        _ustawTrase(trasa);
        _liczy = false;
      });
    } on BladPrzelaju catch (e) {
      if (numer != _numerObliczenia || !mounted) return;
      setState(() {
        _bladTrasy = e.komunikat;
        _liczy = false;
      });
    } on BladTrasy catch (e) {
      if (numer != _numerObliczenia || !mounted) return;
      setState(() {
        _bladTrasy = e.komunikat;
        _liczy = false;
      });
    } on Object catch (e) {
      // np. brak pliku terenu na serwerze: komunikat zamiast kręcącego się paska
      if (numer != _numerObliczenia || !mounted) return;
      setState(() {
        _bladTrasy = 'Nie udało się wyznaczyć trasy: $e';
        _liczy = false;
      });
    }
    await _odswiezWarstwy();
  }

  Future<void> _mojaPozycja() async {
    if (!_lokalizacja) {
      await _zapytajOLokalizacje();
      if (!_lokalizacja) {
        _komunikat('Bez zgody na lokalizację mapa nie pokaże Twojej pozycji.');
        return;
      }
    }
    setState(() => _sledzi = true);
    await _mapa?.updateMyLocationTrackingMode(MyLocationTrackingMode.trackingCompass);
  }

  void _komunikat(String tekst) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tekst)));
  }

  /// Regiony, na które można przełączyć mapę: w telefonie pobrane, w przeglądarce wszystkie z serwera.
  List<RegionPaczki> get _inneRegiony => [
    for (final r in switch (widget.dane) {
      final Magazyn m => m.gotoweRegiony(widget.katalog),
      _ => widget.katalog.regiony,
    })
      if (r.id != widget.region.id) r,
  ];

  Future<void> _przelaczRegion(RegionPaczki r, {ZapisanaTrasa? otworz}) async {
    if (widget.dane case final Magazyn m) await m.ustawAktywny(r.id);
    zapiszUstawienie('region', r.id);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EkranMapy(dane: widget.dane, katalog: widget.katalog, region: r, otworz: otworz),
      ),
    );
  }

  // ---- konto i zapisane trasy ----

  TrasyWChmurze? get _chmura {
    final u = Konto.uzytkownik;
    if (u == null) return null;
    if (_repo?.uid != u.uid) {
      _repo = TrasyWChmurze(u.uid, u.email ?? '')
        ..onBladZapisu = (e) {
          if (mounted) _komunikat('Serwer nie przyjął zapisu trasy: $e');
        };
    }
    return _repo;
  }

  /// Repozytorium tras zalogowanego użytkownika; gdy nikt nie jest zalogowany – najpierw logowanie.
  Future<TrasyWChmurze?> _kontoTras() async {
    if (!Konto.dostepne) return null;
    if (Konto.uzytkownik == null) {
      final zalogowany = await _okno(() => zaloguj(context));
      if (!zalogowany || !mounted) return null;
    }
    return _chmura;
  }

  Future<void> _zaloguj() async {
    if (await _kontoTras() != null && mounted) {
      _komunikat('Zalogowano: ${Konto.uzytkownik?.email ?? ''}. Trasę zapiszesz przyciskiem „Zapisz” w panelu trasy.');
    }
  }

  Future<void> _wyloguj() async {
    await Konto.wyloguj();
    if (mounted) _komunikat('Wylogowano. Zapisane trasy zostają na koncie.');
  }

  Future<void> _zapisz() async {
    final tam = _trasaTam;
    if (tam == null || _liczy || _bladTrasy != null) {
      _komunikat('Najpierw trasa musi się policzyć.');
      return;
    }
    final chmura = await _kontoTras();
    if (chmura == null || !mounted) return;
    final z = _zapisana;
    final wynik = await _okno(
      () => oknoZapisu(context, nazwa: z?.nazwa ?? proponowanaNazwa(_plan, DateTime.now()), zapisana: z != null),
    );
    if (wynik == null || !mounted) return;
    final (nazwa, jakoNowa) = wynik;
    final t = ZapisanaTrasa(
      id: jakoNowa ? null : z?.id,
      nazwa: nazwa,
      region: widget.region.id,
      plan: _plan,
      tryb: _tryb,
      powrot: _powrot,
      unikajStromych: _unikajStromych,
      tam: tam,
    );
    try {
      final id = await chmura.zapisz(t);
      if (!mounted) return;
      setState(() => _zapisana = t.zmien(id: id));
      _komunikat('Zapisano „$nazwa”. Znajdziesz ją w „Moich trasach” w telefonie i w przeglądarce.');
    } on Object catch (e) {
      if (mounted) _komunikat('Nie udało się zapisać trasy: $e');
    }
  }

  Future<void> _mojeTrasy() async {
    final chmura = await _kontoTras();
    if (chmura == null || !mounted) return;
    final id = await _okno(
      () => Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => EkranMoichTras(chmura: chmura, katalog: widget.katalog),
        ),
      ),
    );
    if (id == null || !mounted) return;
    final ZapisanaTrasa? t;
    try {
      t = await chmura.wczytaj(id);
    } on Object catch (e) {
      if (mounted) _komunikat('Nie udało się wczytać trasy: $e');
      return;
    }
    if (t == null || !mounted) return;
    if (t.region == widget.region.id) return _otworz(t);
    final r = widget.katalog.region(t.region);
    if (r == null) {
      _komunikat('Trasa „${t.nazwa}” jest z regionu, którego nie ma w katalogu map.');
    } else if (!_inneRegiony.any((x) => x.id == r.id)) {
      _komunikat('Trasa „${t.nazwa}” leży w regionie ${r.nazwa}. Pobierz go w „Regionach map”.');
    } else {
      await _przelaczRegion(r, otworz: t);
    }
  }

  void _wczytajZapisana(ZapisanaTrasa t) {
    _numerObliczenia++;
    _plan = t.plan;
    _tryb = t.tryb;
    _powrot = t.powrot;
    _unikajStromych = t.unikajStromych;
    _przenoszony = null;
    _bladTrasy = null;
    _liczy = false;
    _zapisana = t;
    _ustawTrase(t.tam);
  }

  /// Pokazuje zapisaną trasę bez ponownego liczenia (ślad jest w zapisie).
  Future<void> _otworz(ZapisanaTrasa t) async {
    setState(() => _wczytajZapisana(t));
    await _odswiezWarstwy();
    await _pokazCalaTrase();
  }

  Future<void> _pokazCalaTrase() async {
    final c = _mapa, t = _trasa;
    if (c == null || !_stylGotowy || t == null || t.punkty.isEmpty) {
      _dopasujKamere = true;
      return;
    }
    _dopasujKamere = false;
    var s = t.punkty.first.lat, n = s, w = t.punkty.first.lon, e = w;
    for (final p in t.punkty) {
      s = min(s, p.lat);
      n = max(n, p.lat);
      w = min(w, p.lon);
      e = max(e, p.lon);
    }
    // panel trasy zajmuje do połowy ekranu od dołu
    final dol = MediaQuery.sizeOf(context).height * 0.5 + 16;
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)),
        left: 40,
        top: 72,
        right: 40,
        bottom: dol,
      ),
    );
  }

  void _menu() {
    _arkusz<void>(
      // przy kilku regionach lista jest dłuższa niż arkusz: przewijana
      (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: Text(widget.region.nazwa),
                subtitle: Text('Dane OSM z ${widget.katalog.daneOsm}'),
              ),
              if (Konto.dostepne) ...[
                if (Konto.uzytkownik case final u?) ...[
                  ListTile(
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: const Text('Moje trasy'),
                    subtitle: const Text('Zapisane na koncie: w telefonie i w przeglądarce'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _mojeTrasy();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Wyloguj'),
                    subtitle: Text(u.email ?? ''),
                    onTap: () {
                      Navigator.pop(ctx);
                      _wyloguj();
                    },
                  ),
                ] else
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Zaloguj się'),
                    subtitle: const Text('Zapisywanie tras: wspólne dla telefonu i przeglądarki'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _zaloguj();
                    },
                  ),
              ],
              for (final inny in _inneRegiony)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text('Przełącz na: ${inny.nazwa}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _przelaczRegion(inny);
                  },
                ),
              if (widget.dane case final Magazyn magazyn)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Regiony map'),
                  subtitle: const Text('Pobieranie, aktualizacja i usuwanie'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(
                      context,
                    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => EkranRegionow(magazyn: magazyn)));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('O aplikacji i licencje'),
                onTap: () {
                  Navigator.pop(ctx);
                  pokazOAplikacji(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final styl = _styl;
    final r = widget.region;
    return Scaffold(
      body: Builder(
        builder: (context) {
          // przeglądarka: po każdym rysowaniu strona dostaje położenie paneli i przycisków
          // (także po zmianie rozmiaru okna: zależność od MediaQuery przebudowuje ten fragment)
          MediaQuery.sizeOf(context);
          if (kIsWeb) WidgetsBinding.instance.addPostFrameCallback((_) => _odswiezNakladki());
          return Stack(
            children: [
              if (styl != null)
                MapLibreMap(
                  styleString: styl,
                  initialCameraPosition: CameraPosition(target: LatLng(r.srodekLat, r.srodekLon), zoom: 11),
                  minMaxZoomPreference: const MinMaxZoomPreference(7, 18),
                  // w przeglądarce kompas MapLibre wchodził pod przycisk pozycji (bez marginesów na webie)
                  compassEnabled: !kIsWeb,
                  compassViewPosition: CompassViewPosition.topRight,
                  compassViewMargins: const Point(16, 96),
                  attributionButtonPosition: AttributionButtonPosition.bottomLeft,
                  myLocationEnabled: _lokalizacja,
                  myLocationTrackingMode: MyLocationTrackingMode.none,
                  myLocationRenderMode: _lokalizacja ? MyLocationRenderMode.compass : MyLocationRenderMode.normal,
                  onMapCreated: (c) => _mapa = c,
                  onStyleLoadedCallback: _poZaladowaniuStylu,
                  // w przeglądarce punkt stawia menu po kliknięciu (_menuMapy)
                  onMapLongClick: kIsWeb ? null : _przytrzymanie,
                  onMapClick: _klikniecie,
                  featureTapsTriggersMapClick: true,
                  onCameraTrackingDismissed: () => setState(() => _sledzi = false),
                )
              else
                Center(child: _bladStylu == null ? const CircularProgressIndicator() : Text(_bladStylu!)),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _nakladka(
                      _kluczMenu,
                      FloatingActionButton.small(heroTag: 'menu', onPressed: _menu, child: const Icon(Icons.menu)),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _nakladka(
                      _kluczPozycji,
                      FloatingActionButton.small(
                        heroTag: 'pozycja',
                        onPressed: _mojaPozycja,
                        child: Icon(_sledzi ? Icons.my_location : Icons.location_searching),
                      ),
                    ),
                  ),
                ),
              ),
              if (_plan.pusty && _stylGotowy)
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: _nakladka(
                        _kluczPodpowiedzi,
                        Chip(
                          avatar: Icon(kIsWeb ? Icons.mouse_outlined : Icons.touch_app, size: 18),
                          label: Text(
                            !kIsWeb
                                ? '$gestDodawania na mapie, aby zacząć trasę'
                                // wąski ekran (telefon w przeglądarce): bez myszy, krótko
                                : MediaQuery.sizeOf(context).width < 600
                                ? 'Kliknij mapę, aby zacząć trasę'
                                : 'Kliknij mapę, aby zacząć trasę. Prawy przycisk przesuwa mapę.',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!_plan.pusty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    // przeglądarka: kliknięcia w panel nie mogą trafiać do mapy pod nim
                    child: _nakladka(
                      _kluczPanelu,
                      PanelTrasy(
                        plan: _plan,
                        trasa: _trasa,
                        odcinki: _odcinki,
                        tryb: _tryb,
                        powrot: _powrot,
                        unikajStromych: _unikajStromych,
                        liczy: _liczy,
                        blad: _bladTrasy,
                        onTryb: _zmienTryb,
                        onPowrot: _zmienPowrot,
                        onUnikajStromych: _zmienUnikanieStromych,
                        przenoszony: _przenoszony,
                        onPunkt: _menuPunktu,
                        onPrzenies: _przenies,
                        onUsun: (i) => _ustawPlan(_plan.usun(i)),
                        onAnulujPrzenoszenie: () => setState(() => _przenoszony = null),
                        onCofnij: () => _ustawPlan(_plan.cofnij()),
                        onWyczysc: _wyczysc,
                        nazwaZapisanej: _zapisana?.nazwa,
                        onZapisz: Konto.dostepne ? _zapisz : null,
                        zwiniety: _panelZwiniety,
                        onZwin: (z) {
                          setState(() => _panelZwiniety = z);
                          _podswietl(null);
                        },
                        podswietlony: _podswietlony,
                        onPodswietl: _podswietl,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
