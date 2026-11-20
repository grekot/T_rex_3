// Ostrzeżenia IMGW, alerty pogodowe i dzień liturgiczny w hubie (kontrakt pkt 11, hub 0.3.44+): State huba `warnings`,
// `alerts`, `today` i ustawienia w Config (`warnings`, `alerts`, `today`). Wszystko liczy hub, aplikacja pokazuje
// i zmienia ustawienia.

import 'json_utils.dart';

double? _num(Object? v) => v is num ? v.toDouble() : null;
int? _int(Object? v) => v is num ? v.toInt() : null;
DateTime? _unix(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Ostrzeżenie meteorologiczne IMGW dla powiatu domu.
class HubWarning {
  const HubWarning({
    required this.id,
    required this.event,
    this.level = 1,
    this.prob,
    this.from,
    this.to,
    this.active = false,
    this.text,
    this.office,
  });

  final String id;
  final String event;

  /// 1-3 = żółty / pomarańczowy / czerwony.
  final int level;

  /// Prawdopodobieństwo (%).
  final int? prob;
  final DateTime? from;
  final DateTime? to;

  /// Trwa teraz (inaczej zapowiedź).
  final bool active;
  final String? text;

  /// Biuro IMGW (tylko `GET /api/warnings`).
  final String? office;

  static HubWarning? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return HubWarning(
      id: j['id'] as String,
      event: _str(j['event']) ?? 'Ostrzeżenie',
      level: (_int(j['level']) ?? 1).clamp(1, 3),
      prob: _int(j['prob']),
      from: _unix(j['from']),
      to: _unix(j['to']),
      active: j['active'] == true,
      text: _str(j['text']),
      office: _str(j['office']),
    );
  }
}

/// Lista ostrzeżeń ze State (`[]` = brak, null = wyłączone / bez powiatu / stare dane).
List<HubWarning>? hubWarnings(Object? v) => v is List ? [for (final x in v) ?HubWarning.fromJson(x)] : null;

/// Alert pogodowy liczony w hubie: przymrozek albo deszcz.
class HubAlert {
  const HubAlert({required this.id, required this.kind, required this.text, this.at, this.until, this.mm, this.t});

  final String id;

  /// `frost` / `rain`.
  final String kind;
  final String text;

  /// Początek opadu / godzina minimum temperatury.
  final DateTime? at;
  final DateTime? until;
  final double? mm;
  final double? t;

  static HubAlert? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['kind'] is! String) return null;
    return HubAlert(
      id: j['id'] as String,
      kind: j['kind'] as String,
      text: _str(j['text']) ?? '',
      at: _unix(j['at']),
      until: _unix(j['until']),
      mm: _num(j['mm']),
      t: _num(j['t']),
    );
  }
}

List<HubAlert>? hubAlerts(Object? v) => v is List ? [for (final x in v) ?HubAlert.fromJson(x)] : null;

/// Dzień liturgiczny (`today`): święty, nazwa dnia, sigla czytań.
class HubToday {
  const HubToday({this.date, this.saint, this.day, this.readings = const []});

  final String? date;
  final String? saint;
  final String? day;
  final List<String> readings;

  static HubToday? fromJson(Object? j) {
    if (j is! Map) return null;
    return HubToday(
      date: _str(j['date']),
      saint: _str(j['saint']),
      day: _str(j['day']),
      readings: [
        for (final r in (j['readings'] is List ? j['readings'] as List : const []))
          if (r is String && r.isNotEmpty) r,
      ],
    );
  }
}

/// Hub z ostrzeżeniami / alertami / dniem liturgicznym (0.3.44+): któreś z pól w Config.
bool hubHasWarnings(Json? cfg) => cfg != null && const ['warnings', 'alerts', 'today'].any(cfg.containsKey);

/// Ustawienia alertów z Config z domyślnymi wartościami kontraktu.
typedef AlertSettings = ({bool frost, double frostBelow, bool rain, double rainMm, int rainDryH});

AlertSettings alertSettings(Object? v) {
  final m = v is Map ? v : const {};
  return (
    frost: m['frost'] != false,
    frostBelow: _num(m['frostBelow']) ?? 0,
    rain: m['rain'] != false,
    rainMm: _num(m['rainMm']) ?? 0.1,
    rainDryH: _int(m['rainDryH']) ?? 2,
  );
}

/// Zakresy z kontraktu (pkt 11).
const frostBelowMin = -10.0, frostBelowMax = 5.0;
const rainMmMin = 0.05, rainMmMax = 5.0;
const rainDryHMax = 12;

/// Kod TERYT powiatu: 4 cyfry albo pusty (powiat z położenia domu).
bool validTeryt(String s) => s.isEmpty || RegExp(r'^\d{4}$').hasMatch(s);
