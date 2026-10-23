// Pomiary wagi z dokumentu waga/{uid} (format: waga/SYNC.md) i obliczenia do wykresu.
// Czysty Dart - testy w test/weights_test.dart.

/// Dzień jako "RRRR-MM-DD" (czas lokalny)
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDay(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// Kolejne dni od [from] do [to] włącznie (bez problemów ze zmianą czasu)
Iterable<DateTime> daysBetween(DateTime from, DateTime to) sync* {
  var d = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  while (!d.isAfter(end)) {
    yield d;
    d = DateTime(d.year, d.month, d.day + 1);
  }
}

const minWeight = 300; // 30,0 kg (w dziesiątych)
const maxWeight = 2500;

/// 823 -> "82,3"
String formatKg(num tenths) {
  final n = tenths.round();
  return '${n ~/ 10},${n % 10}';
}

/// Różnica w dziesiątych: 3 -> "+0,3", -4 -> "−0,4", 0 -> "±0,0"
String formatDelta(num tenths) {
  final n = tenths.round();
  if (n == 0) return '±0,0';
  return '${n > 0 ? '+' : '−'}${formatKg(n.abs())}';
}

/// "82,3" / "82.3" / "82" -> 823; null gdy to nie waga
int? parseKg(String text) {
  final t = text.trim().replaceAll(',', '.').replaceAll(RegExp(r'\s*kg$'), '');
  final v = double.tryParse(t);
  if (v == null) return null;
  final w = (v * 10).round();
  return w >= minWeight && w <= maxWeight ? w : null;
}

class Entry {
  const Entry(this.day, this.w, this.t);

  final String day;

  /// dziesiąte części kg
  final int w;

  /// ms ostatniej zmiany
  final int t;

  DateTime get date => parseDay(day)!;
  double get kg => w / 10;
}

class WeightDoc {
  const WeightDoc({required this.entries, this.goal});

  /// Pomiary rosnąco po dniu, bez usuniętych (w = 0)
  final List<Entry> entries;

  /// Cel w dziesiątych kg
  final int? goal;

  static const empty = WeightDoc(entries: []);

  factory WeightDoc.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    final out = <Entry>[];
    final e = data['e'];
    if (e is Map) {
      e.forEach((key, value) {
        if (key is! String || parseDay(key) == null || value is! Map) return;
        final w = value['w'];
        final t = value['t'];
        if (w is! num || w < minWeight || w > maxWeight) return; // także nagrobki w = 0
        out.add(Entry(key, w.round(), t is num ? t.toInt() : 0));
      });
    }
    out.sort((a, b) => a.day.compareTo(b.day));
    final goal = data['goal'];
    return WeightDoc(
      entries: out,
      goal: goal is num && goal >= minWeight && goal <= maxWeight ? goal.round() : null,
    );
  }

  bool get isEmpty => entries.isEmpty;
  Entry? get last => entries.isEmpty ? null : entries.last;

  Entry? entryFor(String day) {
    for (final e in entries) {
      if (e.day == day) return e;
    }
    return null;
  }

  /// Ostatni pomiar przed danym dniem
  Entry? lastBefore(String day) {
    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].day.compareTo(day) < 0) return entries[i];
    }
    return null;
  }
}

/// Wygładzona waga dzień po dniu (średnia wykładnicza jak w „The Hacker's Diet”:
/// trend += 10% różnicy do dzisiejszego pomiaru; dni bez pomiaru - trend stoi).
/// Wynik: dzień -> trend w dziesiątych (double), od pierwszego pomiaru do [until].
Map<String, double> trend(List<Entry> entries, DateTime until, {double alpha = 0.1}) {
  final out = <String, double>{};
  if (entries.isEmpty) return out;
  final byDay = {for (final e in entries) e.day: e.w};
  double? t;
  for (final d in daysBetween(entries.first.date, until)) {
    final k = dayKey(d);
    final w = byDay[k];
    if (w != null) t = t == null ? w.toDouble() : t + alpha * (w - t);
    out[k] = t!;
  }
  return out;
}

/// Tempo zmiany trendu w dziesiątych kg na tydzień z ostatnich [days] dni
/// (regresja liniowa trendu); null gdy za mało danych.
double? weeklyRate(Map<String, double> trendByDay, DateTime today, {int days = 28}) {
  final xs = <double>[];
  final ys = <double>[];
  for (final d in daysBetween(today.subtract(Duration(days: days - 1)), today)) {
    final v = trendByDay[dayKey(d)];
    if (v == null) continue;
    xs.add(d.difference(today).inHours / 24);
    ys.add(v);
  }
  if (xs.length < 7) return null;
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  if (den == 0) return null;
  return num / den * 7;
}

/// Kiedy trend dojdzie do celu przy obecnym tempie; null gdy idzie w złą stronę albo > 2 lata
DateTime? forecastGoal({required double current, required int goal, required double? ratePerWeek, required DateTime today}) {
  if (ratePerWeek == null) return null;
  final diff = goal - current;
  if (diff.abs() < 1) return today;
  if (ratePerWeek == 0 || diff.sign != ratePerWeek.sign) return null;
  final weeks = diff / ratePerWeek;
  if (weeks > 104) return null;
  final d = today.add(Duration(days: (weeks * 7).round()));
  return DateTime(d.year, d.month, d.day);
}

/// Średnia pomiarów z dni [from]..[to] (dziesiąte); null gdy brak
double? averageBetween(List<Entry> entries, DateTime from, DateTime to) {
  final a = dayKey(from), b = dayKey(to);
  final v = [for (final e in entries) if (e.day.compareTo(a) >= 0 && e.day.compareTo(b) <= 0) e.w];
  if (v.isEmpty) return null;
  return v.reduce((x, y) => x + y) / v.length;
}

/// Pomiary z ostatnich [days] dni (wszystkie gdy null)
List<Entry> lastDays(List<Entry> entries, DateTime today, int? days) {
  if (days == null) return entries;
  final from = dayKey(today.subtract(Duration(days: days - 1)));
  return [for (final e in entries) if (e.day.compareTo(from) >= 0) e];
}

const _weekdays = ['pn', 'wt', 'śr', 'cz', 'pt', 'sb', 'nd'];
const _months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];

/// "pt 23.10"
String shortDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// "23 paź 2026"
String longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
