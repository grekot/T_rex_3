// Kalendarz domu (kontrakt pkt 11 „Kalendarz domu”): `homes/{h}/calendar/{id}` - wywóz śmieci (lista dat),
// urodziny (data z rokiem, co rok) i inne daty (`repeat`). Hub wylicza z tego przypomnienia i parę `calendar`.

import 'json_utils.dart';

enum CalendarKind {
  waste('waste', 'Wywóz śmieci'),
  birthday('birthday', 'Urodziny'),
  date('date', 'Data');

  const CalendarKind(this.wire, this.label);

  final String wire;
  final String label;

  static CalendarKind fromWire(Object? v) => values.where((k) => k.wire == v).firstOrNull ?? CalendarKind.date;
}

/// Powtarzanie daty (`repeat`).
const calendarRepeats = {
  'none': 'jednorazowo',
  'yearly': 'co rok',
  'monthly': 'co miesiąc',
  'weekly': 'co tydzień',
  'biweekly': 'co dwa tygodnie',
};

/// Ikony wywozu (`icon`, opcjonalne - zegar i aplikacja).
const wasteIcons = {
  'mixed': 'Zmieszane',
  'plastic': 'Plastik i metal',
  'paper': 'Papier',
  'glass': 'Szkło',
  'bio': 'Bio',
  'bulky': 'Gabaryty',
};

const calendarMaxDates = 60;
const calendarMaxTitle = 40;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// `YYYY-MM-DD`.
String calendarDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseCalendarDate(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (m == null) return null;
  final d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  return d.month == int.parse(m.group(2)!) && d.day == int.parse(m.group(3)!) ? d : null;
}

class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.title,
    required this.kind,
    this.date,
    this.repeat = 'none',
    this.dates = const [],
    this.notify = true,
    this.icon,
  });

  final String id;
  final String title;
  final CalendarKind kind;

  /// Data pojedyncza (urodziny - z rokiem urodzenia) z [repeat]; wywóz - [dates].
  final DateTime? date;
  final String repeat;
  final List<DateTime> dates;
  final bool notify;
  final String? icon;

  factory CalendarEntry.fromJson(String id, Json j) => CalendarEntry(
    id: id,
    title: j['title'] is String ? j['title'] as String : '',
    kind: CalendarKind.fromWire(j['kind']),
    date: parseCalendarDate(j['date']),
    repeat: calendarRepeats.containsKey(j['repeat']) ? j['repeat'] as String : 'none',
    dates: [for (final d in (j['dates'] is List ? j['dates'] as List : const [])) ?parseCalendarDate(d)]..sort(),
    notify: j['notify'] == true,
    icon: j['icon'] is String ? j['icon'] as String : null,
  );

  Json toJson() => {
    'title': title,
    'kind': kind.wire,
    if (dates.isNotEmpty) 'dates': [for (final d in dates) calendarDate(d)],
    if (dates.isEmpty && date != null) 'date': calendarDate(date!),
    if (dates.isEmpty && date != null) 'repeat': kind == CalendarKind.birthday ? 'yearly' : repeat,
    'notify': notify,
    'icon': ?icon,
  };

  CalendarEntry copyWith({
    String? title,
    CalendarKind? kind,
    DateTime? date,
    String? repeat,
    List<DateTime>? dates,
    bool? notify,
    String? icon,
    bool clearIcon = false,
  }) => CalendarEntry(
    id: id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    date: date ?? this.date,
    repeat: repeat ?? this.repeat,
    dates: dates ?? this.dates,
    notify: notify ?? this.notify,
    icon: clearIcon ? null : (icon ?? this.icon),
  );

  /// Terminy od [from] (włącznie) przez [days] dni.
  List<DateTime> occurrences(DateTime from, int days) {
    final start = _day(from), end = start.add(Duration(days: days));
    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);
    if (dates.isNotEmpty) return dates.where(inRange).toList();
    final d0 = date;
    if (d0 == null) return const [];
    final rep = kind == CalendarKind.birthday ? 'yearly' : repeat;
    final out = <DateTime>[];
    switch (rep) {
      case 'yearly':
        for (var y = start.year; y <= end.year; y++) {
          // 29 lutego w roku nieprzestępnym - 28 lutego.
          var d = DateTime(y, d0.month, d0.day);
          if (d.month != d0.month) d = DateTime(y, d0.month + 1, 0);
          if (inRange(d) && !d.isBefore(d0)) out.add(d);
        }
      case 'monthly':
        for (var m = DateTime(start.year, start.month); m.isBefore(end); m = DateTime(m.year, m.month + 1)) {
          var d = DateTime(m.year, m.month, d0.day);
          if (d.month != m.month) d = DateTime(m.year, m.month + 1, 0);
          if (inRange(d) && !d.isBefore(d0)) out.add(d);
        }
      case 'weekly' || 'biweekly':
        final step = rep == 'weekly' ? 7 : 14;
        var d = d0;
        if (d.isBefore(start)) {
          final n = (start.difference(d).inDays / step).ceil();
          d = DateTime(d.year, d.month, d.day + n * step);
        }
        for (; d.isBefore(end); d = DateTime(d.year, d.month, d.day + step)) {
          if (inRange(d)) out.add(d);
        }
      default:
        if (inRange(d0)) out.add(d0);
    }
    return out;
  }

  /// Najbliższy termin od [from] (do 2 lat naprzód) albo null.
  DateTime? next(DateTime from) => occurrences(from, 800).firstOrNull;

  /// Wiek w dniu [on] (urodziny z rokiem).
  int? ageOn(DateTime on) {
    final d = date;
    if (kind != CalendarKind.birthday || d == null) return null;
    final a = on.year - d.year - ((on.month < d.month || (on.month == d.month && on.day < d.day)) ? 1 : 0);
    return a >= 0 ? a : null;
  }

  /// Problemy przed zapisem (jak w regułach): tytuł, data albo daty, limit dat.
  List<String> problems() => [
    if (title.trim().isEmpty) 'Wpisz nazwę.',
    if (title.length > calendarMaxTitle) 'Nazwa najwyżej $calendarMaxTitle znaków.',
    if (dates.isEmpty && date == null) kind == CalendarKind.waste ? 'Dodaj daty wywozu.' : 'Wybierz datę.',
    if (dates.length > calendarMaxDates) 'Najwyżej $calendarMaxDates dat.',
  ];
}

/// Daty z wklejonego tekstu (harmonogram gminy): `12.11`, `12.11.2026`, `2026-11-12`, `12 listopada`, oddzielone
/// przecinkami, średnikami albo nowymi wierszami. Bez roku - najbliższa przyszła data od [today].
({List<DateTime> dates, List<String> bad}) parseDateList(String text, DateTime today) {
  const months = {
    'sty': 1, 'lut': 2, 'mar': 3, 'kwi': 4, 'maj': 5, 'cze': 6, //
    'lip': 7, 'sie': 8, 'wrz': 9, 'paź': 10, 'paz': 10, 'lis': 11, 'gru': 12,
  };
  final t0 = _day(today);
  final out = <DateTime>{}, bad = <String>[];
  DateTime? make(int y, int m, int d) {
    final x = DateTime(y, m, d);
    return x.month == m && x.day == d ? x : null;
  }

  DateTime? noYear(int m, int d) {
    final x = make(t0.year, m, d);
    if (x == null) return make(t0.year + 1, m, d);
    return x.isBefore(t0) ? make(t0.year + 1, m, d) : x;
  }

  for (final raw in text.split(RegExp(r'[,;\n]+'))) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) continue;
    DateTime? d;
    if (RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s) case final m?) {
      d = make(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    } else if (RegExp(r'^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?\.?$').firstMatch(s) case final m?) {
      final day = int.parse(m.group(1)!), month = int.parse(m.group(2)!);
      final y = m.group(3);
      d = y == null ? noYear(month, day) : make(y.length == 2 ? 2000 + int.parse(y) : int.parse(y), month, day);
    } else if (RegExp(r'^(\d{1,2})\s+(\p{L}+)(?:\s+(\d{4}))?$', unicode: true).firstMatch(s) case final m?) {
      final word = m.group(2)!;
      final month = months[word.length >= 3 ? word.substring(0, 3) : word];
      if (month != null) {
        final day = int.parse(m.group(1)!);
        d = m.group(3) == null ? noYear(month, day) : make(int.parse(m.group(3)!), month, day);
      }
    }
    if (d == null) {
      bad.add(raw.trim());
    } else {
      out.add(d);
    }
  }
  return (dates: out.toList()..sort(), bad: bad);
}
