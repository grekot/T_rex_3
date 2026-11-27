import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../dane/katalog.dart';
import '../dane/magazyn.dart';
import '../dane/pobieranie.dart';
import 'ekran_mapy.dart';

/// Pobranie regionu: mapa (PMTiles), szlaki (GeoJSON), styl i dane tras BRouter (*.rd5).
class EkranPobierania extends StatefulWidget {
  const EkranPobierania({super.key, required this.magazyn, this.aktualizacja = false});

  final Magazyn magazyn;

  /// Na telefonie są dane w starszym formacie: ta wersja aplikacji potrzebuje nowszych.
  final bool aktualizacja;

  @override
  State<EkranPobierania> createState() => _EkranPobieraniaState();
}

class _Zadanie {
  _Zadanie(this.nazwa, this.url, this.cel, {this.rozmiar, this.sha256});
  final String nazwa;
  final String url;
  final String cel;
  final int? rozmiar;
  final String? sha256;
}

class _EkranPobieraniaState extends State<EkranPobierania> {
  Katalog? _katalog;
  String? _tekstKatalogu;
  String? _blad;
  bool _pobiera = false;
  String _co = '';
  double? _postep;

  /// Rozmiary plików tras (HEAD na brouter.de), żeby pokazać, ile trzeba pobrać.
  final Map<String, int?> _rozmiaryRd5 = {};

  @override
  void initState() {
    super.initState();
    _wczytajKatalog();
  }

  Future<void> _wczytajKatalog() async {
    setState(() {
      _blad = null;
      _katalog = null;
    });
    try {
      final tekst = await pobierzTekst(adresKatalogu);
      final k = Katalog.zJson(jsonDecode(tekst) as Map<String, dynamic>);
      setState(() {
        _katalog = k;
        _tekstKatalogu = tekst;
      });
      final nazwy = {for (final r in k.regiony) ...r.rd5};
      for (final n in nazwy) {
        final rozmiar = await rozmiarPliku(k.adresRd5(n));
        if (mounted) setState(() => _rozmiaryRd5[n] = rozmiar);
      }
    } on Object catch (e) {
      setState(() => _blad = 'Nie udało się pobrać listy regionów. Sprawdź internet.\n($e)');
    }
  }

  /// Pliki do pobrania; pomija te, które już leżą na telefonie (ponowienie po przerwie).
  List<_Zadanie> _zadania(Katalog k, RegionPaczki r) {
    final m = widget.magazyn;
    bool brak(String cel, int? rozmiar) {
      final f = File(cel);
      return !f.existsSync() || (rozmiar != null && f.lengthSync() != rozmiar);
    }

    return [
      _Zadanie('Styl mapy', k.adres(k.styl.plik), m.plikStylu, rozmiar: k.styl.rozmiar, sha256: k.styl.sha256),
      _Zadanie('Szlaki', k.adres(r.szlaki.plik), m.plikMapy(r.szlaki.plik),
          rozmiar: r.szlaki.rozmiar, sha256: r.szlaki.sha256),
      if (r.punkty case final p?)
        _Zadanie('Szczyty i schroniska', k.adres(p.plik), m.plikMapy(p.plik), rozmiar: p.rozmiar, sha256: p.sha256),
      _Zadanie('Mapa', k.adres(r.mapa.plik), m.plikMapy(r.mapa.plik), rozmiar: r.mapa.rozmiar, sha256: r.mapa.sha256),
      for (final n in r.rd5) _Zadanie('Dane tras $n', k.adresRd5(n), m.plikRd5(n)),
    ].where((z) => brak(z.cel, z.rozmiar)).toList();
  }

  int _rozmiarRegionu(Katalog k, RegionPaczki r) =>
      k.styl.rozmiar +
      r.mapa.rozmiar +
      r.szlaki.rozmiar +
      (r.punkty?.rozmiar ?? 0) +
      r.rd5.fold(0, (s, n) => s + (_rozmiaryRd5[n] ?? 0));

  /// Ile zostało do pobrania (pliki, których nie ma albo się zmieniły; dane tras bez rozmiaru).
  int _doPobrania(Katalog k, RegionPaczki r) =>
      _zadania(k, r).fold(0, (s, z) => s + (z.rozmiar ?? _rozmiaryRd5[z.nazwa.split(' ').last] ?? 0));

  Future<void> _pobierz(Katalog k, RegionPaczki r) async {
    setState(() {
      _pobiera = true;
      _blad = null;
    });
    final zadania = _zadania(k, r);
    try {
      for (var i = 0; i < zadania.length; i++) {
        final z = zadania[i];
        setState(() {
          _co = '${i + 1}/${zadania.length}: ${z.nazwa}';
          _postep = null;
        });
        await pobierzPlik(z.url, z.cel, rozmiar: z.rozmiar, sha256: z.sha256, postep: (pobrane, calosc) {
          if (!mounted) return;
          setState(() {
            _postep = calosc == null || calosc == 0 ? null : pobrane / calosc;
            _co = '${i + 1}/${zadania.length}: ${z.nazwa} · ${megabajty(pobrane)}'
                '${calosc == null ? '' : ' z ${megabajty(calosc)}'}';
          });
        });
      }
      // Katalog zapisujemy na końcu: jego obecność + komplet plików = region gotowy.
      await File(widget.magazyn.plikKatalogu).writeAsString(_tekstKatalogu!, flush: true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => EkranMapy(magazyn: widget.magazyn, katalog: k, region: r),
      ));
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _pobiera = false;
          _blad = 'Pobieranie przerwane: $e\nSpróbuj ponownie (pobrane pliki zostają).';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = _katalog;
    final teksty = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('MapyChodzone · regiony')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.aktualizacja
                ? 'Ta wersja aplikacji ma nowe warstwy mapy (szczyty, schroniska, przełęcze). '
                    'Dociągnij je: pobiorą się tylko zmienione pliki.'
                : 'Mapa działa bez internetu. Najpierw pobierz region: mapę, szlaki i dane do wyznaczania tras. '
                    'To kilkaset MB, najlepiej przez Wi-Fi.',
            style: teksty.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_blad != null) ...[
            Text(_blad!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            if (k == null) FilledButton(onPressed: _wczytajKatalog, child: const Text('Spróbuj ponownie')),
          ],
          if (k == null && _blad == null) const Center(child: CircularProgressIndicator()),
          if (k != null)
            for (final r in k.regiony)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.nazwa, style: teksty.titleMedium),
                      if (r.opis.isNotEmpty) Text(r.opis, style: teksty.bodySmall),
                      const SizedBox(height: 8),
                      Text(
                        'Mapa ${megabajty(r.mapa.rozmiar)} · szlaki ${megabajty(r.szlaki.rozmiar)} · '
                        'dane tras ${r.rd5.join(', ')}',
                        style: teksty.bodySmall,
                      ),
                      Text('Razem ok. ${megabajty(_rozmiarRegionu(k, r))} · dane OSM z ${k.daneOsm}',
                          style: teksty.bodySmall),
                      if (!_pobiera)
                        Text(
                          _zadania(k, r).isEmpty
                              ? 'Wszystko pobrane.'
                              : 'Do pobrania: ${megabajty(_doPobrania(k, r))}',
                          style: teksty.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      const SizedBox(height: 12),
                      if (_pobiera) ...[
                        LinearProgressIndicator(value: _postep),
                        const SizedBox(height: 4),
                        Text(_co, style: teksty.bodySmall),
                      ] else
                        FilledButton.icon(
                          onPressed: () => _pobierz(k, r),
                          icon: Icon(_zadania(k, r).isEmpty ? Icons.map : Icons.download),
                          label: Text(_zadania(k, r).isEmpty
                              ? 'Otwórz mapę'
                              : (widget.aktualizacja ? 'Zaktualizuj region' : 'Pobierz region')),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
