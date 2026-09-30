import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/employee.dart';
import '../models/check_in.dart';

/// Handles all reads/writes to Firestore for the check-in app.
/// Two collections:
///  - employees: the government's staff roster, loaded once by an admin
///  - checkins: one document per meal logged
class FirestoreService {
  final _db = FirebaseFirestore.instance;

  static String todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Loads the full employee roster once. With 50-200 employees this is
  /// small enough to keep in memory and filter locally as the cashier types,
  /// which is faster than a Firestore query on every keystroke.
  Future<List<Employee>> fetchEmployees() async {
    final snapshot = await _db.collection('employees').orderBy('name').get();
    return snapshot.docs
        .map((doc) => Employee.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  /// Live stream of today's check-ins, newest first. Used both to show the
  /// running count and to power the "undo last few" strip on the home screen.
  Stream<List<CheckIn>> streamTodayCheckins() {
    return _db
        .collection('checkins')
        .where('date', isEqualTo: todayKey())
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CheckIn.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  /// Logs a meal for [employee]. Returns false without writing if that
  /// employee already has a check-in today, so a double-tap can't inflate
  /// the count. Blocked attempts are logged for the manager's Alerts tab.
  Future<bool> logMeal(Employee employee, List<CheckIn> todaysCheckins) async {
    final alreadyLogged =
        todaysCheckins.any((c) => c.employeeId == employee.id);
    if (alreadyLogged) {
      await _logDuplicateAttempt(employee, 'till');
      return false;
    }

    await _db.collection('checkins').add({
      'employeeId': employee.id,
      'employeeName': employee.name,
      'date': todayKey(),
      'timestamp': Timestamp.now(),
    });
    return true;
  }

  /// Removes a check-in — used by the undo strip when a cashier taps the
  /// wrong name.
  Future<void> deleteCheckIn(String checkInId) async {
    await _db.collection('checkins').doc(checkInId).delete();
  }

  /// One-time bulk load of the employee roster. Writes everything in a
  /// single batch (Firestore allows up to 500 writes per batch, well above
  /// a 200-person roster). Safe to call more than once, but running it
  /// twice will create duplicate employee documents with the same name —
  /// so only tap the seed button once per roster.
  Future<int> seedEmployees(List<Map<String, String>> roster) async {
    final batch = _db.batch();
    for (final person in roster) {
      final docRef = _db.collection('employees').doc();
      batch.set(docRef, {
        'name': person['name'],
        'department': person['department'],
      });
    }
    await batch.commit();
    return roster.length;
  }

  /// Self-service check-in from the employee's own phone (after they've
  /// unlocked their record with their PIN). Returns false without writing
  /// if they already have a check-in today, same duplicate protection as
  /// the manager's tablet flow. Blocked attempts are logged separately so
  /// the manager can review who tried to double-log.
  Future<bool> selfLogMeal(Employee employee) async {
    final existing = await _db
        .collection('checkins')
        .where('employeeId', isEqualTo: employee.id)
        .where('date', isEqualTo: todayKey())
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      await _logDuplicateAttempt(employee, 'self-service');
      return false;
    }

    await _db.collection('checkins').add({
      'employeeId': employee.id,
      'employeeName': employee.name,
      'date': todayKey(),
      'timestamp': Timestamp.now(),
    });
    return true;
  }

  /// Records a blocked duplicate attempt for the manager's Alerts tab.
  Future<void> _logDuplicateAttempt(Employee employee, String source) async {
    await _db.collection('duplicate_attempts').add({
      'employeeId': employee.id,
      'employeeName': employee.name,
      'date': todayKey(),
      'timestamp': Timestamp.now(),
      'source': source, // 'self-service' or 'till'
    });
  }

  /// Live stream of today's blocked duplicate attempts, newest first.
  Stream<List<Map<String, dynamic>>> streamTodayDuplicateAttempts() {
    return _db
        .collection('duplicate_attempts')
        .where('date', isEqualTo: todayKey())
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => d.data()).toList());
  }

  /// Finds an employee by exact name match, for the "my record" lookup
  /// screen. Returns null if no one matches.
  Future<Employee?> findEmployeeByName(String name) async {
    final snapshot = await _db
        .collection('employees')
        .where('name', isEqualTo: name.trim())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Employee.fromFirestore(
        snapshot.docs.first.id, snapshot.docs.first.data());
  }

  /// Sets a PIN for an employee the first time they use the lookup screen.
  Future<void> setPin(String employeeId, String pin) async {
    await _db.collection('employees').doc(employeeId).update({'pin': pin});
  }

  /// All of an employee's check-ins for the current calendar month, oldest
  /// first, for the "my record" screen.
  Future<List<CheckIn>> fetchMyCheckInsThisMonth(String employeeId) async {
    final now = DateTime.now();
    final monthStart = DateFormat('yyyy-MM').format(now); // e.g. "2026-09"

    final snapshot = await _db
        .collection('checkins')
        .where('employeeId', isEqualTo: employeeId)
        .orderBy('date')
        .get();

    return snapshot.docs
        .map((doc) => CheckIn.fromFirestore(doc.id, doc.data()))
        .where((c) => c.date.startsWith(monthStart))
        .toList();
  }

  /// Returns all check-ins between [start] and [end] (inclusive), grouped
  /// by employee, for the month-end invoice export.
  Future<Map<String, List<CheckIn>>> fetchCheckInsForRange(
      DateTime start, DateTime end) async {
    final startKey = DateFormat('yyyy-MM-dd').format(start);
    final endKey = DateFormat('yyyy-MM-dd').format(end);

    final snapshot = await _db
        .collection('checkins')
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .orderBy('date')
        .get();

    final checkIns =
        snapshot.docs.map((doc) => CheckIn.fromFirestore(doc.id, doc.data()));

    final grouped = <String, List<CheckIn>>{};
    for (final c in checkIns) {
      grouped.putIfAbsent(c.employeeName, () => []).add(c);
    }
    return grouped;
  }
}
