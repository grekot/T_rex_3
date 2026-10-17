import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wspolne/wspolne.dart';

import 'models.dart';
import 'sorting.dart';

/// Listy zakupów w Firestore (struktura w firebase/firestore.rules).
/// Konto, znajomi i udostępnianie - z [AccountRepository] (wspólne z aplikacją Powrót).
class ShoppingRepository extends AccountRepository {
  ShoppingRepository(super.uid, super.email, {super.db});

  CollectionReference<Map<String, dynamic>> get _lists => db.collection('lists');

  CollectionReference<Map<String, dynamic>> _items(String listId) => _lists.doc(listId).collection('items');

  // --- listy ---

  Stream<List<ShoppingList>> watchLists() => _lists
      .where('members', arrayContains: uid)
      .snapshots()
      .map((snap) => sortLists(snap.docs.map(ShoppingList.fromDoc)));

  /// Pojedyncza lista na żywo; null, gdy usunięta albo odebrano mi dostęp
  Stream<ShoppingList?> watchList(String listId) => _lists
      .doc(listId)
      .snapshots()
      .map<ShoppingList?>((doc) => doc.exists ? ShoppingList.fromDoc(doc) : null)
      .transform(StreamTransformer<ShoppingList?, ShoppingList?>.fromHandlers(
        handleError: (error, stack, sink) {
          // Po opuszczeniu listy reguły odbierają dostęp - traktujemy to jak "lista zniknęła"
          if (error is FirebaseException && error.code == 'permission-denied') {
            sink.add(null);
          } else {
            sink.addError(error, stack);
          }
        },
      ));

  Stream<List<ShoppingItem>> watchItems(String listId) =>
      _items(listId).snapshots().map((snap) => sortItems(snap.docs.map(ShoppingItem.fromDoc)));

  Future<void> createList(String name) => _lists.add({
        'name': name.trim(),
        'ownerId': uid,
        'members': [uid],
        'memberEmails': {uid: email},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> renameList(String listId, String name) => _lists.doc(listId).update({
        'name': name.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Reguły sprawdzają członkostwo przez dokument listy (get) przy każdym produkcie,
  /// a Firestore pozwala na 20 takich odczytów w jednej paczce - zapisujemy po 10.
  static const _chunk = 10;

  Future<void> _inChunks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    void Function(WriteBatch batch, DocumentReference<Map<String, dynamic>> ref) write,
  ) async {
    for (var i = 0; i < docs.length; i += _chunk) {
      final batch = db.batch();
      for (final doc in docs.skip(i).take(_chunk)) {
        write(batch, doc.reference);
      }
      await batch.commit();
    }
  }

  /// Najpierw produkty, potem lista - reguły sprawdzają członkostwo przez dokument listy.
  /// Usunąć listę może tylko właściciel.
  Future<void> deleteList(String listId) async {
    final items = await _items(listId).get();
    await _inChunks(items.docs, (batch, ref) => batch.delete(ref));
    await _lists.doc(listId).delete();
  }

  Future<void> leaveList(String listId) => leave('lists', listId);

  // --- produkty ---

  /// Nazwy produktów ze wszystkich moich list - słownik autokorekty przy dodawaniu z kartki
  Future<List<String>> productHistory() async {
    final lists = await _lists.where('members', arrayContains: uid).get();
    final names = <String>[];
    for (final list in lists.docs) {
      final items = await _items(list.id).get();
      names.addAll(items.docs.map((d) => (d.data()['name'] as String?) ?? '').where((n) => n.isNotEmpty));
    }
    return names;
  }

  Future<void> addItem(String listId, String name) => _items(listId).add({
        'name': name.trim(),
        'checked': false,
        'createdAt': FieldValue.serverTimestamp(),
        'checkedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'phone',
      });

  Future<void> setChecked(String listId, String itemId, bool checked) => _items(listId).doc(itemId).update({
        'checked': checked,
        'checkedAt': checked ? FieldValue.serverTimestamp() : null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'phone',
      });

  Future<void> deleteItem(String listId, String itemId) => _items(listId).doc(itemId).delete();

  /// Przywrócenie usuniętego produktu (przycisk "Cofnij").
  Future<void> restoreItem(String listId, ShoppingItem item) => _items(listId).doc(item.id).set({
        'name': item.name,
        'checked': item.checked,
        'createdAt': item.createdAt != null ? Timestamp.fromDate(item.createdAt!) : FieldValue.serverTimestamp(),
        'checkedAt': item.checkedAt != null ? Timestamp.fromDate(item.checkedAt!) : null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'phone',
      });

  Future<int> deleteChecked(String listId) async {
    final checked = await _items(listId).where('checked', isEqualTo: true).get();
    await _inChunks(checked.docs, (batch, ref) => batch.delete(ref));
    return checked.docs.length;
  }

  Future<void> uncheckAll(String listId) async {
    final checked = await _items(listId).where('checked', isEqualTo: true).get();
    await _inChunks(
      checked.docs,
      (batch, ref) => batch.update(ref, {
        'checked': false,
        'checkedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'phone',
      }),
    );
  }
}
