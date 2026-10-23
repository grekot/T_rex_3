// Aktywność z Health Connect (zapisuje ją tam aplikacja Zepp): kalorie, kroki, treningi.
// Czyste funkcje - testy w test/activity_test.dart; odczyt z telefonu w health_source.dart.

import 'weights.dart';

/// Pojedynczy zapis z Health Connect (np. kalorie z 15 minut)
class Sample {
  const Sample(this.start, this.value, this.source);

  final DateTime start;
  final double value;

  /// Aplikacja, która zapisała (Zepp, Google Fit...)
  final String source;
}

/// Suma na dzień. Gdy kilka aplikacji zapisuje to samo (np. Zepp i Google Fit),
/// bierzemy największą sumę jednej aplikacji zamiast dodawać - inaczej byłoby podwójnie.
Map<String, double> perDay(List<Sample> samples) {
  final bySource = <String, Map<String, double>>{};
  for (final s in samples) {
    final day = dayKey(s.start);
    final m = bySource.putIfAbsent(day, () => {});
    m[s.source] = (m[s.source] ?? 0) + s.value;
  }
  return bySource.map((day, m) => MapEntry(day, m.values.reduce((a, b) => a > b ? a : b)));
}

class DayActivity {
  const DayActivity({this.totalKcal, this.activeKcal, this.steps});

  final double? totalKcal;
  final double? activeKcal;
  final double? steps;
}

class Workout {
  const Workout({
    required this.start,
    required this.end,
    required this.type,
    this.kcal,
    this.distanceM,
    this.steps,
    this.source = '',
  });

  final DateTime start;
  final DateTime end;

  /// Nazwa typu z Health Connect, np. RUNNING
  final String type;
  final double? kcal;
  final double? distanceM;
  final double? steps;
  final String source;

  Duration get duration => end.difference(start);
  String get label => workoutLabel(type);
}

class ActivityData {
  const ActivityData({required this.days, required this.workouts});

  /// dzień "RRRR-MM-DD" -> aktywność
  final Map<String, DayActivity> days;

  /// od najnowszego
  final List<Workout> workouts;

  static const empty = ActivityData(days: {}, workouts: []);

  factory ActivityData.build({
    required List<Sample> total,
    required List<Sample> active,
    required List<Sample> steps,
    required List<Workout> workouts,
  }) {
    final t = perDay(total), a = perDay(active), s = perDay(steps);
    final keys = {...t.keys, ...a.keys, ...s.keys};
    return ActivityData(
      days: {for (final k in keys) k: DayActivity(totalKcal: t[k], activeKcal: a[k], steps: s[k])},
      workouts: [...workouts]..sort((x, y) => y.start.compareTo(x.start)),
    );
  }

  /// Średnio na dzień z dni, w których są dane (null gdy brak)
  double? averageOf(double? Function(DayActivity) pick, DateTime from, DateTime to) {
    final v = <double>[];
    for (final d in daysBetween(from, to)) {
      final x = days[dayKey(d)];
      final y = x == null ? null : pick(x);
      if (y != null && y > 0) v.add(y);
    }
    if (v.isEmpty) return null;
    return v.reduce((a, b) => a + b) / v.length;
  }
}

const _labels = {
  'RUNNING': 'Bieg',
  'RUNNING_TREADMILL': 'Bieżnia',
  'WALKING': 'Spacer',
  'WALKING_TREADMILL': 'Marsz na bieżni',
  'HIKING': 'Wędrówka',
  'BIKING': 'Rower',
  'BIKING_STATIONARY': 'Rowerek',
  'SWIMMING': 'Pływanie',
  'SWIMMING_POOL': 'Basen',
  'SWIMMING_OPEN_WATER': 'Pływanie (wody otwarte)',
  'STRENGTH_TRAINING': 'Siłownia',
  'TRADITIONAL_STRENGTH_TRAINING': 'Siłownia',
  'FUNCTIONAL_STRENGTH_TRAINING': 'Trening funkcjonalny',
  'WEIGHTLIFTING': 'Ciężary',
  'CALISTHENICS': 'Kalistenika',
  'HIGH_INTENSITY_INTERVAL_TRAINING': 'HIIT',
  'YOGA': 'Joga',
  'PILATES': 'Pilates',
  'ELLIPTICAL': 'Orbitrek',
  'ROWING': 'Wioślarstwo',
  'ROWING_MACHINE': 'Ergometr wioślarski',
  'STAIR_CLIMBING': 'Schody',
  'STAIR_CLIMBING_MACHINE': 'Stepper',
  'CROSS_COUNTRY_SKIING': 'Narty biegowe',
  'DOWNHILL_SKIING': 'Narty',
  'SKIING': 'Narty',
  'SNOWBOARDING': 'Snowboard',
  'SKATING': 'Łyżwy',
  'ICE_SKATING': 'Łyżwy',
  'ROCK_CLIMBING': 'Wspinaczka',
  'CLIMBING': 'Wspinaczka',
  'DANCING': 'Taniec',
  'TENNIS': 'Tenis',
  'TABLE_TENNIS': 'Tenis stołowy',
  'BADMINTON': 'Badminton',
  'SQUASH': 'Squash',
  'SOCCER': 'Piłka nożna',
  'BASKETBALL': 'Koszykówka',
  'VOLLEYBALL': 'Siatkówka',
  'GOLF': 'Golf',
  'BOXING': 'Boks',
  'MARTIAL_ARTS': 'Sztuki walki',
  'JUMP_ROPE': 'Skakanka',
  'OTHER': 'Trening',
};

String workoutLabel(String type) => _labels[type] ?? type.replaceAll('_', ' ').toLowerCase();

/// "1:05 h" / "45 min"
String formatDuration(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')} h';
}

/// 1234.5 -> "1 235"
String formatThousands(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// 5230 m -> "5,2 km", 640 -> "640 m"
String formatDistance(double m) {
  if (m < 1000) return '${m.round()} m';
  final km = (m / 100).round();
  return '${km ~/ 10},${km % 10} km';
}
