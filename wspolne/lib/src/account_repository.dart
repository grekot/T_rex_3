import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';
import 'sharing.dart';

enum AddFriendResult { added, alreadyFriend, notFound, self }

/// Konto, znajomi i udostępnianie - wspólne dla Zakupów i Powrotu.
/// Repozytoria aplikacji (listy, miejsca) dziedziczą po tej klasie.
class AccountRepository {
  AccountRepository(this.uid, this.email, {FirebaseFirestore? db}) : db = db ?? FirebaseFirestore.instance;

  final String uid;
  final String email;
  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get _friends => db.collection('users').doc(uid).collection('friends');

  /// Wpis w książce adresowej, żeby inni mogli mnie dodać do znajomych po e-mailu
  Future<void> registerEmail() => db.collection('emails').doc(emailKey(email)).set({
        'uid': uid,
        'email': emailKey(email),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Stream<List<Friend>> watchFriends() => _friends.snapshots().map((snap) {
        return snap.docs.map(Friend.fromDoc).toList()
          ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      });

  /// Zwraca wynik i dodanego znajomego (gdy znaleziono konto)
  Future<(AddFriendResult, Friend?)> addFriend(String friendEmail, {String name = ''}) async {
    final key = emailKey(friendEmail);
    if (key == emailKey(email)) return (AddFriendResult.self, null);
    final entry = await db.collection('emails').doc(key).get();
    final friendUid = entry.data()?['uid'] as String?;
    if (!entry.exists || friendUid == null) return (AddFriendResult.notFound, null);
    final existing = await _friends.doc(friendUid).get();
    final friend = Friend(uid: friendUid, email: key, name: name.trim());
    await _friends.doc(friendUid).set({
      'email': key,
      'name': name.trim(),
      'addedAt': FieldValue.serverTimestamp(),
    });
    return (existing.exists ? AddFriendResult.alreadyFriend : AddFriendResult.added, friend);
  }

  Future<void> addKnownFriend(Friend friend) => _friends.doc(friend.uid).set({
        'email': friend.email,
        'name': friend.name,
        'addedAt': FieldValue.serverTimestamp(),
      });

  Future<void> renameFriend(String friendUid, String name) => _friends.doc(friendUid).update({'name': name.trim()});

  Future<void> removeFriend(String friendUid) => _friends.doc(friendUid).delete();

  /// Dopisuje i usuwa osoby (arrayUnion i arrayRemove muszą iść osobno).
  /// [collection]: 'lists' albo 'places'.
  Future<void> applySharing(String collection, String id, SharingChanges changes) async {
    final ref = db.collection(collection).doc(id);
    if (changes.add.isNotEmpty) {
      await ref.update({
        'members': FieldValue.arrayUnion(changes.add.keys.toList()),
        for (final e in changes.add.entries) FieldPath(['memberEmails', e.key]): e.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (changes.remove.isNotEmpty) {
      await ref.update({
        'members': FieldValue.arrayRemove(changes.remove.toList()),
        for (final r in changes.remove) FieldPath(['memberEmails', r]): FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Wypisanie się z cudzej listy albo cudzego miejsca
  Future<void> leave(String collection, String id) => db.collection(collection).doc(id).update({
        'members': FieldValue.arrayRemove([uid]),
        FieldPath(['memberEmails', uid]): FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
