import 'models.dart';

/// Klucz e-maila w książce adresowej (emails/{klucz}) - taki sam liczą reguły Firestore
String emailKey(String email) => email.trim().toLowerCase();

/// Zmiany udostępnienia wynikające z zaznaczeń w oknie "Udostępnij".
class SharingChanges {
  const SharingChanges(this.add, this.remove);

  /// uid -> e-mail osób do dopisania
  final Map<String, String> add;

  /// uid osób do usunięcia z listy
  final Set<String> remove;

  bool get isEmpty => add.isEmpty && remove.isEmpty;
}

/// [selected] - uid zaznaczonych osób (znajomi + dotychczasowi członkowie).
/// Właściciel może dopisywać i usuwać; pozostali tylko dopisywać.
/// Właściciela i samego siebie nie da się usunąć tym oknem (do tego jest "Opuść listę").
/// [list] - lista zakupów albo miejsce (wszystko, co się udostępnia).
SharingChanges planSharing({
  required Shared list,
  required String myUid,
  required Set<String> selected,
  required Map<String, String> knownEmails,
}) {
  final current = list.members.toSet();
  final add = <String, String>{};
  for (final uid in selected) {
    if (!current.contains(uid)) add[uid] = knownEmails[uid] ?? '';
  }
  final remove = <String>{};
  if (list.isOwner(myUid)) {
    for (final uid in current) {
      if (uid != list.ownerId && uid != myUid && !selected.contains(uid)) remove.add(uid);
    }
  }
  return SharingChanges(add, remove);
}

/// Osoby z moich list, których nie mam jeszcze w znajomych (np. ktoś udostępnił mi listę)
List<Friend> suggestedFriends({
  required Iterable<Shared> lists,
  required String myUid,
  required Iterable<Friend> friends,
}) {
  final known = friends.map((f) => f.uid).toSet()..add(myUid);
  final out = <String, Friend>{};
  for (final list in lists) {
    for (final uid in list.members) {
      final email = list.memberEmails[uid] ?? '';
      if (known.contains(uid) || email.isEmpty || out.containsKey(uid)) continue;
      out[uid] = Friend(uid: uid, email: email);
    }
  }
  return out.values.toList()..sort((a, b) => a.email.compareTo(b.email));
}
