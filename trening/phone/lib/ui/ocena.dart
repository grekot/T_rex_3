import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../silnik/daty.dart';
import '../silnik/flagi.dart';
import '../silnik/sygnalizacja.dart';
import '../trening/test_kierunkowy.dart';
import 'ekran_bezpieczenstwa.dart';
import 'tekst_md.dart';

const kolorEtapu = {1: Color(0xFF42A5F5), 2: Color(0xFF66BB6A), 3: Color(0xFFFFA726)};

Color kolorStrefy(Strefa s) => switch (s) {
      Strefa.zielona => const Color(0xFF4CAF50),
      Strefa.zolta => const Color(0xFFFFC107),
      Strefa.czerwona => const Color(0xFFF44336),
    };

String nazwaStrefy(Strefa s) => switch (s) {
      Strefa.zielona => 'Zielona strefa',
      Strefa.zolta => 'Żółta strefa',
      Strefa.czerwona => 'Czerwona strefa',
    };

String _klucz(Strefa s) => switch (s) {
      Strefa.zielona => 'zielona',
      Strefa.zolta => 'zolta',
      Strefa.czerwona => 'czerwona',
    };

class Kropka extends StatelessWidget {
  const Kropka(this.strefa, {super.key, this.rozmiar = 10});

  final Strefa strefa;
  final double rozmiar;

  @override
  Widget build(BuildContext context) => Container(
        width: rozmiar,
        height: rozmiar,
        decoration: BoxDecoration(color: kolorStrefy(strefa), shape: BoxShape.circle),
      );
}

/// Ból 0–10 dużymi cyframi, gdzie kończy się ból, opcjonalnie mrowienie.
class PoleOceny extends StatelessWidget {
  const PoleOceny({
    super.key,
    required this.bol,
    required this.zasieg,
    required this.onBol,
    required this.onZasieg,
    this.mrowienie,
    this.onMrowienie,
    this.etykieta = 'Ból w krzyżu teraz',
  });

  final int bol;
  final Zasieg zasieg;
  final ValueChanged<int> onBol;
  final ValueChanged<Zasieg> onZasieg;

  /// null = bez pytania o mrowienie.
  final bool? mrowienie;
  final ValueChanged<bool>? onMrowienie;
  final String etykieta;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(etykieta, style: t.titleMedium)),
            Text('$bol', style: t.displaySmall),
            Text(' / 10', style: t.titleMedium),
          ],
        ),
        Slider(
          value: bol.toDouble(),
          max: 10,
          divisions: 10,
          label: '$bol',
          onChanged: (v) => onBol(v.round()),
        ),
        Text('Gdzie kończy się ból?', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final z in Zasieg.values)
              ChoiceChip(label: Text(nazwaZasiegu(z)), selected: zasieg == z, onSelected: (_) => onZasieg(z)),
          ],
        ),
        if (mrowienie != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: mrowienie,
            onChanged: (v) => onMrowienie?.call(v ?? false),
            title: const Text('Mrowienie albo drętwienie'),
          ),
      ],
    );
  }
}

/// Wynik sygnalizacji: kolor, co robić według planu i dodatkowe uwagi.
class KartaStrefy extends StatelessWidget {
  const KartaStrefy({super.key, required this.dane, required this.wynik, required this.bol, this.rano = false});

  final DaneAplikacji dane;
  final WynikSygnalizacji wynik;
  final int bol;

  /// Ocena z porannego check-inu (bez pytania „czy minęło do rana”).
  final bool rano;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tx = dane.plan.teksty;
    final s = wynik.strefa;
    final etap = dane.dzisiaj.etap;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: kolorStrefy(s), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Kropka(s, rozmiar: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(nazwaStrefy(s), style: t.titleLarge)),
            ]),
            const SizedBox(height: 8),
            Text(tx.sygnalizacja[_klucz(s)]!.coRobisz, style: t.titleMedium),
            if (!rano && s == Strefa.zolta && bol >= 3)
              Punkt('Jutro rano zapytam, czy ból minął. Jeśli nie, to strefa czerwona.', styl: t.bodyLarge),
            if (wynik.cofaSie) Punkt(tx.centralizacja.first, styl: t.bodyLarge),
            if (wynik.schodziNizej) Punkt('Ból schodzi niżej niż w ostatnich dniach.', styl: t.bodyLarge),
            if (wynik.objawyNerwowe)
              Punkt('Ból poniżej kolana albo mrowienie: jeśli się utrzyma, umów fizjoterapeutę lub lekarza.',
                  styl: t.bodyLarge),
            if (s == Strefa.czerwona && etap == 1)
              Punkt('W etapie 1 nie ma dokąd się cofnąć. Następny trening zrób w krótszej wersji, tylko z '
                  'ćwiczeniami, które nie nasilają bólu.', styl: t.bodyLarge),
            if (s == Strefa.czerwona)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Gdy ból wraca', style: t.titleMedium),
                  children: [for (final p in tx.gdyBolWraca) Punkt(p, styl: t.bodyLarge)],
                ),
              ),
            if (wynik.pytajOFlagi) ...[
              const SizedBox(height: 8),
              Text('Czy pojawiło się coś z czerwonych flag?',
                  style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
              TextButton.icon(
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Sprawdź czerwone flagi'),
                onPressed: () => otworzBezpieczenstwo(context, dane),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ocena po treningu (ok. 10 sekund): ból, zasięg, mrowienie, opcjonalnie ćwiczenie,
/// które nasiliło ból. Po zapisie pokazuje strefę sygnalizacji.
class PanelOceny extends StatefulWidget {
  const PanelOceny({super.key, required this.dane, required this.data, this.cwiczenia = const [], this.bolesne = const []});

  final DaneAplikacji dane;
  final DateTime data;

  /// Ćwiczenia tego treningu (id planu) do wyboru „które nasiliło ból”.
  final List<String> cwiczenia;

  /// Przerwane przyciskiem „Boli: pomiń” (zaznaczone na start).
  final List<String> bolesne;

  @override
  State<PanelOceny> createState() => _PanelOcenyState();
}

class _PanelOcenyState extends State<PanelOceny> {
  int _bol = 0;
  Zasieg _zasieg = Zasieg.brak;
  bool _mrowienie = false;
  String? _nasililo;
  WynikSygnalizacji? _wynik;
  bool _wstrzymane = false;

  @override
  void initState() {
    super.initState();
    _nasililo = widget.bolesne.isEmpty ? null : widget.bolesne.first;
  }

  Future<void> _zapisz() async {
    final w = await widget.dane.zapiszOcene(
      widget.data,
      OcenaBolu(bol: _bol, zasieg: _zasieg, mrowienie: _mrowienie),
      nasililo: _nasililo,
    );
    if (mounted) setState(() => _wynik = w);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final plan = widget.dane.plan;
    final w = _wynik;
    if (w != null) {
      final nasililo = _nasililo;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KartaStrefy(dane: widget.dane, wynik: w, bol: _bol),
          if (nasililo != null && w.strefa != Strefa.zielona)
            _wstrzymane
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('„${plan.cwiczenia[nasililo]!.nazwa}” wstrzymane na $dniWstrzymania dni. '
                        'Przywrócisz je na ekranie Dziś.', style: t.bodyMedium),
                  )
                : OutlinedButton(
                    onPressed: () async {
                      await widget.dane.wstrzymaj(nasililo);
                      if (mounted) setState(() => _wstrzymane = true);
                    },
                    child: Text('Wstrzymaj „${plan.cwiczenia[nasililo]!.nazwa}” na $dniWstrzymania dni'),
                  ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Jak plecy po treningu?', style: t.titleLarge),
        const SizedBox(height: 8),
        PoleOceny(
          bol: _bol,
          zasieg: _zasieg,
          mrowienie: _mrowienie,
          onBol: (v) => setState(() => _bol = v),
          onZasieg: (v) => setState(() => _zasieg = v),
          onMrowienie: (v) => setState(() => _mrowienie = v),
        ),
        if (widget.cwiczenia.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Które ćwiczenie nasiliło ból? (opcjonalnie)', style: t.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(label: const Text('Żadne'), selected: _nasililo == null, onSelected: (_) => setState(() => _nasililo = null)),
              for (final id in widget.cwiczenia)
                ChoiceChip(
                  label: Text(plan.cwiczenia[id]!.nazwa),
                  selected: _nasililo == id,
                  onSelected: (_) => setState(() => _nasililo = id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _zapisz,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: const Text('Zapisz ocenę', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}

/// Ocena bólu w arkuszu (trening odznaczony bez aplikacji albo ocena później).
Future<void> ocenTrening(BuildContext context, DaneAplikacji dane, DateTime data) {
  final zapis = dane.stan.treningi[iso(data)];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: PanelOceny(dane: dane, data: data, cwiczenia: zapis?.wykonane ?? const [], bolesne: zapis?.bolesne ?? const []),
      ),
    ),
  );
}

/// Poranny check-in (2 pytania). Zwraca wynik sygnalizacji albo null, gdy zamknięto bez zapisu.
Future<WynikSygnalizacji?> pokazCheckin(BuildContext context, DaneAplikacji dane) {
  return showModalBottomSheet<WynikSygnalizacji>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _Checkin(dane: dane),
      ),
    ),
  );
}

class _Checkin extends StatefulWidget {
  const _Checkin({required this.dane});

  final DaneAplikacji dane;

  @override
  State<_Checkin> createState() => _CheckinState();
}

class _CheckinState extends State<_Checkin> {
  int _bol = 0;
  Zasieg _zasieg = Zasieg.brak;
  bool? _minelo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wczoraj = widget.dane.pytajCzyMinelo;
    final gotowe = wczoraj == null || _minelo != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Dzień dobry! Jak plecy rano?', style: t.titleLarge),
        const SizedBox(height: 8),
        PoleOceny(
          etykieta: 'Ból w spoczynku teraz',
          bol: _bol,
          zasieg: _zasieg,
          onBol: (v) => setState(() => _bol = v),
          onZasieg: (v) => setState(() => _zasieg = v),
        ),
        if (wczoraj != null) ...[
          const SizedBox(height: 16),
          Text('Czy ból po wczorajszym treningu (${wczoraj.ocena!.bol}/10) minął?', style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: true, label: Text('Tak, minął')),
              ButtonSegment(value: false, label: Text('Nie')),
            ],
            selected: {?_minelo},
            onSelectionChanged: (s) => setState(() => _minelo = s.firstOrNull),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: gotowe
              ? () async {
                  final nawigator = Navigator.of(context);
                  final w = await widget.dane.zapiszCheckin(_bol, _zasieg, minelo: _minelo);
                  nawigator.pop(w);
                }
              : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: const Text('Zapisz', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}

void otworzBezpieczenstwo(BuildContext context, DaneAplikacji dane) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EkranBezpieczenstwa(dane: dane)));
}

/// Ikona 🛡 w pasku każdego ekranu.
class PrzyciskBezpieczenstwa extends StatelessWidget {
  const PrzyciskBezpieczenstwa({super.key, required this.dane, this.przed});

  final DaneAplikacji dane;

  /// Np. pauza treningu przed otwarciem ekranu.
  final VoidCallback? przed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Bezpieczeństwo',
        icon: const Icon(Icons.shield_outlined),
        onPressed: () {
          przed?.call();
          otworzBezpieczenstwo(context, dane);
        },
      );
}
