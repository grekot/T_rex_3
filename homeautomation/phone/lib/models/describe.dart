// Opis punktów danych urządzenia (kontrakt pkt 14): `GET /api/describe` albo `devices/{id}/describe`.

import 'home.dart';
import 'json_utils.dart';

/// `sensor` - liczba tylko do odczytu, `status` - bool, `setpoint` - liczba do ustawiania,
/// `switch` - bool do ustawiania, `select` - wybór z listy, `action` - przycisk.
enum PointKind {
  sensor('sensor'),
  status('status'),
  setpoint('setpoint'),
  switchKind('switch'),
  select('select'),
  action('action');

  const PointKind(this.wire);

  final String wire;

  static PointKind fromWire(Object? v) => values.firstWhere((k) => k.wire == v, orElse: () => sensor);

  /// Da się ustawiać (pole Set).
  bool get writable => this == setpoint || this == switchKind || this == select || this == action;
}

class DataPoint {
  const DataPoint({
    required this.key,
    required this.name,
    required this.kind,
    this.unit,
    this.decimals,
    this.min,
    this.max,
    this.step,
    this.options = const [],
    this.access = AccessLevel.config,
    this.history,
  });

  /// Pole State (z kropką = zagnieżdżone, np. `outdoor.temp`); dla ustawialnych także pole Set.
  final String key;
  final String name;
  final PointKind kind;
  final String? unit;
  final int? decimals;
  final double? min;
  final double? max;
  final double? step;
  final List<String> options;

  /// Poziom potrzebny do ustawienia (domyślnie `config`).
  final AccessLevel access;

  /// Pole w `history` (wykres).
  final String? history;

  factory DataPoint.fromJson(Json j) => DataPoint(
    key: asString(j['key'], 'key'),
    name: asString(j['name'], 'name'),
    kind: PointKind.fromWire(j['kind']),
    unit: asStringOrNull(j['unit'], 'unit'),
    decimals: asIntOrNull(j['decimals'], 'decimals'),
    min: asDoubleOrNull(j['min'], 'min'),
    max: asDoubleOrNull(j['max'], 'max'),
    step: asDoubleOrNull(j['step'], 'step'),
    options: [
      for (final o in (j['options'] is List ? j['options'] as List : const []))
        if (o is String) o,
    ],
    access: j['access'] == null ? AccessLevel.config : AccessLevel.fromWire(j['access']),
    history: asStringOrNull(j['history'], 'history'),
  );

  /// Wartość z State (obsługa kluczy z kropką).
  Object? valueIn(Json? state) {
    Object? v = state;
    for (final part in key.split('.')) {
      if (v is! Map) return null;
      v = v[part];
    }
    return v;
  }

  /// Tekst do pokazania (liczby po polsku, z jednostką).
  String format(Object? v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'tak' : 'nie';
    if (v is num) {
      final d = decimals ?? (v is int ? 0 : 1);
      final s = v.toStringAsFixed(d).replaceAll('.', ',');
      return unit == null ? s : '$s $unit';
    }
    return v.toString();
  }

  /// Set ustawiający ten punkt (klucz z kropką → zagnieżdżony obiekt).
  Json setFor(Object? value) {
    final parts = key.split('.');
    Object? v = value;
    for (final p in parts.reversed) {
      v = {p: v};
    }
    return v as Json;
  }
}

class DeviceDescription {
  const DeviceDescription({required this.type, required this.points});

  final String type;
  final List<DataPoint> points;

  DataPoint? point(String key) => points.where((p) => p.key == key).firstOrNull;

  factory DeviceDescription.fromJson(Json j) => DeviceDescription(
    type: asString(j['type'], 'type'),
    points: [
      for (final p in (j['points'] is List ? j['points'] as List : const []))
        if (p is Map) DataPoint.fromJson(p.cast<String, dynamic>()),
    ],
  );
}
