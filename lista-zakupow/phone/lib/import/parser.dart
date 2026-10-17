import 'dart:math';

import '../models.dart';
import '../sorting.dart';

/// Zamiana polskich znaków na łacińskie - do porównań odpornych na brak ogonków
/// ("maslo" i "Masło" to dla autokorekty to samo słowo).
String stripDiacritics(String s) {
  const from = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';
  const to = 'acelnoszzACELNOSZZ';
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString();
}

String matchKey(String s) => stripDiacritics(normalizeName(s));

/// Odległość edycyjna (Levenshtein) - ile pojedynczych zmian liter dzieli dwa słowa
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

// Punktory i numeracja na początku linii: "- ", "• ", "1.", "2)", "[ ]", "[x]", "a)" ...
final _leading = RegExp(
  r'^\s*(?:\[[ xX✓✔]?\]\s*|[-–—•*·+>~□☐☑✓✔✗]\s*|\(?\d{1,3}\s*[.)\]:]\s*|[a-zA-Z][.)]\s+)+',
);
final _trailing = RegExp(r'[\s.,;:\-–—•*]+$');
final _spaces = RegExp(r'\s+');
final _letter = RegExp(r'[a-zA-ZąćęłńóśźżĄĆĘŁŃÓŚŹŻ]');

/// Oczyszcza jedną linię z kartki. Zwraca null, gdy to nie produkt (pusta, same cyfry, śmieci).
String? cleanLine(String raw) {
  var s = raw.replaceAll(_spaces, ' ').trim();
  s = s.replaceFirst(_leading, '');
  s = s.replaceFirst(_trailing, '').trim();
  if (s.length < 2 || !_letter.hasMatch(s)) return null;
  if (s.length > 100) s = s.substring(0, 100).trim();
  return s[0].toUpperCase() + s.substring(1);
}

/// Dzieli rozpoznany tekst na kandydatów: linie, a w liniach także przecinki i średniki
/// ("mleko, chleb; masło"), ale nie przecinki w liczbach ("2,5 kg").
List<String> splitCandidates(String text) {
  final out = <String>[];
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    for (final part in line.split(RegExp(r';|,(?!\d)'))) {
      final c = cleanLine(part);
      if (c != null) out.add(c);
    }
  }
  return out;
}

// Słowa, którymi przy dyktowaniu łączy się produkty: "mleko i chleb", "masło oraz ser",
// a także wypowiedziane "przecinek" (gdy rozpoznawanie mowy nie zamieni go na znak)
final _spokenJoin = RegExp(r'(?:^|\s)(?:i|oraz|a także|przecinek)(?=\s|$)', caseSensitive: false);

/// Dzieli podyktowany tekst na produkty: przecinki oraz spójniki "i", "oraz".
/// "mleko chleb" bez przerwy zostaje jednym produktem - takie rozdzielasz pauzą.
List<String> splitSpoken(String text) => splitCandidates(text.replaceAll(_spokenJoin, ','));

/// Słownik do autokorekty: historia użytkownika (ważniejsza) + typowe produkty.
class Vocabulary {
  Vocabulary(Iterable<String> history, Iterable<String> common) {
    for (final name in [...history, ...common]) {
      final clean = cleanLine(name);
      if (clean == null) continue;
      _entries.putIfAbsent(matchKey(clean), () => clean);
      for (final w in clean.split(' ')) {
        if (w.length >= 3 && _letter.hasMatch(w)) _words.putIfAbsent(matchKey(w), () => w.toLowerCase());
      }
    }
  }

  final Map<String, String> _entries = {};
  final Map<String, String> _words = {};

  /// Tolerancja pomyłek. Słowa do 4 liter tylko bez pomyłek (poza ogonkami) - inaczej
  /// "Klej" zmieniałby się w "Olej". 5-6 liter: 1 pomyłka, dłuższe: ok. 1 na 4 litery.
  static bool _close(String a, String b) {
    final shortest = min(a.length, b.length);
    if (shortest < 5) return false;
    final d = editDistance(a, b);
    return max(a.length, b.length) <= 6 ? d <= 1 : d / max(a.length, b.length) <= 0.25;
  }

  static String? _best(String key, Map<String, String> dict) {
    String? best;
    var bestD = 1 << 30;
    for (final e in dict.entries) {
      if ((e.key.length - key.length).abs() > 3) continue;
      if (!_close(key, e.key)) continue;
      final d = editDistance(key, e.key);
      if (d < bestD) {
        bestD = d;
        best = e.value;
      }
    }
    return best;
  }

  /// Poprawiona nazwa albo ta sama, gdy nie ma nic podobnego
  String correct(String name) {
    final key = matchKey(name);
    final exact = _entries[key];
    if (exact != null) return exact;
    final whole = _best(key, _entries);
    if (whole != null) return whole;
    // Poprawianie słowo po słowie: "Mieko 2%" -> "Mleko 2%"
    final words = name.split(' ');
    var changed = false;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.length < 3 || !_letter.hasMatch(w)) continue;
      // _words zawiera tylko słowa od 3 liter; pomyłki poprawia _best od 5 liter
      final wk = matchKey(w);
      final fixed = _words[wk] ?? _best(wk, _words);
      if (fixed != null && fixed != w.toLowerCase()) {
        words[i] = i == 0 ? fixed[0].toUpperCase() + fixed.substring(1) : fixed;
        changed = true;
      }
    }
    return changed ? words.join(' ') : name;
  }
}

enum ImportStatus { add, restore, onList }

/// Pozycja na ekranie sprawdzenia
class ImportCandidate {
  ImportCandidate({required this.original, required this.text, required this.status, required this.selected});

  /// Tak, jak rozpoznano (do cofnięcia autokorekty)
  final String original;
  String text;
  ImportStatus status;
  bool selected;

  bool get corrected => normalizeName(text) != normalizeName(original);
}

/// Stan pozycji względem bieżącej listy (jak przy ręcznym dodawaniu na telefonie)
ImportStatus statusFor(String name, Iterable<ShoppingItem> current) {
  final plan = planAdd(name, current);
  switch (plan.decision) {
    case AddDecision.add:
      return ImportStatus.add;
    case AddDecision.uncheckExisting:
      return ImportStatus.restore;
    case AddDecision.alreadyOnList:
      return ImportStatus.onList;
  }
}

/// Z surowych linii robi listę do sprawdzenia: oczyszcza, poprawia, usuwa powtórzenia,
/// a produkty, które już czekają na liście, domyślnie odznacza.
List<ImportCandidate> planImport(Iterable<String> rawLines, Iterable<ShoppingItem> current, Vocabulary vocab) {
  final seen = <String>{};
  final out = <ImportCandidate>[];
  for (final raw in rawLines) {
    for (final line in splitCandidates(raw)) {
      final fixed = vocab.correct(line);
      final key = normalizeName(fixed);
      if (!seen.add(key)) continue;
      final status = statusFor(fixed, current);
      out.add(ImportCandidate(original: line, text: fixed, status: status, selected: status != ImportStatus.onList));
    }
  }
  return out;
}
