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
