import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wspolne/wspolne.dart';

import 'weights.dart';

/// Pomiary w Firestore: dokument `waga/{uid}` (format w waga/SYNC.md). Zegarek i telefon
/// zapisują tylko zmienione dni (`merge: true`), przy konflikcie wygrywa późniejsze `t`.
class WeightRepository extends AccountRepository {
  WeightRepository(super.uid, super.email, {super.db});

  DocumentReference<Map<String, dynamic>> get _doc => db.collection('waga').doc(uid);

  Stream<WeightDoc> watch() => _doc.snapshots().map((snap) => WeightDoc.fromMap(snap.data()));

  Future<void> _setDay(String day, int w) => _doc.set({
        'e': {
          day: {'w': w, 't': DateTime.now().millisecondsSinceEpoch},
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'v': 1,
      }, SetOptions(merge: true));

  Future<void> setEntry(String day, int w) => _setDay(day, w);

  /// Usunięcie = nagrobek w: 0 (zegarek przy synchronizacji też usunie ten dzień)
  Future<void> deleteEntry(String day) => _setDay(day, 0);

  Future<void> setGoal(int? goal) => _doc.set({
        'goal': goal ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'v': 1,
      }, SetOptions(merge: true));
}
