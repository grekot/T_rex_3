/// Stan użytkownika (`stan.json`, tylko na telefonie): data startu, historia etapów,
/// wynik testu kierunkowego, treningi z oceną bólu, poranne check-iny, dni wolne,
/// ustawienia przypomnień.
library;

import '../przypomnienia/harmonogram.dart';
import '../silnik/daty.dart';
import '../silnik/flagi.dart';
import '../silnik/kalendarz.dart';
import '../silnik/sygnalizacja.dart';

const stanFormat = 'trening-stan/1';

/// Start nowego stanu (testy). W aplikacji datę startu wybierasz na ekranie powitania.
final domyslnyStart = DateTime.utc(2026, 11, 23);

DateTime _data(Object? s) => DateTime.parse('${s}T00:00:00Z');

class WynikTestuKierunkowego {
  WynikTestuKierunkowego({
    required this.data,
    required this.wynik,
    required this.bolPrzed,
    required this.zasiegPrzed,
    required this.bolPo,
    required this.zasiegPo,
    this.mrowienie = false,
  });

  final DateTime data;
  final WynikTestu wynik;
  final int bolPrzed;
  final Zasieg zasiegPrzed;
  final int bolPo;
  final Zasieg zasiegPo;
  final bool mrowienie;

  Map<String, Object?> toJson() => {
        'data': iso(data),
        'wynik': wynik.name,
        'przed': {'bol': bolPrzed, 'zasieg': zasiegPrzed.name},
        'po': {'bol': bolPo, 'zasieg': zasiegPo.name},
        if (mrowienie) 'mrowienie': true,
      };

  static WynikTestuKierunkowego zJson(Map<String, Object?> j) {
    final przed = (j['przed']! as Map).cast<String, Object?>();
    final po = (j['po']! as Map).cast<String, Object?>();
    return WynikTestuKierunkowego(
      data: _data(j['data']),
      wynik: WynikTestu.values.byName(j['wynik']! as String),
      bolPrzed: przed['bol']! as int,
      zasiegPrzed: Zasieg.values.byName(przed['zasieg']! as String),
      bolPo: po['bol']! as int,
      zasiegPo: Zasieg.values.byName(po['zasieg']! as String),
      mrowienie: j['mrowienie'] == true,
    );
  }
}

/// Jak skończył się dzień treningowy.
enum StanDnia { wykonane, skrocone }

/// Ocena bólu po treningu (sekcja 5.1) ze strefą sygnalizacji. Strefa może się
/// zmienić rano: ból 3–4, który nie minął w 24 h, to strefa czerwona.
class OcenaPoTreningu {
  OcenaPoTreningu({
    required this.bol,
    required this.zasieg,
    this.mrowienie = false,
    this.nasililo,
    required this.strefa,
    this.minelo,
  });

  final int bol;
  final Zasieg zasieg;
  final bool mrowienie;

  /// Ćwiczenie planu, które nasiliło ból (opcjonalnie).
  final String? nasililo;
  Strefa strefa;

  /// Odpowiedź z porannego check-inu: czy ból po treningu minął.
  bool? minelo;

  OcenaBolu get jakoOcena => OcenaBolu(bol: bol, zasieg: zasieg, mrowienie: mrowienie);

  Map<String, Object?> toJson() => {
        'bol': bol,
        'zasieg': zasieg.name,
        if (mrowienie) 'mrowienie': true,
        if (nasililo != null) 'nasililo': nasililo,
        'strefa': strefa.name,
        if (minelo != null) 'minelo': minelo,
      };

  static OcenaPoTreningu zJson(Map<String, Object?> j) => OcenaPoTreningu(
        bol: j['bol']! as int,
        zasieg: Zasieg.values.byName(j['zasieg']! as String),
        mrowienie: j['mrowienie'] == true,
        nasililo: j['nasililo'] as String?,
        strefa: Strefa.values.byName(j['strefa']! as String),
        minelo: j['minelo'] as bool?,
      );
}

/// Poranny check-in (sekcja 5.2): ból w spoczynku i gdzie się kończy.
class Checkin {
  Checkin({required DateTime data, required this.bol, required this.zasieg}) : data = dzien(data);

  final DateTime data;
  final int bol;
  final Zasieg zasieg;

  Map<String, Object?> toJson() => {'bol': bol, 'zasieg': zasieg.name};

  static Checkin zJson(String data, Map<String, Object?> j) =>
      Checkin(data: _data(data), bol: j['bol']! as int, zasieg: Zasieg.values.byName(j['zasieg']! as String));
}

class ZapisTreningu {
  ZapisTreningu({
    required this.data,
    required this.sesja,
    required this.stan,
    this.planWersja,
    this.start,
    this.koniec,
    this.wykonane = const [],
    this.pominiete = const [],
    this.bolesne = const [],
    this.recznie = false,
    this.czesci = const [],
    this.ocena,
  });

  final DateTime data;
  final String sesja;
  final StanDnia stan;
  final String? planWersja;
  final DateTime? start;
  final DateTime? koniec;
  final List<String> wykonane;
  final List<String> pominiete;

  /// Ćwiczenia przerwane przyciskiem „Boli: pomiń”.
  final List<String> bolesne;

  /// „Zrobiłem bez aplikacji”.
  final bool recznie;

  /// Zrobione części „dwóch krótszych wersji” (0, 1); pusta = cała sesja naraz.
  final List<int> czesci;

  OcenaPoTreningu? ocena;

  Map<String, Object?> toJson() => {
        if (czesci.isNotEmpty) 'czesci': czesci,
        'sesja': sesja,
        'stan': stan.name,
        if (planWersja != null) 'planWersja': planWersja,
        if (start != null) 'start': start!.toUtc().toIso8601String(),
        if (koniec != null) 'koniec': koniec!.toUtc().toIso8601String(),
        if (wykonane.isNotEmpty) 'wykonane': wykonane,
        if (pominiete.isNotEmpty) 'pominiete': pominiete,
        if (bolesne.isNotEmpty) 'bolesne': bolesne,
        if (recznie) 'recznie': true,
        if (ocena != null) 'ocena': ocena!.toJson(),
      };

  static ZapisTreningu zJson(String data, Map<String, Object?> j) {
    List<String> lista(String k) => (j[k] as List?)?.cast<String>() ?? const [];
    DateTime? czas(String k) => j[k] == null ? null : DateTime.parse(j[k]! as String);
    return ZapisTreningu(
      data: _data(data),
      sesja: j['sesja']! as String,
      stan: StanDnia.values.byName(j['stan']! as String),
      planWersja: j['planWersja'] as String?,
      start: czas('start'),
      koniec: czas('koniec'),
      wykonane: lista('wykonane'),
      pominiete: lista('pominiete'),
      bolesne: lista('bolesne'),
      recznie: j['recznie'] == true,
      czesci: (j['czesci'] as List?)?.cast<int>() ?? const [],
      ocena: j['ocena'] == null ? null : OcenaPoTreningu.zJson((j['ocena']! as Map).cast<String, Object?>()),
    );
  }
}

class Stan {
  Stan({
    DateTime? start,
    List<WpisEtapu>? etapy,
    this.testKierunkowy,
    Map<String, ZapisTreningu>? treningi,
    Set<String>? widzianeTechniki,
    this.slizgiOdFizjo = false,
    Map<String, Checkin>? checkiny,
    Set<String>? wolne,
    Map<String, DateTime>? wstrzymane,
    this.fizjoOd,
    this.fizjoUmowione = false,
    this.powitanieZrobione = false,
    this.pierwszeUruchomienie,
    this.otwarteOkienko,
    this.paliDzis,
    UstawieniaPrzypomnien? przypomnienia,
  })  : start = dzien(start ?? domyslnyStart),
        etapy = etapy ?? [WpisEtapu(1, start ?? domyslnyStart)],
        treningi = treningi ?? {},
        widzianeTechniki = widzianeTechniki ?? {},
        checkiny = checkiny ?? {},
        wolne = wolne ?? {},
        wstrzymane = wstrzymane ?? {},
        przypomnienia = przypomnienia ?? UstawieniaPrzypomnien();

  DateTime start;
  final List<WpisEtapu> etapy;
  WynikTestuKierunkowego? testKierunkowy;

  /// Klucz: data ISO (`2026-11-23`).
  final Map<String, ZapisTreningu> treningi;

  /// Ćwiczenia, których pełny opis techniki już się pokazał (pierwszy raz otwiera się sam).
  final Set<String> widzianeTechniki;
  bool slizgiOdFizjo;

  /// Poranne check-iny; klucz: data ISO.
  final Map<String, Checkin> checkiny;

  /// Dni oznaczone jako wolne (data ISO).
  final Set<String> wolne;

  /// Ćwiczenia wstrzymane po bólu: id ćwiczenia planu → ostatni dzień wstrzymania.
  final Map<String, DateTime> wstrzymane;

  /// Od kiedy aplikacja zaleca fizjoterapeutę (ból poniżej kolana albo mrowienie
  /// w 2 różne dni w ciągu tygodnia); [fizjoUmowione] kończy przypominanie.
  DateTime? fizjoOd;
  bool fizjoUmowione;

  /// Ekran powitania: zastrzeżenie potwierdzone, data startu wybrana.
  bool powitanieZrobione;

  /// Pierwszy dzień z aplikacją: dni przed nim można odznaczyć „bez aplikacji” bez limitu 7 dni.
  DateTime? pierwszeUruchomienie;

  /// Dzień, w którym ostatnio otwarto dzisiejsze okienko (drzwiczki otwierają się raz).
  DateTime? otwarteOkienko;

  /// Dzień, w którym włączono „Pali dziś w krzyżu” (częstsze przerwy do końca dnia).
  DateTime? paliDzis;
  final UstawieniaPrzypomnien przypomnienia;

  /// Gdzie kończył się ból: najgorszy wpis dnia z check-inu i z oceny po treningu.
  Map<DateTime, Zasieg> get zasiegi {
    final m = <DateTime, Zasieg>{};
    void dodaj(DateTime d, Zasieg z) {
      final s = m[d];
      if (s == null || z.index > s.index) m[d] = z;
    }

    for (final c in checkiny.values) {
      dodaj(c.data, c.zasieg);
    }
    for (final t in treningi.values) {
      if (t.ocena != null) dodaj(t.data, t.ocena!.zasieg);
    }
    return m;
  }

  /// Dni z bólem poniżej kolana albo mrowieniem.
  Set<DateTime> get dniObjawowNerwowych => {
        for (final c in checkiny.values)
          if (c.zasieg == Zasieg.ponizejKolana) c.data,
        for (final t in treningi.values)
          if (t.ocena?.jakoOcena.objawyNerwowe ?? false) t.data,
      };

  Set<String> flagi(DateTime dzis) => obliczFlagi(
        dzis: dzis,
        test: testKierunkowy?.wynik,
        zasiegi: zasiegi,
        slizgiOdFizjo: slizgiOdFizjo,
      );

  Map<String, Object?> toJson() => {
        'format': stanFormat,
        'start': iso(start),
        if (powitanieZrobione) 'powitanie': true,
        if (pierwszeUruchomienie != null) 'pierwszeUruchomienie': iso(pierwszeUruchomienie!),
        'etapy': [for (final e in etapy) {'nr': e.nr, 'od': iso(e.od)}],
        if (testKierunkowy != null) 'testKierunkowy': testKierunkowy!.toJson(),
        'treningi': {for (final MapEntry(:key, :value) in treningi.entries) key: value.toJson()},
        'checkiny': {for (final MapEntry(:key, :value) in checkiny.entries) key: value.toJson()},
        if (wolne.isNotEmpty) 'wolne': wolne.toList()..sort(),
        if (wstrzymane.isNotEmpty)
          'wstrzymane': {for (final MapEntry(:key, :value) in wstrzymane.entries) key: iso(value)},
        'widzianeTechniki': widzianeTechniki.toList()..sort(),
        if (slizgiOdFizjo) 'slizgiOdFizjo': true,
        if (fizjoOd != null) 'fizjoOd': iso(fizjoOd!),
        if (fizjoUmowione) 'fizjoUmowione': true,
        if (otwarteOkienko != null) 'otwarteOkienko': iso(otwarteOkienko!),
        if (paliDzis != null) 'paliDzis': iso(paliDzis!),
        'przypomnienia': przypomnienia.toJson(),
      };

  static Stan zJson(Map<String, Object?> j) {
    if (j['format'] != stanFormat) throw FormatException('nieznany format stanu: ${j['format']}');
    DateTime? data(String k) => j[k] == null ? null : _data(j[k]);
    Map<String, Object?> mapa(String k) => ((j[k] as Map?) ?? const {}).cast<String, Object?>();
    return Stan(
      start: _data(j['start']),
      etapy: [
        for (final e in (j['etapy'] as List? ?? const []).cast<Map>()) WpisEtapu(e['nr'] as int, _data(e['od'])),
      ],
      testKierunkowy: j['testKierunkowy'] == null
          ? null
          : WynikTestuKierunkowego.zJson((j['testKierunkowy']! as Map).cast<String, Object?>()),
      treningi: {
        for (final MapEntry(:key, :value) in mapa('treningi').entries)
          key: ZapisTreningu.zJson(key, (value! as Map).cast<String, Object?>()),
      },
      checkiny: {
        for (final MapEntry(:key, :value) in mapa('checkiny').entries)
          key: Checkin.zJson(key, (value! as Map).cast<String, Object?>()),
      },
      wolne: ((j['wolne'] as List?) ?? const []).cast<String>().toSet(),
      wstrzymane: {for (final MapEntry(:key, :value) in mapa('wstrzymane').entries) key: _data(value)},
      widzianeTechniki: ((j['widzianeTechniki'] as List?) ?? const []).cast<String>().toSet(),
      slizgiOdFizjo: j['slizgiOdFizjo'] == true,
      fizjoOd: data('fizjoOd'),
      fizjoUmowione: j['fizjoUmowione'] == true,
      powitanieZrobione: j['powitanie'] == true,
      pierwszeUruchomienie: data('pierwszeUruchomienie'),
      otwarteOkienko: data('otwarteOkienko'),
      paliDzis: data('paliDzis'),
      przypomnienia: UstawieniaPrzypomnien.zJson(mapa('przypomnienia')),
    );
  }
}
