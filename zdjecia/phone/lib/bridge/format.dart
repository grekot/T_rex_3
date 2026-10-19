// Teksty na ekranie: rozmiary, czasy, daty (bez pakietu intl).

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} KB';
  return '${(kb / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

String formatDuration(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatDateTime(DateTime t) =>
    '${_two(t.day)}.${_two(t.month)}.${t.year} ${_two(t.hour)}:${_two(t.minute)}';

String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String formatDay(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';
