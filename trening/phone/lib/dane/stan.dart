/// Stan użytkownika (`stan.json`, tylko na telefonie): data startu, historia etapów,
/// wynik testu kierunkowego, zapisy treningów. W M3 dojdą check-iny, oceny bólu,
/// pomiary i ustawienia przypomnień.
library;

import '../silnik/daty.dart';
import '../silnik/flagi.dart';
import '../silnik/kalendarz.dart';

const stanFormat = 'trening-stan/1';

/// Plan treningowy ruszył 23.11.2026. Do czasu ekranu profilu (M3) to domyślny start.
final domyslnyStart = DateTime.utc(2026, 11, 23);

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
      data: DateTime.parse('${j['data']}T00:00:00Z'),
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
      };

  static ZapisTreningu zJson(String data, Map<String, Object?> j) {
    List<String> lista(String k) => (j[k] as List?)?.cast<String>() ?? const [];
    DateTime? czas(String k) => j[k] == null ? null : DateTime.parse(j[k]! as String);
    return ZapisTreningu(
      data: DateTime.parse('${data}T00:00:00Z'),
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
  })  : start = dzien(start ?? domyslnyStart),
        etapy = etapy ?? [WpisEtapu(1, start ?? domyslnyStart)],
        treningi = treningi ?? {},
        widzianeTechniki = widzianeTechniki ?? {};

  final DateTime start;
  final List<WpisEtapu> etapy;
  WynikTestuKierunkowego? testKierunkowy;

  /// Klucz: data ISO (`2026-11-23`).
  final Map<String, ZapisTreningu> treningi;

  /// Ćwiczenia, których pełny opis techniki już się pokazał (pierwszy raz otwiera się sam).
  final Set<String> widzianeTechniki;
  bool slizgiOdFizjo;

  Set<String> flagi(DateTime dzis) => obliczFlagi(
        dzis: dzis,
        test: testKierunkowy?.wynik,
        slizgiOdFizjo: slizgiOdFizjo,
      );

  Map<String, Object?> toJson() => {
        'format': stanFormat,
        'start': iso(start),
        'etapy': [for (final e in etapy) {'nr': e.nr, 'od': iso(e.od)}],
        if (testKierunkowy != null) 'testKierunkowy': testKierunkowy!.toJson(),
        'treningi': {for (final MapEntry(:key, :value) in treningi.entries) key: value.toJson()},
        'widzianeTechniki': widzianeTechniki.toList()..sort(),
        if (slizgiOdFizjo) 'slizgiOdFizjo': true,
      };

  static Stan zJson(Map<String, Object?> j) {
    if (j['format'] != stanFormat) throw FormatException('nieznany format stanu: ${j['format']}');
    DateTime data(Object? s) => DateTime.parse('${s}T00:00:00Z');
    return Stan(
      start: data(j['start']),
      etapy: [
        for (final e in (j['etapy'] as List? ?? const []).cast<Map>()) WpisEtapu(e['nr'] as int, data(e['od'])),
      ],
      testKierunkowy: j['testKierunkowy'] == null
          ? null
          : WynikTestuKierunkowego.zJson((j['testKierunkowy']! as Map).cast<String, Object?>()),
      treningi: {
        for (final MapEntry(:key, :value) in ((j['treningi'] as Map?) ?? const {}).entries)
          key as String: ZapisTreningu.zJson(key, (value as Map).cast<String, Object?>()),
      },
      widzianeTechniki: ((j['widzianeTechniki'] as List?) ?? const []).cast<String>().toSet(),
      slizgiOdFizjo: j['slizgiOdFizjo'] == true,
    );
  }
}
