import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../dane/okienka.dart';
import '../silnik/daty.dart';
import '../silnik/kalendarz.dart';
import '../silnik/sygnalizacja.dart';
import '../trening/test_kierunkowy.dart';
import 'daty_slownie.dart';
import 'ocena.dart';
import 'tekst_md.dart';

const _dniKrotko = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

/// Kalendarz „adwentowy” (plan aplikacji, sekcja 3): okienko na każdy dzień planu.
/// Dzisiejsze okienko otwiera się stuknięciem, przeszłe pokazują, co się wydarzyło,
/// przyszłe można podejrzeć przytrzymaniem, a dni następnego etapu czekają na kryteria.
class EkranKalendarza extends StatelessWidget {
  const EkranKalendarza({super.key, required this.dane});

  final DaneAplikacji dane;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dane,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final k = dane.kalendarz;
        final biezacy = dane.plan.etap(dane.dzisiaj.etap);
        final nastepny = k.koniecMinimum;
        return Scaffold(
          appBar: AppBar(title: const Text('Kalendarz'), actions: [PrzyciskBezpieczenstwa(dane: dane)]),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final e in dane.plan.etapy)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 14, height: 4, color: kolorEtapu[e.nr]),
                      const SizedBox(width: 4),
                      Text('${e.nr}: ${e.nazwa}', style: t.bodySmall),
                    ]),
                ],
              ),
              const SizedBox(height: 8),
              Text('Treningi w tym tygodniu: ${treningiWTygodniu(dane.stan, dane.dzis)}/7', style: t.titleMedium),
              if (nastepny != null)
                Row(children: [
                  Expanded(
                    child: Text(
                      'Etap ${biezacy.nr + 1} najwcześniej od ${dataSlownieKrotko(nastepny)}, gdy spełnisz kryteria.',
                      style: t.bodyMedium,
                    ),
                  ),
                  TextButton(onPressed: () => _kryteria(context), child: const Text('Kryteria')),
                ]),
              const SizedBox(height: 8),
              _Siatka(dane: dane, kalendarz: k),
              const SizedBox(height: 12),
              const _Legenda(),
            ],
          ),
        );
      },
    );
  }

  void _kryteria(BuildContext context) {
    final etap = dane.plan.etap(dane.dzisiaj.etap);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _Kryteria(dane: dane, etap: etap.nr),
        ),
      ),
    );
  }
}

class _Kryteria extends StatelessWidget {
  const _Kryteria({required this.dane, required this.etap});

  final DaneAplikacji dane;
  final int etap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = dane.plan.etap(etap);
    final koniec = dane.kalendarz.koniecMinimum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Przejście do etapu ${etap + 1}', style: t.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Etap $etap trwa co najmniej ${e.minDni} dni'
          '${koniec == null ? '' : ' (do ${dataSlownieKrotko(koniec)})'}. Potem przechodzisz dalej, gdy spełnisz '
          'kryteria. Jeśli nie, zostajesz w etapie $etap, a kolejne etapy przesuwają się o dzień.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 8),
        for (final k in e.kryteria)
          Punkt(k.auto == null ? k.tekst : '${k.tekst} *(aplikacja sprawdzi sama)*', styl: t.bodyLarge),
        const SizedBox(height: 8),
        Text('Sprawdzanie kryteriów i przejście do etapu ${etap + 1} dojdą w kolejnej wersji aplikacji, '
            'przed końcem minimum.', style: t.bodySmall),
      ],
    );
  }
}

class _Siatka extends StatelessWidget {
  const _Siatka({required this.dane, required this.kalendarz});

  final DaneAplikacji dane;
  final Kalendarz kalendarz;

  static const _odstep = 4.0;
  static const _etykieta = 26.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final przesuniecie = kalendarz.start.weekday - 1;
    final wiersze = ((przesuniecie + kalendarz.dlugosc) / 7).ceil();
    return LayoutBuilder(builder: (context, c) {
      final szer = (c.maxWidth - _etykieta - 6 * _odstep) / 7;
      final wys = szer * 1.12;
      Widget wiersz(Widget etykieta, List<Widget> komorki, {double? wysokosc}) => Padding(
            padding: const EdgeInsets.only(bottom: _odstep),
            child: Row(children: [
              SizedBox(width: _etykieta, child: etykieta),
              for (final (i, k) in komorki.indexed) ...[
                if (i > 0) const SizedBox(width: _odstep),
                SizedBox(width: szer, height: wysokosc, child: k),
              ],
            ]),
          );
      Widget komorka(int i) =>
          i < 0 || i >= kalendarz.dlugosc ? const SizedBox() : _Komorka(dane: dane, okienko: dane.okienkoNa(kalendarz.dni[i]));
      return Column(children: [
        wiersz(const SizedBox(), [for (final d in _dniKrotko) Center(child: Text(d, style: t.labelMedium))]),
        for (var r = 0; r < wiersze; r++)
          wiersz(
            Text('${r + 1}', style: t.labelMedium, textAlign: TextAlign.center),
            [for (var c = 0; c < 7; c++) komorka(r * 7 + c - przesuniecie)],
            wysokosc: wys,
          ),
      ]);
    });
  }
}

class _Komorka extends StatefulWidget {
  const _Komorka({required this.dane, required this.okienko});

  final DaneAplikacji dane;
  final Okienko okienko;

  @override
  State<_Komorka> createState() => _KomorkaState();
}

class _KomorkaState extends State<_Komorka> with SingleTickerProviderStateMixin {
  // Tylko dzisiejsze zamknięte okienko potrzebuje animacji drzwiczek.
  AnimationController? _kontroler;

  AnimationController get _drzwi =>
      _kontroler ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void dispose() {
    _kontroler?.dispose();
    super.dispose();
  }

  bool get _zamkniete => widget.okienko.dzis && !widget.dane.okienkoOtwarte;

  Future<void> _stukniecie() async {
    final o = widget.okienko;
    if (_zamkniete) {
      await _drzwi.forward();
      await widget.dane.otworzOkienko();
      if (mounted) pokazDzien(context, widget.dane, o.dzien);
      return;
    }
    if (o.stan == StanOkienka.przyszle) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('To okienko otworzy się ${dataSlownieKrotko(o.data)}. Przytrzymaj, żeby podejrzeć.'),
        ));
      return;
    }
    pokazDzien(context, widget.dane, o.dzien);
  }

  Future<void> _przytrzymanie() async {
    final o = widget.okienko;
    if (o.odznaczone && widget.dane.moznaOdznaczyc(o.data)) {
      await cofnijOdznaczenie(context, widget.dane, o.data);
    } else if (!_zamkniete) {
      pokazDzien(context, widget.dane, o.dzien);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.okienko;
    final kolory = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final zablokowane = o.stan == StanOkienka.zablokowane;
    final tlo = switch (o.stan) {
      StanOkienka.wykonane || StanOkienka.skrocone => kolory.surfaceContainerHighest,
      StanOkienka.pominiete => Colors.transparent,
      StanOkienka.zablokowane => kolory.surfaceContainerLowest,
      _ => kolory.surfaceContainer,
    };
    final wyszarz = kolory.onSurface.withValues(alpha: 0.38);

    final srodek = switch (o.stan) {
      StanOkienka.wykonane => Icon(Icons.check, color: kolory.primary, size: 22),
      StanOkienka.skrocone => Text('½', style: t.titleLarge?.copyWith(color: kolory.primary)),
      StanOkienka.pominiete => Icon(Icons.close, color: wyszarz, size: 20),
      StanOkienka.wolne => Icon(Icons.spa_outlined, color: kolory.tertiary, size: 20),
      StanOkienka.zablokowane => Icon(Icons.lock_outline, color: wyszarz, size: 16),
      StanOkienka.czeka || StanOkienka.przyszle => Text(o.sesja, style: t.titleMedium),
    };

    final tresc = Stack(children: [
      Positioned(
        left: 4,
        top: 2,
        child: Text('${o.data.day}', style: t.labelSmall?.copyWith(color: zablokowane ? wyszarz : null)),
      ),
      if (o.strefa != null) Positioned(right: 4, top: 4, child: Kropka(o.strefa!, rozmiar: 8)),
      if (o.test) Positioned(left: 3, bottom: 6, child: Icon(Icons.explore_outlined, size: 12, color: kolory.secondary)),
      Center(child: srodek),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          height: 3,
          color: kolorEtapu[o.dzien.etap]!.withValues(alpha: zablokowane ? 0.35 : 1),
        ),
      ),
    ]);

    return Semantics(
      button: true,
      label: '${dataSlownie(o.data)}, ${_opisStanu(o)}',
      child: GestureDetector(
        onTap: _stukniecie,
        onLongPress: _przytrzymanie,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tlo,
              border: Border.all(
                color: o.dzis ? kolory.primary : kolory.outlineVariant,
                width: o.dzis ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _zamkniete
                ? AnimatedBuilder(
                    animation: _drzwi,
                    builder: (context, _) => Stack(children: [
                      tresc,
                      Positioned.fill(
                        child: Transform(
                          alignment: Alignment.centerLeft,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002)
                            ..rotateY(-_drzwi.value * math.pi / 2),
                          child: _Drzwi(kolor: kolory.primary, dzien: o.data.day),
                        ),
                      ),
                    ]),
                  )
                : tresc,
          ),
        ),
      ),
    );
  }
}

/// Zamknięte drzwiczki dzisiejszego okienka.
class _Drzwi extends StatelessWidget {
  const _Drzwi({required this.kolor, required this.dzien});

  final Color kolor;
  final int dzien;

  @override
  Widget build(BuildContext context) {
    final na = Theme.of(context).colorScheme.onPrimary;
    return Container(
      color: kolor,
      child: Stack(children: [
        Center(child: Text('$dzien', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: na))),
        Positioned(
          right: 3,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(width: 5, height: 5, decoration: BoxDecoration(color: na, shape: BoxShape.circle)),
          ),
        ),
      ]),
    );
  }
}

String _opisStanu(Okienko o) => switch (o.stan) {
      StanOkienka.czeka => 'dziś',
      StanOkienka.wykonane => 'zrobione',
      StanOkienka.skrocone => 'zrobiona część',
      StanOkienka.pominiete => 'pominięte',
      StanOkienka.wolne => 'dzień wolny',
      StanOkienka.przyszle => 'sesja ${o.sesja}',
      StanOkienka.zablokowane => 'czeka na kryteria',
    };

class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodySmall;
    final kolory = Theme.of(context).colorScheme;
    Widget poz(Widget ikona, String tekst) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 22, child: Center(child: ikona)),
          const SizedBox(width: 4),
          Text(tekst, style: t),
        ]);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        poz(Text('R', style: Theme.of(context).textTheme.titleSmall), 'rutyna 15 min'),
        poz(Icon(Icons.check, size: 18, color: kolory.primary), 'zrobione'),
        poz(Text('½', style: TextStyle(color: kolory.primary)), 'część'),
        poz(const Icon(Icons.close, size: 18), 'pominięte'),
        poz(Icon(Icons.spa_outlined, size: 18, color: kolory.tertiary), 'wolne'),
        poz(const Icon(Icons.lock_outline, size: 16), 'czeka na kryteria'),
        poz(Icon(Icons.explore_outlined, size: 14, color: kolory.secondary), 'test kierunkowy'),
        poz(const Row(mainAxisSize: MainAxisSize.min, children: [
          Kropka(Strefa.zielona, rozmiar: 6),
          Kropka(Strefa.zolta, rozmiar: 6),
          Kropka(Strefa.czerwona, rozmiar: 6),
        ]), 'ból po treningu'),
      ],
    );
  }
}

/// Szczegóły dnia z akcjami: zrobiłem bez aplikacji, dzień wolny, ocena, cofnięcie.
void pokazDzien(BuildContext context, DaneAplikacji dane, DzienPlanu d) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _ArkuszDnia(dane: dane, dzien: d),
      ),
    ),
  );
}

Future<void> cofnijOdznaczenie(BuildContext context, DaneAplikacji dane, DateTime d) async {
  final tak = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Cofnąć odznaczenie?'),
      content: Text('${dataSlownie(d)}: trening i ocena bólu z tego dnia zostaną usunięte.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nie')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cofnij')),
      ],
    ),
  );
  if (tak == true) await dane.cofnijOdznaczenie(d);
}

class _ArkuszDnia extends StatelessWidget {
  const _ArkuszDnia({required this.dane, required this.dzien});

  final DaneAplikacji dane;
  final DzienPlanu dzien;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dane,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final o = dane.okienkoNa(dzien);
        final etap = dane.plan.etap(dzien.etap);
        final sesja = dane.plan.sesje[o.sesja]!;
        final zapis = o.zapis;
        final ocena = zapis?.ocena;
        final checkin = dane.stan.checkiny[iso(dzien.data)];
        final test = dane.stan.testKierunkowy;
        final mozna = dane.moznaOdznaczyc(dzien.data);
        final przyszly = o.stan == StanOkienka.przyszle || o.stan == StanOkienka.zablokowane;

        final stan = switch (o.stan) {
          StanOkienka.wykonane => '✓ Zrobione${zapis!.recznie ? ' (bez aplikacji)' : ''}',
          StanOkienka.skrocone => '½ Zrobiona część (${zapis!.wykonane.length} ćwiczeń)',
          StanOkienka.pominiete => 'Nieodznaczone',
          StanOkienka.wolne => 'Dzień wolny',
          StanOkienka.czeka => 'Dziś, jeszcze przed treningiem',
          StanOkienka.przyszle => 'Podgląd',
          StanOkienka.zablokowane => 'Czeka na kryteria przejścia',
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_wielka(dataSlownie(dzien.data)), style: t.titleLarge),
            Text('Dzień ${dzien.nr} planu · Etap ${etap.nr}: ${etap.nazwa} · tydzień ${dzien.tydzienEtapu}',
                style: t.bodyMedium),
            const SizedBox(height: 12),
            Text(sesja.nazwa + (sesja.minuty == null ? '' : ' · ok. ${sesja.minuty} min'), style: t.titleMedium),
            Text(stan, style: t.bodyLarge),
            if (ocena != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Kropka(ocena.strefa),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ból po treningu: ${ocena.bol}/10, ${nazwaZasiegu(ocena.zasieg).toLowerCase()}'
                    '${ocena.mrowienie ? ', mrowienie' : ''}'
                    '${ocena.minelo == null ? '' : ocena.minelo! ? ' · minął do rana' : ' · nie minął do rana'}',
                    style: t.bodyLarge,
                  ),
                ),
              ]),
              if (ocena.nasililo != null)
                Text('Nasiliło ból: ${dane.plan.cwiczenia[ocena.nasililo]?.nazwa ?? ocena.nasililo}', style: t.bodyMedium),
            ],
            if (checkin != null)
              Text('Rano: ból ${checkin.bol}/10, ${nazwaZasiegu(checkin.zasieg).toLowerCase()}', style: t.bodyMedium),
            if (test != null && test.data == dzien.data)
              Text('Test kierunkowy: ${nazwaWyniku(test.wynik)}', style: t.bodyMedium),
            if (o.stan == StanOkienka.zablokowane) ...[
              const SizedBox(height: 12),
              _Kryteria(dane: dane, etap: dane.dzisiaj.etap),
            ] else if (przyszly) ...[
              const SizedBox(height: 8),
              if (!sesja.wkrotce)
                for (final c in dane.rozpiszNa(dzien).cwiczenia) Punkt(c.cwiczenie.nazwa, styl: t.bodyMedium),
            ],
            if (mozna) ...[
              const SizedBox(height: 16),
              if (!o.odznaczone && o.stan != StanOkienka.wolne)
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Zrobiłem bez aplikacji'),
                  onPressed: () => dane.oznaczRecznie(dzien),
                ),
              if (o.odznaczone && ocena == null)
                FilledButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Oceń ból po treningu'),
                  onPressed: () => ocenTrening(context, dane, dzien.data),
                ),
              if (!o.odznaczone)
                OutlinedButton.icon(
                  icon: const Icon(Icons.spa_outlined),
                  label: Text(o.stan == StanOkienka.wolne ? 'Cofnij dzień wolny' : 'Dzień wolny'),
                  onPressed: () => dane.ustawWolne(dzien.data, o.stan != StanOkienka.wolne),
                ),
              if (o.odznaczone)
                TextButton(
                  onPressed: () => cofnijOdznaczenie(context, dane, dzien.data),
                  child: const Text('Cofnij odznaczenie'),
                ),
            ] else if (o.stan == StanOkienka.pominiete) ...[
              const SizedBox(height: 8),
              Text('Odznaczyć można do $dniWstecz dni wstecz.', style: t.bodySmall),
            ],
          ],
        );
      },
    );
  }
}

String _wielka(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
