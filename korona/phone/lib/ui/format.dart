import 'package:flutter/material.dart';

/// Kolory jak na zegarku: zdobyte zielone, niezdobyte szare, własne niebieskie
const climbedColor = Color(0xFF2E9E4F);
const customColor = Color(0xFF2F7DD1);
const unclimbedColor = Color(0xFF8A9199);

const _months = [
  'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', //
  'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia',
];

/// „15 lipca 2024”
String formatDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// „15.07.2024”
String formatShortDay(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// „20 października 2026, 14:05”
String formatDateTime(DateTime d) => '${formatDay(d)}, ${d.hour}:${_two(d.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');

/// „1725 m” albo „—” bez wysokości
String formatHeight(int? h) => h == null ? '—' : '$h m';

/// Odmiana: 1 szczyt, 2 szczyty, 5 szczytów
String plural(int n, String one, String few, String many) {
  if (n == 1) return '$n $one';
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n $few';
  return '$n $many';
}

String peaksCount(int n) => plural(n, 'szczyt', 'szczyty', 'szczytów');

/// „49,17958° N, 20,08811° E”
String formatLatLon(double lat, double lon) {
  String f(double v) => v.abs().toStringAsFixed(5).replaceAll('.', ',');
  return '${f(lat)}° ${lat >= 0 ? 'N' : 'S'}, ${f(lon)}° ${lon >= 0 ? 'E' : 'W'}';
}
