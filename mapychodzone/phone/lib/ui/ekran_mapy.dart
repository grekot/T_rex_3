import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../dane/katalog.dart';
import '../dane/magazyn.dart';
import '../mapa/styl.dart';
import '../trasa/brouter.dart';
import '../trasa/trasa.dart';
import '../urzadzenie.dart';
import 'ekran_pobierania.dart';
import 'o_aplikacji.dart';
import 'panel_trasy.dart';

const _kolorTrasy = '#d81b60';
const _pustyGeojson = <String, dynamic>{'type': 'FeatureCollection', 'features': <dynamic>[]};

/// Mapa offline regionu z planowaniem trasy: przytrzymanie palca dodaje punkt
/// (start, cel, kolejne punkty przedłużają trasę), BRouter liczy trasę po ścieżkach.
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

  final List<(double, double)> _punkty = [];
  Trasa? _trasa;
  bool _liczy = false;
  String? _bladTrasy;
  int _numerObliczenia = 0;

  @override
  void initState() {
    super.initState();
    _wczytajStyl();
    _zapytajOLokalizacje();
  }

  Future<void> _wczytajStyl() async {
    try {
      final m = widget.magazyn;
      final szablon = await File(m.plikStylu).readAsString();
      setState(() {
        _styl = przygotujStyl(
          szablon,
          paczka: m.plikMapy(widget.region.mapa.plik),
          szlaki: m.plikMapy(widget.region.szlaki.plik),
          glify: m.glify,
          sprite: m.sprite,
        );
      });
    } on Object catch (e) {
      setState(() => _bladStylu = 'Nie udało się wczytać stylu mapy: $e');
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
    );
    await c.addLineLayer(
      'trasa',
      'trasa-linia',
      const LineLayerProperties(lineColor: _kolorTrasy, lineWidth: 5, lineJoin: 'round', lineCap: 'round'),
    );
    await c.addGeoJsonSource('punkty', _pustyGeojson);
    await c.addCircleLayer(
      'punkty',
      'punkty-kolka',
      const CircleLayerProperties(
        circleRadius: 7,
        circleColor: '#ffffff',
        circleStrokeColor: _kolorTrasy,
        circleStrokeWidth: 3,
      ),
    );
    setState(() => _stylGotowy = true);
    await _odswiezWarstwy();
  }

  Future<void> _odswiezWarstwy() async {
    final c = _mapa;
    if (c == null || !_stylGotowy) return;
    await c.setGeoJsonSource('punkty', {
      'type': 'FeatureCollection',
      'features': [
        for (final (lon, lat) in _punkty)
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [lon, lat],
            },
          },
      ],
    });
    await c.setGeoJsonSource('trasa', _trasa?.geojson ?? _pustyGeojson);
  }

  void _dodajPunkt(LatLng p) {
    if (!widget.region.zawiera(p.longitude, p.latitude)) {
      _komunikat('Ten punkt leży poza pobranym regionem.');
      return;
    }
    setState(() {
      _punkty.add((p.longitude, p.latitude));
      _bladTrasy = null;
    });
    _przelicz();
  }

  void _cofnij() {
    if (_punkty.isEmpty) return;
    setState(() {
      _punkty.removeLast();
      _bladTrasy = null;
      if (_punkty.length < 2) _trasa = null;
    });
    _przelicz();
  }

  void _wyczysc() {
    setState(() {
      _punkty.clear();
      _trasa = null;
      _bladTrasy = null;
      _liczy = false;
    });
    _numerObliczenia++;
    _odswiezWarstwy();
  }

  Future<void> _przelicz() async {
    final numer = ++_numerObliczenia;
    await _odswiezWarstwy();
    if (_punkty.length < 2) return;
    setState(() => _liczy = true);
    try {
      final trasa = await _brouter.oblicz(List.of(_punkty));
      if (numer != _numerObliczenia || !mounted) return;
      setState(() {
        _trasa = trasa;
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
              onMapLongClick: (_, p) => _dodajPunkt(p),
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
          if (_punkty.isEmpty && _stylGotowy)
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
          if (_punkty.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: PanelTrasy(
                  liczbaPunktow: _punkty.length,
                  trasa: _trasa,
                  liczy: _liczy,
                  blad: _bladTrasy,
                  onCofnij: _cofnij,
                  onWyczysc: _wyczysc,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
