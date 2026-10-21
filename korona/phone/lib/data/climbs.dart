import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Zdobycia z dokumentu Firestore `korona/{uid}`, zapisywanego przez zegarek
/// (kontrakt w korona/SYNC.md). Telefon tylko czyta.
class Climb {
  const Climb({required this.peakId, required this.date, this.gps = false});

  final String peakId;

  /// Dzień zdobycia w czasie lokalnym zegarka (bez godziny)
  final DateTime date;

  /// true = zaliczony na szczycie po GPS, false = dodany ręcznie z datą
  final bool gps;
}

/// Szczyt dodany ręcznie na zegarku („Dodaj szczyt tutaj”), id `c<ms>`
class CustomPeak {
  const CustomPeak({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.date,
    this.gps = false,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final DateTime date;
  final bool gps;
}

class ClimbsDoc {
  const ClimbsDoc({this.climbs = const {}, this.custom = const [], this.updatedAt, this.exists = true});

  /// Brak dokumentu = zegarek jeszcze nic nie wysłał
  const ClimbsDoc.empty() : this(exists: false);

  final Map<String, Climb> climbs;
  final List<CustomPeak> custom;
  final DateTime? updatedAt;
  final bool exists;

  /// Odporne na braki i śmieci: pomija wpisy bez poprawnej daty
  factory ClimbsDoc.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const ClimbsDoc.empty();
    final climbs = <String, Climb>{};
    final rawClimbs = data['climbs'];
    if (rawClimbs is Map) {
      rawClimbs.forEach((key, value) {
        if (value is! Map) return;
        final d = parseDay(value['d']);
        if (d == null) return;
        climbs['$key'] = Climb(peakId: '$key', date: d, gps: value['gps'] == true);
      });
    }
    final custom = <CustomPeak>[];
    final rawCustom = data['custom'];
    if (rawCustom is Map) {
      rawCustom.forEach((key, value) {
        if (value is! Map) return;
        final d = parseDay(value['d']);
        final lat = value['lat'], lon = value['lon'];
        if (d == null || lat is! num || lon is! num) return;
        final name = value['name'];
        custom.add(CustomPeak(
          id: '$key',
          name: name is String && name.trim().isNotEmpty ? name.trim() : 'Szczyt',
          lat: lat.toDouble(),
          lon: lon.toDouble(),
          date: d,
          gps: value['gps'] == true,
        ));
      });
    }
    custom.sort((a, b) => b.date.compareTo(a.date));
    final u = data['updatedAt'];
    final updatedAt = u is Timestamp ? u.toDate() : (u is DateTime ? u : null);
    return ClimbsDoc(climbs: climbs, custom: custom, updatedAt: updatedAt);
  }

  int get total => climbs.length + custom.length;
}

/// „RRRR-MM-DD” → DateTime (lokalny dzień), null dla złego formatu
DateTime? parseDay(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, mo, d);
  return date.month == mo ? date : null;
}
