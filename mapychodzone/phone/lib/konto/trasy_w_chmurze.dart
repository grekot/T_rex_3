import 'package:cloud_firestore/cloud_firestore.dart';

import 'zapisana_trasa.dart';

/// Trasy zapisane na koncie: kolekcja `trasy/{id}` w Firestore (reguły: App_storage/firebase/firestore.rules).
///
/// Dokument ma `ownerId`, `members` i `memberEmails` jak miejsca z Powrotu, więc później można
/// trasę udostępnić znajomym tym samym oknem „Udostępnij” z pakietu `wspolne`.
/// W telefonie Firestore trzyma kopię w pamięci urządzenia: lista tras działa bez internetu,
/// a zapis bez zasięgu wyśle się, gdy telefon złapie sieć.
class TrasyWChmurze {
  TrasyWChmurze(this.uid, this.email, {FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final String uid;
  final String email;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _trasy => _db.collection('trasy');

  /// Czas zmiany: `t` (zegar urządzenia, jest od razu, także przed potwierdzeniem przez serwer)
  /// albo `updatedAt` (czas serwera).
  static DateTime? _czas(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m?['t'] case final int ms) return DateTime.fromMillisecondsSinceEpoch(ms);
    final t = m?['updatedAt'];
    return t is Timestamp ? t.toDate() : null;
  }

  static int get _teraz => DateTime.now().millisecondsSinceEpoch;

  /// Moje trasy, od ostatnio zmienionej (sortowanie u nas: bez indeksu złożonego w Firestore).
  Stream<List<OpisTrasy>> obserwuj() =>
      _trasy.where('members', arrayContains: uid).snapshots().map((s) {
        final lista = [for (final d in s.docs) OpisTrasy.zMapy(d.id, d.data(), zmieniona: _czas(d))];
        lista.sort((a, b) => (b.zmieniona ?? DateTime(2100)).compareTo(a.zmieniona ?? DateTime(2100)));
        return lista;
      });

  Future<ZapisanaTrasa?> wczytaj(String id) async {
    final d = await _trasy.doc(id).get();
    final m = d.data();
    return m == null ? null : ZapisanaTrasa.zMapy(d.id, m, zmieniona: _czas(d));
  }

  /// Zapisuje nową trasę (bez [ZapisanaTrasa.id]) albo nadpisuje istniejącą. Zwraca id.
  ///
  /// Nie czekamy na serwer: bez internetu zapis czeka w kolejce Firestore, a id jest od razu.
  Future<String> zapisz(ZapisanaTrasa t) async {
    final id = t.id;
    if (id == null) {
      final ref = _trasy.doc();
      _poZapisie(ref.set({
        ...t.doMapy(),
        'ownerId': uid,
        'members': [uid],
        'memberEmails': {uid: email},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        't': _teraz,
      }));
      return ref.id;
    }
    _poZapisie(_trasy.doc(id).update({...t.doMapy(), 'updatedAt': FieldValue.serverTimestamp(), 't': _teraz}));
    return id;
  }

  Future<void> zmienNazwe(String id, String nazwa) =>
      _trasy.doc(id).update({'nazwa': nazwa, 'updatedAt': FieldValue.serverTimestamp(), 't': _teraz});

  Future<void> usun(String id) => _trasy.doc(id).delete();

  /// Błąd zapisu (np. odrzucony przez reguły) – do pokazania, gdy przyjdzie odpowiedź serwera.
  void Function(Object blad)? onBladZapisu;

  void _poZapisie(Future<void> zapis) {
    zapis.catchError((Object e) => onBladZapisu?.call(e));
  }
}
