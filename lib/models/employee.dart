import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final String id;
  final String name;
  final String department;

  /// Whether this person has created their PIN yet. The PIN itself lives
  /// in Firebase Authentication, never in the database.
  final bool pinSet;

  /// Who added this person and when ('roster' = loaded from the office's
  /// list, 'counter' = added at the restaurant). Older records have none.
  final String? addedBy;
  final DateTime? addedAt;
  final String? source;

  Employee({
    required this.id,
    required this.name,
    required this.department,
    this.pinSet = false,
    this.addedBy,
    this.addedAt,
    this.source,
  });

  bool get addedAtCounter => source == 'counter';

  factory Employee.fromFirestore(String id, Map<String, dynamic> data) {
    return Employee(
      id: id,
      name: (data['name'] ?? '').toString(),
      department: (data['department'] ?? '').toString(),
      pinSet: data['pinSet'] == true,
      addedBy: data['addedBy'] as String?,
      addedAt: (data['addedAt'] as Timestamp?)?.toDate(),
      source: data['source'] as String?,
    );
  }
}
