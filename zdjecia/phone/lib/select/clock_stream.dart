// Strumień zdjęć dla zegarów biurkowych HomeAutomation (most: /clocks.json). Zegar trzyma najwyżej ~20 zdjęć
// i bierze te, które najpóźniej trafiły do strumienia ([ClockSlot.added]), więc:
//  - nowe zdjęcia puli zegarka (świeże i wspomnienia) wchodzą od razu,
//  - co godzinę (w dzień) dochodzi [clockArchivePerHour] zdjęć z archiwum - zegar wymienia je po kilka,
//    w ciągu dnia przewija się ponad sto różnych zdjęć zamiast tych samych 20.
// Od 0.14.0 lista jest długa ([clockStreamSize]): HomeAutomation 1.33.0+ wymienia zdjęcia „spalone” na zegarze
// (obejrzane przy przeglądaniu) na kolejne z listy, więc reszta listy to zapas zamienników.
// Od 0.15.0 „ten dzień X lat temu” ([markThisDay]): raz dziennie zdjęcia zrobione tego samego dnia i miesiąca
// w poprzednich latach dostają czas dodania „koniec dzisiejszego dnia” - przez cały dzień są najnowsze, więc zegar
// je trzyma (sam rozpoznaje je po `taken` i opisuje „20 listopada 2019 · 6 lat temu”), a od jutra schodzą same.
// Czysta logika (testy).
import 'crop.dart';

/// Długość listy: ~20 najnowszych na zegarze + zapas na zdjęcia „spalone” przy przeglądaniu
const int clockStreamSize = 150;
const int clockArchivePerHour = 8;

/// Archiwum dokłada zdjęcia tylko w tych godzinach (w nocy zegary i tak nikt nie ogląda)
const int clockFromHour = 6;
const int clockToHour = 23;

/// „Ten dzień X lat temu”: najwyżej tyle zdjęć z archiwum dziennie (do tego zdjęcia puli z tą datą)
const int thisDayMax = 6;

/// Zdjęcie z archiwum wraca na zegary najwcześniej po tylu dniach (przy ~130 dziennie i ~1100 w archiwum
/// całe archiwum przewija się mniej więcej co 9 dni; gdy wszystkie odpoczywają - najdawniej pokazane pierwsze)
const Duration clockRest = Duration(days: 7);

class ClockSlot {
  const ClockSlot({
    required this.id,
    required this.ref,
    required this.archive,
    required this.added,
    required this.taken,
    this.caption = '',
    this.frame,
    this.thisDay = false,
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

  /// „Ten dzień X lat temu” (czas dodania „koniec dnia”, [markThisDay])
  final bool thisDay;

  ClockSlot copy({required DateTime added, required bool thisDay}) => ClockSlot(
      id: id, ref: ref, archive: archive, added: added, taken: taken, caption: caption, frame: frame, thisDay: thisDay);

  Map<String, Object> toJson() => {
        'id': id,
        'ref': ref,
        if (archive) 'a': true,
        'added': added.millisecondsSinceEpoch,
        'taken': taken.millisecondsSinceEpoch,
        if (caption.isNotEmpty) 'c': caption,
        if (frame != null) 'frame': frame!.toJson(),
        if (thisDay) 'td': true,
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
      thisDay: j['td'] == true,
    );
  }
}

class ClockStream {
  ClockStream({List<ClockSlot>? slots, Set<String>? poolSeen, Map<String, DateTime>? shown, this.lastArchive, this.thisDay})
      : slots = slots ?? [],
        poolSeen = poolSeen ?? {},
        shown = shown ?? {};

  List<ClockSlot> slots;

  /// Zdjęcia puli, które już weszły do strumienia (żeby po wypadnięciu ze strumienia nie wracały jako „nowe”)
  final Set<String> poolSeen;

  /// Zdjęcia z archiwum: kiedy ostatnio weszły do strumienia
  final Map<String, DateTime> shown;
  DateTime? lastArchive;

  /// Dzień ([dayKey]), dla którego wybrano już zdjęcia „ten dzień X lat temu”
  String? thisDay;

  Set<String> get archiveIds => {for (final s in slots) if (s.archive) s.ref};

  Map<String, Object?> toJson() => {
        'slots': [for (final s in slots) s.toJson()],
        'poolSeen': poolSeen.toList(),
        'shown': {for (final e in shown.entries) e.key: e.value.millisecondsSinceEpoch},
        'lastArchive': lastArchive?.millisecondsSinceEpoch,
        'thisDay': ?thisDay,
      };

  factory ClockStream.fromJson(Map<String, dynamic> j) => ClockStream(
        slots: [for (final s in (j['slots'] as List? ?? const [])) ?ClockSlot.fromJson(s)],
        poolSeen: {...(j['poolSeen'] as List? ?? const []).whereType<String>()},
        shown: {
          for (final e in ((j['shown'] as Map?) ?? const {}).entries)
            if (e.value is int) e.key as String: DateTime.fromMillisecondsSinceEpoch(e.value as int),
        },
        lastArchive: j['lastArchive'] is int ? DateTime.fromMillisecondsSinceEpoch(j['lastArchive'] as int) : null,
        thisDay: j['thisDay'] as String?,
      );
}

/// Zdjęcia puli w strumieniu: nowe dochodzą (z kolejnymi czasami, żeby kolejność była stała), te, które wypadły
/// z puli - znikają. [pool] = (id, zrobione) opublikowanych zdjęć.
void syncPoolSlots(ClockStream s, List<({String id, DateTime taken})> pool, DateTime now) {
  final ids = {for (final p in pool) p.id};
  s.slots.removeWhere((x) => !x.archive && !ids.contains(x.ref));
  s.poolSeen.removeWhere((id) => !ids.contains(id));
  var k = 0;
  final today = s.thisDay == dayKey(now);
  for (final p in pool) {
    if (!s.poolSeen.add(p.id)) continue;
    // Zdjęcie z tą datą sprzed lat, które weszło do puli w ciągu dnia - też „ten dzień”
    final special = today && isThisDay(p.taken, now);
    final added = special ? thisDayAdded(now, 100 + k) : now.add(Duration(milliseconds: k));
    k++;
    s.slots.add(ClockSlot(id: p.id, ref: p.id, archive: false, added: added, taken: p.taken, thisDay: special));
  }
  trimStream(s);
}

/// Ten sam dzień i miesiąc co [now] (czas lokalny), wcześniejszy rok - tak rozpoznaje je zegar
bool isThisDay(DateTime taken, DateTime now) => taken.month == now.month && taken.day == now.day && taken.year < now.year;

String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Czy dziś trzeba jeszcze wybrać „ten dzień X lat temu” (raz dziennie, od [clockFromHour])
bool thisDayDue(ClockStream s, DateTime now) => now.hour >= clockFromHour && s.thisDay != dayKey(now);

/// Czas dodania „ten dzień”: tuż przed północą - przez cały dzień nowszy od wszystkiego, co dojdzie
DateTime thisDayAdded(DateTime now, int k) =>
    DateTime(now.year, now.month, now.day + 1).subtract(Duration(milliseconds: 1 + k));

/// „Ten dzień X lat temu” na dziś:
///  - poprzednie (z innego dnia) schodzą na czas dodania sprzed doby - pod wszystko, co dodano wczoraj i dziś,
///    na zegarze zostają tylko jako zamienniki dla zdjęć „spalonych”,
///  - zdjęcia puli z tą datą i [archiveSlots] (wybrane przez [pickThisDay], z kadrem; pierwsze = najlepsze)
///    dostają czas dodania „koniec dnia”, więc zegar trzyma je cały dzień, a przycinanie listy ich nie wyrzuca.
void markThisDay(ClockStream s, List<ClockSlot> archiveSlots, DateTime now) {
  final dayBefore = DateTime(now.year, now.month, now.day - 1);
  var old = 0, pool = 0;
  s.slots = [
    for (final x in s.slots)
      if (x.thisDay && !isThisDay(x.taken, now))
        x.copy(added: dayBefore.subtract(Duration(milliseconds: ++old)), thisDay: false)
      else if (!x.archive && isThisDay(x.taken, now))
        x.copy(added: thisDayAdded(now, 50 + pool++), thisDay: true)
      else
        x,
  ];
  var k = 0;
  for (final slot in archiveSlots) {
    s.slots.removeWhere((x) => x.archive && x.ref == slot.ref);
    s.slots.add(slot.copy(added: thisDayAdded(now, k++), thisDay: true));
    s.shown[slot.ref] = now;
  }
  s.thisDay = dayKey(now);
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
