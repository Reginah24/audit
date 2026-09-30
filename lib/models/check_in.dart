import 'package:cloud_firestore/cloud_firestore.dart';

class CheckIn {
  final String id;
  final String employeeId;
  final String employeeName;
  final String date; // yyyy-MM-dd, so "today" is a simple string match
  final Timestamp timestamp;

  CheckIn({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.timestamp,
  });

  factory CheckIn.fromFirestore(String id, Map<String, dynamic> data) {
    return CheckIn(
      id: id,
      employeeId: (data['employeeId'] ?? '').toString(),
      employeeName: (data['employeeName'] ?? '').toString(),
      date: (data['date'] ?? '').toString(),
      timestamp: (data['timestamp'] as Timestamp?) ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'date': date,
      'timestamp': timestamp,
    };
  }
}
