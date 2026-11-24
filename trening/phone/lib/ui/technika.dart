import 'package:flutter/material.dart';

import '../plan/atlas.dart';
import '../trening/rozpiska.dart';
import 'tekst_md.dart';

/// Arkusz „Technika”: pełny opis z atlasu, rysunek, uwagi, zasady wspólne.
Future<void> pokazTechnike(BuildContext context, CwiczenieSesji c, List<String> zasadyWspolne) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, przewijanie) => ArkuszTechniki(c, zasadyWspolne, przewijanie: przewijanie),
    ),
  );
}

class ArkuszTechniki extends StatelessWidget {
  const ArkuszTechniki(this.c, this.zasadyWspolne, {super.key, this.przewijanie});

  final CwiczenieSesji c;
  final List<String> zasadyWspolne;
  final ScrollController? przewijanie;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = c.atlas;
    final r = c.rysunek;
    return ListView(
      controller: przewijanie,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Text(c.cwiczenie.nazwa, style: t.headlineSmall),
        if (r != null) ...[
          const SizedBox(height: 12),
          RysunekCwiczenia(r),
          Text(podpisAI, style: t.bodySmall),
        ],
        if (c.cwiczenie.jak != null) ...[
          const SizedBox(height: 16),
          Text('Z planu', style: t.titleMedium),
          const SizedBox(height: 4),
          TekstMd(c.cwiczenie.jak!, styl: t.bodyLarge),
        ],
        if (c.cwiczenie.uwaga != null) ...[
          const SizedBox(height: 8),
          TekstMd(c.cwiczenie.uwaga!, styl: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
        ],
        if (a != null)
          for (final s in a.sekcje) _Sekcja(s),
        if (zasadyWspolne.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Zasady wspólne dla wszystkich ćwiczeń', style: t.titleMedium),
            children: [for (final z in zasadyWspolne) Punkt(z, styl: t.bodyMedium)],
          ),
      ],
    );
  }
}

class _Sekcja extends StatelessWidget {
  const _Sekcja(this.s);

  final SekcjaAtlasu s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final przerwij = s.rodzaj == 'przerwijJesli';
    final kolor = przerwij ? Theme.of(context).colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.tytul.isNotEmpty) Text(s.tytul, style: t.titleMedium?.copyWith(color: kolor)),
          if (s.tekst != null) TekstMd(s.tekst!, styl: t.bodyLarge?.copyWith(color: kolor)),
          for (final (i, p) in s.punkty.indexed)
            Punkt(p, znak: s.numerowane ? '${i + 1}.' : '•', styl: t.bodyLarge),
        ],
      ),
    );
  }
}

/// Rysunki atlasu powstały w Gemini; warunki Google zabraniają podawać je jako dzieło człowieka.
const podpisAI = 'Rysunek poglądowy wygenerowany przez AI (Gemini). Obowiązuje opis.';

/// Rysunek z atlasu; stuknięcie otwiera pełny ekran z przybliżaniem. Pod spodem uwaga,
/// gdy rysunek odbiega od opisu (obowiązuje opis).
class RysunekCwiczenia extends StatelessWidget {
  const RysunekCwiczenia(this.r, {super.key, this.wysokosc});

  final Rysunek r;
  final double? wysokosc;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black, title: Text(r.podpis ?? r.opis)),
              body: Column(children: [
                Expanded(child: Center(child: InteractiveViewer(maxScale: 5, child: Image.asset(r.asset)))),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('$podpisAI ${r.uwaga ?? ''}'.trim(), style: const TextStyle(color: Colors.white70)),
                  ),
                ),
              ]),
            ),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Colors.white,
              height: wysokosc,
              child: Image.asset(r.asset, fit: BoxFit.contain, semanticLabel: r.opis),
            ),
          ),
        ),
        if (r.uwaga != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Rysunek poglądowy. ${r.uwaga} Obowiązuje opis.',
                style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
}
