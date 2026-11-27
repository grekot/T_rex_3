import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../teren/model_terenu.dart';
import 'trasa.dart';

/// Trasa na przełaj („na azymut”): możliwie prosto, ale z omijaniem przeszkód terenowych.
///
/// Siatka to piksele modelu terenu (zoom 12, ok. 25 m). Koszt przejścia to głównie odległość,
/// więc trasa trzyma się prostej, a odbija tylko przed:
///  - stokami: do 15° bez kary, potem coraz drożej, powyżej [UstawieniaPrzelaju.maxKat] zakaz
///    (nachylenie z wygładzonego modelu terenu, żeby skraj lasu w modelu DSM nie udawał progu),
///  - urwiskami (OSM natural=cliff, z marginesem jednego piksela) i wodą: zakaz,
///  - rzekami: bród, bardzo drogo,
///  - piargiem i nagą skałą: wolniej,
///  - podejściami: każdy metr w górę kosztuje jak kilka metrów marszu.
/// Wynik upraszczamy do odcinków prostych, z których każdy ma azymut do marszu z kompasem.

class UstawieniaPrzelaju {
  const UstawieniaPrzelaju({this.maxKat = 35, this.karaZaStromizne = 4});

  /// „Unikaj stromych”: zakaz już od 25° i mocniejsza kara.
  const UstawieniaPrzelaju.lagodnie() : this(maxKat: 25, karaZaStromizne: 8);

  /// Stoki stromsze niż tyle stopni są nie do przejścia.
  final double maxKat;

  /// Mnożnik kosztu przy samym [maxKat] (rośnie z kwadratem od 15°).
  final double karaZaStromizne;
}

/// Rodzaje komórek z przeszkód OSM (wyższy wygrywa).
const _wolno = 1, _rzeka = 2, _zakaz = 3;

/// Przeszkody regionu z `<region>-przeszkody.geojson` (narzedzia/przeszkody.mjs).
class Przeszkody {
  Przeszkody(this.linie, this.wielokaty, this.parki);

  /// (rodzaj, punkty [lon, lat]) – urwiska ([_zakaz], z marginesem) i rzeki ([_rzeka]).
  final List<(int, List<(double, double)>)> linie;

  /// (rodzaj, pierścień) – woda ([_zakaz]), piarg i skała ([_wolno]).
  final List<(int, List<(double, double)>)> wielokaty;

  /// (nazwa, pierścień) – parki narodowe: tylko ostrzeżenie.
  final List<(String, List<(double, double)>)> parki;

  static final pusty = Przeszkody(const [], const [], const []);

  factory Przeszkody.zGeojson(String tekst) {
    final linie = <(int, List<(double, double)>)>[];
    final wielokaty = <(int, List<(double, double)>)>[];
    final parki = <(String, List<(double, double)>)>[];
    List<(double, double)> punkty(List wsp) => [for (final p in wsp) ((p[0] as num).toDouble(), (p[1] as num).toDouble())];
    for (final f in (jsonDecode(tekst) as Map<String, dynamic>)['features'] as List) {
      final w = f['properties'] as Map<String, dynamic>;
      final g = f['geometry'] as Map<String, dynamic>;
      final t = w['t'];
      if (g['type'] == 'LineString') {
        final rodzaj = t == 'urwisko' ? _zakaz : (t == 'rzeka' ? _rzeka : null);
        if (rodzaj != null) linie.add((rodzaj, punkty(g['coordinates'] as List)));
      } else if (g['type'] == 'Polygon') {
        final pierscien = punkty((g['coordinates'] as List).first as List);
        switch (t) {
          case 'woda':
            wielokaty.add((_zakaz, pierscien));
          case 'piarg' || 'skala':
            wielokaty.add((_wolno, pierscien));
          case 'park':
            parki.add(((w['n'] as String?) ?? 'park narodowy', pierscien));
        }
      }
    }
    return Przeszkody(linie, wielokaty, parki);
  }
}

/// Siatka kosztów: komórka (x, y) to piksel globalny (px0 + x, py0 + y).
class SiatkaKosztow {
  SiatkaKosztow({
    required this.px0,
    required this.py0,
    required this.w,
    required this.h,
    required this.mpp,
    required this.wysokosc,
    required this.kat,
    required this.mnoznik,
    required this.rodzaj,
  });

  final int px0, py0, w, h;

  /// Metry na komórkę.
  final double mpp;

  /// Wysokość (m, wygładzona), nachylenie (stopnie), mnożnik kosztu (∞ = zakaz), rodzaj z OSM.
  final Float32List wysokosc, kat, mnoznik;
  final Uint8List rodzaj;
}

/// Mnożnik kosztu dla nachylenia [kat] (stopnie).
double mnoznikNachylenia(double kat, UstawieniaPrzelaju u) {
  if (kat.isNaN || kat >= u.maxKat) return double.infinity;
  if (kat <= 15) return 1;
  final t = (kat - 15) / (u.maxKat - 15);
  return 1 + u.karaZaStromizne * t * t;
}

/// Buduje siatkę kosztów z wysokości ([surowe], w×h) i rodzajów komórek z przeszkód.
SiatkaKosztow siatkaKosztow({
  required int px0,
  required int py0,
  required int w,
  required int h,
  required double mpp,
  required Float32List surowe,
  required Uint8List rodzaj,
  required UstawieniaPrzelaju ustawienia,
}) {
  // dwa razy średnia 3×3: nachylenie mierzone na ok. 75 m, a nie na 25 m
  var v = Float32List.fromList(surowe);
  for (var k = 0; k < 2; k++) {
    final t = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            final z = v[yy * w + xx];
            if (z.isNaN) continue;
            s += z;
            n++;
          }
        }
        t[y * w + x] = n == 0 ? double.nan : s / n;
      }
    }
    v = t;
  }
  final kat = Float32List(w * h);
  final mnoznik = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final xl = math.max(0, x - 1), xp = math.min(w - 1, x + 1);
      final yg = math.max(0, y - 1), yd = math.min(h - 1, y + 1);
      final dzdx = (v[y * w + xp] - v[y * w + xl]) / ((xp - xl) * mpp);
      final dzdy = (v[yd * w + x] - v[yg * w + x]) / ((yd - yg) * mpp);
      final a = math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy)) * 180 / math.pi;
      kat[i] = a;
      var m = mnoznikNachylenia(a, ustawienia);
      switch (rodzaj[i]) {
        case _zakaz:
          m = double.infinity;
        case _rzeka:
          m *= 10;
        case _wolno:
          m *= 1.6;
      }
      mnoznik[i] = m;
    }
  }
  return SiatkaKosztow(
    px0: px0, py0: py0, w: w, h: h, mpp: mpp, wysokosc: v, kat: kat, mnoznik: mnoznik, rodzaj: rodzaj);
}

/// Nanosi przeszkody na siatkę rodzajów (w pikselach globalnych, początek px0, py0).
void nanies(Uint8List rodzaj, int px0, int py0, int w, int h, Przeszkody p) {
  void ustaw(int x, int y, int r) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (rodzaj[i] < r) rodzaj[i] = r;
  }

  (double, double) naSiatke((double, double) q) => (lonNaPx(q.$1) - px0, latNaPx(q.$2) - py0);

  for (final (r, pkt) in p.linie) {
    final margines = r == _zakaz ? 1 : 0;
    for (var k = 1; k < pkt.length; k++) {
      final (ax, ay) = naSiatke(pkt[k - 1]);
      final (bx, by) = naSiatke(pkt[k]);
      if (math.max(ax, bx) < -2 || math.min(ax, bx) > w + 2 || math.max(ay, by) < -2 || math.min(ay, by) > h + 2) continue;
      final kroki = (math.max((bx - ax).abs(), (by - ay).abs()) * 2).ceil() + 1;
      for (var s = 0; s <= kroki; s++) {
        final x = (ax + (bx - ax) * s / kroki).floor(), y = (ay + (by - ay) * s / kroki).floor();
        for (var dy = -margines; dy <= margines; dy++) {
          for (var dx = -margines; dx <= margines; dx++) {
            ustaw(x + dx, y + dy, r);
          }
        }
      }
    }
  }
  for (final (r, pierscien) in p.wielokaty) {
    final pkt = [for (final q in pierscien) naSiatke(q)];
    var minY = double.infinity, maxY = -double.infinity, minX = double.infinity, maxX = -double.infinity;
    for (final (x, y) in pkt) {
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
    }
    if (maxX < 0 || minX > w || maxY < 0 || minY > h) continue;
    for (var y = math.max(0, minY.floor()); y <= math.min(h - 1, maxY.ceil()); y++) {
      final sy = y + 0.5;
      final przeciecia = <double>[];
      for (var k = 1; k < pkt.length; k++) {
        final (ax, ay) = pkt[k - 1];
        final (bx, by) = pkt[k];
        if ((ay <= sy) != (by <= sy)) przeciecia.add(ax + (sy - ay) / (by - ay) * (bx - ax));
      }
      przeciecia.sort();
      for (var k = 0; k + 1 < przeciecia.length; k += 2) {
        for (var x = math.max(0, (przeciecia[k] - 0.5).ceil()); x <= math.min(w - 1, (przeciecia[k + 1] - 0.5).floor()); x++) {
          ustaw(x, y, r);
        }
      }
    }
  }
}

/// A* po 8 sąsiadach. Zwraca indeksy komórek od [start] do [cel] albo null, gdy nie ma przejścia.
/// Komórki startu i celu są dozwolone zawsze (punkt mógł trafić w stromiznę).
List<int>? szukajDrogi(SiatkaKosztow s, int start, int cel) {
  final w = s.w, n = s.w * s.h;
  final m = Float32List.fromList(s.mnoznik);
  for (final i in [start, cel]) {
    if (!m[i].isFinite) m[i] = 5;
  }
  final g = Float64List(n)..fillRange(0, n, double.infinity);
  final skad = Int32List(n)..fillRange(0, n, -1);
  final zamkniete = Uint8List(n);
  final kopiec = _Kopiec();
  final cx = cel % w, cy = cel ~/ w;
  double heurystyka(int i) {
    final dx = (i % w - cx).toDouble(), dy = (i ~/ w - cy).toDouble();
    return math.sqrt(dx * dx + dy * dy) * s.mpp;
  }

  g[start] = 0;
  kopiec.dodaj(heurystyka(start), start);
  const sasiedzi = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)];
  while (kopiec.niepusty) {
    final i = kopiec.zdejmij();
    if (zamkniete[i] == 1) continue;
    if (i == cel) {
      final droga = <int>[];
      for (var k = cel; k != -1; k = skad[k]) {
        droga.add(k);
      }
      return droga.reversed.toList();
    }
    zamkniete[i] = 1;
    final x = i % w, y = i ~/ w;
    for (final (dx, dy) in sasiedzi) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= s.h) continue;
      final j = ny * w + nx;
      if (zamkniete[j] == 1 || !m[j].isFinite) continue;
      final d = (dx != 0 && dy != 0 ? math.sqrt2 : 1) * s.mpp;
      final dh = s.wysokosc[j] - s.wysokosc[i];
      final koszt = d * (m[i] + m[j]) / 2 + (dh.isNaN ? 0 : (dh > 0 ? 4 * dh : -0.5 * dh));
      final nowe = g[i] + koszt;
      if (nowe < g[j]) {
        g[j] = nowe;
        skad[j] = i;
        kopiec.dodaj(nowe + heurystyka(j), j);
      }
    }
  }
  return null;
}

class _Kopiec {
  final _f = <double>[];
  final _i = <int>[];

  bool get niepusty => _f.isNotEmpty;

  void dodaj(double f, int i) {
    _f.add(f);
    _i.add(i);
    var k = _f.length - 1;
    while (k > 0) {
      final r = (k - 1) >> 1;
      if (_f[r] <= _f[k]) break;
      _zamien(r, k);
      k = r;
    }
  }

  int zdejmij() {
    final wynik = _i[0];
    final ostF = _f.removeLast(), ostI = _i.removeLast();
    if (_f.isNotEmpty) {
      _f[0] = ostF;
      _i[0] = ostI;
      var k = 0;
      while (true) {
        final l = 2 * k + 1, p = l + 1;
        var min = k;
        if (l < _f.length && _f[l] < _f[min]) min = l;
        if (p < _f.length && _f[p] < _f[min]) min = p;
        if (min == k) break;
        _zamien(k, min);
        k = min;
      }
    }
    return wynik;
  }

  void _zamien(int a, int b) {
    final f = _f[a];
    _f[a] = _f[b];
    _f[b] = f;
    final i = _i[a];
    _i[a] = _i[b];
    _i[b] = i;
  }
}

/// Upraszcza drogę (indeksy komórek) do odcinków prostych: kawałek drogi zastępujemy prostą,
/// gdy nie jest od niego droższa (bez przeszkód, nie przez stromiznę, której droga unikała);
/// inaczej dzielimy go w punkcie najdalszym od prostej (jak Douglas–Peucker) i sprawdzamy połówki.
List<int> uproscDroge(SiatkaKosztow s, List<int> droga) {
  if (droga.length < 3) return droga;
  final w = s.w;
  final zostaw = Uint8List(droga.length);
  zostaw[0] = zostaw[droga.length - 1] = 1;

  double m(int i) => s.mnoznik[i].isFinite ? s.mnoznik[i] : 5;

  /// Skrót prostą z a do b: bez komórek zakazanych i nie droższy (odległość × mnożnik terenu)
  /// niż kawałek drogi z A*, który zastępuje. Schodki siatki 8 kierunków się prostują,
  /// a skrót przez stromiznę, której droga unikała, nie przechodzi.
  bool prostaDozwolona(int a, int b) {
    var oryginal = 0.0;
    for (var k = a; k < b; k++) {
      final i = droga[k], j = droga[k + 1];
      final d = (i % w != j % w && i ~/ w != j ~/ w) ? math.sqrt2 : 1.0;
      oryginal += d * (m(i) + m(j)) / 2;
    }
    final ax = droga[a] % w + 0.5, ay = droga[a] ~/ w + 0.5;
    final bx = droga[b] % w + 0.5, by = droga[b] ~/ w + 0.5;
    final dl = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    final kroki = math.max(1, (dl * 2).ceil());
    var prosta = 0.0;
    for (var k = 0; k < kroki; k++) {
      final t = (k + 0.5) / kroki;
      final i = (ay + (by - ay) * t).floor() * w + (ax + (bx - ax) * t).floor();
      if (!s.mnoznik[i].isFinite && i != droga[a] && i != droga[b]) return false;
      prosta += dl / kroki * m(i);
    }
    return prosta <= oryginal * 1.02;
  }

  final stos = [(0, droga.length - 1)];
  while (stos.isNotEmpty) {
    final (a, b) = stos.removeLast();
    if (b - a < 2) continue;
    final ax = (droga[a] % w).toDouble(), ay = (droga[a] ~/ w).toDouble();
    final bx = (droga[b] % w).toDouble(), by = (droga[b] ~/ w).toDouble();
    final dl = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    var max = -1.0, gdzie = -1;
    for (var k = a + 1; k < b; k++) {
      final px = (droga[k] % w).toDouble(), py = (droga[k] ~/ w).toDouble();
      final d = dl == 0
          ? math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay))
          : ((bx - ax) * (ay - py) - (ax - px) * (by - ay)).abs() / dl;
      if (d > max) {
        max = d;
        gdzie = k;
      }
    }
    if (!prostaDozwolona(a, b)) {
      zostaw[gdzie] = 1;
      stos
        ..add((a, gdzie))
        ..add((gdzie, b));
    }
  }
  return [for (var k = 0; k < droga.length; k++) if (zostaw[k] == 1) droga[k]];
}

/// Azymut geograficzny (0–360°, od północy w prawo) z punktu A do B.
double azymut(double lon1, double lat1, double lon2, double lat2) {
  final f1 = lat1 * math.pi / 180, f2 = lat2 * math.pi / 180;
  final dl = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(dl) * math.cos(f2);
  final x = math.cos(f1) * math.sin(f2) - math.sin(f1) * math.cos(f2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Czy punkt leży w wielokącie (pierścień [lon, lat]).
bool wWielokacie(double lon, double lat, List<(double, double)> p) {
  var w = false;
  for (var i = 0, j = p.length - 1; i < p.length; j = i++) {
    final (xi, yi) = p[i];
    final (xj, yj) = p[j];
    if ((yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) w = !w;
  }
  return w;
}

/// Wyznacza trasę na przełaj przez kolejne punkty (lon, lat).
/// [model] daje wysokości, [przeszkody] – urwiska, wodę i parki.
Future<Trasa> trasaNaPrzelaj(
  List<(double, double)> punkty, {
  required ModelTerenu model,
  required Przeszkody przeszkody,
  UstawieniaPrzelaju ustawienia = const UstawieniaPrzelaju(),
}) async {
  final wynik = <PunktTrasy>[];
  final odcinki = <OdcinekAzymutu>[];
  var maxKat = 0.0;
  var rzeka = false;
  final parki = <String>{};

  for (var k = 1; k < punkty.length; k++) {
    final (lonA, latA) = punkty[k - 1];
    final (lonB, latB) = punkty[k];
    final ax = lonNaPx(lonA), ay = latNaPx(latA), bx = lonNaPx(lonB), by = latNaPx(latB);
    final mpp = metryNaPx((latA + latB) / 2);
    final dlugoscPx = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    if (dlugoscPx * mpp > 15000) {
      throw BladPrzelaju('Odcinek na przełaj ma ponad 15 km. Dodaj punkty pośrednie.');
    }
    final margines = math.max(20, (dlugoscPx * 0.35).ceil());
    final px0 = (math.min(ax, bx) - margines).floor(), py0 = (math.min(ay, by) - margines).floor();
    final w = (math.max(ax, bx) + margines).ceil() - px0, h = (math.max(ay, by) + margines).ceil() - py0;
    final surowe = await model.siatka(px0, py0, w, h);
    final rodzaj = Uint8List(w * h);
    nanies(rodzaj, px0, py0, w, h, przeszkody);
    final s = siatkaKosztow(
        px0: px0, py0: py0, w: w, h: h, mpp: mpp, surowe: surowe, rodzaj: rodzaj, ustawienia: ustawienia);
    final start = (ay.floor() - py0) * w + (ax.floor() - px0);
    final cel = (by.floor() - py0) * w + (bx.floor() - px0);
    final droga = szukajDrogi(s, start, cel);
    if (droga == null) {
      throw BladPrzelaju('Nie da się przejść na przełaj: po drodze są urwiska, woda albo stoki stromsze niż '
          '${ustawienia.maxKat.round()}°. Dodaj punkt „przez” w innym miejscu albo wybierz trasę szlakami.');
    }
    for (final i in droga) {
      if (i != start && i != cel) maxKat = math.max(maxKat, s.kat[i]);
      if (s.rodzaj[i] == _rzeka) rzeka = true;
    }
    final wierzcholki = uproscDroge(s, droga);
    // punkty: początek i koniec odcinka dokładnie w punktach planu, w środku środki komórek
    final wsp = <(double, double)>[
      (lonA, latA),
      for (final i in wierzcholki.sublist(1, wierzcholki.length - 1))
        (pxNaLon(px0 + i % w + 0.5), pxNaLat(py0 + i ~/ w + 0.5)),
      (lonB, latB),
    ];
    double wysokoscW(double lon, double lat) {
      final x = (lonNaPx(lon) - px0 - 0.5).clamp(0, w - 1.001), y = (latNaPx(lat) - py0 - 0.5).clamp(0, h - 1.001);
      final x0 = x.floor(), y0 = y.floor(), tx = x - x0, ty = y - y0;
      double z(int xx, int yy) => surowe[math.min(h - 1, yy) * w + math.min(w - 1, xx)];
      return (z(x0, y0) * (1 - tx) + z(x0 + 1, y0) * tx) * (1 - ty) + (z(x0, y0 + 1) * (1 - tx) + z(x0 + 1, y0 + 1) * tx) * ty;
    }

    for (var j = 1; j < wsp.length; j++) {
      final (l1, f1) = wsp[j - 1];
      final (l2, f2) = wsp[j];
      final dl = odlegloscM(f1, l1, f2, l2);
      odcinki.add(OdcinekAzymutu(azymut(l1, f1, l2, f2), dl));
      // punkty co ok. 25 m: profil wysokości i odległości
      final n = math.max(1, (dl / mpp).ceil());
      for (var q = (j == 1 && wynik.isEmpty) ? 0 : 1; q <= n; q++) {
        final lon = l1 + (l2 - l1) * q / n, lat = f1 + (f2 - f1) * q / n;
        final h = wysokoscW(lon, lat);
        final ost = wynik.isEmpty ? null : wynik.last;
        wynik.add(PunktTrasy(lon, lat, h.isNaN ? null : h, ost == null ? 0 : ost.odStartu + odlegloscM(ost.lat, ost.lon, lat, lon)));
      }
    }
  }

  for (var k = 0; k < wynik.length; k += 2) {
    for (final (nazwa, p) in przeszkody.parki) {
      if (!parki.contains(nazwa) && wWielokacie(wynik[k].lon, wynik[k].lat, p)) parki.add(nazwa);
    }
  }
  final uwagi = [
    if (parki.isNotEmpty)
      'Trasa idzie poza szlakiem przez park narodowy (${parki.join(', ')}). Tam chodzenie poza szlakami jest zabronione.',
    if (rzeka) 'Trasa przechodzi przez rzekę (bród).',
    if (maxKat >= 25) 'Najbardziej strome miejsce: ok. ${maxKat.round()}°.',
  ];
  return Trasa(wynik, uwagi: uwagi, azymuty: odcinki);
}

class BladPrzelaju implements Exception {
  BladPrzelaju(this.komunikat);
  final String komunikat;
  @override
  String toString() => komunikat;
}
