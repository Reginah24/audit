import '../dates.dart';
import '../models/attendance.dart';
import '../models/check_in.dart';
import '../models/employee.dart';

/// One employee's line in the daily report.
class DayRow {
  final Employee employee;
  final Attendance? attendance; // null = didn't answer
  final CheckIn? meal; // null = didn't eat

  DayRow(this.employee, this.attendance, this.meal);

  bool get ate => meal != null;
  bool get saidYes => attendance?.coming == true;
  bool get saidNo => attendance?.coming == false;

  /// Said they'd come, food was cooked, but they never checked in.
  bool get noShow => saidYes && !ate;

  /// Ate without having said yes — the kitchen didn't plan for them.
  bool get unplanned => ate && !saidYes;

  /// Said they would not come, but came and ate.
  bool get ateSaidNo => ate && saidNo;

  /// Never said whether they would come (no account, or didn't answer),
  /// but came and ate.
  bool get ateUnregistered => ate && attendance == null;

  String get comingLabel => saidYes ? 'Yes' : (saidNo ? 'No' : 'No answer');

  String get note {
    if (noShow) return 'Said yes, did not eat';
    if (ateSaidNo) return 'Said no, but ate';
    if (ateUnregistered) return 'Did not register, but ate';
    return '';
  }
}

/// Who booked, who ate and who didn't, for one day.
class DayReport {
  final String date;
  final List<DayRow> rows;

  /// Meals the restaurant recorded and then removed that day.
  final List<VoidedCheckIn> corrections;

  /// People added at the restaurant counter that day.
  final List<Employee> added;

  DayReport(this.date, this.rows,
      [this.corrections = const [], this.added = const []]);

  /// [roster] is that week's roster (employee ids), if the office set one:
  /// then only people on it — or who answered or ate that day — are listed.
  factory DayReport.build(String date, List<Employee> employees,
      List<CheckIn> checkIns, List<Attendance> attendance,
      [List<VoidedCheckIn> voided = const [], Set<String>? roster]) {
    final meals = {
      for (final c in checkIns.where((c) => c.date == date)) c.employeeId: c,
    };
    final answers = {
      for (final a in attendance.where((a) => a.date == date)) a.employeeId: a,
    };

    // Someone added on the 24th wasn't expected to eat on the 20th, and
    // someone taken off the list (or an old duplicate record) only shows
    // if they answered or ate that day.
    // A week's roster decides who was expected, even before they were
    // entered in the app (weeks filled in later from the paper lists).
    final onList = employees.where((e) =>
        answers.containsKey(e.id) ||
        meals.containsKey(e.id) ||
        (e.active &&
            (roster != null
                ? roster.contains(e.id)
                : e.addedAt == null ||
                    dateKey(e.addedAt!).compareTo(date) <= 0)));
    final rows = [
      for (final e in onList) DayRow(e, answers[e.id], meals[e.id]),
    ];

    // Someone removed from the roster can still have a meal on record —
    // keep it in the report rather than silently dropping it.
    final rosterIds = onList.map((e) => e.id).toSet();
    for (final c
        in meals.values.where((c) => !rosterIds.contains(c.employeeId))) {
      rows.add(DayRow(
        Employee(id: c.employeeId, name: c.employeeName, department: ''),
        answers[c.employeeId],
        c,
      ));
    }

    rows.sort((a, b) =>
        a.employee.name.toLowerCase().compareTo(b.employee.name.toLowerCase()));
    return DayReport(
      date,
      rows,
      voided.where((v) => v.original.date == date).toList(),
      addedAtCounter(employees, date, date),
    );
  }

  int get total => rows.length;
  int get saidYes => rows.where((r) => r.saidYes).length;
  int get saidNo => rows.where((r) => r.saidNo).length;
  int get noAnswer => total - saidYes - saidNo;
  int get ate => rows.where((r) => r.ate).length;
  int get didNotEat => total - ate;
  int get noShows => rows.where((r) => r.noShow).length;
  int get unplanned => rows.where((r) => r.unplanned).length;
  int get ateSaidNo => rows.where((r) => r.ateSaidNo).length;
  int get ateUnregistered => rows.where((r) => r.ateUnregistered).length;
}

/// One employee's totals for the monthly report.
class MonthRow {
  final Employee employee;
  int meals = 0;
  int booked = 0;
  int noShows = 0;
  int unplanned = 0;

  MonthRow(this.employee);
}

/// One day's totals for the monthly report.
class MonthDay {
  final String date;
  final int booked;
  final int ate;

  MonthDay(this.date, this.booked, this.ate);
}

class MonthReport {
  final List<MonthRow> rows;
  final List<MonthDay> days;
  final List<VoidedCheckIn> corrections;
  final List<Employee> added;

  MonthReport(this.rows, this.days,
      [this.corrections = const [], this.added = const []]);

  /// [todayKey] is the current date; bookings after it are for days that
  /// haven't happened yet, so they can't be no-shows. [startKey]/[endKey]
  /// bound the month, for listing people added at the counter.
  factory MonthReport.build(List<Employee> employees, List<CheckIn> checkIns,
      List<Attendance> attendance, String todayKey,
      [List<VoidedCheckIn> voided = const [],
      String startKey = '',
      String endKey = '',
      Map<String, Set<String>> rosters = const {}]) {
    final dates = {
      ...checkIns.map((c) => c.date),
      ...attendance.map((a) => a.date),
    }.toList()
      ..sort();

    final byId = <String, MonthRow>{
      for (final e in employees) e.id: MonthRow(e),
    };
    final days = <MonthDay>[];

    for (final date in dates.where((d) => d.compareTo(todayKey) <= 0)) {
      final day = DayReport.build(date, employees, checkIns, attendance,
          const [], rosters[dateKey(mondayOf(parseDateKey(date)))]);
      days.add(MonthDay(date, day.saidYes, day.ate));
      for (final r in day.rows) {
        final row = byId.putIfAbsent(r.employee.id, () => MonthRow(r.employee));
        if (r.ate) row.meals++;
        if (r.saidYes) row.booked++;
        if (r.noShow) row.noShows++;
        if (r.unplanned) row.unplanned++;
      }
    }

    final rows = byId.values.toList()
      ..sort((a, b) => a.employee.name
          .toLowerCase()
          .compareTo(b.employee.name.toLowerCase()));
    return MonthReport(
        rows, days, voided, addedAtCounter(employees, startKey, endKey));
  }

  int get totalMeals => rows.fold(0, (sum, r) => sum + r.meals);
  int get totalBooked => rows.fold(0, (sum, r) => sum + r.booked);
  int get totalNoShows => rows.fold(0, (sum, r) => sum + r.noShows);
  int get totalUnplanned => rows.fold(0, (sum, r) => sum + r.unplanned);
}

/// People added at the restaurant counter (not from the office's list)
/// between [startKey] and [endKey], oldest first.
List<Employee> addedAtCounter(
    List<Employee> employees, String startKey, String endKey) {
  if (startKey.isEmpty) return const [];
  return employees.where((e) {
    if (!e.addedAtCounter || e.addedAt == null) return false;
    final k = dateKey(e.addedAt!);
    return k.compareTo(startKey) >= 0 && k.compareTo(endKey) <= 0;
  }).toList()
    ..sort((a, b) => a.addedAt!.compareTo(b.addedAt!));
}
