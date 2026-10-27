import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../dates.dart';
import '../text_match.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/check_in.dart';
import '../models/guest_meal.dart';

/// Result of trying to record a meal.
enum MealResult { logged, alreadyLogged }

/// Thrown when adding or renaming would put the same name on the list twice.
class NameTaken implements Exception {
  final Employee existing;
  NameTaken(this.existing);

  @override
  String toString() => existing.active
      ? '${existing.name} is already on the list'
          '${existing.department.isEmpty ? '' : ' (${existing.department})'}. '
          'Search for the name instead of adding it again.'
      : '${existing.name} was removed from the list earlier. '
          'Ask the office to bring them back instead of adding them again.';
}

/// One working day in a customer's history: what they said, and whether
/// they ate.
typedef DayHistory = ({String date, Attendance? answer, CheckIn? meal});

/// Everything the report screens need for one day or one month.
class ReportData {
  final List<Employee> employees;
  final List<CheckIn> checkIns;
  final List<Attendance> attendance;
  final List<VoidedCheckIn> voided;

  /// Each week's roster in the range, keyed by its Monday (yyyy-MM-dd).
  final Map<String, Set<String>> rosters;

  final List<GuestMeal> guests;

  ReportData(this.employees, this.checkIns, this.attendance, this.voided,
      [this.rosters = const {}, this.guests = const []]);
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
    final all = await fetchAllEmployees();
    return all.where((employee) => employee.active).toList();
  }

  Future<List<Employee>> fetchAllEmployees() async {
    final snapshot = await _db.collection('employees').orderBy('name').get();
    return snapshot.docs
        .map((doc) => Employee.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  Future<Employee?> fetchEmployee(String id) async {
    final doc = await _db.collection('employees').doc(id).get();
    final data = doc.data();
    if (!doc.exists || data == null || data['active'] == false) return null;
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
      batch.set(
          _db.collection('employees').doc(),
          _newPerson(name, person['department'] ?? '', 'roster')
            ..['active'] = true);
      added++;
    }
    if (added > 0) await batch.commit();
    return added;
  }

  /// Adds everyone in [roster] who isn't in the database yet and updates
  /// departments. Nobody is taken off the list here: people added at the
  /// counter stay, and the office removes people with the Remove button.
  /// A name that is in the database more than once (from older versions)
  /// is cleaned up — one record is kept, the others switched off. Returns
  /// how many were added.
  Future<int> replaceRoster(List<Map<String, String>> roster) async {
    final all = await fetchAllEmployees();
    final byName = <String, List<Employee>>{};
    for (final employee in all) {
      byName.putIfAbsent(normalizeName(employee.name), () => []).add(employee);
    }
    final renamedFrom = {
      for (final e in all)
        for (final n in e.formerNames) normalizeName(n),
    };
    final writes =
        <(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>)>[];
    final seen = <String>{};
    var added = 0;

    for (final person in roster) {
      final name = tidyName(person['name'] ?? '');
      final key = normalizeName(name);
      if (name.length < 2 || !seen.add(key)) continue;
      final department = tidyName(person['department'] ?? '');
      final existing = byName[key];
      if (existing == null) {
        // The office corrected this spelling; don't add the old one back.
        if (renamedFrom.contains(key)) continue;
        writes.add((
          _db.collection('employees').doc(),
          _newPerson(name, department, 'roster'),
        ));
        added++;
      } else {
        final keep = _keeper(existing);
        writes.add((
          _db.collection('employees').doc(keep.id),
          {
            if (keep.removedBy == null) 'active': true,
            if (department.isNotEmpty) 'department': department,
          },
        ));
      }
    }

    for (final group in byName.values.where((g) => g.length > 1)) {
      final keep = _keeper(group);
      for (final e in group.where((e) => e.id != keep.id && e.active)) {
        writes.add((_db.collection('employees').doc(e.id), {'active': false}));
      }
    }

    for (var i = 0; i < writes.length; i += 450) {
      final batch = _db.batch();
      for (final (ref, data) in writes.skip(i).take(450)) {
        if (data.isNotEmpty) batch.set(ref, data, SetOptions(merge: true));
      }
      await batch.commit();
    }
    return added;
  }

  /// Of several records with one name, the one to keep: the one the person
  /// made a PIN on, otherwise the oldest.
  static Employee _keeper(List<Employee> sameName) {
    final sorted = [...sameName]..sort((a, b) {
        if (a.pinSet != b.pinSet) return a.pinSet ? -1 : 1;
        if (a.active != b.active) return a.active ? -1 : 1;
        final at = a.addedAt, bt = b.addedAt;
        if (at == null || bt == null) return at == null ? -1 : 1;
        return at.compareTo(bt);
      });
    return sorted.first;
  }

  /// "  regina   ANTHONY " and "Anthony Regina" are the same person.
  static String normalizeName(String s) => nameKey(s);

  /// Anyone — on the list or removed — already using [name] (or who used
  /// to, before a correction), other than [except].
  Future<Employee?> _nameTaken(String name, {String? except}) async {
    final all = await fetchAllEmployees();
    for (final e in all) {
      if (e.id == except) continue;
      if (sameName(e.name, name) ||
          e.formerNames.any((n) => sameName(n, name))) {
        return e;
      }
    }
    return null;
  }

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
        'active': true,
      };

  /// Adds one person — to the office roster ([source] 'roster') or at the
  /// restaurant counter ('counter'). Refuses a name that is already in the
  /// database, even for someone removed from the list.
  Future<Employee> addEmployee(String name, String department,
      {String source = 'roster'}) async {
    final taken = await _nameTaken(name);
    if (taken != null) throw NameTaken(taken);
    final ref = _db.collection('employees').doc();
    final data = _newPerson(tidyName(name), department, source);
    await ref.set(data);
    return Employee(
      id: ref.id,
      name: data['name'],
      department: data['department'],
      addedBy: _signedInEmail,
      addedAt: DateTime.now(),
      source: source,
    );
  }

  Future<void> updateEmployeeDepartment(
      Employee employee, String department) async {
    await _db.collection('employees').doc(employee.id).update({
      'department': tidyName(department),
    });
  }

  /// Corrects a spelling. Meals already recorded keep the name they were
  /// recorded under; the old name is remembered so it can't be added again.
  Future<void> renameEmployee(Employee employee, String name) async {
    final tidy = tidyName(name);
    final taken = await _nameTaken(tidy, except: employee.id);
    if (taken != null) throw NameTaken(taken);
    await _db.collection('employees').doc(employee.id).update({
      'name': tidy,
      'formerNames': FieldValue.arrayUnion([employee.name]),
    });
  }

  /// Takes someone off the list (left the office, added by mistake). Their
  /// records stay on the reports.
  Future<void> removeEmployee(Employee employee) async {
    await _db.collection('employees').doc(employee.id).update({
      'active': false,
      'removedBy': _signedInEmail,
    });
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

  Future<Map<String, Attendance>> fetchAttendanceForDates(
      String employeeId, List<String> dates) async {
    final answers =
        await Future.wait(dates.map((d) => fetchAttendance(employeeId, d)));
    return {
      for (var i = 0; i < dates.length; i++)
        if (answers[i] != null) dates[i]: answers[i]!,
    };
  }

  /// Saves the customer's plan. A day they answered themselves is locked;
  /// a day the office or restaurant filled in for them they may still
  /// answer, and their own answer replaces it.
  Future<void> saveAttendancePlan(
      Employee employee, Map<String, bool> plan) async {
    final existing =
        await fetchAttendanceForDates(employee.id, plan.keys.toList());
    final open = plan.entries
        .where((e) => existing[e.key]?.setBy != 'employee')
        .toList();
    if (open.isEmpty) {
      throw StateError('This meal plan has already been submitted.');
    }
    for (final entry in open) {
      final ref =
          _db.collection('attendance').doc('${entry.key}_${employee.id}');
      await _db.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists && existing.data()?['setBy'] == 'employee') {
          throw StateError('This meal plan has already been submitted.');
        }
        tx.set(ref, {
          'employeeId': employee.id,
          'employeeName': employee.name,
          'date': entry.key,
          'coming': entry.value,
          'setBy': 'employee',
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _signedInEmail,
        });
      });
    }
  }

  /// Saves many answers in one go — the office entering its weekly list.
  /// Each answer's rule checks that the employee exists, and Firestore
  /// allows only 20 such checks per batch, hence the small batches.
  Future<void> setAttendanceMany(
      List<({Employee employee, String date, bool coming})> answers,
      String setBy) async {
    for (var i = 0; i < answers.length; i += 20) {
      final batch = _db.batch();
      for (final a in answers.skip(i).take(20)) {
        batch.set(
            _db.collection('attendance').doc('${a.date}_${a.employee.id}'), {
          'employeeId': a.employee.id,
          'employeeName': a.employee.name,
          'date': a.date,
          'coming': a.coming,
          'setBy': setBy,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _signedInEmail,
        });
      }
      await batch.commit();
    }
  }

  /// Live answers from [startKey] to [endKey] (inclusive), keyed by the
  /// document id `<date>_<employeeId>`.
  Stream<Map<String, Attendance>> streamAttendanceRange(
      String startKey, String endKey) {
    return _db
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .snapshots()
        .map((snapshot) => {
              for (final doc in snapshot.docs)
                doc.id: Attendance.fromFirestore(doc.data()),
            });
  }

  /// Removes many answers at once, by document id `<date>_<employeeId>`.
  Future<void> clearAttendanceMany(List<String> docIds) async {
    for (var i = 0; i < docIds.length; i += 450) {
      final batch = _db.batch();
      for (final id in docIds.skip(i).take(450)) {
        batch.delete(_db.collection('attendance').doc(id));
      }
      await batch.commit();
    }
  }

  // ---- Weekly duty roster ----------------------------------------------

  /// The office's roster for the week starting [mondayKey]: the ids of the
  /// people working that week. Null when none has been set.
  Stream<Set<String>?> streamWeekRoster(String mondayKey) => _db
      .collection('week_rosters')
      .doc(mondayKey)
      .snapshots()
      .map((doc) => doc.exists ? _rosterIds(doc.data()) : null);

  Future<Set<String>?> fetchWeekRoster(String mondayKey) async {
    final doc = await _db.collection('week_rosters').doc(mondayKey).get();
    return doc.exists ? _rosterIds(doc.data()) : null;
  }

  static Set<String> _rosterIds(Map<String, dynamic>? data) =>
      {for (final id in (data?['employeeIds'] as List?) ?? const []) '$id'};

  Future<void> setWeekRoster(String mondayKey, Set<String> employeeIds) async {
    await _db.collection('week_rosters').doc(mondayKey).set({
      'employeeIds': employeeIds.toList()..sort(),
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
  /// person whose name contains all the typed words. A note in brackets
  /// after a name ("NTIRENGANYA Evariste (PSAD)", for two people sharing a
  /// name) is ignored for the exact match, so both come back.
  Future<List<Employee>> findEmployeesByName(String typed) async {
    if (foldText(typed).isEmpty) return const [];
    final all = await fetchEmployees();
    final exact = all
        .where((e) =>
            sameName(e.name.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), ''), typed))
        .toList();
    if (exact.isNotEmpty) return exact;
    return all.where((e) => nameMatches(e.name, typed)).toList();
  }

  /// All of an employee's check-ins for [month] (default: this month),
  /// oldest first, for the "my record" screen.
  Future<List<CheckIn>> fetchMyCheckInsThisMonth(String employeeId,
      [DateTime? month]) async {
    final monthStart = DateFormat('yyyy-MM').format(month ?? DateTime.now());

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

  /// Every working day of [month] up to today, newest first, with what
  /// the customer said and whether they ate — their own record to point
  /// to if a meal is ever disputed.
  Future<List<DayHistory>> fetchMyMonth(
      String employeeId, DateTime month) async {
    final t = today();
    final days = <String>[];
    for (var d = DateTime(month.year, month.month, 1);
        d.month == month.month && !d.isAfter(t);
        d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
        days.add(dateKey(d));
      }
    }
    final (meals, answers) = await (
      fetchMyCheckInsThisMonth(employeeId, month),
      fetchAttendanceForDates(employeeId, days),
    ).wait;
    final byDate = {for (final m in meals) m.date: m};
    // A meal on a weekend still belongs in the record.
    final all = {...days, ...byDate.keys}.toList()..sort();
    return [
      for (final d in all.reversed)
        (date: d, answer: answers[d], meal: byDate[d]),
    ];
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

    final mondays = <String>[
      for (var m = mondayOf(start);
          !m.isAfter(end);
          m = DateTime(m.year, m.month, m.day + 7))
        dateKey(m),
    ];
    final (employees, checkIns, attendance, voided, rosterList, guests) =
        await (
      fetchAllEmployees(),
      inRange('checkins'),
      inRange('attendance'),
      inRange('voided_checkins'),
      Future.wait(mondays.map(fetchWeekRoster)),
      inRange('guest_meals'),
    ).wait;
    final rosters = {
      for (var i = 0; i < mondays.length; i++)
        if (rosterList[i] != null) mondays[i]: rosterList[i]!,
    };

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
      rosters,
      guests.docs
          .map((doc) => GuestMeal.fromFirestore(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
    );
  }

  // ---- Guests ----------------------------------------------------------

  /// Records a meal for a visitor today. The time is set by the server.
  Future<void> addGuestMeal(String name, String note) async {
    await _db.collection('guest_meals').add({
      'date': todayKey(),
      'name': tidyName(name),
      'note': note.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'recordedBy': _signedInEmail,
    });
  }

  Future<void> deleteGuestMeal(String id) =>
      _db.collection('guest_meals').doc(id).delete();

  Stream<List<GuestMeal>> streamTodayGuests() {
    return _db
        .collection('guest_meals')
        .where('date', isEqualTo: todayKey())
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GuestMeal.fromFirestore(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
  }
}
