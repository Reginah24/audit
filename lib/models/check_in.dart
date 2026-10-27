import 'package:cloud_firestore/cloud_firestore.dart';

class CheckIn {
  final String id;
  final String employeeId;
  final String employeeName;
  final String date; // yyyy-MM-dd, so "today" is a simple string match
  final Timestamp timestamp;

  /// 'scan', 'tap' (at the till), 'self' (own phone) or 'paper' (copied
  /// later from the signed paper list — the time of the meal isn't known).
  final String method;

  CheckIn({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.timestamp,
    this.method = 'tap',
  });

  factory CheckIn.fromFirestore(String id, Map<String, dynamic> data) {
    return CheckIn(
      id: id,
      employeeId: (data['employeeId'] ?? '').toString(),
      employeeName: (data['employeeName'] ?? '').toString(),
      date: (data['date'] ?? '').toString(),
      timestamp: (data['timestamp'] as Timestamp?) ?? Timestamp.now(),
      method: (data['method'] ?? 'tap').toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'date': date,
      'timestamp': timestamp,
      'method': method,
    };
  }

  bool get fromPaper => method == 'paper';

  String get methodLabel => switch (method) {
        'scan' => 'Scanned pass',
        'self' => 'Own phone',
        'paper' => 'Signed paper list',
        _ => 'Tapped at till',
      };
}

/// A meal the restaurant removed (wrong name tapped, etc.). Kept forever
/// and shown on the office's report, so a removal can't go unnoticed.
class VoidedCheckIn {
  final CheckIn original;
  final Timestamp voidedAt;
  final String voidedBy;
  final String reason;

  VoidedCheckIn({
    required this.original,
    required this.voidedAt,
    required this.voidedBy,
    required this.reason,
  });

  factory VoidedCheckIn.fromFirestore(String id, Map<String, dynamic> data) {
    return VoidedCheckIn(
      original: CheckIn.fromFirestore(id, data),
      voidedAt: (data['voidedAt'] as Timestamp?) ?? Timestamp.now(),
      voidedBy: (data['voidedBy'] ?? '').toString(),
      reason: (data['reason'] ?? '').toString(),
    );
  }
}
