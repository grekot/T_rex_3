import 'package:flutter/material.dart';

import '../dane/magazyn.dart';
import '../urzadzenie.dart';
import 'ekran_mapy.dart';
import 'ekran_pobierania.dart';

/// Przygotowuje pliki aplikacji i otwiera mapę albo pobieranie regionu.
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
      final magazyn = Magazyn(await Urzadzenie.katalog());
      await magazyn.przygotujZasoby();
      if (!mounted) return;
      final katalog = magazyn.wczytajKatalog();
      final region = magazyn.gotowyRegion();
      final Widget cel = (katalog != null && region != null)
          ? EkranMapy(magazyn: magazyn, katalog: katalog, region: region)
          : EkranPobierania(magazyn: magazyn, aktualizacja: katalog != null && !katalog.aktualny);
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => cel));
    } on Object catch (e) {
      setState(() => _blad = '$e');
    }
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
