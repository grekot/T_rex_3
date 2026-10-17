import 'package:cloud_firestore/cloud_firestore.dart';

/// Coś, co się udostępnia znajomym: lista zakupów albo miejsce.
/// W Firestore: ownerId, members (uid osób z dostępem), memberEmails (uid -> e-mail).
abstract class Shared {
  String get id;
  String get name;
  String get ownerId;
  List<String> get members;
  Map<String, String> get memberEmails;

  bool isOwner(String uid) => ownerId == uid;
  bool get isShared => members.length > 1;
  String get ownerEmail => memberEmails[ownerId] ?? '';
}

/// Znajomy - osoba, której można szybko udostępnić listę albo miejsce
class Friend {
  const Friend({required this.uid, required this.email, this.name = ''});

  final String uid;
  final String email;

  /// opcjonalna nazwa, np. "Żona"
  final String name;

  String get label => name.isNotEmpty ? name : email;

  factory Friend.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Friend(
      uid: doc.id,
      email: (data['email'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
    );
  }
}

/// Pomocnicze do czytania dokumentów
List<String> parseMembers(Object? value) => ((value as List?) ?? const []).whereType<String>().toList();

Map<String, String> parseMemberEmails(Object? value) =>
    value is Map ? value.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) : const {};

DateTime? parseDate(Object? value) => value is Timestamp ? value.toDate() : null;
