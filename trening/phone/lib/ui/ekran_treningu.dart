import 'dart:async';

import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../plan/model.dart';
import '../trening/przebieg.dart';
import '../trening/rozpiska.dart';
import '../trening/sygnaly_urzadzenia.dart';
import '../urzadzenie.dart';
import 'tekst_md.dart';
import 'technika.dart';

/// Prowadzenie treningu krok po kroku: rysunek, skrót techniki, licznik albo
/// timer, przerwy, „Boli: pomiń”. Ekran nie gaśnie, dopóki jest otwarty.
class EkranTreningu extends StatefulWidget {
  const EkranTreningu({
    super.key,
    required this.dane,
    required this.rozpiska,
    this.czesc,
    this.urzadzenie = const Urzadzenie(),
    this.zegar,
  });

  final DaneAplikacji dane;
  final Rozpiska rozpiska;
  final int? czesc;
  final Urzadzenie urzadzenie;
  final DateTime Function()? zegar;

  @override
  State<EkranTreningu> createState() => _EkranTreninguState();
}

class _EkranTreninguState extends State<EkranTreningu> {
  late final Przebieg p;
  Timer? _tyk;
  bool _zapisano = false;
  int? _pokazanaTechnika;

  @override
  void initState() {
    super.initState();
    p = Przebieg(widget.rozpiska, zegar: widget.zegar, sygnaly: SygnalyUrzadzenia(widget.urzadzenie))
      ..addListener(_zmiana);
    widget.urzadzenie.ekranWlaczony(true);
    _tyk = Timer.periodic(const Duration(milliseconds: 200), (_) => p.tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _technikaPierwszyRaz());
  }

  @override
  void dispose() {
    _tyk?.cancel();
    p.removeListener(_zmiana);
    p.dispose();
    widget.urzadzenie.ekranWlaczony(false);
    super.dispose();
  }

  void _zmiana() {
    if (p.koniec && !_zapisano) {
      _zapisano = true;
      _tyk?.cancel();
      widget.dane.zapiszTrening(widget.rozpiska, p.wynik(), czesc: widget.czesc);
    }
    if (!p.koniec) _technikaPierwszyRaz();
    setState(() {});
  }

  /// Pełny opis techniki otwiera się sam przy pierwszym w ogóle spotkaniu z ćwiczeniem.
  void _technikaPierwszyRaz() {
    if (!mounted || p.koniec || p.faza is! FazaPrzygotowanie) return;
    final c = p.cwiczenie;
    if (_pokazanaTechnika == p.faza.cwiczenie || widget.dane.stan.widzianeTechniki.contains(c.cwiczenie.atlasId)) {
      return;
    }
    _pokazanaTechnika = p.faza.cwiczenie;
    widget.dane.oznaczTechnikeWidziana(c.cwiczenie.atlasId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) pokazTechnike(context, c, widget.dane.atlas.zasadyWspolne);
    });
  }

  Future<bool> _potwierdzWyjscie() async {
    if (p.koniec) return true;
    p.pauzuj();
    final wyjdz = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Zakończyć trening?'),
        content: const Text('Zrobione ćwiczenia zapiszą się jako trening skrócony.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Wracam do ćwiczeń')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Zakończ')),
        ],
      ),
    );
    if (wyjdz == true) {
      p.zakonczTeraz();
      return true;
    }
    p.wznow();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: p.koniec,
      onPopInvokedWithResult: (zamkniete, _) async {
        if (zamkniete) return;
        final nawigator = Navigator.of(context);
        if (await _potwierdzWyjscie() && mounted) nawigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.rozpiska.sesja.nazwa),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: p.postep),
          ),
        ),
        body: SafeArea(child: p.koniec ? _Koniec(p: p) : _Faza(p: p, dane: widget.dane)),
      ),
    );
  }
}

class _Faza extends StatelessWidget {
  const _Faza({required this.p, required this.dane});

  final Przebieg p;
  final DaneAplikacji dane;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = p.cwiczenie;
    final f = p.faza;
    final r = c.rysunek;
    final nastepne = p.nastepneCwiczenie;
    final przygotowanie = f is FazaPrzygotowanie;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(c.cwiczenie.nazwa, style: t.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(_podtytul(f), style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 8),
          if (r != null) Flexible(flex: przygotowanie ? 5 : 4, child: RysunekCwiczenia(r)),
          const SizedBox(height: 8),
          Expanded(
            flex: przygotowanie ? 4 : 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final w in c.skrot) Punkt(w, styl: t.bodyLarge),
                  if (c.przerwijJesli != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TekstMd('Przerwij, jeśli: ${c.przerwijJesli}',
                          styl: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 12),
                  _Srodek(p: p),
                ],
              ),
            ),
          ),
          _Przyciski(p: p, dane: dane),
          if (nastepne != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Dalej: ${nastepne.cwiczenie.nazwa}', style: t.bodySmall, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }

  String _podtytul(Faza f) {
    return switch (f) {
      FazaPrzygotowanie() => 'Przygotuj się',
      FazaPowtorzenia(:final seria, :final serii, :final strona, :final naZmiane, :final opis) =>
        [opis ?? '', this.seria(seria, serii), naZmiane ? 'strony na zmianę' : ''].where((e) => e.isNotEmpty).join(' · ') +
            this.strona(strona),
      FazaTrzymanie(:final opis, :final seria, :final serii, :final strona) =>
        [this.seria(seria, serii), opis].where((e) => e.isNotEmpty).join(' · ') + this.strona(strona),
      FazaOddechy() => 'Oddychanie',
      FazaPrzerwa(:final powod) => switch (powod) {
          PowodPrzerwy.strona => 'Zmiana strony',
          PowodPrzerwy.seria => 'Przerwa przed następną serią',
          PowodPrzerwy.powtorzenie => 'Opuść i odpocznij',
          PowodPrzerwy.pozycja => 'Zmiana pozycji',
          PowodPrzerwy.runda => 'Przerwa przed następną rundą',
        },
    };
  }

  String seria(int s, int n) => n > 1 ? 'Seria $s/$n' : '';
  String strona(Strona? s) => s == null ? '' : ' · ${s.nazwa}';
}

class _Srodek extends StatelessWidget {
  const _Srodek({required this.p});

  final Przebieg p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kolor = Theme.of(context).colorScheme;
    final duzy = t.displayLarge?.copyWith(fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()]);
    final f = p.faza;
    switch (f) {
      case FazaPrzygotowanie():
        final c = p.cwiczenie;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.cwiczenie.jak != null) TekstMd(c.cwiczenie.jak!, styl: t.bodyLarge),
            if (c.cwiczenie.uwaga != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TekstMd(c.cwiczenie.uwaga!, styl: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 8),
            Text('Dawka: ${opisDawki(c)}', style: t.titleMedium),
          ],
        );
      case FazaPowtorzenia():
        return Column(
          children: [
            InkWell(
              onTap: p.plusJeden,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${p.licznik} / ${f.cel}', style: duzy, textAlign: TextAlign.center),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: p.minusJeden, child: const Text('−1')),
                const SizedBox(width: 16),
                OutlinedButton(onPressed: p.plusJeden, child: const Text('+1')),
              ],
            ),
            if (f.pauzaGoraS != null) Text('${f.pauzaGoraS} s pauzy u góry', style: t.bodyLarge),
            if (f.tempo != null) Text('tempo: ${f.tempo!.dolS} s w dół · ${f.tempo!.goraS} s w górę', style: t.bodyLarge),
            if (!f.zakres.staly) Text('zakres z planu: ${f.zakres}', style: t.bodySmall),
          ],
        );
      case FazaTrzymanie() || FazaPrzerwa():
        final przerwa = f is FazaPrzerwa;
        final calosc = p.sekundyFazy!;
        final zostalo = p.pozostalo!;
        return Column(
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: calosc == 0 ? 0 : zostalo / calosc,
                    strokeWidth: 10,
                    color: przerwa ? kolor.tertiary : kolor.primary,
                  ),
                  Center(child: Text('$zostalo', style: duzy)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (przerwa) Text('Rozluźnij brzuch.', style: t.bodyLarge),
            if (f is FazaTrzymanie && !f.zakres.staly) Text('zakres z planu: ${f.zakres} s', style: t.bodySmall),
            TextButton(onPressed: () => p.dodajSekundy(przerwa ? 15 : 5), child: Text(przerwa ? '+15 s' : '+5 s')),
          ],
        );
      case FazaOddechy():
        final wdech = p.wdech;
        return Column(
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: ((wdech ? f.wdechS : f.wydechS) * 1000).round()),
              curve: Curves.easeInOut,
              width: wdech ? 120 : 64,
              height: wdech ? 120 : 64,
              decoration: BoxDecoration(shape: BoxShape.circle, color: kolor.primary.withValues(alpha: 0.35)),
            ),
            const SizedBox(height: 8),
            Text(wdech ? 'Wdech nosem…' : 'Wydech ustami…', style: t.headlineSmall),
            Text('${p.licznik} / ${f.cel} oddechów (plan: ${f.zakres})', style: t.titleMedium),
          ],
        );
    }
  }
}

String opisDawki(CwiczenieSesji c) {
  final d = c.krok.dawka;
  final str = d.naStrone ? ' na stronę' : '';
  return switch (d) {
    Powtorzenia(:final serie, :final ile, :final trzymanieS) =>
      '${serie.staly && serie.min == 1 ? '' : '$serie × '}$ile$str${trzymanieS != null ? ', trzymanie $trzymanieS s' : ''}',
    Piramida(:final serie, :final trzymanieS) => '${serie.join(', ')} powtórzeń$str, każde $trzymanieS s',
    Trzymanie(:final serie, :final s) => '${serie.staly && serie.min == 1 ? '' : '$serie × '}$s s$str',
    Oddechy(:final ile) => '$ile oddechów',
    Pozycje(:final etapy) => etapy.map((e) => e.s != null ? '${e.nazwa} ${e.s} s' : '${e.nazwa} ${e.powt}×').join(', potem '),
  };
}

class _Przyciski extends StatelessWidget {
  const _Przyciski({required this.p, required this.dane});

  final Przebieg p;
  final DaneAplikacji dane;

  @override
  Widget build(BuildContext context) {
    final f = p.faza;
    final glowny = switch (f) {
      FazaPrzygotowanie() => 'Start',
      FazaPowtorzenia() || FazaOddechy() => 'Gotowe',
      FazaTrzymanie() => 'Dalej',
      FazaPrzerwa() => 'Pomiń przerwę',
    };
    const ciasno = EdgeInsets.symmetric(horizontal: 8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => pokazTechnike(context, p.cwiczenie, dane.atlas.zasadyWspolne),
                icon: const Icon(Icons.info_outline),
                label: const Text('Technika', maxLines: 1),
                style: OutlinedButton.styleFrom(padding: ciasno),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => p.pominCwiczenie(boli: true),
                icon: const Icon(Icons.healing_outlined),
                label: const Text('Boli: pomiń', maxLines: 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  padding: ciasno,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: p.pauza ? p.wznow : p.pauzuj,
              icon: Icon(p.pauza ? Icons.play_arrow : Icons.pause),
              tooltip: p.pauza ? 'Wznów' : 'Pauza',
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: p.dalej,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          child: Text(glowny, style: const TextStyle(fontSize: 22)),
        ),
      ],
    );
  }
}

class _Koniec extends StatelessWidget {
  const _Koniec({required this.p});

  final Przebieg p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final w = p.wynik();
    final minuty = w.koniec.difference(w.start).inMinutes;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.check_circle, size: 96, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(w.ukonczony ? 'Brawo, trening zrobiony!' : 'Trening przerwany', style: t.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Czas: $minuty min · ćwiczeń: ${w.wykonane.length}', style: t.titleMedium, textAlign: TextAlign.center),
        if (w.bolesne.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Bolało przy:', style: t.titleMedium),
          for (final id in w.bolesne) Punkt(p.rozpiska.cwiczenia.firstWhere((c) => c.id == id).cwiczenie.nazwa),
          const SizedBox(height: 8),
          Text('Zgodnie z sygnalizacją świetlną: przerwij to ćwiczenie. Jeśli ból jest silny albo schodzi niżej, '
              'zajrzyj na ekran bezpieczeństwa.', style: t.bodyMedium),
        ],
        const SizedBox(height: 16),
        Text('Ocena bólu po treningu i okienko w kalendarzu przyjdą w wersji 0.1.', style: t.bodySmall),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Wróć')),
      ],
    );
  }
}
