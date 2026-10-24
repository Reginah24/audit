import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giraphe_meal_app/dates.dart';
import 'package:giraphe_meal_app/models/attendance.dart';
import 'package:giraphe_meal_app/models/check_in.dart';
import 'package:giraphe_meal_app/models/employee.dart';
import 'package:giraphe_meal_app/services/report.dart';
import 'package:giraphe_meal_app/text_match.dart';

void main() {
  group('service days', () {
    test('Friday rolls over to Monday', () {
      expect(nextServiceDay(DateTime(2026, 10, 23)), DateTime(2026, 10, 26));
    });
    test('midweek is the next day', () {
      expect(nextServiceDay(DateTime(2026, 10, 21)), DateTime(2026, 10, 22));
    });
    test('Monday steps back to Friday', () {
      expect(
          previousServiceDay(DateTime(2026, 10, 26)), DateTime(2026, 10, 23));
    });
  });

  group('badges', () {
    test('round-trips an employee id and key', () {
      final badge = parseBadge(badgeCodeFor('abc123', 'K7Q2'));
      expect(badge?.id, 'abc123');
      expect(badge?.key, 'K7Q2');
    });
    test('rejects codes that are not ours, or have no key', () {
      expect(parseBadge('https://example.com'), isNull);
      expect(parseBadge('GIRAPHE:'), isNull);
      expect(parseBadge('GIRAPHE:abc123'), isNull); // old badge format
      expect(parseBadge('GIRAPHE:abc123:'), isNull);
      expect(parseBadge(null), isNull);
    });
  });

  group('typing names, capitals do not matter', () {
    const princess = 'Princess Uwase';
    test('any capitals find the person', () {
      for (final typed in [
        'princess',
        'PRINCESS',
        'Princess',
        'pRiNcEsS',
        'PRINCESS UWASE',
        '  princess   uwase  '
      ]) {
        expect(nameMatches(princess, typed), isTrue, reason: typed);
      }
    });
    test('word order, start of a word and accents', () {
      expect(nameMatches(princess, 'uwase princess'), isTrue);
      expect(nameMatches(princess, 'PRIN'), isTrue);
      expect(nameMatches('Clémentine Ingabire', 'CLEMENTINE'), isTrue);
      expect(nameMatches('Jean-Paul Habimana', 'jean paul'), isTrue);
    });
    test('does not match the wrong person', () {
      expect(nameMatches(princess, 'aline'), isFalse);
      expect(nameMatches(princess, 'princess mugisha'), isFalse);
      expect(nameMatches(princess, 'cess'), isFalse);
    });
    test('same name check ignores capitals, spaces and accents', () {
      expect(sameName('Princess Uwase', ' PRINCESS  uwase'), isTrue);
      expect(sameName('Finance', 'FINANCE'), isTrue);
      expect(sameName('Clémentine', 'clementine'), isTrue);
      expect(sameName('Princess Uwase', 'Princess'), isFalse);
    });
  });

  group('reports', () {
    final regina =
        Employee(id: 'r', name: 'Regina Anthony', department: 'Finance');
    final jean = Employee(id: 'j', name: 'Jean Paul', department: 'IT');
    final aline = Employee(id: 'a', name: 'Aline Uwase', department: 'HR');
    final roster = [regina, jean, aline];

    CheckIn meal(Employee e, String date) => CheckIn(
          id: '${date}_${e.id}',
          employeeId: e.id,
          employeeName: e.name,
          date: date,
          timestamp: Timestamp.fromDate(DateTime(2026, 10, 22, 12, 30)),
          method: 'scan',
        );
    Attendance answer(Employee e, String date, bool coming) => Attendance(
        employeeId: e.id,
        employeeName: e.name,
        date: date,
        coming: coming,
        setBy: 'employee');

    test('day report sorts people into ate / no-show / unplanned', () {
      const d = '2026-10-22';
      final report = DayReport.build(
        d,
        roster,
        [meal(regina, d), meal(jean, d)],
        [answer(regina, d, true), answer(aline, d, true)],
      );

      expect(report.total, 3);
      expect(report.saidYes, 2);
      expect(report.ate, 2);
      expect(report.didNotEat, 1);
      expect(report.noShows, 1); // Aline said yes, didn't eat
      expect(report.unplanned, 1); // Jean ate without booking
      expect(report.rows.map((r) => r.employee.name),
          ['Aline Uwase', 'Jean Paul', 'Regina Anthony']);
    });

    test('meal by someone no longer on the roster is still reported', () {
      const d = '2026-10-22';
      final gone = Employee(id: 'x', name: 'Former Staff', department: '');
      final report = DayReport.build(d, roster, [meal(gone, d)], []);
      expect(report.total, 4);
      expect(report.ate, 1);
    });

    test('corrections are reported on their own day only', () {
      VoidedCheckIn voided(String date) => VoidedCheckIn(
          original: meal(jean, date),
          voidedAt: Timestamp.fromDate(DateTime(2026, 10, 22, 13)),
          voidedBy: 'restaurant@example.com',
          reason: 'Wrong person was recorded');
      final report = DayReport.build('2026-10-22', roster, [], [],
          [voided('2026-10-22'), voided('2026-10-21')]);
      expect(report.corrections.length, 1);
      expect(report.ate, 0); // a removed meal doesn't count as eaten
    });

    test('someone added at the counter is reported, and not expected earlier',
        () {
      final walkIn = Employee(
          id: 'w',
          name: 'Eric Mugisha',
          department: 'Audit',
          addedBy: 'anthonyregina48@gmail.com',
          addedAt: DateTime(2026, 10, 22, 12, 5),
          source: 'counter');
      final all = [...roster, walkIn];

      final before = DayReport.build('2026-10-21', all, [], []);
      expect(before.total, 3); // not on the list yet that day
      expect(before.added, isEmpty);

      final sameDay = DayReport.build('2026-10-22', all, [], []);
      expect(sameDay.total, 4);
      expect(sameDay.added.map((e) => e.name), ['Eric Mugisha']);

      expect(addedAtCounter(all, '2026-10-01', '2026-10-31').length, 1);
      expect(addedAtCounter(all, '2026-11-01', '2026-11-30'), isEmpty);
    });

    test('month report ignores bookings for days not yet reached', () {
      final report = MonthReport.build(
        roster,
        [meal(regina, '2026-10-21')],
        [
          answer(regina, '2026-10-21', true),
          answer(jean, '2026-10-21', true),
          answer(aline, '2026-10-26', true), // future
        ],
        '2026-10-23',
      );
      expect(report.days.length, 1);
      expect(report.totalMeals, 1);
      expect(report.totalBooked, 2);
      expect(report.totalNoShows, 1);
    });
  });
}
