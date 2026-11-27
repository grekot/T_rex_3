import 'package:flutter/material.dart';

import '../trasa/trasa.dart';
import 'profil_wysokosci.dart';

/// Dolny panel planowania trasy: podpowiedź, liczby, profil wysokości, przyciski.
class PanelTrasy extends StatelessWidget {
  const PanelTrasy({
    super.key,
    required this.liczbaPunktow,
    required this.trasa,
    required this.liczy,
    required this.blad,
    required this.onCofnij,
    required this.onWyczysc,
  });

  final int liczbaPunktow;
  final Trasa? trasa;
  final bool liczy;
  final String? blad;
  final VoidCallback onCofnij;
  final VoidCallback onWyczysc;

  @override
  Widget build(BuildContext context) {
    final teksty = Theme.of(context).textTheme;
    final t = trasa;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (liczy) const LinearProgressIndicator(),
            if (blad != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(blad!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (liczbaPunktow == 1 && !liczy)
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
              if (liczbaPunktow >= 2)
                Text('Przytrzymaj palec na mapie, aby przedłużyć trasę.', style: teksty.bodySmall),
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
