import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../dane/katalog.dart';
import '../dane/magazyn.dart';
import '../dane/pobieranie.dart';
import 'ekran_mapy.dart';

/// Menedżer regionów (telefon): pobieranie, aktualizacja, usuwanie i wybór regionu do pokazania.
///
/// Każdy region to mapa (PMTiles), szlaki i punkty (GeoJSON); do tego wspólny styl i dane tras
/// BRouter (*.rd5, wspólne dla sąsiednich regionów). Ekran zastępuje mapę na stosie nawigacji:
/// „wstecz” wraca do mapy aktywnego regionu, jeśli jest na telefonie.
class EkranRegionow extends StatefulWidget {
  const EkranRegionow({super.key, required this.magazyn, this.aktualizacja = false});

  final Magazyn magazyn;

  /// Na telefonie są dane w starszym formacie: ta wersja aplikacji potrzebuje nowszych.
  final bool aktualizacja;

  @override
  State<EkranRegionow> createState() => _EkranRegionowState();
}

class _Zadanie {
  _Zadanie(this.nazwa, this.url, this.cel, {this.rozmiar, this.sha256});
  final String nazwa;
  final String url;
  final String cel;
  final int? rozmiar;
  final String? sha256;
}

class _EkranRegionowState extends State<EkranRegionow> {
  Katalog? _katalog;
  String? _tekstKatalogu;

  /// Katalog z internetu (true) albo zapisany na telefonie (false: brak sieci).
  bool _zSieci = false;
  String? _blad;
  String? _pobierany;
  String _co = '';
  double? _postep;

  /// Rozmiary plików tras (HEAD na brouter.de), żeby pokazać, ile trzeba pobrać.
  final Map<String, int?> _rozmiaryRd5 = {};

  Magazyn get _m => widget.magazyn;

  @override
  void initState() {
    super.initState();
    _wczytajKatalog();
  }

  Future<void> _wczytajKatalog() async {
    setState(() => _blad = null);
    try {
      final tekst = await pobierzTekst(adresKatalogu);
      final k = Katalog.zJson(jsonDecode(tekst) as Map<String, dynamic>);
      setState(() {
        _katalog = k;
        _tekstKatalogu = tekst;
        _zSieci = true;
      });
      final nazwy = {for (final r in k.regiony) ...r.rd5};
      for (final n in nazwy) {
        final rozmiar = await rozmiarPliku(k.adresRd5(n));
        if (mounted) setState(() => _rozmiaryRd5[n] = rozmiar);
      }
    } on Object catch (e) {
      final lokalny = _m.wczytajKatalog();
      setState(() {
        _katalog ??= lokalny;
        _blad = lokalny == null
            ? 'Nie udało się pobrać listy regionów. Sprawdź internet.\n($e)'
            : 'Bez internetu: widać tylko regiony na telefonie.';
      });
    }
  }

  /// Pliki do pobrania; pomija te, które już leżą na telefonie (ponowienie po przerwie).
  List<_Zadanie> _zadania(Katalog k, RegionPaczki r) {
    bool brak(String cel, int? rozmiar) {
      final f = File(cel);
      return !f.existsSync() || (rozmiar != null && f.lengthSync() != rozmiar);
    }

    final nazwy = {
      r.mapa.plik: 'Mapa',
      r.szlaki.plik: 'Szlaki',
      r.punkty?.plik: 'Szczyty i schroniska',
      r.poziomice?.plik: 'Poziomice',
      r.teren?.plik: 'Ukształtowanie terenu',
      r.przeszkody?.plik: 'Przeszkody terenowe',
    };
    return [
      _Zadanie('Styl mapy', k.adres(k.styl.plik), _m.plikStylu, rozmiar: k.styl.rozmiar, sha256: k.styl.sha256),
      for (final p in r.pliki)
        _Zadanie(nazwy[p.plik] ?? p.plik, k.adres(p.plik), _m.plikMapy(p.plik), rozmiar: p.rozmiar, sha256: p.sha256),
      for (final n in r.rd5) _Zadanie('Dane tras $n', k.adresRd5(n), _m.plikRd5(n)),
    ].where((z) => brak(z.cel, z.rozmiar)).toList();
  }

  int _rozmiarRegionu(RegionPaczki r) =>
      r.pliki.fold(0, (s, p) => s + p.rozmiar) + r.rd5.fold(0, (s, n) => s + (_rozmiaryRd5[n] ?? 0));

  /// Ile zostało do pobrania (pliki, których nie ma albo się zmieniły).
  int _doPobrania(Katalog k, RegionPaczki r) =>
      _zadania(k, r).fold(0, (s, z) => s + (z.rozmiar ?? _rozmiaryRd5[z.nazwa.split(' ').last] ?? 0));

  Future<void> _pobierz(Katalog k, RegionPaczki r) async {
    setState(() {
      _pobierany = r.id;
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
      await File(_m.plikKatalogu).writeAsString(_tekstKatalogu!, flush: true);
      await _pokaz(k, r);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _pobierany = null;
          _blad = 'Pobieranie przerwane: $e\nSpróbuj ponownie (pobrane pliki zostają).';
        });
      }
    }
  }

  Future<void> _pokaz(Katalog k, RegionPaczki r) async {
    await _m.ustawAktywny(r.id);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => EkranMapy(dane: _m, katalog: k, region: r),
    ));
  }

  Future<void> _usun(Katalog k, RegionPaczki r) async {
    final tak = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć „${r.nazwa}”?'),
        content: Text('Zwolni ok. ${megabajty(_m.zajeteMiejsce(r))} na telefonie. '
            'Region można później pobrać ponownie.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (tak != true) return;
    await _m.usunRegion(k, r);
    if (mounted) setState(() {});
  }

  /// „Wstecz”: mapa aktywnego (albo innego kompletnego) regionu, jeśli jest na telefonie.
  void _wstecz() {
    final k = _m.wczytajKatalog();
    final r = _m.gotowyRegion();
    if (k == null || r == null) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => EkranMapy(dane: _m, katalog: k, region: r),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final k = _katalog;
    final teksty = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (zrobione, _) {
        if (!zrobione && _pobierany == null) _wstecz();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Regiony map')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.aktualizacja
                  ? 'Ta wersja aplikacji ma nowe warstwy mapy (poziomice i cieniowanie terenu). Zaktualizuj region: pobiorą się tylko '
                      'zmienione pliki.'
                  : 'Mapa działa bez internetu. Pobierz regiony, w które się wybierasz: mapę, szlaki i dane do '
                      'wyznaczania tras. To od kilkudziesięciu do kilkuset MB, najlepiej przez Wi-Fi.',
              style: teksty.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_blad != null) ...[
              Text(_blad!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              if (!_zSieci) OutlinedButton(onPressed: _wczytajKatalog, child: const Text('Spróbuj ponownie')),
              const SizedBox(height: 8),
            ],
            if (k == null && _blad == null) const Center(child: CircularProgressIndicator()),
            if (k != null)
              for (final r in k.regiony)
                if (_zSieci || _m.regionCzesciowo(r)) _karta(k, r, teksty),
          ],
        ),
      ),
    );
  }

  Widget _karta(Katalog k, RegionPaczki r, TextTheme teksty) {
    final gotowy = _m.regionGotowy(k, r);
    final czesciowo = !gotowy && _m.regionCzesciowo(r);
    final aktywny = gotowy && _m.aktywnyRegion == r.id;
    final pobiera = _pobierany == r.id;
    final zajety = _pobierany != null;
    final String stan;
    if (gotowy) {
      stan = 'Na telefonie · ${megabajty(_m.zajeteMiejsce(r))}';
    } else if (!_zSieci) {
      stan = 'Niekompletny: zaktualizuj przy dostępie do internetu';
    } else if (czesciowo) {
      stan = 'Do aktualizacji: ${megabajty(_doPobrania(k, r))}';
    } else {
      stan = 'Do pobrania: ok. ${megabajty(_doPobrania(k, r))}';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(r.nazwa, style: teksty.titleMedium)),
                if (aktywny) const Chip(label: Text('na mapie'), visualDensity: VisualDensity.compact),
              ],
            ),
            if (r.opis.isNotEmpty) Text(r.opis, style: teksty.bodySmall),
            const SizedBox(height: 6),
            Text('Mapa ${megabajty(r.mapa.rozmiar)} · szlaki ${megabajty(r.szlaki.rozmiar)} · '
                '${r.poziomice == null ? '' : 'poziomice ${megabajty(r.poziomice!.rozmiar)} · '}'
                '${r.teren == null ? '' : 'teren ${megabajty(r.teren!.rozmiar)} · '}'
                'razem z danymi tras ok. ${megabajty(_rozmiarRegionu(r))}', style: teksty.bodySmall),
            Text(stan, style: teksty.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            if (pobiera) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _postep),
              const SizedBox(height: 4),
              Text(_co, style: teksty.bodySmall),
            ],
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if ((gotowy || czesciowo) && !pobiera)
                  TextButton.icon(
                    onPressed: zajety ? null : () => _usun(k, r),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Usuń'),
                  ),
                if (!gotowy && _zSieci && !pobiera)
                  FilledButton.icon(
                    onPressed: zajety ? null : () => _pobierz(k, r),
                    icon: const Icon(Icons.download),
                    label: Text(czesciowo ? 'Zaktualizuj' : 'Pobierz'),
                  ),
                if (gotowy)
                  FilledButton.icon(
                    onPressed: zajety ? null : () => _pokaz(k, r),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pokaż na mapie'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
