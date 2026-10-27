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
  final bool active;

  /// Names this person had before the office corrected them, so loading
  /// the prepared list doesn't add the old spelling back as a new person.
  final List<String> formerNames;

  /// Who took this person off the list with the Remove button. Loading
  /// the prepared list won't bring them back.
  final String? removedBy;

  Employee({
    required this.id,
    required this.name,
    required this.department,
    this.pinSet = false,
    this.addedBy,
    this.addedAt,
    this.source,
    this.active = true,
    this.formerNames = const [],
    this.removedBy,
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
      active: data['active'] != false,
      formerNames: [
        for (final n in (data['formerNames'] as List?) ?? const []) '$n'
      ],
      removedBy: data['removedBy'] as String?,
    );
  }
}
