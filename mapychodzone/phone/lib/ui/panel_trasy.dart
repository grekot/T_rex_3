import 'package:flutter/material.dart';

import '../trasa/plan.dart';
import '../trasa/trasa.dart';
import 'profil_wysokosci.dart';

/// Nazwa punktu planu do wyświetlenia: nazwa z mapy albo „Start”, „Przystanek 2”, „Cel”.
String nazwaPunktu(PlanTrasy plan, int i, {bool powrot = false}) {
  final p = plan.punkty[i];
  final z = p.nazwa;
  final rodzaj = switch (p.rodzaj) {
    RodzajPunktu.start => 'Start',
    RodzajPunktu.cel => powrot ? 'Punkt zawrócenia' : 'Cel',
    RodzajPunktu.przystanek => 'Przystanek ${plan.numerPrzystanku(i)}',
    RodzajPunktu.przez => 'Punkt „przez”',
  };
  return z == null ? rodzaj : '$rodzaj: $z';
}

/// Dolny panel planowania trasy: tryb, liczby, profil wysokości, odcinki, przyciski.
class PanelTrasy extends StatelessWidget {
  const PanelTrasy({
    super.key,
    required this.plan,
    required this.trasa,
    required this.odcinki,
    required this.tryb,
    required this.powrot,
    required this.unikajStromych,
    required this.liczy,
    required this.blad,
    required this.onTryb,
    required this.onPowrot,
    required this.onUnikajStromych,
    required this.onCofnij,
    required this.onWyczysc,
  });

  final PlanTrasy plan;
  final Trasa? trasa;
  final List<Odcinek> odcinki;
  final TrybTrasy tryb;

  /// Trasa wraca do startu tą samą drogą.
  final bool powrot;

  /// BRouter omija podejścia stromsze niż ok. 15 %.
  final bool unikajStromych;
  final bool liczy;
  final String? blad;
  final ValueChanged<TrybTrasy> onTryb;
  final ValueChanged<bool> onPowrot;
  final ValueChanged<bool> onUnikajStromych;
  final VoidCallback onCofnij;
  final VoidCallback onWyczysc;

  @override
  Widget build(BuildContext context) {
    final teksty = Theme.of(context).textTheme;
    final t = trasa;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
      child: Card(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<TrybTrasy>(
                  // bez ikon: z ikoną „Szlakami” łamało się na dwie linie
                  segments: const [
                    ButtonSegment(value: TrybTrasy.szlakami, label: Text('Szlakami')),
                    ButtonSegment(value: TrybTrasy.szlakiISkroty, label: Text('Ze skrótami')),
                    ButtonSegment(value: TrybTrasy.najkrocej, label: Text('Najkrócej')),
                  ],
                  selected: {tryb},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (s) => onTryb(s.first),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  FilterChip(
                    avatar: powrot ? null : const Icon(Icons.u_turn_left, size: 18),
                    label: const Text('Powrót tą samą drogą'),
                    selected: powrot,
                    visualDensity: VisualDensity.compact,
                    onSelected: onPowrot,
                  ),
                  FilterChip(
                    avatar: unikajStromych ? null : const Icon(Icons.trending_up, size: 18),
                    label: const Text('Unikaj stromych'),
                    tooltip: 'Omija podejścia stromsze niż ok. 15 %',
                    selected: unikajStromych,
                    visualDensity: VisualDensity.compact,
                    onSelected: onUnikajStromych,
                  ),
                ],
              ),
              if (liczy) const LinearProgressIndicator(),
              if (blad != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(blad!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (plan.dlugosc == 1 && !liczy)
                Text('Start ustawiony. Przytrzymaj palec na mapie w miejscu celu.', style: teksty.bodyMedium),
              if (t != null) ...[
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _Liczba(Icons.straighten, opisDlugosci(t.dlugosc)),
                    _Liczba(Icons.north_east, '${t.podejscia.round()} m'),
                    _Liczba(Icons.south_east, '${t.zejscia.round()} m'),
                    _Liczba(Icons.schedule, opisCzasu(t.czas)),
                  ],
                ),
                const SizedBox(height: 8),
                ProfilWysokosci(trasa: t),
                if (odcinki.length > 1) ...[
                  // przy powrocie: tam + z powrotem, nawet bez przystanków
                  const SizedBox(height: 6),
                  Text(powrot ? 'Odcinki (tam i z powrotem)' : 'Odcinki między przystankami', style: teksty.labelLarge),
                  for (final (i, o) in odcinki.indexed) _WierszOdcinka(numer: i + 1, plan: plan, odcinek: o, powrot: powrot),
                ],
                const SizedBox(height: 4),
                Text(
                  'Przytrzymaj palec na mapie: prowadź tędy, przystanek albo nowy cel. '
                  'Przeciągnij punkt, żeby go przesunąć; dotknij, żeby zmienić lub usunąć.',
                  style: teksty.bodySmall,
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(onPressed: onCofnij, icon: const Icon(Icons.undo), label: const Text('Cofnij')),
                  TextButton.icon(onPressed: onWyczysc, icon: const Icon(Icons.close), label: const Text('Wyczyść')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WierszOdcinka extends StatelessWidget {
  const _WierszOdcinka({required this.numer, required this.plan, required this.odcinek, required this.powrot});

  final int numer;
  final PlanTrasy plan;
  final Odcinek odcinek;
  final bool powrot;

  @override
  Widget build(BuildContext context) {
    final teksty = Theme.of(context).textTheme;
    final o = odcinek;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text('$numer.', style: teksty.bodySmall)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.powrot ? 'Powrót do startu' : 'do: ${nazwaPunktu(plan, o.doIndeksu, powrot: powrot)}', style: teksty.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${opisDlugosci(o.dlugosc)} · ↑${o.podejscia.round()} m · ↓${o.zejscia.round()} m · ${opisCzasu(o.czas)}',
                  style: teksty.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Liczba extends StatelessWidget {
  const _Liczba(this.ikona, this.tekst);
  final IconData ikona;
  final String tekst;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikona, size: 18),
        const SizedBox(width: 4),
        Text(tekst, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
