// Formatowanie po polsku: przecinek dziesiętny, jednostki ze spacją.

String fmtNumber(double v, {int decimals = 1}) => v.toStringAsFixed(decimals).replaceAll('.', ',');

String fmtTemp(double? v, {int decimals = 1}) => v == null ? '—' : '${fmtNumber(v, decimals: decimals)} °C';

String fmtPercent(double? v) => v == null ? '—' : '${v.round()} %';

String fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String fmtUptime(int seconds) {
  final d = Duration(seconds: seconds);
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}

String fmtAge(int seconds) {
  if (seconds < 90) return 'przed chwilą';
  if (seconds < 3600) return '${(seconds / 60).round()} min temu';
  return '${(seconds / 3600).round()} h temu';
}

/// Odliczanie: `4:05`, `1:02:03`.
String fmtCountdown(int seconds) {
  final d = Duration(seconds: seconds < 0 ? 0 : seconds);
  String two(int x) => x.toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : fmtDuration(d);
}

/// Czas w ustawieniach: `nie`, `45 s`, `3 min`, `1 min 30 s`, `2 h`.
String fmtSeconds(int s) {
  if (s <= 0) return 'nie';
  if (s < 60) return '$s s';
  if (s % 3600 == 0) return '${s ~/ 3600} h';
  if (s % 60 == 0) return '${s ~/ 60} min';
  return '${s ~/ 60} min ${s % 60} s';
}

/// Czas impulsu w ms: `0,5 s`, `2 s`.
String fmtMillis(int ms) => ms % 1000 == 0 ? '${ms ~/ 1000} s' : '${fmtNumber(ms / 1000)} s';

/// Krótko do kafelka: `45 s`, `5 min`, `2 h`.
String fmtLeftShort(int s) => s < 60
    ? '$s s'
    : s < 3600
    ? '${(s / 60).ceil()} min'
    : '${fmtNumber(s / 3600, decimals: s % 3600 == 0 ? 0 : 1)} h';
