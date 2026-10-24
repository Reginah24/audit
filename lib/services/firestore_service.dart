import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../dates.dart';
import '../text_match.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/check_in.dart';

/// Result of trying to record a meal.
enum MealResult { logged, alreadyLogged }

/// Everything the report screens need for one day or one month.
class ReportData {
  final List<Employee> employees;
  final List<CheckIn> checkIns;
  final List<Attendance> attendance;
  final List<VoidedCheckIn> voided;

  ReportData(this.employees, this.checkIns, this.attendance, this.voided);
}

/// Handles all reads/writes to Firestore for the check-in app.
/// Collections (who may do what is enforced in firestore.rules):
///  - employees: the government's staff roster
///  - badges: the secret key printed on each employee's badge
///  - checkins: one document per meal eaten, id `<date>_<employeeId>`
///  - voided_checkins: meals the restaurant removed, kept permanently
///  - attendance: "will I eat here that day?", id `<date>_<employeeId>`
///  - duplicate_attempts: blocked second meals, for the Alerts tab
class FirestoreService {
  final FirebaseFirestore _db;

  /// Restaurant and office screens use the default app; the employee
  /// screen passes the employee app's database (see auth.dart).
  FirestoreService([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  static String todayKey() => dateKey(DateTime.now());

  /// Email of whoever is signed in on this connection — stored with every
  /// change so the office can see who did what.
  String get _signedInEmail =>
      FirebaseAuth.instanceFor(app: _db.app).currentUser?.email ?? '';

  /// Loads the full employee roster once. With 50-200 employees this is
  /// small enough to keep in memory and filter locally as the cashier types,
  /// which is faster than a Firestore query on every keystroke.
  Future<List<Employee>> fetchEmployees() async {
    final snapshot = await _db.collection('employees').orderBy('name').get();
    return snapshot.docs
        .map((doc) => Employee.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  Future<Employee?> fetchEmployee(String id) async {
    final doc = await _db.collection('employees').doc(id).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return Employee.fromFirestore(doc.id, data);
  }

  /// Earlier versions kept employees' PINs readable in the employees
  /// collection. Run by the restaurant account on sign-in to wipe any that
  /// are left; PINs now live only in Firebase Authentication.
  Future<void> removeLegacyPins() async {
    final snapshot = await _db.collection('employees').get();
    final stale = snapshot.docs.where((d) => d.data().containsKey('pin'));
    if (stale.isEmpty) return;
    final batch = _db.batch();
    for (final doc in stale) {
      batch.update(doc.reference, {'pin': FieldValue.delete()});
    }
    await batch.commit();
  }

  /// Live stream of today's check-ins, newest first. Used both to show the
  /// running count and to power the correction buttons on the staff screen.
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

  /// Records a meal for [employee] today. [method] is 'scan' or 'tap' and
  /// shows up in the report. The time is set by Firebase's server, not the
  /// tablet, so it can't be backdated. A second meal on the same day is
  /// refused and logged for the Alerts tab — the check-in's id is
  /// `<date>_<employeeId>`, so even two tablets scanning at the same
  /// moment can't both write one.
  Future<MealResult> recordMeal(Employee employee, String method) async {
    final date = todayKey();

    // Check-ins from before ids were per-day have random ids, so look for
    // those by field as well.
    final existing = await _db
        .collection('checkins')
        .where('employeeId', isEqualTo: employee.id)
        .where('date', isEqualTo: date)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      await _logDuplicateAttempt(employee, method);
      return MealResult.alreadyLogged;
    }

    final ref = _db.collection('checkins').doc('${date}_${employee.id}');
    final created = await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.set(ref, {
        'employeeId': employee.id,
        'employeeName': employee.name,
        'department': employee.department,
        'date': date,
        'timestamp': FieldValue.serverTimestamp(),
        'method': method,
        'recordedBy': _signedInEmail,
      });
      return true;
    });

    if (!created) {
      await _logDuplicateAttempt(employee, method);
      return MealResult.alreadyLogged;
    }
    return MealResult.logged;
  }

  /// Removes a meal recorded by mistake. The meal isn't simply deleted:
  /// a permanent copy goes to voided_checkins with who removed it, when,
  /// and why, and the office sees it on the report. The database refuses
  /// a removal that doesn't leave that record.
  Future<void> voidCheckIn(CheckIn checkIn, String reason) async {
    final batch = _db.batch();
    batch.set(_db.collection('voided_checkins').doc(checkIn.id), {
      ...checkIn.toFirestore(),
      'voidedAt': FieldValue.serverTimestamp(),
      'voidedBy': _signedInEmail,
      'reason': reason,
    });
    batch.delete(_db.collection('checkins').doc(checkIn.id));
    await batch.commit();
  }

  /// Adds the people in [roster] who aren't already in the database
  /// (matched by name, ignoring capitals and spaces), so pressing the load
  /// button twice can't create duplicates. Returns how many were added.
  Future<int> seedEmployees(List<Map<String, String>> roster) async {
    final existing =
        (await fetchEmployees()).map((e) => normalizeName(e.name)).toSet();
    final batch = _db.batch();
    var added = 0;
    for (final person in roster) {
      final name = tidyName(person['name'] ?? '');
      if (name.length < 2 || !existing.add(normalizeName(name))) continue;
      batch.set(_db.collection('employees').doc(),
          _newPerson(name, person['department'] ?? '', 'roster'));
      added++;
    }
    if (added > 0) await batch.commit();
    return added;
  }

  /// "  regina   ANTHONY " and "Regina Anthony" are the same person.
  static String normalizeName(String s) => foldText(s);

  /// Collapses extra spaces; keeps the capitals the cashier typed.
  static String tidyName(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, dynamic> _newPerson(
          String name, String department, String source) =>
      {
        'name': name,
        'department': tidyName(department),
        'addedBy': _signedInEmail,
        'addedAt': FieldValue.serverTimestamp(),
        'source': source,
      };

  /// Adds one person at the restaurant counter (someone missing from the
  /// office's list) and gives them a pass straight away. The database
  /// records who added them and when, and the office report lists them.
  Future<Employee> addEmployee(String name, String department) async {
    final ref = _db.collection('employees').doc();
    final data = _newPerson(tidyName(name), department, 'counter');
    await ref.set(data);
    await ensureBadgeKeys([
      Employee(id: ref.id, name: data['name'], department: data['department'])
    ]);
    return Employee(
      id: ref.id,
      name: data['name'],
      department: data['department'],
      addedBy: _signedInEmail,
      addedAt: DateTime.now(),
      source: 'counter',
    );
  }

  /// Records a blocked duplicate attempt for the manager's Alerts tab.
  Future<void> _logDuplicateAttempt(Employee employee, String source) async {
    await _db.collection('duplicate_attempts').add({
      'employeeId': employee.id,
      'employeeName': employee.name,
      'date': todayKey(),
      'timestamp': FieldValue.serverTimestamp(),
      'source': source, // 'scan' or 'tap'
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

  // ---- Badges ----------------------------------------------------------

  static String _newBadgeKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(10, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Every employee's current badge key, keyed by employee id.
  Future<Map<String, String>> fetchBadgeKeys() async {
    final snapshot = await _db.collection('badges').get();
    return {
      for (final doc in snapshot.docs)
        doc.id: (doc.data()['key'] ?? '').toString(),
    };
  }

  Future<String?> fetchBadgeKey(String employeeId) async {
    final doc = await _db.collection('badges').doc(employeeId).get();
    return doc.data()?['key'] as String?;
  }

  /// Makes sure everyone in [employees] has a badge key, creating the
  /// missing ones. Existing keys are kept, so printing again doesn't cancel
  /// badges already handed out.
  Future<Map<String, String>> ensureBadgeKeys(List<Employee> employees) async {
    final keys = await fetchBadgeKeys();
    final batch = _db.batch();
    var created = 0;
    for (final e in employees) {
      if ((keys[e.id] ?? '').isNotEmpty) continue;
      final key = _newBadgeKey();
      keys[e.id] = key;
      batch.set(_db.collection('badges').doc(e.id), {'key': key});
      created++;
    }
    if (created > 0) await batch.commit();
    return keys;
  }

  /// For a lost badge: gives the person a new key, so the old card stops
  /// working the moment this returns.
  Future<String> replaceBadgeKey(String employeeId) async {
    final key = _newBadgeKey();
    await _db.collection('badges').doc(employeeId).set({'key': key});
    return key;
  }

  // ---- Attendance ------------------------------------------------------

  /// Saves whether [employee] will eat at the restaurant on [date].
  /// [setBy] is 'employee' when they answered themselves, 'staff' when the
  /// restaurant marked it (e.g. from the office's list of people on leave).
  Future<void> setAttendance(
      Employee employee, String date, bool coming, String setBy) async {
    await _db.collection('attendance').doc('${date}_${employee.id}').set({
      'employeeId': employee.id,
      'employeeName': employee.name,
      'date': date,
      'coming': coming,
      'setBy': setBy,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _signedInEmail,
    });
  }

  /// Removes an answer so the person shows as "no answer" again.
  Future<void> clearAttendance(String employeeId, String date) async {
    await _db.collection('attendance').doc('${date}_$employeeId').delete();
  }

  Future<Attendance?> fetchAttendance(String employeeId, String date) async {
    final doc =
        await _db.collection('attendance').doc('${date}_$employeeId').get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return Attendance.fromFirestore(data);
  }

  /// Live answers for one day, keyed by employee id.
  Stream<Map<String, Attendance>> streamAttendance(String date) {
    return _db
        .collection('attendance')
        .where('date', isEqualTo: date)
        .snapshots()
        .map((snapshot) => {
              for (final doc in snapshot.docs)
                (doc.data()['employeeId'] ?? '').toString():
                    Attendance.fromFirestore(doc.data()),
            });
  }

  // ---- Employee self-service -------------------------------------------

  /// Finds people by name for the "my meals" screen, ignoring capitals,
  /// accents, spacing and word order: "PRINCESS" finds "Princess Uwase".
  /// An exact full-name match comes back on its own; otherwise every
  /// person whose name contains all the typed words.
  Future<List<Employee>> findEmployeesByName(String typed) async {
    if (foldText(typed).isEmpty) return const [];
    final all = await fetchEmployees();
    final exact = all.where((e) => sameName(e.name, typed)).toList();
    if (exact.isNotEmpty) return exact;
    return all.where((e) => nameMatches(e.name, typed)).toList();
  }

  /// All of an employee's check-ins for the current calendar month, oldest
  /// first, for the "my record" screen.
  Future<List<CheckIn>> fetchMyCheckInsThisMonth(String employeeId) async {
    final monthStart = DateFormat('yyyy-MM').format(DateTime.now());

    final snapshot = await _db
        .collection('checkins')
        .where('employeeId', isEqualTo: employeeId)
        .get();

    return snapshot.docs
        .map((doc) => CheckIn.fromFirestore(doc.id, doc.data()))
        .where((c) => c.date.startsWith(monthStart))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // ---- Reports ---------------------------------------------------------

  /// Everyone on the roster, plus every check-in, attendance answer and
  /// correction between [start] and [end] (inclusive) — the raw material
  /// for both the daily and the monthly report.
  Future<ReportData> fetchReport(DateTime start, DateTime end) async {
    final startKey = dateKey(start);
    final endKey = dateKey(end);

    Future<QuerySnapshot<Map<String, dynamic>>> inRange(String collection) =>
        _db
            .collection(collection)
            .where('date', isGreaterThanOrEqualTo: startKey)
            .where('date', isLessThanOrEqualTo: endKey)
            .get();

    final (employees, checkIns, attendance, voided) = await (
      fetchEmployees(),
      inRange('checkins'),
      inRange('attendance'),
      inRange('voided_checkins'),
    ).wait;

    return ReportData(
      employees,
      checkIns.docs
          .map((doc) => CheckIn.fromFirestore(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
      attendance.docs
          .map((doc) => Attendance.fromFirestore(doc.data()))
          .toList(),
      voided.docs
          .map((doc) => VoidedCheckIn.fromFirestore(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.voidedAt.compareTo(b.voidedAt)),
    );
  }
}
