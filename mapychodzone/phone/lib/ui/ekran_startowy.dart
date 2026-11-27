import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dane/katalog.dart';
import '../dane/magazyn.dart';
import '../dane/zrodlo.dart';
import '../pamiec/pamiec.dart';
import '../urzadzenie.dart';
import 'ekran_mapy.dart';
import 'ekran_regionow.dart';

/// Przygotowuje pliki aplikacji i otwiera mapę albo pobieranie regionu.
/// W przeglądarce czyta katalog z serwera i od razu otwiera mapę.
class EkranStartowy extends StatefulWidget {
  const EkranStartowy({super.key});

  @override
  State<EkranStartowy> createState() => _EkranStartowyState();
}

class _EkranStartowyState extends State<EkranStartowy> {
  String? _blad;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (kIsWeb) return await _startWww();
      final magazyn = Magazyn(await Urzadzenie.katalog());
      await magazyn.przygotujZasoby();
      if (!mounted) return;
      final katalog = magazyn.wczytajKatalog();
      final region = magazyn.gotowyRegion();
      final Widget cel = (katalog != null && region != null)
          ? EkranMapy(dane: magazyn, katalog: katalog, region: region)
          : EkranRegionow(magazyn: magazyn, aktualizacja: katalog != null && !katalog.aktualny);
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => cel));
    } on Object catch (e) {
      setState(() => _blad = '$e');
    }
  }

  Future<void> _startWww() async {
    final dane = ZrodloWww();
    final katalog = Katalog.zJson(jsonDecode(await dane.tekst('katalog.json')) as Map<String, dynamic>);
    if (katalog.regiony.isEmpty) throw Exception('Katalog na serwerze nie ma regionów');
    if (!mounted) return;
    final region = katalog.region(odczytajUstawienie('region') ?? '') ?? katalog.regiony.first;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => EkranMapy(dane: dane, katalog: katalog, region: region),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _blad == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Nie udało się uruchomić aplikacji:\n$_blad', textAlign: TextAlign.center),
              ),
      ),
    );
  }
}
