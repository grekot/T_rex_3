import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../dane/stan.dart';
import '../silnik/kalendarz.dart';
import '../trening/rozpiska.dart';
import '../trening/test_kierunkowy.dart';
import 'ekran_bezpieczenstwa.dart';
import 'ekran_testu.dart';
import 'ekran_treningu.dart';

const _miesiace = [
  'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', //
  'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia',
];
const _dni = ['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'];

String dataSlownie(DateTime d) => '${_dni[d.weekday - 1]}, ${d.day} ${_miesiace[d.month - 1]}';

/// Ekran startowy: dzisiejszy dzień planu, sesja ze Startem, zadania dnia.
/// Kalendarz z okienkami, ocena bólu i przypomnienia przychodzą w wersji 0.1.
class EkranDzis extends StatelessWidget {
  const EkranDzis({super.key, required this.dane});

  final DaneAplikacji dane;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dane,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final d = dane.dzisiaj;
        final etap = dane.plan.etap(d.etap);
        final sesja = dane.plan.sesje[d.sesja]!;
        final zapis = dane.treningDzis;
        final test = dane.stan.testKierunkowy;
        final cel = celSpaceru(etap, d.tydzienEtapu);
        final rozpiska = sesja.wkrotce ? null : dane.rozpiszDzis();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Trening'),
            actions: [
              IconButton(
                tooltip: 'Bezpieczeństwo',
                icon: const Icon(Icons.shield_outlined),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => EkranBezpieczenstwa(plan: dane.plan))),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(dataSlownie(dane.dzis), style: t.titleMedium),
              Text('Dzień ${d.nr} planu · Etap ${etap.nr}: ${etap.nazwa} · tydzień ${d.tydzienEtapu}',
                  style: t.bodyLarge),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(sesja.nazwa, style: t.headlineSmall),
                      if (sesja.minuty != null) Text('ok. ${sesja.minuty} min', style: t.bodyLarge),
                      if (zapis != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          zapis.stan == StanDnia.wykonane
                              ? '✓ Dziś zrobione'
                              : '½ Dziś zrobiona część (${zapis.wykonane.length} ćwiczeń)',
                          style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (rozpiska == null)
                        Text('Ta sesja dojdzie w kolejnej wersji aplikacji.', style: t.bodyLarge)
                      else ...[
                        FilledButton(
                          onPressed: () => _start(context, rozpiska),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          child: Text(zapis == null ? 'Start' : 'Zrób jeszcze raz', style: const TextStyle(fontSize: 20)),
                        ),
                        if (sesja.krotszaWersja.length == 2) ...[
                          const SizedBox(height: 8),
                          Text('Gorszy dzień? Dwie krótsze wersje:', style: t.bodyMedium),
                          Row(
                            children: [
                              for (final (i, (od, do_)) in sesja.krotszaWersja.indexed) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _start(context, dane.rozpiszDzis(czesc: i), czesc: i),
                                    child: Text('${zapis?.czesci.contains(i) ?? false ? '✓ ' : ''}'
                                        'Ćw. ${od + 1}–${do_ + 1}'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        for (final c in rozpiska.cwiczenia) _Wiersz(c.cwiczenie.nazwa, opisDawki(c)),
                        for (final p in rozpiska.pominiete) _Wiersz(p.cwiczenie.nazwa, p.powod, wylaczone: true),
                      ],
                    ],
                  ),
                ),
              ),
              if (test == null || d.zadania.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Zadania na dziś', style: t.titleMedium),
              ],
              if (test == null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.explore_outlined),
                    title: const Text('Test kierunkowy (ok. 5 min)'),
                    subtitle: Text(dane.plan.testKierunkowy.kiedy),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _test(context),
                  ),
                )
              else
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.explore_outlined),
                    title: Text('Test kierunkowy: ${nazwaWyniku(test.wynik)}'),
                    subtitle: Text(dane.plan.testKierunkowy.wyniki[test.wynik.name]!.coRobisz),
                    trailing: TextButton(onPressed: () => _test(context), child: const Text('Powtórz')),
                  ),
                ),
              for (final id in d.zadania)
                for (final z in etap.zadania.where((z) => z.id == id && z.id != 'test-kierunkowy'))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(z.nazwa + (z.opcjonalne ? ' (opcjonalnie)' : '')),
                      subtitle: z.opis == null ? null : Text(z.opis!),
                    ),
                  ),
              if (cel != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_walk),
                    title: const Text('Spacer'),
                    subtitle: Text(cel.tekst),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(dane.plan.zastrzezenie, style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
  }

  void _start(BuildContext context, Rozpiska r, {int? czesc}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EkranTreningu(dane: dane, rozpiska: r, czesc: czesc),
    ));
  }

  void _test(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EkranTestu(dane: dane)));
  }
}

class _Wiersz extends StatelessWidget {
  const _Wiersz(this.nazwa, this.opis, {this.wylaczone = false});

  final String nazwa;
  final String opis;
  final bool wylaczone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final styl = wylaczone ? TextStyle(color: Theme.of(context).disabledColor) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: Text(nazwa, style: t.bodyLarge?.merge(styl))),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: Text(opis, style: t.bodyMedium?.merge(styl))),
        ],
      ),
    );
  }
}
