// Zamiana atlasu ćwiczeń (Markdown) na dane `atlas.json`.
//
// Atlas: `<a id="kotwica"></a>` + `## N. Tytuł`, rysunki `![alt](img/plik.jpg)`,
// sekcje jako pogrubione nagłówki: `**Ruch**` (z listą pod spodem) albo
// `**Po co:** tekst` (w jednej linii). Nagłówki grup ćwiczeń to `# Tytuł`.
// Parser jest celowo prosty i nie gubi niczego: nieznane nagłówki trafiają
// do sekcji rodzaju `inne` razem z tytułem.

const atlasFormat = 'trening-atlas/1';

/// Rodzaj sekcji na podstawie początku tytułu (małe litery).
String rodzajSekcji(String tytul) {
  final t = tytul.toLowerCase();
  const mapa = [
    ('po co', 'poCo'),
    ('pozycja wyjściowa', 'pozycja'),
    ('ruch', 'ruch'),
    ('gdzie czujesz', 'gdzieCzujesz'),
    ('najczęstsze błędy', 'bledy'),
    ('łatwiej', 'latwiej'),
    ('trudniej', 'trudniej'),
    ('przerwij, jeśli', 'przerwijJesli'),
    ('kiedy', 'kiedy'),
    ('warunki', 'kiedy'),
    ('warunek', 'kiedy'),
  ];
  for (final (prefiks, rodzaj) in mapa) {
    if (t.startsWith(prefiks)) return rodzaj;
  }
  return 'inne';
}

final _kotwica = RegExp(r'^<a id="([^"]+)"></a>\s*$');
final _tytul = RegExp(r'^##\s+\d+\.\s+(.+?)\s*$');
final _grupa = RegExp(r'^#\s+(.+?)\s*$');
final _rysunek = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)\s*$');
final _punkt = RegExp(r'^-\s+(.+)$');
final _numer = RegExp(r'^\d+\.\s+(.+)$');
final _naglowekSam = RegExp(r'^\*\*([^*]+?)\*\*\s*$');
final _naglowekZTekstem = RegExp(r'^\*\*([^*]+?)\*\*\s*(.+)$');

class _Sekcja {
  _Sekcja(this.tytul);
  final String tytul;
  final List<String> teksty = [];
  final List<String> punkty = [];
  bool numerowane = false;

  Map<String, Object?> toJson() => {
        'rodzaj': tytul.isEmpty ? 'inne' : rodzajSekcji(tytul),
        'tytul': tytul,
        if (teksty.isNotEmpty) 'tekst': teksty.join(' '),
        if (punkty.isNotEmpty) 'punkty': punkty,
        if (punkty.isNotEmpty) 'numerowane': numerowane,
      };
}

String _bezDwukropka(String s) {
  final t = s.trim();
  return t.endsWith(':') ? t.substring(0, t.length - 1).trim() : t;
}

/// Najdłuższy wspólny początek nazw plików (do kluczy wariantów rysunków).
String _wspolnyPrefiks(List<String> nazwy) {
  if (nazwy.isEmpty) return '';
  var p = nazwy.first;
  for (final n in nazwy.skip(1)) {
    var i = 0;
    while (i < p.length && i < n.length && p[i] == n[i]) {
      i++;
    }
    p = p.substring(0, i);
  }
  return p;
}

String _nazwaPliku(String sciezka) {
  final nazwa = sciezka.split('/').last;
  final kropka = nazwa.lastIndexOf('.');
  return kropka > 0 ? nazwa.substring(0, kropka) : nazwa;
}

/// Zdanie od „Rysunek pokazuje” do końca punktu albo tekstu.
String? _uwagaORysunku(String tekst) {
  final i = tekst.indexOf('Rysunek pokazuje');
  if (i < 0) return null;
  return tekst.substring(i).replaceAll('**', '').trim();
}

Map<String, Object?> parsujAtlas(String markdown) {
  final linie = markdown.replaceAll('\r\n', '\n').split('\n');
  final zasady = <String>[];
  final cwiczenia = <String, Map<String, Object?>>{};

  String? grupa;
  String? id;
  String? nazwa;
  var sekcje = <_Sekcja>[];
  var rysunki = <Map<String, String>>[];
  String? podpisCzekajacy;
  _Sekcja? biezaca;
  var wZasadach = false;

  void zamknij() {
    if (id == null) return;
    final uzyte = sekcje
        .where((s) => s.teksty.isNotEmpty || s.punkty.isNotEmpty)
        .toList();
    // klucze wariantów: jeden rysunek → '', kilka → nazwa pliku bez wspólnego początku
    final pliki = [for (final r in rysunki) _nazwaPliku(r['plik']!)];
    final prefiks = pliki.length > 1 ? _wspolnyPrefiks(pliki) : null;
    final mapa = <String, Map<String, String>>{};
    for (var i = 0; i < rysunki.length; i++) {
      final klucz = prefiks == null ? '' : pliki[i].substring(prefiks.length);
      mapa[klucz] = rysunki[i];
    }
    // uwagi „Rysunek pokazuje…”: do wariantu, którego klucz pojawia się w zdaniu
    for (final s in uzyte) {
      for (final tekst in [...s.teksty, ...s.punkty]) {
        final uwaga = _uwagaORysunku(tekst);
        if (uwaga == null) continue;
        String? cel;
        if (mapa.length == 1) {
          cel = mapa.keys.first;
        } else {
          // wariant wymieniony najwcześniej („**Na kolanach:** … stopy za sobą” → kolana)
          final maly = tekst.toLowerCase();
          var najwczesniej = maly.length;
          for (final k in mapa.keys) {
            final rdzen = k.length > 5 ? k.substring(0, 5) : k;
            final i = k.isEmpty ? -1 : maly.indexOf(rdzen);
            if (i >= 0 && i < najwczesniej) {
              najwczesniej = i;
              cel = k;
            }
          }
        }
        if (cel != null) mapa[cel]!['uwaga'] = uwaga;
      }
    }
    cwiczenia[id!] = {
      'nazwa': nazwa ?? id,
      'grupa': grupa,
      'rysunki': mapa,
      'sekcje': [for (final s in uzyte) s.toJson()],
    };
    id = null;
    nazwa = null;
    sekcje = [];
    rysunki = [];
    podpisCzekajacy = null;
    biezaca = null;
  }

  for (var n = 0; n < linie.length; n++) {
    final linia = linie[n].trimRight();
    final t = linia.trim();

    if (t.startsWith('## Zasady wspólne')) {
      wZasadach = true;
      continue;
    }
    if (wZasadach) {
      if (t.startsWith('## ') || t.startsWith('# ') || t == '---') {
        wZasadach = false;
      } else {
        final m = _punkt.firstMatch(t);
        if (m != null) zasady.add(m.group(1)!);
        continue;
      }
    }

    final mk = _kotwica.firstMatch(t);
    if (mk != null) {
      zamknij();
      id = mk.group(1);
      continue;
    }
    final mg = _grupa.firstMatch(t);
    if (mg != null && !t.startsWith('##')) {
      zamknij();
      grupa = mg.group(1);
      continue;
    }
    if (id == null) continue;

    final mt = _tytul.firstMatch(t);
    if (mt != null) {
      nazwa = mt.group(1);
      continue;
    }
    if (t == '---') {
      zamknij();
      continue;
    }
    if (t.isEmpty) continue;

    final mr = _rysunek.firstMatch(t);
    if (mr != null) {
      rysunki.add({
        'plik': mr.group(2)!,
        'opis': mr.group(1)!,
        if (podpisCzekajacy != null) 'podpis': podpisCzekajacy!,
      });
      podpisCzekajacy = null;
      continue;
    }

    final ms = _naglowekSam.firstMatch(t);
    if (ms != null) {
      // pogrubiona linia tuż przed rysunkiem to podpis wariantu, nie sekcja
      var k = n + 1;
      while (k < linie.length && linie[k].trim().isEmpty) {
        k++;
      }
      if (k < linie.length && _rysunek.hasMatch(linie[k].trim())) {
        podpisCzekajacy = ms.group(1)!.trim();
        continue;
      }
      biezaca = _Sekcja(_bezDwukropka(ms.group(1)!));
      sekcje.add(biezaca!);
      continue;
    }
    final mz = _naglowekZTekstem.firstMatch(t);
    if (mz != null && !_punkt.hasMatch(t)) {
      biezaca = _Sekcja(_bezDwukropka(mz.group(1)!))
        ..teksty.add(mz.group(2)!.trim());
      sekcje.add(biezaca!);
      continue;
    }

    final mp = _punkt.firstMatch(t);
    final mn = _numer.firstMatch(t);
    if (mp != null || mn != null) {
      if (biezaca == null || biezaca!.teksty.isNotEmpty && biezaca!.punkty.isEmpty && biezaca!.tytul.isNotEmpty) {
        biezaca = _Sekcja('');
        sekcje.add(biezaca!);
      }
      biezaca!.punkty.add((mp ?? mn)!.group(1)!.trim());
      if (mn != null) biezaca!.numerowane = true;
      continue;
    }

    // zwykły akapit: osobna sekcja bez tytułu, chyba że ciągnie poprzedni tekst
    if (biezaca == null || biezaca!.punkty.isNotEmpty || biezaca!.tytul.isNotEmpty) {
      biezaca = _Sekcja('');
      sekcje.add(biezaca!);
    }
    biezaca!.teksty.add(t);
  }
  zamknij();

  return {
    'format': atlasFormat,
    'zrodlo': 'cwiczenia/atlas_cwiczen.md',
    'zasadyWspolne': zasady,
    'cwiczenia': cwiczenia,
  };
}
