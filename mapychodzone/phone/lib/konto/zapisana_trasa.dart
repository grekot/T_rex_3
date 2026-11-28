import '../trasa/plan.dart';
import '../trasa/trasa.dart';

/// Trasa zapisana na koncie (Firestore `trasy/{id}`), wspólna dla telefonu i przeglądarki.
///
/// Zapisujemy plan (punkty, tryb, opcje) i gotowy ślad „tam”. Otwarta trasa pokazuje się od razu,
/// bez ponownego liczenia: w górach, bez internetu, telefon ma dokładnie to, co zaplanowano na
/// komputerze (BRouter w telefonie i brouter.de mogą mieć dane OSM z różnych dni).
/// Po zmianie punktów trasa liczy się na nowo jak zwykle.
class ZapisanaTrasa {
  const ZapisanaTrasa({
    this.id,
    required this.nazwa,
    required this.region,
    required this.plan,
    required this.tryb,
    required this.powrot,
    required this.unikajStromych,
    required this.tam,
    this.zmieniona,
  });

  /// Id dokumentu; null dla trasy jeszcze niezapisanej.
  final String? id;
  final String nazwa;

  /// Id regionu z katalogu paczek (np. `wyspowy-gorce`).
  final String region;
  final PlanTrasy plan;
  final TrybTrasy tryb;
  final bool powrot;
  final bool unikajStromych;

  /// Trasa „tam” (bez powrotu; powrót dokłada [Trasa.zPowrotem]).
  final Trasa tam;
  final DateTime? zmieniona;

  /// Trasa do pokazania: z powrotem albo bez.
  Trasa get trasa => powrot ? tam.zPowrotem() : tam;

  /// Wersja formatu dokumentu.
  static const format = 1;

  ZapisanaTrasa zmien({String? id, String? nazwa}) => ZapisanaTrasa(
        id: id ?? this.id,
        nazwa: nazwa ?? this.nazwa,
        region: region,
        plan: plan,
        tryb: tryb,
        powrot: powrot,
        unikajStromych: unikajStromych,
        tam: tam,
        zmieniona: zmieniona,
      );

  /// Pola dokumentu bez właściciela i znaczników czasu (dokłada je repozytorium).
  /// Firestore nie zna tablic w tablicach, dlatego punkty i azymuty to listy map.
  Map<String, dynamic> doMapy() {
    final t = trasa;
    return {
      'v': format,
      'nazwa': nazwa,
      'region': region,
      'tryb': tryb.name,
      'powrot': powrot,
      'unikajStromych': unikajStromych,
      'punkty': [
        for (final p in plan.punkty)
          {
            'x': p.lon,
            'y': p.lat,
            'r': p.rodzaj.name,
            'n': ?p.nazwa,
          },
      ],
      'slad': zakodujSlad(tam.punkty),
      'trudnyTeren': {for (final e in tam.trudnyTeren.entries) '${e.key}': e.value},
      'uwagi': tam.uwagi,
      'azymuty': [
        for (final o in tam.azymuty) {'a': o.azymut, 'd': o.dlugosc},
      ],
      // do listy tras (bez dekodowania śladu); z powrotem, jeśli zaznaczony
      'dlugosc': t.dlugosc.roundToDouble(),
      'podejscia': t.podejscia.roundToDouble(),
      'zejscia': t.zejscia.roundToDouble(),
    };
  }

  factory ZapisanaTrasa.zMapy(String id, Map<String, dynamic> m, {DateTime? zmieniona}) {
    final punkty = [
      for (final p in (m['punkty'] as List? ?? const []).cast<Map>())
        PunktPlanu(
          (p['x'] as num).toDouble(),
          (p['y'] as num).toDouble(),
          RodzajPunktu.values.asNameMap()[p['r']] ?? RodzajPunktu.przez,
          nazwa: p['n'] as String?,
        ),
    ];
    final trudny = <int, double>{
      for (final e in (m['trudnyTeren'] as Map? ?? const {}).entries)
        ?int.tryParse('${e.key}'): (e.value as num).toDouble(),
    };
    return ZapisanaTrasa(
      id: id,
      nazwa: m['nazwa'] as String? ?? 'Trasa',
      region: m['region'] as String? ?? '',
      plan: PlanTrasy(punkty),
      tryb: TrybTrasy.values.asNameMap()[m['tryb']] ?? TrybTrasy.szlakami,
      powrot: m['powrot'] == true,
      unikajStromych: m['unikajStromych'] == true,
      tam: Trasa(
        odkodujSlad(m['slad'] as String? ?? ''),
        trudnyTeren: trudny,
        uwagi: [for (final u in m['uwagi'] as List? ?? const []) '$u'],
        azymuty: [
          for (final o in (m['azymuty'] as List? ?? const []).cast<Map>())
            OdcinekAzymutu((o['a'] as num).toDouble(), (o['d'] as num).toDouble()),
        ],
      ),
      zmieniona: zmieniona,
    );
  }
}

/// Podsumowanie trasy z dokumentu, bez dekodowania śladu (lista „Moje trasy”).
class OpisTrasy {
  const OpisTrasy({
    required this.id,
    required this.nazwa,
    required this.region,
    required this.dlugosc,
    required this.podejscia,
    required this.tryb,
    this.zmieniona,
  });

  final String id;
  final String nazwa;
  final String region;
  final double dlugosc;
  final double podejscia;
  final TrybTrasy tryb;
  final DateTime? zmieniona;

  factory OpisTrasy.zMapy(String id, Map<String, dynamic> m, {DateTime? zmieniona}) => OpisTrasy(
        id: id,
        nazwa: m['nazwa'] as String? ?? 'Trasa',
        region: m['region'] as String? ?? '',
        dlugosc: (m['dlugosc'] as num? ?? 0).toDouble(),
        podejscia: (m['podejscia'] as num? ?? 0).toDouble(),
        tryb: TrybTrasy.values.asNameMap()[m['tryb']] ?? TrybTrasy.szlakami,
        zmieniona: zmieniona,
      );
}

/// Proponowana nazwa nowej trasy: „Start → Cel” z nazw punktów (bez nazw: „Trasa 28.11.2026”).
String proponowanaNazwa(PlanTrasy plan, DateTime teraz) {
  String? nazwa(PunktPlanu p) {
    final n = p.nazwa;
    if (n == null) return null;
    // „Schronisko PTTK na Turbaczu (1283 m)” → bez wysokości w nawiasie
    return n.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '');
  }

  final a = plan.punkty.isEmpty ? null : nazwa(plan.punkty.first);
  final b = plan.punkty.length < 2 ? null : nazwa(plan.punkty.last);
  final data = '${teraz.day}.${teraz.month.toString().padLeft(2, '0')}.${teraz.year}';
  if (a != null && b != null) return a == b ? a : '$a → $b';
  if (a != null || b != null) return '${a ?? b} · $data';
  return 'Trasa $data';
}

const _brakWysokosci = -9999.0;

/// Ślad jako tekst: kolejne różnice (szerokość, długość ×1e6, wysokość ×10) zakodowane jak
/// w Google Encoded Polyline. Ok. 12 znaków na punkt zamiast ok. 40 w JSON-ie.
String zakodujSlad(List<PunktTrasy> punkty) {
  final b = StringBuffer();
  var pLat = 0, pLon = 0, pH = 0;
  for (final p in punkty) {
    final lat = (p.lat * 1e6).round();
    final lon = (p.lon * 1e6).round();
    final h = ((p.wysokosc ?? _brakWysokosci) * 10).round();
    _liczba(b, lat - pLat);
    _liczba(b, lon - pLon);
    _liczba(b, h - pH);
    pLat = lat;
    pLon = lon;
    pH = h;
  }
  return b.toString();
}

// Arytmetyka zamiast `~` i przesunięć ujemnych liczb: w przeglądarce (dart2js) operacje bitowe
// dają 32-bitowe liczby bez znaku, więc ~4 to 4294967291, a nie -5.
void _liczba(StringBuffer b, int v) {
  var u = v < 0 ? -2 * v - 1 : 2 * v;
  while (u >= 0x20) {
    b.writeCharCode((0x20 | (u & 0x1f)) + 63);
    u >>= 5;
  }
  b.writeCharCode(u + 63);
}

/// Odwrotność [zakodujSlad]; odległości od startu liczone na nowo.
List<PunktTrasy> odkodujSlad(String tekst) {
  final wynik = <PunktTrasy>[];
  var i = 0;
  int liczba() {
    var u = 0, przesuniecie = 0, c = 0;
    do {
      c = tekst.codeUnitAt(i++) - 63;
      u |= (c & 0x1f) << przesuniecie;
      przesuniecie += 5;
    } while (c >= 0x20);
    return u.isOdd ? -(u >> 1) - 1 : u >> 1;
  }

  var lat = 0, lon = 0, h = 0;
  double suma = 0;
  while (i < tekst.length) {
    lat += liczba();
    lon += liczba();
    h += liczba();
    final y = lat / 1e6, x = lon / 1e6;
    final wys = h / 10;
    if (wynik.isNotEmpty) suma += odlegloscM(wynik.last.lat, wynik.last.lon, y, x);
    wynik.add(PunktTrasy(x, y, wys <= _brakWysokosci + 1 ? null : wys, suma));
  }
  return wynik;
}
