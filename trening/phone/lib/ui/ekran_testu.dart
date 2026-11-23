import 'dart:async';

import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../dane/stan.dart';
import '../plan/model.dart';
import '../silnik/flagi.dart';
import '../trening/test_kierunkowy.dart';
import '../urzadzenie.dart';
import 'technika.dart';
import 'tekst_md.dart';

/// Test kierunkowy krok po kroku: ocena, leżenie na brzuchu, sfinks, 10 wyprostów,
/// marsz, ponowna ocena; potem propozycja wyniku z tabeli planu.
class EkranTestu extends StatefulWidget {
  const EkranTestu({super.key, required this.dane, this.urzadzenie = const Urzadzenie()});

  final DaneAplikacji dane;
  final Urzadzenie urzadzenie;

  @override
  State<EkranTestu> createState() => _EkranTestuState();
}

class _Ocena {
  int bol = 3;
  Zasieg zasieg = Zasieg.brak;
  bool mrowienie = false;
}

class _EkranTestuState extends State<EkranTestu> {
  TestKierunkowy get test => widget.dane.plan.testKierunkowy;

  int _krok = 0;
  final _przed = _Ocena();
  final _po = _Ocena();
  bool _drugaSeria = false;
  WynikTestu? _wynik;
  bool _wynikiWidoczne = false;

  // timer i licznik bieżącego kroku
  Timer? _tyk;
  DateTime? _startTimera;
  int _licznik = 0;

  bool get _pierwszaOcena => _krok == 0;

  @override
  void initState() {
    super.initState();
    widget.urzadzenie.ekranWlaczony(true);
  }

  @override
  void dispose() {
    _tyk?.cancel();
    widget.urzadzenie.ekranWlaczony(false);
    super.dispose();
  }

  void _dalej() {
    _tyk?.cancel();
    _startTimera = null;
    _licznik = 0;
    setState(() {
      if (_krok < test.kroki.length - 1) {
        _krok++;
      } else {
        _wynik = proponujWynik(
          bolPrzed: _przed.bol,
          zasiegPrzed: _przed.zasieg,
          bolPo: _po.bol,
          zasiegPo: _po.zasieg,
          mrowienie: _po.mrowienie,
        );
        _wynikiWidoczne = true;
      }
    });
  }

  void _drugaSeriaWyprostow() {
    final i = test.kroki.indexWhere((k) => k.typ == 'powtorzenia');
    setState(() {
      _drugaSeria = true;
      _wynikiWidoczne = false;
      _krok = i;
    });
  }

  void _startTimer(int sekundy) {
    _startTimera = DateTime.now();
    _tyk?.cancel();
    _tyk = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final minelo = DateTime.now().difference(_startTimera!).inMilliseconds;
      if (minelo >= sekundy * 1000) {
        _tyk?.cancel();
        widget.urzadzenie.ton('wysoki', ms: 400);
        widget.urzadzenie.wibracja(ms: 250);
      }
      setState(() {});
    });
    setState(() {});
  }

  Future<void> _zapisz() async {
    await widget.dane.zapiszTest(WynikTestuKierunkowego(
      data: widget.dane.dzis,
      wynik: _wynik!,
      bolPrzed: _przed.bol,
      zasiegPrzed: _przed.zasieg,
      bolPo: _po.bol,
      zasiegPo: _po.zasieg,
      mrowienie: _po.mrowienie,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test kierunkowy'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: _wynikiWidoczne ? 1 : _krok / test.kroki.length),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _wynikiWidoczne ? _wyniki(t) : _biezacyKrok(t),
        ),
      ),
    );
  }

  List<Widget> _biezacyKrok(TextTheme t) {
    final k = test.kroki[_krok];
    final naglowek = [
      Text('Krok ${_krok + 1}/${test.kroki.length}', style: t.labelLarge),
      Text(k.nazwa + (_drugaSeria && k.typ == 'powtorzenia' ? ' (druga seria)' : ''), style: t.headlineSmall),
      const SizedBox(height: 8),
      TekstMd(k.opis, styl: t.bodyLarge),
      const SizedBox(height: 16),
    ];
    if (_krok == 0) {
      naglowek.insertAll(0, [
        TekstMd(test.cel, styl: t.bodyLarge),
        const SizedBox(height: 4),
        Text(test.kiedy, style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
        const Divider(height: 32),
      ]);
    }
    final atlas = widget.dane.atlas.cwiczenia['wyprosty-w-lezeniu']?.rysunek('');
    return [
      ...naglowek,
      if (k.typ != 'ocena' && k.typ != 'marsz' && atlas != null) ...[RysunekCwiczenia(atlas), const SizedBox(height: 16)],
      ...switch (k.typ) {
        'ocena' => _ocena(t, _pierwszaOcena ? _przed : _po, mrowienie: !_pierwszaOcena),
        'powtorzenia' => _powtorzenia(t, k),
        _ => _timer(t, k),
      },
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _dalej,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: Text(_krok == test.kroki.length - 1 ? 'Pokaż wynik' : 'Dalej', style: const TextStyle(fontSize: 20)),
      ),
    ];
  }

  List<Widget> _ocena(TextTheme t, _Ocena o, {required bool mrowienie}) => [
        Text('Ból w krzyżu: ${o.bol}/10', style: t.titleLarge),
        Slider(
          value: o.bol.toDouble(),
          max: 10,
          divisions: 10,
          label: '${o.bol}',
          onChanged: (v) => setState(() => o.bol = v.round()),
        ),
        Text('Gdzie kończy się ból?', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final z in Zasieg.values)
              ChoiceChip(
                label: Text(nazwaZasiegu(z)),
                selected: o.zasieg == z,
                onSelected: (_) => setState(() => o.zasieg = z),
              ),
          ],
        ),
        if (mrowienie)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: o.mrowienie,
            onChanged: (v) => setState(() => o.mrowienie = v ?? false),
            title: const Text('Pojawiło się mrowienie albo drętwienie'),
          ),
      ];

  List<Widget> _timer(TextTheme t, KrokTestu k) {
    final sekundy = k.s!.min.round();
    final start = _startTimera;
    final minelo = start == null ? 0 : DateTime.now().difference(start).inSeconds;
    final zostalo = (sekundy - minelo).clamp(0, sekundy);
    final m = zostalo ~/ 60, s = zostalo % 60;
    return [
      Center(child: Text('$m:${s.toString().padLeft(2, '0')}', style: t.displayLarge)),
      if (!k.s!.staly) Center(child: Text('plan: ${_czas(k.s!.min)}–${_czas(k.s!.max)}', style: t.bodyMedium)),
      const SizedBox(height: 8),
      if (start == null)
        OutlinedButton(onPressed: () => _startTimer(sekundy), child: const Text('Start odliczania'))
      else if (zostalo == 0)
        Center(child: Text('Czas minął. Możesz przejść dalej.', style: t.titleMedium)),
    ];
  }

  String _czas(num s) => s >= 60 && s % 60 == 0 ? '${s ~/ 60} min' : '$s s';

  List<Widget> _powtorzenia(TextTheme t, KrokTestu k) => [
        Center(
          child: InkWell(
            onTap: () {
              setState(() => _licznik++);
              if (_licznik == k.powt) widget.urzadzenie.ton('potwierdzenie', ms: 250);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('$_licznik / ${k.powt}', style: t.displayLarge),
            ),
          ),
        ),
        if (k.pauzaGoraS != null) Center(child: Text('na górze wydech i ${k.pauzaGoraS} s', style: t.bodyLarge)),
        Center(child: Text('Stuknij liczbę po każdym powtórzeniu.', style: t.bodySmall)),
      ];

  List<Widget> _wyniki(TextTheme t) {
    final propozycja = proponujWynik(
      bolPrzed: _przed.bol,
      zasiegPrzed: _przed.zasieg,
      bolPo: _po.bol,
      zasiegPo: _po.zasieg,
      mrowienie: _po.mrowienie,
    );
    return [
      Text('Wynik', style: t.headlineSmall),
      Text(
        'Przed: ${_przed.bol}/10, ${nazwaZasiegu(_przed.zasieg).toLowerCase()} · '
        'po: ${_po.bol}/10, ${nazwaZasiegu(_po.zasieg).toLowerCase()}${_po.mrowienie ? ', mrowienie' : ''}',
        style: t.bodyLarge,
      ),
      const SizedBox(height: 4),
      Text('Propozycja aplikacji: ${nazwaWyniku(propozycja)}. Wybierz to, co pasuje do Twoich odczuć.',
          style: t.bodyMedium),
      const SizedBox(height: 8),
      RadioGroup<WynikTestu>(
        groupValue: _wynik,
        onChanged: (v) => setState(() => _wynik = v),
        child: Column(
          children: [
            for (final w in WynikTestu.values)
              Card(
                child: RadioListTile<WynikTestu>(
                  value: w,
                  title: Text('${nazwaWyniku(w)}: ${test.wyniki[w.name]!.gdy}'),
                  subtitle: Text('${test.wyniki[w.name]!.znaczenie} ${test.wyniki[w.name]!.coRobisz}'),
                ),
              ),
          ],
        ),
      ),
      if (_wynik == WynikTestu.bezZmian && !_drugaSeria)
        OutlinedButton(onPressed: _drugaSeriaWyprostow, child: const Text('Zrób drugą serię 10 wyprostów')),
      if (test.wskazowka != null) ...[
        const SizedBox(height: 12),
        TekstMd('Wskazówka: ${test.wskazowka}', styl: t.bodyMedium),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _wynik == null ? null : _zapisz,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: const Text('Zapisz wynik', style: TextStyle(fontSize: 20)),
      ),
    ];
  }
}
