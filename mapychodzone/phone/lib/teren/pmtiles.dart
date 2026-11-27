import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Odczyt fragmentu pliku: w telefonie z dysku, w przeglądarce przez nagłówek Range.
typedef CzytajZakres = Future<Uint8List> Function(int od, int dlugosc);

/// Minimalny czytnik archiwum PMTiles v3 (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md):
/// nagłówek, katalogi (gzip, varinty) i pojedyncze kafelki. Wystarcza do modelu terenu
/// (kafelki PNG bez kompresji); MapLibre czyta te same pliki sam.
class PMTiles {
  PMTiles(this._czytaj);

  final CzytajZakres _czytaj;
  _Naglowek? _naglowek;
  final Map<int, List<WpisKatalogu>> _katalogi = {};

  Future<_Naglowek> _wczytajNaglowek() async {
    final n = _naglowek;
    if (n != null) return n;
    final b = ByteData.sublistView(await _czytaj(0, 127));
    final magia = String.fromCharCodes(Uint8List.sublistView(b, 0, 7));
    if (magia != 'PMTiles' || b.getUint8(7) != 3) throw const FormatException('To nie jest PMTiles v3');
    return _naglowek = _Naglowek(
      katalogOd: _u64(b, 8),
      katalogDl: _u64(b, 16),
      liscieOd: _u64(b, 40),
      daneOd: _u64(b, 56),
      kompresjaKatalogow: b.getUint8(97),
      kompresjaKafli: b.getUint8(98),
      minZoom: b.getUint8(100),
      maxZoom: b.getUint8(101),
    );
  }

  Future<int> get maxZoom async => (await _wczytajNaglowek()).maxZoom;

  Future<List<WpisKatalogu>> _katalog(int od, int dl, int kompresja) async {
    final gotowy = _katalogi[od];
    if (gotowy != null) return gotowy;
    return _katalogi[od] = katalogZBajtow(_rozpakuj(await _czytaj(od, dl), kompresja));
  }

  /// Dane kafelka z/x/y albo null, gdy go nie ma (poza regionem).
  Future<Uint8List?> kafelek(int z, int x, int y) async {
    final n = await _wczytajNaglowek();
    if (z < n.minZoom || z > n.maxZoom) return null;
    final id = idKafelka(z, x, y);
    var od = n.katalogOd, dl = n.katalogDl;
    for (var glebokosc = 0; glebokosc < 4; glebokosc++) {
      final wpisy = await _katalog(od, dl, n.kompresjaKatalogow);
      final w = znajdzWpis(wpisy, id);
      if (w == null) return null;
      if (w.ileKolejnych > 0) {
        return _rozpakuj(await _czytaj(n.daneOd + w.przesuniecie, w.dlugosc), n.kompresjaKafli);
      }
      od = n.liscieOd + w.przesuniecie;
      dl = w.dlugosc;
    }
    return null;
  }

  static Uint8List _rozpakuj(Uint8List dane, int kompresja) => switch (kompresja) {
    0 || 1 => dane, // nieznana / brak
    2 => Uint8List.fromList(const GZipDecoder().decodeBytes(dane)),
    _ => throw FormatException('Nieobsługiwana kompresja PMTiles: $kompresja'),
  };
}

/// Liczba 64-bitowa (little endian) jako dwie 32-bitowe: ByteData.getUint64 nie działa w przeglądarce.
int _u64(ByteData b, int od) => b.getUint32(od, Endian.little) + b.getUint32(od + 4, Endian.little) * 0x100000000;

class _Naglowek {
  const _Naglowek({
    required this.katalogOd,
    required this.katalogDl,
    required this.liscieOd,
    required this.daneOd,
    required this.kompresjaKatalogow,
    required this.kompresjaKafli,
    required this.minZoom,
    required this.maxZoom,
  });

  final int katalogOd, katalogDl, liscieOd, daneOd;
  final int kompresjaKatalogow, kompresjaKafli, minZoom, maxZoom;
}

/// Wpis katalogu PMTiles.
class WpisKatalogu {
  const WpisKatalogu(this.idKafelka, this.przesuniecie, this.dlugosc, this.ileKolejnych);
  final int idKafelka, przesuniecie, dlugosc;

  /// 0 = wpis wskazuje katalog liścia, n > 0 = n kolejnych kafelków o tej samej treści.
  final int ileKolejnych;
}

/// Katalog PMTiles: liczba wpisów, potem kolumny varintów (różnice id, powtórzenia, długości, przesunięcia).
List<WpisKatalogu> katalogZBajtow(Uint8List b) {
  var i = 0;
  int varint() {
    var wynik = 0, przes = 0;
    while (true) {
      final bajt = b[i++];
      wynik += (bajt & 0x7f) * (1 << przes);
      if (bajt < 0x80) return wynik;
      przes += 7;
    }
  }

  final n = varint();
  final id = List.filled(n, 0), powt = List.filled(n, 0), dl = List.filled(n, 0), od = List.filled(n, 0);
  var ostatni = 0;
  for (var k = 0; k < n; k++) {
    ostatni += varint();
    id[k] = ostatni;
  }
  for (var k = 0; k < n; k++) {
    powt[k] = varint();
  }
  for (var k = 0; k < n; k++) {
    dl[k] = varint();
  }
  for (var k = 0; k < n; k++) {
    final v = varint();
    od[k] = v == 0 && k > 0 ? od[k - 1] + dl[k - 1] : v - 1;
  }
  return [for (var k = 0; k < n; k++) WpisKatalogu(id[k], od[k], dl[k], powt[k])];
}

/// Ostatni wpis o id ≤ szukanemu, jeśli go obejmuje (kafelki) albo wskazuje liść.
WpisKatalogu? znajdzWpis(List<WpisKatalogu> wpisy, int id) {
  var lo = 0, hi = wpisy.length - 1;
  while (lo <= hi) {
    final s = (lo + hi) >> 1;
    final c = wpisy[s].idKafelka;
    if (c < id) {
      lo = s + 1;
    } else if (c > id) {
      hi = s - 1;
    } else {
      return wpisy[s];
    }
  }
  if (hi < 0) return null;
  final w = wpisy[hi];
  if (w.ileKolejnych == 0) return w;
  return id - w.idKafelka < w.ileKolejnych ? w : null;
}

/// Id kafelka w PMTiles: kafelki niższych zoomów, potem krzywa Hilberta na danym zoomie.
int idKafelka(int z, int x, int y) {
  var wczesniej = 0;
  for (var i = 0; i < z; i++) {
    wczesniej += 1 << (2 * i);
  }
  var d = 0;
  var px = x, py = y;
  for (var s = (1 << z) >> 1; s > 0; s >>= 1) {
    final rx = (px & s) > 0 ? 1 : 0;
    final ry = (py & s) > 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        px = s - 1 - px;
        py = s - 1 - py;
      }
      final t = px;
      px = py;
      py = t;
    }
  }
  return wczesniej + d;
}
