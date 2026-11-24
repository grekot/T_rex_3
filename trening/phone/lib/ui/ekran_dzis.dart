import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../dane/stan.dart';
import '../przypomnienia/harmonogram.dart';
import '../silnik/kalendarz.dart';
import '../silnik/sygnalizacja.dart';
import '../trening/rozpiska.dart';
import '../trening/test_kierunkowy.dart';
import 'daty_slownie.dart';
import 'ekran_testu.dart';
import 'ekran_treningu.dart';
import 'ocena.dart';

/// Ekran startowy: poranny check-in, dzisiejsza sesja ze Startem, ocena po
/// treningu, zadania dnia, spacer, przerwy w siedzeniu.
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
        final test = dane.stan.testKierunkowy;
        final cel = celSpaceru(etap, d.tydzienEtapu);
        final u = dane.stan.przypomnienia;

        return Scaffold(
          appBar: AppBar(title: const Text('Dziś'), actions: [PrzyciskBezpieczenstwa(dane: dane)]),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(dataSlownie(dane.dzis), style: t.titleMedium),
              Text('Dzień ${d.nr} planu · Etap ${etap.nr}: ${etap.nazwa} · tydzień ${d.tydzienEtapu}',
                  style: t.bodyLarge),
              const SizedBox(height: 12),
              ..._rano(context),
              if (dane.zalecenieFizjo) _Fizjo(dane: dane),
              _KartaSesji(dane: dane),
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
              if (u.przerwy && u.przerwyDni.contains(dane.teraz.weekday))
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.chair_alt_outlined),
                    title: const Text('Pali dziś w krzyżu'),
                    subtitle: Text(dane.paliDzis
                        ? 'Przerwy co ${UstawieniaPrzypomnien.przerwyCoGdyPali} min do ${godzina(u.przerwyDo)}'
                        : 'Przerwy w siedzeniu co ${u.przerwyCo} min, ${godzina(u.przerwyOd)}–${godzina(u.przerwyDo)}'),
                    value: dane.paliDzis,
                    onChanged: dane.ustawPaliDzis,
                  ),
                ),
              const SizedBox(height: 16),
              Text(dane.plan.zastrzezenie, style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
  }

  /// Poranny check-in albo jego wynik.
  List<Widget> _rano(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (dane.potrzebnyCheckin) {
      final wczoraj = dane.pytajCzyMinelo;
      return [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Jak plecy rano?'),
            subtitle: Text(wczoraj == null
                ? '2 pytania, 10 sekund'
                : '2 pytania i czy minął ból po wczorajszym treningu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pokazCheckin(context, dane),
          ),
        ),
      ];
    }
    final c = dane.checkinDzis;
    if (c == null) return const [];
    final w = ocenStrefe(OcenaBolu(bol: c.bol, zasieg: c.zasieg), odniesienie: dane.odniesienie(dane.dzis));
    return [
      Row(children: [
        Kropka(w.strefa),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Rano: ból ${c.bol}/10, ${nazwaZasiegu(c.zasieg).toLowerCase()}', style: t.bodyLarge),
        ),
      ]),
      if (w.strefa != Strefa.zielona || w.cofaSie) KartaStrefy(dane: dane, wynik: w, bol: c.bol, rano: true),
      const SizedBox(height: 4),
    ];
  }

  void _test(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EkranTestu(dane: dane)));
  }
}

class _Fizjo extends StatelessWidget {
  const _Fizjo({required this.dane});

  final DaneAplikacji dane;

  @override
  Widget build(BuildContext context) {
    final blad = Theme.of(context).colorScheme.error;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: blad)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nie czekaj do końca etapu: umów fizjoterapeutę lub lekarza',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Ból poniżej kolana albo mrowienie wracało w ostatnich dniach.'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: dane.fizjoUmowione, child: const Text('Umówione')),
            ),
          ],
        ),
      ),
    );
  }
}

class _KartaSesji extends StatelessWidget {
  const _KartaSesji({required this.dane});

  final DaneAplikacji dane;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kolory = Theme.of(context).colorScheme;
    final sesja = dane.plan.sesje[dane.dzisiaj.sesja]!;
    final zapis = dane.treningDzis;
    final ocena = zapis?.ocena;
    final wolne = dane.wolneDzis;
    final rozpiska = sesja.wkrotce ? null : dane.rozpiszDzis();

    return Card(
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
                style: t.titleMedium?.copyWith(color: kolory.primary),
              ),
              if (ocena != null)
                Row(children: [
                  Kropka(ocena.strefa),
                  const SizedBox(width: 8),
                  Text('Ból po treningu: ${ocena.bol}/10 · ${nazwaStrefy(ocena.strefa).toLowerCase()}',
                      style: t.bodyLarge),
                ])
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Oceń ból po treningu'),
                    onPressed: () => ocenTrening(context, dane, dane.dzis),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            if (wolne) ...[
              Row(children: [
                Icon(Icons.spa_outlined, color: kolory.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Dziś wolne. Dzień przerwy nie psuje postępu.', style: t.bodyLarge)),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => dane.ustawWolne(dane.dzis, false), child: const Text('Jednak ćwiczę')),
              ),
            ] else if (rozpiska == null)
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
              for (final p in rozpiska.pominiete)
                _Wiersz(
                  p.cwiczenie.nazwa,
                  p.powod,
                  wylaczone: true,
                  onTap: p.wstrzymaneDo == null ? null : () => _przywroc(context, p),
                ),
              if (zapis == null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.spa_outlined),
                    label: const Text('Dziś wolne'),
                    onPressed: () => dane.ustawWolne(dane.dzis, true),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _start(BuildContext context, Rozpiska r, {int? czesc}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EkranTreningu(dane: dane, rozpiska: r, czesc: czesc),
    ));
  }

  Future<void> _przywroc(BuildContext context, PominieteCwiczenie p) async {
    final tak = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Przywrócić „${p.cwiczenie.nazwa}”?'),
        content: const Text('Wróci do sesji od dziś. Jeśli znowu nasili ból, przerwij je przyciskiem „Boli: pomiń”.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nie')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Przywróć')),
        ],
      ),
    );
    if (tak == true) await dane.przywroc(p.cwiczenie.id);
  }
}

class _Wiersz extends StatelessWidget {
  const _Wiersz(this.nazwa, this.opis, {this.wylaczone = false, this.onTap});

  final String nazwa;
  final String opis;
  final bool wylaczone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final styl = wylaczone ? TextStyle(color: Theme.of(context).disabledColor) : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: Text(nazwa, style: t.bodyLarge?.merge(styl))),
            const SizedBox(width: 8),
            Expanded(flex: 4, child: Text(opis, style: t.bodyMedium?.merge(styl))),
            if (onTap != null) Icon(Icons.undo, size: 18, color: Theme.of(context).disabledColor),
          ],
        ),
      ),
    );
  }
}
