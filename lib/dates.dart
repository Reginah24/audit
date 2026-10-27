import 'package:intl/intl.dart';

/// Every record is stored against a yyyy-MM-dd string, so "today" or
/// "Monday" is a simple string match in Firestore.
String dateKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

DateTime parseDateKey(String key) => DateFormat('yyyy-MM-dd').parse(key);

DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// The next day the restaurant serves the office — skips Saturday and
/// Sunday, so on a Friday "tomorrow" means Monday.
DateTime nextServiceDay(DateTime from) {
  var day = DateTime(from.year, from.month, from.day + 1);
  while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return day;
}

/// The Monday of [day]'s week — the id of that week's roster.
DateTime mondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - 1));

/// Same as [nextServiceDay] but going backwards, for stepping through
/// days in the staff and report screens.
DateTime previousServiceDay(DateTime from) {
  var day = DateTime(from.year, from.month, from.day - 1);
  while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return day;
}

/// "Monday" when the day is within the coming week, otherwise a full date,
/// so the question on screen reads naturally: "Will you eat here Monday?"
String friendlyDayName(DateTime day) {
  final t = today();
  if (day == t) return 'today';
  if (day == DateTime(t.year, t.month, t.day + 1)) return 'tomorrow';
  if (day.difference(t).inDays < 7) return DateFormat('EEEE').format(day);
  return DateFormat('EEE d MMM').format(day);
}

/// Badges carry this prefix so a random QR code (a product label, a
/// website) is rejected instead of being treated as an employee ID.
const badgePrefix = 'GIRAPHE:';

/// A badge is "GIRAPHE:<employee id>:<key>". The key is secret (only the
/// restaurant can read it) and changes when a lost badge is replaced, so
/// the old card stops working.
String badgeCodeFor(String employeeId, String key) =>
    '$badgePrefix$employeeId:$key';

/// Returns the employee ID and key in a scanned badge, or null if the code
/// isn't one of ours.
({String id, String key})? parseBadge(String? raw) {
  if (raw == null || !raw.startsWith(badgePrefix)) return null;
  final parts = raw.substring(badgePrefix.length).trim().split(':');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
  return (id: parts[0], key: parts[1]);
}
