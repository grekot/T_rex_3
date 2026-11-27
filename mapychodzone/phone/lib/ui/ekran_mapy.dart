import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../dane/katalog.dart';
import '../dane/magazyn.dart';
import '../dane/zrodlo.dart';
import '../pamiec/pamiec.dart';
import '../mapa/punkty_nazwane.dart';
import '../mapa/styl.dart';
import '../teren/model_terenu.dart';
import '../teren/pmtiles.dart';
import '../trasa/brouter.dart';
import '../trasa/na_przelaj.dart';
import '../trasa/plan.dart';
import '../trasa/trasa.dart';
import '../urzadzenie.dart';
import 'ekran_regionow.dart';
import 'o_aplikacji.dart';
import 'panel_trasy.dart';

const _kolorTrasy = '#d81b60';
const _pustyGeojson = <String, dynamic>{'type': 'FeatureCollection', 'features': <dynamic>[]};

/// Mapa offline regionu z planowaniem trasy.
///
/// Przytrzymanie palca: start, potem cel, potem wybór – punkt „przez” (prowadź tędy),
/// przystanek (cel pośredni) albo nowy cel. W przeglądarce zamiast przytrzymania: podwójne kliknięcie.
/// Punkty trasy: lista w panelu albo dotknięcie punktu – zmiana rodzaju, usunięcie
/// albo „postaw w nowym miejscu” (następne dotknięcie mapy przenosi punkt).
/// BRouter liczy trasę (w telefonie offline, w przeglądarce przez brouter.de) w wybranym trybie (szlakami, ze skrótami, najkrócej),
/// opcjonalnie omijając strome podejścia.
class EkranMapy extends StatefulWidget {
  const EkranMapy({super.key, required this.dane, required this.katalog, required this.region});

  final ZrodloDanych dane;
  final Katalog katalog;
  final RegionPaczki region;

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

  @override
  void initState() {
    super.initState();
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
    setState(() => _stylGotowy = true);
    await _odswiezWarstwy();
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
  bool _arkuszOtwarty = false;

  bool get _klikDlaNakladki =>
      _arkuszOtwarty || DateTime.now().difference(_dotykNakladki) < const Duration(milliseconds: 500);

  Widget _nakladka({required Widget child}) =>
      Listener(onPointerDown: (_) => _dotykNakladki = DateTime.now(), child: child);

  Future<T?> _arkusz<T>(WidgetBuilder builder) async {
    _arkuszOtwarty = true;
    try {
      return await showModalBottomSheet<T>(context: context, builder: builder);
    } finally {
      // kliknięcie, które zamknęło arkusz, dociera do mapy chwilę później
      _arkuszOtwarty = false;
      _dotykNakladki = DateTime.now();
    }
  }

  Future<void> _przytrzymanie(LatLng p) async {
    if (_klikDlaNakladki) return;
    if (_przenoszony case final i?) return _postawPunkt(i, p);
    final lon = p.longitude, lat = p.latitude;
    if (!widget.region.zawiera(lon, lat)) {
      _komunikat('Ten punkt leży poza pobranym regionem.');
      return;
    }
    final (x, y, nazwa) = _przyciagnij(p);
    if (_plan.dlugosc < 2) {
      _ustawPlan(_plan.dodajNaKoncu(x, y, nazwa: nazwa));
      return;
    }
    final wybor = await _arkusz<String>(
      (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (nazwa != null) ListTile(title: Text(nazwa, style: Theme.of(ctx).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(Icons.alt_route),
              title: const Text('Prowadź tędy'),
              subtitle: const Text('Trasa przejdzie przez ten punkt. To nie jest cel: bez przystanku i odliczania.'),
              onTap: () => Navigator.pop(ctx, 'przez'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Przystanek po drodze'),
              subtitle: const Text('Cel pośredni, np. schronisko. Trasa dzieli się tu na odcinki.'),
              onTap: () => Navigator.pop(ctx, 'przystanek'),
            ),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: const Text('Nowy cel – przedłuż trasę'),
              subtitle: const Text('Dotychczasowy cel stanie się przystankiem.'),
              onTap: () => Navigator.pop(ctx, 'cel'),
            ),
          ],
        ),
      ),
    );
    if (wybor == null) return;
    _ustawPlan(switch (wybor) {
      'przez' => _plan.wstaw(x, y, RodzajPunktu.przez, nazwa: nazwa, trasa: _trasaTam),
      'przystanek' => _plan.wstaw(x, y, RodzajPunktu.przystanek, nazwa: nazwa, trasa: _trasaTam),
      _ => _plan.dodajNaKoncu(x, y, nazwa: nazwa),
    });
  }

  /// Dotknięcie mapy: stawia przenoszony punkt, a jeśli blisko punktu trasy – menu tego punktu.
  Future<void> _klikniecie(Point<double> ekran, LatLng p) async {
    if (_klikDlaNakladki) return;
    if (_przenoszony case final i?) return _postawPunkt(i, p);
    final c = _mapa;
    if (c == null || _plan.pusty) return;
    final naEkranie = await c.toScreenLocationBatch([for (final q in _plan.punkty) LatLng(q.lat, q.lon)]);
    if (!mounted) return;
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
    if (trafiony != null) await _menuPunktu(trafiony);
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

  Future<void> _przelaczRegion(RegionPaczki r) async {
    if (widget.dane case final Magazyn m) await m.ustawAktywny(r.id);
    zapiszUstawienie('region', r.id);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EkranMapy(dane: widget.dane, katalog: widget.katalog, region: r),
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
      body: Stack(
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
              onMapLongClick: (_, p) => _przytrzymanie(p),
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
                  child: FloatingActionButton.small(heroTag: 'menu', onPressed: _menu, child: const Icon(Icons.menu)),
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
                  child: FloatingActionButton.small(
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
                  child: Chip(
                    avatar: const Icon(Icons.touch_app, size: 18),
                    label: Text('$gestDodawania na mapie, aby zacząć trasę'),
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
                  child: PanelTrasy(
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
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
