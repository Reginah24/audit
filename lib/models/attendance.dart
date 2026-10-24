/// Whether an employee said they will eat at the restaurant on a given day.
/// This is what replaces the office's paper list — the restaurant reads the
/// "yes" count to know how many to cook for.
class Attendance {
  final String employeeId;
  final String employeeName;
  final String date; // yyyy-MM-dd
  final bool coming;
  final String setBy; // 'employee' or 'staff'

  Attendance({
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.coming,
    required this.setBy,
  });

  factory Attendance.fromFirestore(Map<String, dynamic> data) {
    return Attendance(
      employeeId: (data['employeeId'] ?? '').toString(),
      employeeName: (data['employeeName'] ?? '').toString(),
      date: (data['date'] ?? '').toString(),
      coming: data['coming'] == true,
      setBy: (data['setBy'] ?? 'employee').toString(),
    );
  }
}
