// Strumień zdjęć dla zegarów biurkowych HomeAutomation (most: /clocks.json). Zegar trzyma najwyżej ~20 zdjęć
// i bierze te, które najpóźniej trafiły do strumienia ([ClockSlot.added]), więc:
//  - nowe zdjęcia puli zegarka (świeże i wspomnienia) wchodzą od razu,
//  - co godzinę (w dzień) dochodzi [clockArchivePerHour] zdjęć z archiwum - zegar wymienia je po kilka,
//    w ciągu dnia przewija się kilkadziesiąt różnych zdjęć zamiast tych samych 20.
// Czysta logika (testy).
import 'crop.dart';

const int clockStreamSize = 40;
const int clockArchivePerHour = 4;

/// Archiwum dokłada zdjęcia tylko w tych godzinach (w nocy zegary i tak nikt nie ogląda)
const int clockFromHour = 6;
const int clockToHour = 23;

/// Zdjęcie z archiwum wraca na zegary najwcześniej po tylu dniach
const Duration clockRest = Duration(days: 45);

class ClockSlot {
  const ClockSlot({
    required this.id,
    required this.ref,
    required this.archive,
    required this.added,
    required this.taken,
    this.caption = '',
    this.frame,
  });

  /// Id dla zegara (w moście)
  final String id;

  /// Zdjęcie z puli zegarka: id opublikowanego zdjęcia; z archiwum: id w archiwum
  final String ref;
  final bool archive;
  final DateTime added;
  final DateTime taken;

  /// Podpis jak dla zegarka („Nad jeziorem · 2014”) - tylko zdjęcia z archiwum (pula ma swój)
  final String caption;

  /// Dane kadru prostokątnego - tylko zdjęcia z archiwum (pula ma je w published.json)
  final CropFrame? frame;

  Map<String, Object> toJson() => {
        'id': id,
        'ref': ref,
        if (archive) 'a': true,
        'added': added.millisecondsSinceEpoch,
        'taken': taken.millisecondsSinceEpoch,
        if (caption.isNotEmpty) 'c': caption,
        if (frame != null) 'frame': frame!.toJson(),
      };

  static ClockSlot? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['ref'] is! String || j['added'] is! int) return null;
    return ClockSlot(
      id: j['id'] as String,
      ref: j['ref'] as String,
      archive: j['a'] == true,
      added: DateTime.fromMillisecondsSinceEpoch(j['added'] as int),
      taken: DateTime.fromMillisecondsSinceEpoch(j['taken'] as int? ?? 0),
      caption: j['c'] as String? ?? '',
      frame: j['frame'] is Map ? CropFrame.fromJson((j['frame'] as Map).cast<String, dynamic>()) : null,
    );
  }
}

class ClockStream {
  ClockStream({List<ClockSlot>? slots, Set<String>? poolSeen, Map<String, DateTime>? shown, this.lastArchive})
      : slots = slots ?? [],
        poolSeen = poolSeen ?? {},
        shown = shown ?? {};

  List<ClockSlot> slots;

  /// Zdjęcia puli, które już weszły do strumienia (żeby po wypadnięciu ze strumienia nie wracały jako „nowe”)
  final Set<String> poolSeen;

  /// Zdjęcia z archiwum: kiedy ostatnio weszły do strumienia
  final Map<String, DateTime> shown;
  DateTime? lastArchive;

  Set<String> get archiveIds => {for (final s in slots) if (s.archive) s.ref};

  Map<String, Object?> toJson() => {
        'slots': [for (final s in slots) s.toJson()],
        'poolSeen': poolSeen.toList(),
        'shown': {for (final e in shown.entries) e.key: e.value.millisecondsSinceEpoch},
        'lastArchive': lastArchive?.millisecondsSinceEpoch,
      };

  factory ClockStream.fromJson(Map<String, dynamic> j) => ClockStream(
        slots: [for (final s in (j['slots'] as List? ?? const [])) ?ClockSlot.fromJson(s)],
        poolSeen: {...(j['poolSeen'] as List? ?? const []).whereType<String>()},
        shown: {
          for (final e in ((j['shown'] as Map?) ?? const {}).entries)
            if (e.value is int) e.key as String: DateTime.fromMillisecondsSinceEpoch(e.value as int),
        },
        lastArchive: j['lastArchive'] is int ? DateTime.fromMillisecondsSinceEpoch(j['lastArchive'] as int) : null,
      );
}

/// Zdjęcia puli w strumieniu: nowe dochodzą (z kolejnymi czasami, żeby kolejność była stała), te, które wypadły
/// z puli - znikają. [pool] = (id, zrobione) opublikowanych zdjęć.
void syncPoolSlots(ClockStream s, List<({String id, DateTime taken})> pool, DateTime now) {
  final ids = {for (final p in pool) p.id};
  s.slots.removeWhere((x) => !x.archive && !ids.contains(x.ref));
  s.poolSeen.removeWhere((id) => !ids.contains(id));
  var k = 0;
  for (final p in pool) {
    if (!s.poolSeen.add(p.id)) continue;
    s.slots.add(ClockSlot(id: p.id, ref: p.id, archive: false, added: now.add(Duration(milliseconds: k++)), taken: p.taken));
  }
  trimStream(s);
}

/// Ile zdjęć z archiwum dołożyć teraz: [clockArchivePerHour] na każdą pełną godzinę od ostatniego razu
/// (najwyżej dwie godziny zaległości), tylko w godzinach [clockFromHour]-[clockToHour].
int archiveDue(ClockStream s, DateTime now) {
  if (now.hour < clockFromHour || now.hour >= clockToHour) return 0;
  final last = s.lastArchive;
  if (last == null || now.isBefore(last)) return clockArchivePerHour;
  final hours = now.difference(last).inMinutes ~/ 60;
  return (hours * clockArchivePerHour).clamp(0, 2 * clockArchivePerHour);
}

/// Dokłada zdjęcia z archiwum (już z kadrem) i przycina strumień do [clockStreamSize] najnowszych.
void addArchiveSlots(ClockStream s, List<ClockSlot> slots, DateTime now) {
  var k = 0;
  for (final slot in slots) {
    s.slots.removeWhere((x) => x.archive && x.ref == slot.ref);
    s.slots.add(ClockSlot(
      id: slot.id,
      ref: slot.ref,
      archive: true,
      added: now.add(Duration(milliseconds: k++)),
      taken: slot.taken,
      caption: slot.caption,
      frame: slot.frame,
    ));
    s.shown[slot.ref] = now;
  }
  s.lastArchive = now;
  s.shown.removeWhere((_, at) => now.difference(at) > clockRest * 2);
  trimStream(s);
}

void trimStream(ClockStream s) {
  s.slots.sort((a, b) => a.added.compareTo(b.added));
  if (s.slots.length > clockStreamSize) s.slots = s.slots.sublist(s.slots.length - clockStreamSize);
}

/// Id zdjęcia z archiwum na zegarze
String clockArchiveId(String archiveId) => 'z_$archiveId';
