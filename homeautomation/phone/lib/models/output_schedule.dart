// Harmonogram wyjścia („codziennie 6:30 włącz”): zwykła automatyka huba (pkt 11, ARCHITEKTURA 4.5) z jednym
// wyzwalaczem czasu (`time` + `days`), bez warunków i z jedną akcją `set` jednego wyjścia (`on` / `onN`).
// Takie automatyki - także zrobione w edytorze automatyk - ekran urządzenia pokazuje jako harmonogram.

import 'hub.dart';

/// Wpis harmonogramu: [minute] od północy, [days] 1 = poniedziałek … 7 = niedziela.
class OutputSchedule {
  const OutputSchedule({
    required this.id,
    required this.device,
    required this.point,
    required this.on,
    required this.minute,
    this.days = const [1, 2, 3, 4, 5, 6, 7],
    this.enabled = true,
    this.name = '',
  });

  final String id;
  final String device;

  /// `on` (całe urządzenie) albo `onN` (kanał).
  final String point;
  final bool on;
  final int minute;
  final List<int> days;
  final bool enabled;
  final String name;

  /// `06:30`.
  String get time => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  /// Wpis z automatyki albo null, gdy to nie prosty harmonogram jednego wyjścia.
  static OutputSchedule? from(Automation a) {
    if (a.when.length != 1 || a.conditions.isNotEmpty || a.then.length != 1) return null;
    final w = a.when.single, t = a.then.single;
    final time = w['time'];
    if (time is! String || w.keys.any((k) => k != 'time' && k != 'days')) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
    if (m == null) return null;
    final minute = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    if (minute >= 1440) return null;
    final device = t['device'], set = t['set'];
    if (device is! String || set is! Map || set.length != 1 || t.length != 2) return null;
    final point = set.keys.single, on = set.values.single;
    if (point is! String || !RegExp(r'^on\d*$').hasMatch(point) || on is! bool) return null;
    final days = [
      for (final d in (w['days'] is List ? w['days'] as List : const [1, 2, 3, 4, 5, 6, 7]))
        if (d is int && d >= 1 && d <= 7) d,
    ]..sort();
    if (days.isEmpty) return null;
    return OutputSchedule(
      id: a.id,
      device: device,
      point: point,
      on: on,
      minute: minute,
      days: days,
      enabled: a.enabled,
      name: a.name,
    );
  }

  /// Automatyka huba z tym wpisem; [name] - opis widoczny też w edytorze automatyk.
  Automation toAutomation({String? name}) => Automation(
    id: id,
    name: name ?? this.name,
    enabled: enabled,
    when: [
      {'time': time, if (days.length < 7) 'days': days},
    ],
    then: [
      {
        'device': device,
        'set': <String, Object?>{point: on},
      },
    ],
  );

  OutputSchedule copyWith({String? point, bool? on, int? minute, List<int>? days, bool? enabled}) => OutputSchedule(
    id: id,
    device: device,
    point: point ?? this.point,
    on: on ?? this.on,
    minute: minute ?? this.minute,
    days: days ?? this.days,
    enabled: enabled ?? this.enabled,
    name: name,
  );
}

const _dayShort = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'Sb', 'Nd'];

/// Skrót dnia (1 = Pn).
String dayShort(int d) => _dayShort[(d - 1) % 7];

/// Dni po polsku: „codziennie”, „Pn–Pt”, „weekend”, „Pn, Śr, Pt”.
String daysLabel(List<int> days) {
  final s = {...days};
  if (s.length == 7) return 'codziennie';
  if (s.length == 5 && s.containsAll(const [1, 2, 3, 4, 5])) return 'Pn–Pt';
  if (s.length == 2 && s.containsAll(const [6, 7])) return 'weekend';
  return ([...s]..sort()).map(dayShort).join(', ');
}

/// Wpisy harmonogramu urządzenia [device] z listy automatyk, po godzinie.
List<OutputSchedule> schedulesFor(String device, Iterable<Automation> all) =>
    [for (final a in all) ?OutputSchedule.from(a)].where((s) => s.device == device).toList()
      ..sort((a, b) => a.minute.compareTo(b.minute));
