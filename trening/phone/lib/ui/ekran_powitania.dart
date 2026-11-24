import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../przypomnienia/harmonogram.dart';
import '../urzadzenie.dart';
import 'daty_slownie.dart';
import 'tekst_md.dart';

/// Pierwsze uruchomienie: zastrzeżenie, data startu planu, przypomnienia.
class EkranPowitania extends StatefulWidget {
  const EkranPowitania({super.key, required this.dane, this.urzadzenie = const Urzadzenie()});

  final DaneAplikacji dane;
  final Urzadzenie urzadzenie;

  @override
  State<EkranPowitania> createState() => _EkranPowitaniaState();
}

class _EkranPowitaniaState extends State<EkranPowitania> {
  late DateTime _start = widget.dane.dzis;
  bool _rozumiem = false;
  bool _przypomnienia = true;

  Future<void> _wybierzStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: widget.dane.dzis.subtract(const Duration(days: 120)),
      lastDate: widget.dane.dzis.add(const Duration(days: 30)),
      helpText: 'Data startu planu',
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _zaczynam() async {
    final u = widget.dane.stan.przypomnienia;
    if (_przypomnienia) {
      await widget.urzadzenie.poprosOPowiadomienia();
    } else {
      u
        ..trening = false
        ..przerwy = false;
    }
    await widget.dane.zakonczPowitanie(_start);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final plan = widget.dane.plan;
    final u = widget.dane.stan.przypomnienia;
    final dzis = widget.dane.dzis;
    final wstecz = _start.isBefore(dzis);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Trening', style: t.displaySmall),
            Text(plan.tytul, style: t.titleMedium),
            const SizedBox(height: 16),
            Text('Codziennie okienko w kalendarzu, prowadzenie treningu krok po kroku, ocena bólu po treningu '
                'i przypomnienia. Etapy zmieniają się według kryteriów z planu, nie według kalendarza.',
                style: t.bodyLarge),
            const SizedBox(height: 20),
            Text('Zanim zaczniesz', style: t.titleLarge),
            const SizedBox(height: 4),
            TekstMd(plan.zastrzezenie, styl: t.bodyLarge),
            const SizedBox(height: 8),
            Text('Od razu do lekarza lub na SOR, gdy:', style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
            for (final f in plan.teksty.czerwoneFlagi) Punkt(f, styl: t.bodyMedium),
            Text('Te informacje są zawsze pod ikoną tarczy w prawym górnym rogu.', style: t.bodySmall),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _rozumiem,
              onChanged: (v) => setState(() => _rozumiem = v ?? false),
              title: const Text('Rozumiem'),
            ),
            const SizedBox(height: 12),
            Text('Kiedy zaczynasz plan?', style: t.titleLarge),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(dataPelna(_start), style: t.titleMedium),
              subtitle: Text(wstecz
                  ? 'Dni od tej daty do wczoraj odznaczysz w kalendarzu: „Zrobiłem bez aplikacji”.'
                  : 'Pierwsze okienko kalendarza to ten dzień.'),
              trailing: TextButton(onPressed: _wybierzStart, child: const Text('Zmień')),
            ),
            const SizedBox(height: 12),
            Text('Przypomnienia', style: t.titleLarge),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _przypomnienia,
              onChanged: (v) => setState(() => _przypomnienia = v),
              title: Text('Trening o ${godzina(u.treningMin)}, przerwy w siedzeniu Pn–Pt '
                  '${godzina(u.przerwyOd)}–${godzina(u.przerwyDo)} co ${u.przerwyCo} min'),
              subtitle: const Text('Telefon zapyta o zgodę na powiadomienia. Zmienisz to w zakładce Więcej.'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _rozumiem ? _zaczynam : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: const Text('Zaczynam', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
