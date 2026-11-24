import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../silnik/daty.dart';
import '../urzadzenie.dart';
import 'daty_slownie.dart';
import 'ekran_treningu.dart';
import 'tekst_md.dart';

/// Ekran bezpieczeństwa (plan aplikacji, sekcja 8): czerwone flagi z przyciskiem 112,
/// kiedy do specjalisty, gdy ból wraca (z rutyną skróconą), czego unikać do kiedy.
class EkranBezpieczenstwa extends StatelessWidget {
  const EkranBezpieczenstwa({super.key, required this.dane, this.urzadzenie = const Urzadzenie()});

  final DaneAplikacji dane;
  final Urzadzenie urzadzenie;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final blad = Theme.of(context).colorScheme.error;
    final plan = dane.plan;
    final tx = plan.teksty;
    final (odTyg, doTyg) = (tx.czegoUnikacTygodnie.min.round(), tx.czegoUnikacTygodnie.max.round());
    final unikajDo = dodajDni(dane.stan.start, doTyg * 7);
    final sesja = plan.sesje[dane.dzisiaj.sesja]!;

    Widget sekcja(String tytul, List<String> punkty, {Color? kolor}) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tytul, style: t.titleLarge?.copyWith(color: kolor)),
              const SizedBox(height: 4),
              for (final p in punkty) Punkt(p, styl: t.bodyLarge),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Bezpieczeństwo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          sekcja('Czerwone flagi: od razu do lekarza lub na SOR', tx.czerwoneFlagi, kolor: blad),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => urzadzenie.zadzwon('112'),
            style: FilledButton.styleFrom(
              backgroundColor: blad,
              foregroundColor: Theme.of(context).colorScheme.onError,
              minimumSize: const Size.fromHeight(56),
            ),
            icon: const Icon(Icons.call),
            label: const Text('Zadzwoń 112', style: TextStyle(fontSize: 20)),
          ),
          Text('Otwiera ekran wybierania numeru. Nie dzwoni sam.', style: t.bodySmall),
          if (dane.zalecenieFizjo)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Card(
                child: ListTile(
                  leading: Icon(Icons.medical_services_outlined, color: blad),
                  title: const Text('Umów fizjoterapeutę lub lekarza'),
                  subtitle: const Text('Ból poniżej kolana albo mrowienie wracało w ostatnich dniach.'),
                ),
              ),
            ),
          sekcja('Kiedy iść do specjalisty', tx.kiedyDoSpecjalisty),
          sekcja('Gdy ból wraca', tx.gdyBolWraca),
          if (sesja.krotszaWersja.isNotEmpty && !sesja.wkrotce) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text('Rutyna skrócona (ćw. ${sesja.krotszaWersja.first.$1 + 1}–${sesja.krotszaWersja.first.$2 + 1})'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EkranTreningu(dane: dane, rozpiska: dane.rozpiszDzis(czesc: 0), czesc: 0),
              )),
            ),
          ],
          sekcja('Sygnalizacja świetlna', [
            for (final MapEntry(:key, :value) in tx.sygnalizacja.entries)
              '**${{'zielona': 'Zielona', 'zolta': 'Żółta', 'czerwona': 'Czerwona'}[key]}:** ${value.bol} ${value.coRobisz}',
          ]),
          sekcja('Centralizacja i peryferyzacja', tx.centralizacja),
          sekcja(
            'Czego na razie unikać (pierwsze $odTyg–$doTyg tygodni, do ok. ${dataSlownieKrotko(unikajDo)})',
            tx.czegoUnikac,
          ),
          const SizedBox(height: 20),
          TekstMd(plan.zastrzezenie, styl: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}
