import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../trasa/plan.dart';
import '../trasa/trasa.dart';
import 'profil_wysokosci.dart';

/// Gest dodawania punktu: w telefonie przytrzymanie, w przeglądarce podwójne kliknięcie
/// (maplibre_gl na webie zamienia „długie dotknięcie” na dblclick).
const gestDodawania = kIsWeb ? 'Kliknij prawym przyciskiem' : 'Przytrzymaj palec';

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

/// Dolny panel planowania trasy.
///
/// Zawsze widoczne: nagłówek (z przyciskiem zwijania), tryb, opcje, liczby, profil wysokości
/// i przyciski na dole. Przewija się tylko środek: ostrzeżenia, azymuty, odcinki i lista punktów,
/// więc przy długiej trasie przyciski i profil nie uciekają. Zwinięty panel to jeden pasek.
class PanelTrasy extends StatefulWidget {
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
    required this.przenoszony,
    required this.onPunkt,
    required this.onPrzenies,
    required this.onUsun,
    required this.onAnulujPrzenoszenie,
    required this.onCofnij,
    required this.onWyczysc,
    this.nazwaZapisanej,
    this.onZapisz,
    this.zwiniety = false,
    this.onZwin,
    this.podswietlony,
    this.onPodswietl,
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

  /// Indeks punktu czekającego na nowe miejsce (null = żaden).
  final int? przenoszony;

  /// Dotknięcie punktu na liście: menu punktu (rodzaj, przeniesienie, usunięcie).
  final ValueChanged<int> onPunkt;
  final ValueChanged<int> onPrzenies;
  final ValueChanged<int> onUsun;
  final VoidCallback onAnulujPrzenoszenie;
  final VoidCallback onCofnij;
  final VoidCallback onWyczysc;

  /// Nazwa trasy z konta, gdy pokazujemy zapisaną trasę.
  final String? nazwaZapisanej;

  /// Zapis trasy na koncie; null, gdy ta wersja aplikacji nie ma konta (bez Firebase).
  final VoidCallback? onZapisz;

  /// Panel zwinięty do jednego paska; [onZwin] zwija (true) i rozwija (false).
  final bool zwiniety;
  final ValueChanged<bool>? onZwin;

  /// Punkt wskazany kursorem na liście (przeglądarka); [onPodswietl] z null, gdy kursor zszedł z listy.
  final int? podswietlony;
  final ValueChanged<int?>? onPodswietl;

  @override
  State<PanelTrasy> createState() => _PanelTrasyState();
}

class _PanelTrasyState extends State<PanelTrasy> {
  final _przewijanie = ScrollController();

  @override
  void dispose() {
    _przewijanie.dispose();
    super.dispose();
  }

  String get _tytul => widget.nazwaZapisanej ?? 'Trasa';

  String? get _skrot {
    final t = widget.trasa;
    if (t == null) return null;
    return '${opisDlugosci(t.dlugosc)} · ↑${t.podejscia.round()} m · ${opisCzasu(t.czas)}';
  }

  Widget _zwiniety(BuildContext context) {
    final teksty = Theme.of(context).textTheme;
    final skrot = _skrot;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onZwin?.call(false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              Icon(
                widget.nazwaZapisanej == null ? Icons.route : Icons.bookmark,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  skrot == null ? _tytul : '$_tytul · $skrot',
                  style: teksty.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.liczy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(
                icon: const Icon(Icons.expand_less),
                tooltip: 'Rozwiń panel trasy',
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.onZwin?.call(false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.zwiniety) return _zwiniety(context);
    final teksty = Theme.of(context).textTheme;
    final kolory = Theme.of(context).colorScheme;
    final w = widget;
    final t = w.trasa;
    final plan = w.plan;

    // część przewijana: ostrzeżenia, azymuty, odcinki, punkty
    final srodek = <Widget>[
      if (t != null) ...[
        for (final ostrzezenie in [?ostrzezenieTrudnosci(t.trudnyTeren), ...t.uwagi])
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: kolory.error),
                const SizedBox(width: 6),
                Expanded(child: Text(ostrzezenie, style: teksty.bodySmall)),
              ],
            ),
          ),
        if (t.azymuty.isNotEmpty) _Azymuty(t.azymuty),
        if (w.odcinki.length > 1) ...[
          // przy powrocie: tam + z powrotem, nawet bez przystanków
          const SizedBox(height: 6),
          Text(w.powrot ? 'Odcinki (tam i z powrotem)' : 'Odcinki między przystankami', style: teksty.labelLarge),
          for (final (i, o) in w.odcinki.indexed)
            _WierszOdcinka(numer: i + 1, plan: plan, odcinek: o, powrot: w.powrot),
        ],
      ],
      if (plan.dlugosc > 1) ...[
        const SizedBox(height: 6),
        Text('Punkty trasy', style: teksty.labelLarge),
        for (var i = 0; i < plan.dlugosc; i++)
          _WierszPunktu(
            plan: plan,
            indeks: i,
            powrot: w.powrot,
            przenoszony: w.przenoszony == i,
            podswietlony: w.podswietlony == i,
            onTap: () => w.onPunkt(i),
            onPrzenies: () => w.onPrzenies(i),
            onUsun: () => w.onUsun(i),
            onKursor: w.onPodswietl == null ? null : (nad) => w.onPodswietl!(nad ? i : null),
          ),
        const SizedBox(height: 4),
        Text(
          kIsWeb
              ? 'Kliknij mapę prawym przyciskiem: prowadź tędy, przystanek albo nowy cel. Punkt przeniesiesz '
                    'albo usuniesz z listy powyżej lub klikając go na mapie. Lewy przycisk przesuwa mapę.'
              : '$gestDodawania na mapie: prowadź tędy, przystanek albo nowy cel. '
                    'Punkt przeniesiesz albo usuniesz z listy powyżej lub dotykając go na mapie.',
          style: teksty.bodySmall,
        ),
        const SizedBox(height: 4),
      ],
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
      child: Card(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // nagłówek: nazwa i zwijanie
              Row(
                children: [
                  Icon(w.nazwaZapisanej == null ? Icons.route : Icons.bookmark, size: 18, color: kolory.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_tytul, style: teksty.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (w.onZwin != null)
                    IconButton(
                      icon: const Icon(Icons.expand_more),
                      tooltip: 'Zwiń panel (cała mapa widoczna)',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => w.onZwin!(true),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<TrybTrasy>(
                        // bez ikon i z krótkimi napisami: cztery tryby muszą się zmieścić w jednym wierszu
                        segments: const [
                          ButtonSegment(value: TrybTrasy.szlakami, label: Text('Szlakami', softWrap: false)),
                          ButtonSegment(value: TrybTrasy.szlakiISkroty, label: Text('Skróty', softWrap: false)),
                          ButtonSegment(value: TrybTrasy.najkrocej, label: Text('Najkrócej', softWrap: false)),
                          ButtonSegment(
                            value: TrybTrasy.azymut,
                            label: Text('Azymut', softWrap: false),
                            tooltip: 'Na przełaj, z omijaniem urwisk, wody i stromizn',
                          ),
                        ],
                        selected: {w.tryb},
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        onSelectionChanged: (s) => w.onTryb(s.first),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // zawsze jeden wiersz: na wąskim ekranie (S23) chipy łamały się na dwa wiersze
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          FilterChip(
                            avatar: w.powrot ? null : const Icon(Icons.u_turn_left, size: 18),
                            label: const Text('Powrót tą samą drogą'),
                            selected: w.powrot,
                            visualDensity: VisualDensity.compact,
                            onSelected: w.onPowrot,
                          ),
                          FilterChip(
                            avatar: w.unikajStromych ? null : const Icon(Icons.trending_up, size: 18),
                            label: const Text('Unikaj stromych'),
                            tooltip: 'Omija podejścia stromsze niż ok. 15 %',
                            selected: w.unikajStromych,
                            visualDensity: VisualDensity.compact,
                            onSelected: w.onUnikajStromych,
                          ),
                        ],
                      ),
                    ),
                    if (w.liczy) const LinearProgressIndicator(),
                    if (w.blad != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(w.blad!, style: TextStyle(color: kolory.error)),
                      ),
                    if (w.przenoszony case final i? when i < plan.dlugosc)
                      _Przenoszenie(
                        opis: nazwaPunktu(plan, i, powrot: w.powrot),
                        onAnuluj: w.onAnulujPrzenoszenie,
                      )
                    else if (plan.dlugosc == 1 && !w.liczy)
                      Text(
                        kIsWeb
                            ? 'Start ustawiony. Kliknij prawym przyciskiem w miejscu celu.'
                            : 'Start ustawiony. $gestDodawania na mapie w miejscu celu.',
                        style: teksty.bodyMedium,
                      ),
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
                      const SizedBox(height: 4),
                      ProfilWysokosci(trasa: t),
                    ],
                  ],
                ),
              ),
              if (srodek.isNotEmpty)
                Flexible(
                  child: Scrollbar(
                    controller: _przewijanie,
                    thumbVisibility: kIsWeb,
                    child: SingleChildScrollView(
                      controller: _przewijanie,
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: srodek),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (w.onZapisz != null)
                      TextButton.icon(
                        onPressed: t != null && !w.liczy && w.blad == null ? w.onZapisz : null,
                        icon: Icon(w.nazwaZapisanej == null ? Icons.bookmark_add_outlined : Icons.bookmark_outlined),
                        label: const Text('Zapisz'),
                      ),
                    TextButton.icon(onPressed: w.onCofnij, icon: const Icon(Icons.undo), label: const Text('Cofnij')),
                    TextButton.icon(
                      onPressed: w.onWyczysc,
                      icon: const Icon(Icons.close),
                      label: const Text('Wyczyść'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Komunikat „dotknij mapy w nowym miejscu” z przyciskiem Anuluj.
class _Przenoszenie extends StatelessWidget {
  const _Przenoszenie({required this.opis, required this.onAnuluj});

  final String opis;
  final VoidCallback onAnuluj;

  @override
  Widget build(BuildContext context) {
    final kolory = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(color: kolory.primaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(Icons.edit_location_alt_outlined, size: 20, color: kolory.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${kIsWeb ? 'Kliknij mapę' : 'Dotknij mapy'} w nowym miejscu: $opis',
              style: TextStyle(color: kolory.onPrimaryContainer),
            ),
          ),
          TextButton(onPressed: onAnuluj, child: const Text('Anuluj')),
        ],
      ),
    );
  }
}

/// Punkt trasy na liście: ikona rodzaju, nazwa, przenieś, usuń.
class _WierszPunktu extends StatelessWidget {
  const _WierszPunktu({
    required this.plan,
    required this.indeks,
    required this.powrot,
    required this.przenoszony,
    required this.podswietlony,
    required this.onTap,
    required this.onPrzenies,
    required this.onUsun,
    this.onKursor,
  });

  final PlanTrasy plan;
  final int indeks;
  final bool powrot;
  final bool przenoszony;

  /// Kursor nad tym wierszem: punkt podświetlony też na mapie.
  final bool podswietlony;
  final VoidCallback onTap;
  final VoidCallback onPrzenies;
  final VoidCallback onUsun;

  /// Kursor wszedł na wiersz (true) albo z niego zszedł (false).
  final ValueChanged<bool>? onKursor;

  @override
  Widget build(BuildContext context) {
    final kolory = Theme.of(context).colorScheme;
    final (ikona, kolor) = switch (plan.punkty[indeks].rodzaj) {
      RodzajPunktu.start => (Icons.trip_origin, const Color(0xFF2E7D32)),
      RodzajPunktu.cel => (Icons.place, const Color(0xFFC62828)),
      RodzajPunktu.przystanek => (Icons.flag_outlined, const Color(0xFFD81B60)),
      RodzajPunktu.przez => (Icons.alt_route, kolory.onSurfaceVariant),
    };
    return MouseRegion(
      onEnter: onKursor == null ? null : (_) => onKursor!(true),
      onExit: onKursor == null ? null : (_) => onKursor!(false),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: przenoszony
              ? kolory.primaryContainer
              : podswietlony
              ? const Color(0x55FFD600)
              : null,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(ikona, size: 20, color: kolor),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  nazwaPunktu(plan, indeks, powrot: powrot),
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_location_alt_outlined),
                tooltip: 'Postaw w nowym miejscu',
                visualDensity: VisualDensity.compact,
                onPressed: onPrzenies,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Usuń punkt',
                visualDensity: VisualDensity.compact,
                onPressed: onUsun,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// „1 odcinek”, „3 odcinki”, „5 odcinków”, „22 odcinki”.
String odmianaOdcinkow(int n) {
  if (n == 1) return 'odcinek';
  final j = n % 10, d = n % 100;
  return j >= 2 && j <= 4 && (d < 12 || d > 14) ? 'odcinki' : 'odcinków';
}

/// Odcinki proste trasy na przełaj: azymut i długość, do marszu z kompasem.
class _Azymuty extends StatelessWidget {
  const _Azymuty(this.odcinki);
  final List<OdcinekAzymutu> odcinki;

  @override
  Widget build(BuildContext context) {
    final teksty = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text('Na azymut (${odcinki.length} ${odmianaOdcinkow(odcinki.length)})', style: teksty.labelLarge),
        Text(
          'Azymuty geograficzne. Na kompasie ok. ${deklinacjaMagnetyczna.round()}° mniej (deklinacja). '
          'Trasa z modelu terenu (siatka ok. 25 m) omija urwiska, wodę i strome stoki, ale drobnych progów '
          'skalnych i zarośli może nie wykryć.',
          style: teksty.bodySmall,
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            for (final (i, o) in odcinki.indexed)
              Text('${i + 1}. ${opisAzymutu(o.azymut)} · ${opisDlugosci(o.dlugosc)}', style: teksty.bodyMedium),
          ],
        ),
      ],
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
                Text(
                  o.powrot ? 'Powrót do startu' : 'do: ${nazwaPunktu(plan, o.doIndeksu, powrot: powrot)}',
                  style: teksty.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
