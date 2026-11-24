import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import '../przypomnienia/harmonogram.dart';
import '../urzadzenie.dart';
import 'daty_slownie.dart';
import 'ocena.dart';
import 'tekst_md.dart';

const _dniKrotko = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

/// Ustawienia: przypomnienia, instrukcja dla Samsunga, data startu, o aplikacji.
class EkranWiecej extends StatefulWidget {
  const EkranWiecej({super.key, required this.dane, this.urzadzenie = const Urzadzenie()});

  final DaneAplikacji dane;
  final Urzadzenie urzadzenie;

  @override
  State<EkranWiecej> createState() => _EkranWiecejState();
}

class _EkranWiecejState extends State<EkranWiecej> with WidgetsBindingObserver {
  bool? _powiadomienia;
  bool? _bateria;

  DaneAplikacji get dane => widget.dane;
  UstawieniaPrzypomnien get u => dane.stan.przypomnienia;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sprawdz();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Po powrocie z ustawień systemu sprawdź jeszcze raz zgodę i baterię.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sprawdz();
  }

  Future<void> _sprawdz() async {
    final p = await widget.urzadzenie.powiadomieniaWlaczone();
    final b = await widget.urzadzenie.bateriaBezOgraniczen();
    if (!mounted) return;
    setState(() {
      _powiadomienia = p;
      _bateria = b;
    });
  }

  Future<void> _zmien(void Function() zmiana) async {
    setState(zmiana);
    await dane.zapiszUstawienia();
  }

  Future<int?> _godzina(int min) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: min ~/ 60, minute: min % 60),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _test() async {
    final ok = await widget.urzadzenie.poprosOPowiadomienia();
    await widget.urzadzenie.przypomnienieTestowe(przypomnienieTestowe(DateTime.now()));
    if (!mounted) return;
    setState(() => _powiadomienia = ok);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Przypomnienie przyjdzie za ok. minutę (czasem kilka). Zablokuj telefon i sprawdź też zegarek.'
          : 'Powiadomienia są wyłączone. Włącz je w ustawieniach.'),
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wyprostyDozwolone = dane.flagi.contains('wyprostNieSzkodzi');
    Widget naglowek(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(s, style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Więcej'), actions: [PrzyciskBezpieczenstwa(dane: dane)]),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          naglowek('Przypomnienia'),
          if (_powiadomienia == false)
            ListTile(
              leading: Icon(Icons.notifications_off_outlined, color: Theme.of(context).colorScheme.error),
              title: const Text('Powiadomienia są wyłączone'),
              subtitle: const Text('Bez nich przypomnienia nie przyjdą ani na telefon, ani na zegarek.'),
              trailing: FilledButton(
                onPressed: () async {
                  final ok = await widget.urzadzenie.poprosOPowiadomienia();
                  if (!ok) await widget.urzadzenie.ustawieniaPowiadomien();
                  await _sprawdz();
                },
                child: const Text('Włącz'),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.fitness_center),
            title: const Text('Trening'),
            subtitle: Text('codziennie o ${godzina(u.treningMin)}; znika, gdy trening jest zrobiony'),
            value: u.trening,
            onChanged: (v) => _zmien(() => u.trening = v),
          ),
          if (u.trening) ...[
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Godzina'),
              trailing: Text(godzina(u.treningMin), style: t.titleMedium),
              onTap: () async {
                final m = await _godzina(u.treningMin);
                if (m != null) await _zmien(() => u.treningMin = m);
              },
            ),
            CheckboxListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: Text('Drugie o ${godzina(UstawieniaPrzypomnien.drugieMin)}'),
              value: u.drugie,
              onChanged: (v) => _zmien(() => u.drugie = v ?? false),
            ),
          ],
          SwitchListTile(
            secondary: const Icon(Icons.chair_alt_outlined),
            title: const Text('Przerwy w siedzeniu'),
            subtitle: Text('co ${u.przerwyCo} min, ${godzina(u.przerwyOd)}–${godzina(u.przerwyDo)}, '
                '${_dni(u.przerwyDni)}'),
            value: u.przerwy,
            onChanged: (v) => _zmien(() => u.przerwy = v),
          ),
          if (u.przerwy)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, children: [
                    for (final m in const [30, 40, 45])
                      ChoiceChip(
                        label: Text('co $m min'),
                        selected: u.przerwyCo == m,
                        onSelected: (_) => _zmien(() => u.przerwyCo = m),
                      ),
                  ]),
                  Row(children: [
                    TextButton(
                      onPressed: () async {
                        final m = await _godzina(u.przerwyOd);
                        if (m != null && m < u.przerwyDo) await _zmien(() => u.przerwyOd = m);
                      },
                      child: Text('od ${godzina(u.przerwyOd)}'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final m = await _godzina(u.przerwyDo);
                        if (m != null && m > u.przerwyOd) await _zmien(() => u.przerwyDo = m);
                      },
                      child: Text('do ${godzina(u.przerwyDo)}'),
                    ),
                  ]),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(_dniKrotko[d - 1]),
                        selected: u.przerwyDni.contains(d),
                        onSelected: (v) => _zmien(() => v ? u.przerwyDni.add(d) : u.przerwyDni.remove(d)),
                      ),
                  ]),
                  Text('W dni, gdy pali w krzyżu, włącz na ekranie Dziś „Pali dziś w krzyżu”: przerwy co '
                      '${UstawieniaPrzypomnien.przerwyCoGdyPali} min do końca dnia.', style: t.bodySmall),
                ],
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.self_improvement),
            title: const Text('Wyprosty w leżeniu'),
            subtitle: Text(wyprostyDozwolone
                ? 'co ${u.wyprostyCoH} h, ${godzina(UstawieniaPrzypomnien.wyprostyOd)}–'
                    '${godzina(UstawieniaPrzypomnien.wyprostyDo)}, gdy ból wraca'
                : 'Dostępne, gdy test kierunkowy wypadnie dobrze (lepiej albo bez zmian).'),
            value: u.wyprosty && wyprostyDozwolone,
            onChanged: wyprostyDozwolone ? (v) => _zmien(() => u.wyprosty = v) : null,
          ),
          if (u.wyprosty && wyprostyDozwolone)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16),
              child: Wrap(spacing: 8, children: [
                for (final h in const [2, 3])
                  ChoiceChip(
                    label: Text('co $h h'),
                    selected: u.wyprostyCoH == h,
                    onSelected: (_) => _zmien(() => u.wyprostyCoH = h),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Test przypomnienia (za 1 min)'),
              onPressed: _test,
            ),
          ),
          naglowek('Żeby przypomnienia docierały (Samsung)'),
          ListTile(
            leading: Icon(
              _bateria == true ? Icons.battery_full : Icons.battery_alert,
              color: _bateria == true ? Colors.green : Theme.of(context).colorScheme.error,
            ),
            title: Text(_bateria == true
                ? 'Trening działa w tle bez ograniczeń'
                : 'Samsung może usypiać Trening i przypomnienia nie przyjdą'),
            trailing: _bateria == true
                ? null
                : FilledButton(onPressed: widget.urzadzenie.zwolnijZBaterii, child: const Text('Zezwól')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Przypomnienia idą na zegarek przez aplikację Zepp, więc ona też nie może być usypiana. '
                    'Nazwy menu mogą się trochę różnić:', style: t.bodyMedium),
                const SizedBox(height: 4),
                Punkt('Ustawienia → Aplikacje → **Trening** → Bateria → **Bez ograniczeń** '
                    '(przycisk „Zezwól” wyżej robi to samo).', znak: '1.', styl: t.bodyMedium),
                Punkt('To samo dla aplikacji **Zepp**.', znak: '2.', styl: t.bodyMedium),
                Punkt('Ustawienia → Pielęgnacja urządzenia (albo Bateria) → Limity użycia w tle: dodaj Trening i Zepp '
                    'do **Aplikacji nigdy nieusypianych**.', znak: '3.', styl: t.bodyMedium),
                Punkt('Na koniec stuknij „Test przypomnienia”, zablokuj telefon i poczekaj.', znak: '4.', styl: t.bodyMedium),
                TextButton(onPressed: widget.urzadzenie.ustawieniaAplikacji, child: const Text('Otwórz ustawienia aplikacji')),
              ],
            ),
          ),
          naglowek('Plan'),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Data startu planu'),
            subtitle: Text(dane.moznaZmienicStart
                ? dataPelna(dane.stan.start)
                : '${dataPelna(dane.stan.start)} (po przejściu do etapu 2 już się nie zmienia)'),
            trailing: dane.moznaZmienicStart ? const Icon(Icons.edit_outlined) : null,
            onTap: dane.moznaZmienicStart ? _zmienStart : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.medical_services_outlined),
            title: const Text('Fizjoterapeuta zalecił ślizgi nerwowe'),
            subtitle: const Text('Włącza ślizgi w rutynie także bez objawów w udzie.'),
            value: dane.stan.slizgiOdFizjo,
            onChanged: (v) async {
              await dane.ustawSlizgi(v);
              if (mounted) setState(() {});
            },
          ),
          naglowek('O aplikacji'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(dane.plan.tytul),
            subtitle: Text('Wersja planu ${dane.plan.wersja}. Dane zostają tylko na tym telefonie: aplikacja nie ma '
                'dostępu do internetu. Rysunki ćwiczeń wygenerowała AI (Gemini); są poglądowe, obowiązuje opis.'),
          ),
        ],
      ),
    );
  }

  Future<void> _zmienStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dane.stan.start,
      firstDate: dane.dzis.subtract(const Duration(days: 120)),
      lastDate: dane.dzis.add(const Duration(days: 30)),
      helpText: 'Data startu planu',
    );
    if (d == null) return;
    await dane.zmienStart(d);
    if (mounted) setState(() {});
  }
}

String _dni(Set<int> dni) {
  if (dni.length == 5 && dni.containsAll(dniRobocze)) return 'Pn–Pt';
  if (dni.length == 7) return 'codziennie';
  if (dni.isEmpty) return 'żadnego dnia';
  return (dni.toList()..sort()).map((d) => _dniKrotko[d - 1]).join(', ');
}
