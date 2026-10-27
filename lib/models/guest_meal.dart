import 'package:cloud_firestore/cloud_firestore.dart';

/// A meal for a visitor who isn't office staff ("abashitsi"). Counted in
/// the day's total, but kept apart from staff meals.
class GuestMeal {
  final String id;
  final String date; // yyyy-MM-dd
  final String name;

  /// Optional: who invited them, their organisation, etc.
  final String note;
  final Timestamp timestamp;
  final String recordedBy;

  GuestMeal({
    required this.id,
    required this.date,
    required this.name,
    this.note = '',
    required this.timestamp,
    this.recordedBy = '',
  });

  factory GuestMeal.fromFirestore(String id, Map<String, dynamic> data) {
    return GuestMeal(
      id: id,
      date: (data['date'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      note: (data['note'] ?? '').toString(),
      timestamp: (data['timestamp'] as Timestamp?) ?? Timestamp.now(),
      recordedBy: (data['recordedBy'] ?? '').toString(),
    );
  }
}
