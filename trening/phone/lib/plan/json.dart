/// Pomocnicze odczyty JSON-a planu: ścisłe typy, nieznane klucze to błąd
/// (literówka w plan.json ma się wysypać w teście, a nie po cichu zniknąć).
library;

class BladPlanu implements Exception {
  BladPlanu(this.sciezka, this.opis);
  final String sciezka;
  final String opis;

  @override
  String toString() => 'Błąd planu w $sciezka: $opis';
}

/// Zakres liczb z planu, np. „6–8 oddechów” → Zakres(6, 8). Pojedyncza liczba → (n, n).
class Zakres {
  const Zakres(this.min, this.max);
  const Zakres.jeden(num n) : this(n, n);

  final num min;
  final num max;

  bool get staly => min == max;

  static Zakres z(Object? v, String sciezka) {
    if (v is num) return Zakres.jeden(v);
    if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
      final a = v[0] as num, b = v[1] as num;
      if (a > b) throw BladPlanu(sciezka, 'zakres malejący $v');
      return Zakres(a, b);
    }
    throw BladPlanu(sciezka, 'oczekiwano liczby albo [min, max], jest $v');
  }

  static Zakres? opcja(Object? v, String sciezka) => v == null ? null : z(v, sciezka);

  String _f(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString().replaceAll('.', ',');

  @override
  String toString() => staly ? _f(min) : '${_f(min)}–${_f(max)}';

  @override
  bool operator ==(Object other) => other is Zakres && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

class Odczyt {
  Odczyt(Object? json, this.sciezka, {Set<String>? dozwolone}) : m = _mapa(json, sciezka) {
    if (dozwolone != null) {
      final obce = m.keys.where((k) => !dozwolone.contains(k)).toList();
      if (obce.isNotEmpty) throw BladPlanu(sciezka, 'nieznane pola: ${obce.join(', ')}');
    }
  }

  final Map<String, Object?> m;
  final String sciezka;

  static Map<String, Object?> _mapa(Object? json, String sciezka) {
    if (json is Map<String, Object?>) return json;
    if (json is Map) return json.cast<String, Object?>();
    throw BladPlanu(sciezka, 'oczekiwano obiektu');
  }

  String p(String k) => '$sciezka.$k';

  bool ma(String k) => m.containsKey(k) && m[k] != null;

  String tekst(String k) {
    final v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw BladPlanu(p(k), 'oczekiwano niepustego tekstu');
  }

  String? tekstOpcja(String k) => ma(k) ? tekst(k) : null;

  int calkowita(String k) {
    final v = m[k];
    if (v is int) return v;
    throw BladPlanu(p(k), 'oczekiwano liczby całkowitej');
  }

  int? calkowitaOpcja(String k) => ma(k) ? calkowita(k) : null;

  bool flaga(String k, {bool domyslnie = false}) {
    final v = m[k];
    if (v == null) return domyslnie;
    if (v is bool) return v;
    throw BladPlanu(p(k), 'oczekiwano true/false');
  }

  Zakres zakres(String k) => Zakres.z(m[k], p(k));

  Zakres? zakresOpcja(String k) => Zakres.opcja(m[k], p(k));

  List<String> teksty(String k, {bool wymagane = false}) {
    final v = m[k];
    if (v == null && !wymagane) return const [];
    if (v is List && v.every((e) => e is String && e.isNotEmpty)) return v.cast<String>();
    throw BladPlanu(p(k), 'oczekiwano listy tekstów');
  }

  List<Object?> lista(String k, {bool wymagane = false}) {
    final v = m[k];
    if (v == null && !wymagane) return const [];
    if (v is List) return v;
    throw BladPlanu(p(k), 'oczekiwano listy');
  }

  Map<String, Object?> obiekt(String k) => _mapa(m[k], p(k));
}
