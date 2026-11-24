import 'package:flutter/material.dart';

import '../dane/aplikacja.dart';
import 'ekran_dzis.dart';
import 'ekran_kalendarza.dart';
import 'ekran_wiecej.dart';

/// Pasek dolny: Dziś, Kalendarz, Więcej. Postępy (dziennik tygodniowy) dojdą w wersji 0.2.
class EkranGlowny extends StatefulWidget {
  const EkranGlowny({super.key, required this.dane});

  final DaneAplikacji dane;

  @override
  State<EkranGlowny> createState() => _EkranGlownyState();
}

class _EkranGlownyState extends State<EkranGlowny> with WidgetsBindingObserver {
  int _zakladka = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Powrót do aplikacji (np. następnego dnia): nowa data, check-in, odświeżone przypomnienia.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.dane.odswiez();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _zakladka,
        children: [
          EkranDzis(dane: widget.dane),
          EkranKalendarza(dane: widget.dane),
          EkranWiecej(dane: widget.dane),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _zakladka,
        onDestinationSelected: (i) => setState(() => _zakladka = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Dziś'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Kalendarz',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Więcej'),
        ],
      ),
    );
  }
}
