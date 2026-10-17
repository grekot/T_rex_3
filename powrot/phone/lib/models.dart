import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wspolne/wspolne.dart';

/// Miejsce zapisane zegarkiem w aplikacji Powrót (np. gdzie stoi auto)
class Place extends Shared {
  Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.ownerId,
    this.members = const [],
    this.memberEmails = const {},
    this.savedAt,
  });

  @override
  final String id;
  @override
  final String name;
  final double lat;
  final double lon;
  @override
  final String ownerId;
  @override
  final List<String> members;
  @override
  final Map<String, String> memberEmails;
  final DateTime? savedAt;

  factory Place.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Place(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lon: (data['lon'] as num?)?.toDouble() ?? 0,
      ownerId: (data['ownerId'] as String?) ?? '',
      members: parseMembers(data['members']),
      memberEmails: parseMemberEmails(data['memberEmails']),
      savedAt: parseDate(data['savedAt']) ?? parseDate(data['createdAt']),
    );
  }
}
