import 'cloud_store.dart';

/// Punkt wykresu.
typedef HistoryPoint = ({DateTime at, double value});

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Historia jednego pola z `history/{h}/{id}/{RRRR-MM-DD}/{HHMM}` (pkt 8.1) za ostatnie [hours] godzin.
Future<List<HistoryPoint>> loadHistory(
  CloudStore store, {
  required String homeId,
  required String deviceId,
  required String field,
  int hours = 24,
  DateTime? now,
}) async {
  final end = now ?? DateTime.now();
  final start = end.subtract(Duration(hours: hours));
  final days = <DateTime>[];
  for (var d = DateTime(start.year, start.month, start.day); !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    days.add(d);
  }
  final out = <HistoryPoint>[];
  for (final day in days) {
    final raw = toJsonObject(await store.read('history/$homeId/$deviceId/${_day(day)}'));
    if (raw == null) continue;
    for (final e in raw.entries) {
      if (e.key.length != 4) continue;
      final h = int.tryParse(e.key.substring(0, 2)), m = int.tryParse(e.key.substring(2));
      final v = e.value is Map ? (e.value as Map)[field] : null;
      if (h == null || m == null || v is! num) continue;
      final at = DateTime(day.year, day.month, day.day, h, m);
      if (at.isBefore(start) || at.isAfter(end)) continue;
      out.add((at: at, value: v.toDouble()));
    }
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}
