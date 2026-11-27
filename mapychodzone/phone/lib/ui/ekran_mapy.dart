import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../dane/katalog.dart';
import '../dane/magazyn.dart';
import '../mapa/punkty_nazwane.dart';
import '../mapa/styl.dart';
import '../trasa/brouter.dart';
import '../trasa/plan.dart';
import '../trasa/trasa.dart';
import '../urzadzenie.dart';
import 'ekran_pobierania.dart';
import 'o_aplikacji.dart';
import 'panel_trasy.dart';

const _kolorTrasy = '#d81b60';
const _pustyGeojson = <String, dynamic>{'type': 'FeatureCollection', 'features': <dynamic>[]};

/// Mapa offline regionu z planowaniem trasy.
///
/// Przytrzymanie palca: start, potem cel, potem wybór – punkt „przez” (prowadź tędy),
/// przystanek (cel pośredni) albo nowy cel. Dotknięcie punktu: zmiana rodzaju albo usunięcie.
/// BRouter liczy trasę offline w wybranym trybie (szlakami, ze skrótami, najkrócej).
class EkranMapy extends StatefulWidget {
  const EkranMapy({super.key, required this.magazyn, required this.katalog, required this.region});

  final Magazyn magazyn;
  final Katalog katalog;
  final RegionPaczki region;

  @override
  State<EkranMapy> createState() => _EkranMapyState();
}

class _EkranMapyState extends State<EkranMapy> {
  late final BRouter _brouter = BRouter(widget.magazyn);
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
    _zapytajOLokalizacje();
  }

  Future<void> _wczytajStyl() async {
    try {
      final m = widget.magazyn;
      final szablon = await File(m.plikStylu).readAsString();
      final punkty = widget.region.punkty;
      setState(() {
        _styl = przygotujStyl(
          szablon,
          paczka: m.plikMapy(widget.region.mapa.plik),
          szlaki: m.plikMapy(widget.region.szlaki.plik),
          punkty: punkty == null ? null : m.plikMapy(punkty.plik),
          glify: m.glify,
          sprite: m.sprite,
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
      final tekst = await File(widget.magazyn.plikMapy(p.plik)).readAsString();
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
      const LineLayerProperties(lineColor: '#ffffff', lineWidth: 8, lineOpacity: 0.9, lineJoin: 'round', lineCap: 'round'),
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
        circleRadius: ['match', ['get', 'r'], 'przez', 5.5, 8.5],
        circleColor: ['match', ['get', 'r'], 'start', '#2e7d32', 'cel', '#c62828', '#ffffff'],
        circleStrokeColor: ['match', ['get', 'r'], 'przystanek', _kolorTrasy, 'przez', '#555555', '#ffffff'],
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

  Future<void> _odswiezWarstwy() async {
    final c = _mapa;
    if (c == null || !_stylGotowy) return;
    await c.setGeoJsonSource('punkty-trasy', {
      'type': 'FeatureCollection',
      'features': [
        for (final (i, p) in _plan.punkty.indexed)
          {
            'type': 'Feature',
            'properties': <String, dynamic>{
              'r': p.rodzaj.name,
              'nr': _plan.numerPrzystanku(i)?.toString() ?? '',
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [p.lon, p.lat],
            },
          },
      ],
    });
    await c.setGeoJsonSource('trasa', _trasa?.geojson ?? _pustyGeojson);
  }

  void _ustawPlan(PlanTrasy plan) {
    setState(() {
      _plan = plan;
      _bladTrasy = null;
      if (plan.dlugosc < 2) {
        _trasaTam = null;
        _trasa = null;
        _odcinki = const [];
      }
    });
    _przelicz();
  }

  Future<void> _przytrzymanie(LatLng p) async {
    final lon = p.longitude, lat = p.latitude;
    if (!widget.region.zawiera(lon, lat)) {
      _komunikat('Ten punkt leży poza pobranym regionem.');
      return;
    }
    final obiekt = _nazwane?.najblizszy(lon, lat);
    // przy nazwanym obiekcie punkt trafia dokładnie w niego (np. w schronisko)
    final (x, y) = obiekt == null ? (lon, lat) : (obiekt.lon, obiekt.lat);
    final nazwa = obiekt?.opis;
    if (_plan.dlugosc < 2) {
      _ustawPlan(_plan.dodajNaKoncu(x, y, nazwa: nazwa));
      return;
    }
    final wybor = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
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

  /// Dotknięcie mapy: jeśli blisko punktu trasy – menu tego punktu.
  Future<void> _klikniecie(Point<double> ekran, LatLng p) async {
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
    final wybor = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(nazwaPunktu(_plan, i, powrot: _powrot), style: Theme.of(ctx).textTheme.titleMedium)),
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
      case 'usun':
        _ustawPlan(_plan.usun(i));
    }
  }

  void _wyczysc() {
    _numerObliczenia++;
    setState(() {
      _plan = const PlanTrasy();
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

  Future<void> _przelicz() async {
    final numer = ++_numerObliczenia;
    await _odswiezWarstwy();
    if (_plan.dlugosc < 2) return;
    setState(() => _liczy = true);
    final plan = _plan;
    try {
      final trasa = await _brouter.oblicz(plan.wspolrzedne, tryb: _tryb);
      if (numer != _numerObliczenia || !mounted) return;
      setState(() {
        _ustawTrase(trasa);
        _liczy = false;
      });
    } on BladTrasy catch (e) {
      if (numer != _numerObliczenia || !mounted) return;
      setState(() {
        _bladTrasy = e.komunikat;
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

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(widget.region.nazwa),
              subtitle: Text('Dane OSM z ${widget.katalog.daneOsm}'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Regiony map'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EkranPobierania(magazyn: widget.magazyn),
                ));
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
              compassEnabled: true,
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
              onCameraTrackingDismissed: () => setState(() => _sledzi = false),
            )
          else
            Center(child: _bladStylu == null ? const CircularProgressIndicator() : Text(_bladStylu!)),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FloatingActionButton.small(
                  heroTag: 'menu',
                  onPressed: _menu,
                  child: const Icon(Icons.menu),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FloatingActionButton.small(
                  heroTag: 'pozycja',
                  onPressed: _mojaPozycja,
                  child: Icon(_sledzi ? Icons.my_location : Icons.location_searching),
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
                    label: const Text('Przytrzymaj palec na mapie, aby zacząć trasę'),
                  ),
                ),
              ),
            ),
          if (!_plan.pusty)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: PanelTrasy(
                  plan: _plan,
                  trasa: _trasa,
                  odcinki: _odcinki,
                  tryb: _tryb,
                  powrot: _powrot,
                  liczy: _liczy,
                  blad: _bladTrasy,
                  onTryb: _zmienTryb,
                  onPowrot: _zmienPowrot,
                  onCofnij: () => _ustawPlan(_plan.cofnij()),
                  onWyczysc: _wyczysc,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
