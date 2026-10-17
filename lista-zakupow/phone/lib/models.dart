import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wspolne/wspolne.dart';

class ShoppingList extends Shared {
  ShoppingList({
    required this.id,
    required this.name,
    required this.ownerId,
    this.members = const [],
    this.memberEmails = const {},
    this.createdAt,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final String ownerId;

  /// uid osób z dostępem do listy (właściciel też tu jest)
  @override
  final List<String> members;

  /// uid -> e-mail, do wyświetlania, kto ma dostęp (starsze listy mogą go nie mieć)
  @override
  final Map<String, String> memberEmails;
  final DateTime? createdAt;

  factory ShoppingList.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ShoppingList(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      ownerId: (data['ownerId'] as String?) ?? '',
      members: parseMembers(data['members']),
      memberEmails: parseMemberEmails(data['memberEmails']),
      createdAt: parseDate(data['createdAt']),
    );
  }
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.checked,
    this.createdAt,
    this.checkedAt,
  });

  final String id;
  final String name;
  final bool checked;
  final DateTime? createdAt;
  final DateTime? checkedAt;

  factory ShoppingItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ShoppingItem(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      checked: (data['checked'] as bool?) ?? false,
      createdAt: parseDate(data['createdAt']),
      checkedAt: parseDate(data['checkedAt']),
    );
  }
}
