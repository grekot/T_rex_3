// Pomocnicze funkcje do odczytu JSON-a z kontraktu docs/API.md.
//
// Firmware powstaje równolegle, więc parser jest tolerancyjny: brak pola
// niewymagającego `null` daje wartość domyślną, a zły typ rzuca FormatException.

typedef Json = Map<String, dynamic>;

double? asDoubleOrNull(Object? v, String field) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  throw FormatException('Pole "$field": oczekiwano liczby, jest ${v.runtimeType}');
}

double asDouble(Object? v, String field, [double fallback = 0]) => asDoubleOrNull(v, field) ?? fallback;

int? asIntOrNull(Object? v, String field) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  throw FormatException('Pole "$field": oczekiwano liczby całkowitej, jest ${v.runtimeType}');
}

int asInt(Object? v, String field, [int fallback = 0]) => asIntOrNull(v, field) ?? fallback;

bool asBool(Object? v, String field, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  throw FormatException('Pole "$field": oczekiwano true/false, jest ${v.runtimeType}');
}

String? asStringOrNull(Object? v, String field) {
  if (v == null) return null;
  if (v is String) return v;
  // lat/lon mogą przyjść jako liczba, choć kontrakt mówi o tekście.
  if (v is num) return v.toString();
  throw FormatException('Pole "$field": oczekiwano tekstu, jest ${v.runtimeType}');
}

String asString(Object? v, String field, [String fallback = '']) => asStringOrNull(v, field) ?? fallback;

Json? asObjectOrNull(Object? v, String field) {
  if (v == null) return null;
  if (v is Map) return v.cast<String, dynamic>();
  throw FormatException('Pole "$field": oczekiwano obiektu, jest ${v.runtimeType}');
}

/// Mapa błędów pól z `errors`, np. `{"schedule.weekday": "format"}`.
Map<String, String> asErrors(Object? v) {
  final obj = asObjectOrNull(v, 'errors');
  if (obj == null) return const {};
  return obj.map((k, e) => MapEntry(k, e?.toString() ?? ''));
}

/// Dodaje do mapy tylko wartości różne od null.
void putIfNotNull(Json json, String key, Object? value) {
  if (value != null) json[key] = value;
}
