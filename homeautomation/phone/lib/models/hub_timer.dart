// Odliczanie w hubie („wyłącz za 30 min”, kontrakt pkt 11): jednorazowy Set urządzenia o czasie `at`.
// Hub trzyma timery we flash i pokazuje je w swoim State (`timers`); brak pola = hub bez timerów.

import 'json_utils.dart';

class HubTimer {
  const HubTimer({required this.id, required this.device, required this.set, required this.at, this.by});

  final String id;
  final String device;
  final Json set;

  /// Chwila wykonania (z `at`, unix s); null - hub nie zna jeszcze czasu (odlicza `in` od dodania).
  final DateTime? at;

  /// Autor (uid albo nazwa klienta tokenu) - tylko z `GET /api/timers`.
  final String? by;

  static HubTimer? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], device = j['device'], set = j['set'], at = j['at'];
    if (id is! String || device is! String || set is! Map || (at != null && at is! num)) return null;
    return HubTimer(
      id: id,
      device: device,
      set: set.cast<String, dynamic>(),
      at: at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000) : null,
      by: j['by'] is String ? j['by'] as String : null,
    );
  }

  /// Sekundy do wykonania (0, gdy już minęło); null bez znanego czasu huba.
  int? leftAt(DateTime now) {
    final at = this.at;
    if (at == null) return null;
    final s = (at.difference(now).inMilliseconds / 1000).ceil();
    return s < 0 ? 0 : s;
  }

  /// Punkt wyjścia (`on` / `onN`) i wartość, gdy timer tylko włącza albo wyłącza jedno wyjście.
  ({String point, bool on})? get output {
    if (set.length != 1) return null;
    final e = set.entries.single;
    if (!RegExp(r'^on\d*$').hasMatch(e.key) || e.value is! bool) return null;
    return (point: e.key, on: e.value as bool);
  }
}

/// Timery z State huba albo null, gdy hub ich nie obsługuje (brak pola `timers`).
List<HubTimer>? hubTimers(Json? hubState) {
  final v = hubState?['timers'];
  if (v is! List) return null;
  // Bez znanego czasu na końcu.
  final far = DateTime(9999);
  return [for (final e in v) ?HubTimer.fromJson(e)]..sort((a, b) => (a.at ?? far).compareTo(b.at ?? far));
}

/// Kody błędów timera (`400 device|set|in|at`, `403 forbidden`, `507 limit`; przez chmurę w polu `timerAdd`).
String describeTimerError(String code) => switch (code) {
  'device' => 'Hub nie zna tego urządzenia.',
  'set' => 'Tego hub nie odliczy - tylko sterowanie (włącz, wyłącz, jasność).',
  'in' || 'at' => 'Czas od 10 s do 7 dni.',
  'forbidden' => 'Brak uprawnień do sterowania tym urządzeniem.',
  'limit' => 'Hub ma już 20 odliczań - anuluj któreś.',
  'not_found' => 'Tego odliczania już nie ma.',
  final c => 'Hub zgłosił błąd ($c).',
};
