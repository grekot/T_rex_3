import 'package:flutter/material.dart';
import 'package:wspolne/wspolne.dart';

import '../dane/katalog.dart';
import '../konto/konto.dart';
import '../konto/trasy_w_chmurze.dart';
import '../konto/zapisana_trasa.dart';
import '../trasa/trasa.dart';

/// Logowanie tym samym kontem co w Zakupach i Powrocie. Zwraca true, gdy użytkownik jest zalogowany.
Future<bool> zaloguj(BuildContext context) async {
  if (Konto.uzytkownik != null) return true;
  final wynik = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const _EkranLogowania()),
  );
  return wynik == true;
}

class _EkranLogowania extends StatefulWidget {
  const _EkranLogowania();

  @override
  State<_EkranLogowania> createState() => _EkranLogowaniaState();
}

class _EkranLogowaniaState extends State<_EkranLogowania> {
  @override
  void initState() {
    super.initState();
    Konto.zmiany.firstWhere((u) => u != null).then((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const LoginScreen(
          appName: 'MapyChodzone',
          icon: Icons.hiking,
          description: 'Konto jest potrzebne tylko do zapisywania tras: zapisane w przeglądarce '
              'masz w telefonie i odwrotnie. Mapa działa też bez konta.',
        ),
        // ekran logowania z pakietu wspolne nie ma paska z powrotem (w innych aplikacjach jest pierwszy)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: BackButton(onPressed: () => Navigator.of(context).pop(false)),
          ),
        ),
      ],
    );
  }
}

/// Lista tras zapisanych na koncie. Dotknięcie trasy zwraca jej id (mapa ją otwiera).
class EkranMoichTras extends StatelessWidget {
  const EkranMoichTras({super.key, required this.chmura, required this.katalog});

  final TrasyWChmurze chmura;
  final Katalog katalog;

  String _opis(OpisTrasy t) {
    final region = katalog.region(t.region)?.nazwa ?? t.region;
    final z = t.zmieniona;
    return [
      region,
      opisDlugosci(t.dlugosc),
      '↑${t.podejscia.round()} m',
      t.tryb.etykieta,
      if (z != null) '${z.day}.${z.month.toString().padLeft(2, '0')}.${z.year}',
    ].join(' · ');
  }

  Future<void> _zmienNazwe(BuildContext context, OpisTrasy t) async {
    final nazwa = await zapytajONazwe(context, tytul: 'Nazwa trasy', nazwa: t.nazwa, przycisk: 'Zmień');
    if (nazwa != null && nazwa != t.nazwa) await chmura.zmienNazwe(t.id, nazwa);
  }

  Future<void> _usun(BuildContext context, OpisTrasy t) async {
    final tak = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć trasę?'),
        content: Text('„${t.nazwa}” zniknie z telefonu i z przeglądarki. Tego nie da się cofnąć.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (tak == true) await chmura.usun(t.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moje trasy')),
      body: StreamBuilder<List<OpisTrasy>>(
        stream: chmura.obserwuj(),
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Nie udało się wczytać tras: ${s.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final trasy = s.data;
          if (trasy == null) return const Center(child: CircularProgressIndicator());
          if (trasy.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nie masz jeszcze zapisanych tras.\nWyznacz trasę na mapie i dotknij „Zapisz” w panelu trasy.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: trasy.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = trasy[i];
              return ListTile(
                leading: Icon(t.tryb.poDrogach ? Icons.route : Icons.explore_outlined),
                title: Text(t.nazwa),
                subtitle: Text(_opis(t)),
                onTap: () => Navigator.of(context).pop(t.id),
                trailing: PopupMenuButton<String>(
                  onSelected: (w) => w == 'nazwa' ? _zmienNazwe(context, t) : _usun(context, t),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'nazwa', child: Text('Zmień nazwę')),
                    PopupMenuItem(value: 'usun', child: Text('Usuń')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Okno z polem na nazwę trasy. Zwraca nazwę albo null (anulowano).
Future<String?> zapytajONazwe(BuildContext context, {required String tytul, required String nazwa, required String przycisk}) async {
  final w = await _oknoNazwy(context, tytul: tytul, nazwa: nazwa, przycisk: przycisk);
  return w?.$1;
}

/// Okno zapisu trasy. Dla trasy już zapisanej ([zapisana]) są dwa przyciski: „Zapisz zmiany”
/// (nadpisuje) i „Jako nową”. Zwraca (nazwa, czy jako nową) albo null.
Future<(String, bool)?> oknoZapisu(BuildContext context, {required String nazwa, required bool zapisana}) =>
    _oknoNazwy(
      context,
      tytul: zapisana ? 'Zapisz trasę' : 'Zapisz trasę na koncie',
      nazwa: nazwa,
      przycisk: zapisana ? 'Zapisz zmiany' : 'Zapisz',
      jakoNowa: zapisana,
      opis: 'Zapisana trasa będzie w „Moich trasach” w telefonie i w przeglądarce.',
    );

Future<(String, bool)?> _oknoNazwy(
  BuildContext context, {
  required String tytul,
  required String nazwa,
  required String przycisk,
  bool jakoNowa = false,
  String? opis,
}) {
  final pole = TextEditingController(text: nazwa);
  return showDialog<(String, bool)>(
    context: context,
    builder: (ctx) {
      void gotowe(bool nowa) {
        final n = pole.text.trim();
        if (n.isNotEmpty) Navigator.pop(ctx, (n, nowa));
      }

      return AlertDialog(
        title: Text(tytul),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (opis != null) Text(opis, style: Theme.of(ctx).textTheme.bodySmall),
            TextField(
              controller: pole,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Nazwa'),
              onSubmitted: (_) => gotowe(false),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          if (jakoNowa) TextButton(onPressed: () => gotowe(true), child: const Text('Jako nową')),
          FilledButton(onPressed: () => gotowe(false), child: Text(przycisk)),
        ],
      );
    },
  );
}
