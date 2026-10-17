import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wspolne/wspolne.dart';

import 'models.dart';

/// Miejsca w Firestore (kolekcja places, reguły w lista-zakupow/firebase/firestore.rules).
/// Konto, znajomi i udostępnianie - z [AccountRepository] (wspólne z aplikacją Zakupy).
class PlacesRepository extends AccountRepository {
  PlacesRepository(super.uid, super.email, {super.db});

  CollectionReference<Map<String, dynamic>> get _places => db.collection('places');

  /// Moje miejsca i udostępnione mi, najnowsze na górze
  Stream<List<Place>> watchPlaces() => _places.where('members', arrayContains: uid).snapshots().map((snap) {
        final far = DateTime.utc(1970);
        return snap.docs.map(Place.fromDoc).toList()..sort((a, b) => (b.savedAt ?? far).compareTo(a.savedAt ?? far));
      });

  Future<void> deletePlace(String placeId) => _places.doc(placeId).delete();

  Future<void> renamePlace(String placeId, String name) => _places.doc(placeId).update({
        'name': name.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> leavePlace(String placeId) => leave('places', placeId);
}
