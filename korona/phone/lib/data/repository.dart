import 'package:wspolne/wspolne.dart';

import 'climbs.dart';

/// Zdobycia w Firestore: dokument `korona/{uid}` zapisywany przez zegarek (Side Service).
/// Telefon tylko czyta (wersja 1 kontraktu, korona/SYNC.md). Konto - z [AccountRepository].
class ClimbsRepository extends AccountRepository {
  ClimbsRepository(super.uid, super.email, {super.db});

  Stream<ClimbsDoc> watchClimbs() =>
      db.collection('korona').doc(uid).snapshots().map((snap) => ClimbsDoc.fromMap(snap.data()));
}
