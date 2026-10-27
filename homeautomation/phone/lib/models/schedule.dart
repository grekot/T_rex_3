// Okresy czasu w formacie z kontraktu: `HH:MM-HH:MM`, kilka po przecinku, `-` = brak.

/// Maksymalna liczba okresów komfortu w jednym planie.
const maxComfortPeriods = 4;

/// Pora dnia w minutach od północy; 1440 = `24:00` (dozwolone tylko jako koniec okresu).
class DayTime implements Comparable<DayTime> {
  const DayTime(this.minutes) : assert(minutes >= 0 && minutes <= 1440);

  DayTime.hm(int hour, int minute) : this(hour * 60 + minute);

  final int minutes;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  static final _re = RegExp(r'^(\d{2}):(\d{2})$');

  /// Zwraca null dla złego formatu albo godziny spoza 00:00-24:00.
  static DayTime? tryParse(String s) {
    final m = _re.firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (min > 59 || h > 24 || (h == 24 && min != 0)) return null;
    return DayTime.hm(h, min);
  }

  String format() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(DayTime other) => minutes.compareTo(other.minutes);

  bool operator <(DayTime o) => minutes < o.minutes;
  bool operator <=(DayTime o) => minutes <= o.minutes;

  @override
  bool operator ==(Object other) => other is DayTime && other.minutes == minutes;

  @override
  int get hashCode => minutes;

  @override
  String toString() => format();
}

/// Jeden okres `HH:MM-HH:MM`.
class TimePeriod {
  const TimePeriod(this.start, this.end);

  final DayTime start;
  final DayTime end;

  /// Długość w minutach; okres nocny może przechodzić przez północ.
  int get lengthMinutes {
    final d = end.minutes - start.minutes;
    return d >= 0 ? d : d + 1440;
  }

  static TimePeriod? tryParse(String s) {
    final parts = s.split('-');
    if (parts.length != 2) return null;
    final a = DayTime.tryParse(parts[0]);
    final b = DayTime.tryParse(parts[1]);
    if (a == null || b == null) return null;
    return TimePeriod(a, b);
  }

  String format() => '${start.format()}-${end.format()}';

  @override
  bool operator ==(Object other) => other is TimePeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => format();
}

/// Plan dnia: lista okresów komfortu (poza nimi obowiązuje temperatura eko).
class DayPlan {
  const DayPlan(this.periods);

  static const empty = DayPlan([]);

  final List<TimePeriod> periods;

  /// Parsuje bez walidacji kolejności; null przy złym formacie któregoś okresu.
  static DayPlan? tryParse(String s) {
    final t = s.trim();
    if (t == '-' || t.isEmpty) return empty;
    final periods = <TimePeriod>[];
    for (final part in t.split(',')) {
      final p = TimePeriod.tryParse(part.trim());
      if (p == null) return null;
      periods.add(p);
    }
    return DayPlan(periods);
  }

  /// `-` dla planu bez okresów komfortu (cały dzień eko).
  String format() => periods.isEmpty ? '-' : periods.map((p) => p.format()).join(',');

  /// Opis błędu po polsku albo null, gdy plan spełnia kontrakt:
  /// do 4 okresów, rosnąco, bez nakładania, początek < koniec, `24:00` tylko na końcu.
  String? validate() {
    if (periods.length > maxComfortPeriods) {
      return 'Najwyżej $maxComfortPeriods okresy komfortu';
    }
    DayTime? prevEnd;
    for (final p in periods) {
      if (p.start.minutes >= 1440) return 'Okres nie może zaczynać się o 24:00';
      if (p.end <= p.start) return 'Koniec okresu ${p.format()} musi być po początku';
      if (prevEnd != null && p.start < prevEnd) {
        return 'Okresy muszą iść po kolei i nie mogą na siebie nachodzić';
      }
      prevEnd = p.end;
    }
    return null;
  }

  @override
  String toString() => format();
}

/// Pora nocna ekranu: jeden okres (może przechodzić przez północ) albo `-`.
class NightPeriod {
  /// Zwraca null dla `-`, rzuca FormatException przy złym formacie.
  static TimePeriod? parse(String s) {
    final t = s.trim();
    if (t == '-' || t.isEmpty) return null;
    final p = TimePeriod.tryParse(t);
    if (p == null || p.start.minutes >= 1440 || p.start == p.end) {
      throw FormatException('Zła pora nocna: $s');
    }
    return p;
  }

  static String format(TimePeriod? p) => p == null ? '-' : p.format();
}
