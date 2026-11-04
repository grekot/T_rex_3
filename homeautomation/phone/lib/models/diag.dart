// Diagnostyka urządzenia (kontrakt pkt 3c): `GET /api/diag` w domu, `homes/{h}/devices/{id}/diag` w chmurze.

import 'json_utils.dart';

/// Powód restartu po polsku (`resetReason`, `crashes[].reason`).
String resetReasonText(String? r) => switch (r) {
  'poweron' => 'włączenie zasilania',
  'external' => 'przycisk reset',
  'software' => 'restart programowy (np. po aktualizacji)',
  'panic' => 'awaria programu',
  'int_wdt' => 'watchdog przerwań',
  'task_wdt' => 'watchdog zadań (zawieszenie)',
  'wdt' => 'watchdog',
  'brownout' => 'spadek napięcia zasilania',
  'deepsleep' => 'wybudzenie z uśpienia',
  'earlier' => 'awaria sprzed tego startu',
  null || 'unknown' => 'nieznany',
  final x => x,
};

/// Czy restart był awaryjny (warto pokazać na czerwono).
bool resetIsFault(String? r) => const {'panic', 'int_wdt', 'task_wdt', 'wdt', 'brownout'}.contains(r);

/// Błąd z diagnostyki: [t] - czas pracy (s) przy ostatnim wystąpieniu, [n] - powtórzenia pod rząd.
typedef DiagError = ({int t, String msg, int n});

/// Podsumowanie awarii z zrzutem (`crashes`, ostatnie 3).
typedef DiagCrash = ({int? boot, String? reason, String? task, String? pc, String? elf});

class DeviceDiag {
  const DeviceDiag({
    this.fw,
    this.elf,
    this.resetReason,
    this.boots,
    this.wdtResets = 0,
    this.panics = 0,
    this.brownouts = 0,
    this.heapFree,
    this.heapMin,
    this.heapMaxBlock,
    this.psramFree,
    this.uptime,
    this.otaPartition,
    this.otaTrial = false,
    this.rollbacks = 0,
    this.rolledBackFrom,
    this.errors = const [],
    this.guardRestarts = 0,
    this.guardLast,
    this.crashes = const [],
    this.coreDump = false,
  });

  final String? fw;
  final String? elf;
  final String? resetReason;
  final int? boots;
  final int wdtResets;
  final int panics;
  final int brownouts;
  final int? heapFree;
  final int? heapMin;
  final int? heapMaxBlock;
  final int? psramFree;

  /// s od startu.
  final int? uptime;
  final String? otaPartition;
  final bool otaTrial;
  final int rollbacks;
  final String? rolledBackFrom;
  final List<DiagError> errors;

  /// Restarty przez strażnika łącza (hub, pkt 11) i ostatni: `"<epoch> <powód>"`.
  final int guardRestarts;
  final String? guardLast;
  final List<DiagCrash> crashes;

  /// Pełny zrzut awarii leży we flashu (`GET /api/coredump`).
  final bool coreDump;

  /// Ostatni restart strażnika: czas (z epoki, gdy znany) i powód.
  ({DateTime? at, String why})? get guard {
    final last = guardLast;
    if (last == null || last.isEmpty) return null;
    final sp = last.indexOf(' ');
    final epoch = int.tryParse(sp < 0 ? last : last.substring(0, sp));
    return (
      at: epoch == null || epoch < 1600000000 ? null : DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
      why: sp < 0 ? '' : last.substring(sp + 1),
    );
  }

  factory DeviceDiag.fromJson(Json j) {
    final ota = asObjectOrNull(j['ota'], 'ota') ?? const {};
    final guard = asObjectOrNull(j['guard'], 'guard') ?? const {};
    return DeviceDiag(
      fw: asStringOrNull(j['fw'], 'fw'),
      elf: asStringOrNull(j['elf'], 'elf'),
      resetReason: asStringOrNull(j['resetReason'], 'resetReason'),
      boots: asIntOrNull(j['boots'], 'boots'),
      wdtResets: asIntOrNull(j['wdtResets'], 'wdtResets') ?? 0,
      panics: asIntOrNull(j['panics'], 'panics') ?? 0,
      brownouts: asIntOrNull(j['brownouts'], 'brownouts') ?? 0,
      heapFree: asIntOrNull(j['heapFree'], 'heapFree'),
      heapMin: asIntOrNull(j['heapMin'], 'heapMin'),
      heapMaxBlock: asIntOrNull(j['heapMaxBlock'], 'heapMaxBlock'),
      psramFree: asIntOrNull(j['psramFree'], 'psramFree'),
      uptime: asIntOrNull(j['uptime'], 'uptime'),
      otaPartition: asStringOrNull(ota['partition'], 'ota.partition'),
      otaTrial: ota['trial'] == true,
      rollbacks: asIntOrNull(ota['rollbacks'], 'ota.rollbacks') ?? 0,
      rolledBackFrom: asStringOrNull(ota['rolledBackFrom'], 'ota.rolledBackFrom'),
      errors: [
        for (final e in (j['errors'] is List ? j['errors'] as List : const []))
          if (e is Map && e['msg'] is String)
            (
              t: e['t'] is num ? (e['t'] as num).toInt() : 0,
              msg: e['msg'] as String,
              n: e['n'] is num ? (e['n'] as num).toInt() : 1,
            ),
      ],
      guardRestarts: asIntOrNull(guard['n'], 'guard.n') ?? 0,
      guardLast: asStringOrNull(guard['last'], 'guard.last'),
      crashes: [
        for (final c in (j['crashes'] is List ? j['crashes'] as List : const []))
          if (c is Map)
            (
              boot: c['boot'] is num ? (c['boot'] as num).toInt() : null,
              reason: c['reason'] is String ? c['reason'] as String : null,
              task: c['task'] is String ? c['task'] as String : null,
              pc: c['pc'] is String ? c['pc'] as String : null,
              elf: c['elf'] is String ? c['elf'] as String : null,
            ),
      ],
      coreDump: j['coreDump'] == true,
    );
  }
}
