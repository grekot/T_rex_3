import 'package:flutter/material.dart';

import '../plan/model.dart';
import 'tekst_md.dart';

/// Czerwone flagi i teksty bezpieczeństwa z planu. Pełny ekran (z numerem 112
/// i powiązaniem z oceną bólu) przychodzi w wersji 0.1.
class EkranBezpieczenstwa extends StatelessWidget {
  const EkranBezpieczenstwa({super.key, required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final blad = Theme.of(context).colorScheme.error;
    final tx = plan.teksty;
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
          sekcja('Sygnalizacja świetlna', [
            for (final MapEntry(:key, :value) in tx.sygnalizacja.entries)
              '${{'zielona': '🟢', 'zolta': '🟡', 'czerwona': '🔴'}[key]} ${value.bol} ${value.coRobisz}',
          ]),
          sekcja('Centralizacja i peryferyzacja', tx.centralizacja),
          sekcja('Gdy ból wraca', tx.gdyBolWraca),
          sekcja('Kiedy iść do specjalisty', tx.kiedyDoSpecjalisty),
          sekcja('Czego na razie unikać (pierwsze ${tx.czegoUnikacTygodnie} tygodni)', tx.czegoUnikac),
          const SizedBox(height: 20),
          TekstMd(plan.zastrzezenie, styl: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}
