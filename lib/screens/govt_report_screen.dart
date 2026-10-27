import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../dates.dart';
import '../theme.dart';
import '../services/firestore_service.dart';
import '../services/pdf_service.dart';
import '../services/report.dart';
import '../models/check_in.dart';
import '../models/employee.dart';
import '../models/guest_meal.dart';
import '../widgets/sign_in_gate.dart';
import '../auth.dart';
import 'roster_screen.dart';
import 'weekly_plan_screen.dart';

enum _Mode { day, month }

enum _DayFilter { all, ate, didNotEat, noShow, ateSaidNo, unregistered }

/// Read-only report for the government office: for any day, who said they
/// would eat, who ate and who didn't; for any month, meals per employee.
/// Both can be printed or shared as a PDF. Open to the restaurant and
/// office accounts listed in firestore.rules.
class GovtReportScreen extends StatelessWidget {
  const GovtReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SignInGate(
      title: 'Meal report',
      explanation: 'Sign in with the office or restaurant account to see '
          'the meal report.',
      // Corrections are readable by report accounts only.
      probe: () => FirebaseFirestore.instance
          .collection('voided_checkins')
          .limit(1)
          .get(),
      builder: (_) => const _Report(),
    );
  }
}

class _Report extends StatefulWidget {
  const _Report();

  @override
  State<_Report> createState() => _ReportState();
}

class _ReportState extends State<_Report> {
  final _service = FirestoreService();

  _Mode _mode = _Mode.day;
  _DayFilter _filter = _DayFilter.all;
  DateTime _selectedDay = today();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  DayReport? _day;
  MonthReport? _month;
  List<GuestMeal> _guests = const [];
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      if (_mode == _Mode.day) {
        final data = await _service.fetchReport(_selectedDay, _selectedDay);
        _day = DayReport.build(
            dateKey(_selectedDay),
            data.employees,
            data.checkIns,
            data.attendance,
            data.voided,
            data.rosters[dateKey(mondayOf(_selectedDay))]);
        _guests = data.guests;
      } else {
        final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
        final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
        final data = await _service.fetchReport(start, end);
        _month = MonthReport.build(
            data.employees,
            data.checkIns,
            data.attendance,
            FirestoreService.todayKey(),
            data.voided,
            dateKey(start),
            dateKey(end),
            data.rosters);
        _guests = data.guests;
      }
    } catch (e) {
      _loadError = 'Could not load the report: $e';
    }

    if (mounted) setState(() => _loading = false);
  }

  void _step(int delta) {
    setState(() {
      if (_mode == _Mode.day) {
        _selectedDay = delta > 0
            ? nextServiceDay(_selectedDay)
            : previousServiceDay(_selectedDay);
      } else {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month + delta);
      }
    });
    _loadReport();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2024),
      lastDate: DateTime(today().year + 1),
    );
    if (picked == null) return;
    setState(() => _selectedDay = picked);
    _loadReport();
  }

  Future<(Uint8List, String)?> _buildPdf() async {
    if (_mode == _Mode.day) {
      final day = _day;
      if (day == null) return null;
      return (
        await buildDayReportPdf(day, _guests),
        'meal-report-${day.date}.pdf'
      );
    }
    final month = _month;
    if (month == null) return null;
    return (
      await buildMonthReportPdf(_selectedMonth, month, _guests.length),
      'meal-report-${DateFormat('yyyy-MM').format(_selectedMonth)}.pdf',
    );
  }

  Future<void> _print() async {
    final pdf = await _buildPdf();
    if (pdf != null) await printPdf(pdf.$1, pdf.$2);
  }

  Future<void> _share() async {
    final pdf = await _buildPdf();
    if (pdf != null) await sharePdf(pdf.$1, pdf.$2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GiColors.paper,
      appBar: AppBar(
        title: const Text('REPORTS'),
        actions: [
          if (staffRoleForEmail(
                  FirebaseAuth.instance.currentUser?.email ?? '') ==
              StaffRole.audit) ...[
            IconButton(
              icon: const Icon(Icons.event_note),
              tooltip: 'Who is coming this week',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WeeklyPlanScreen()),
                );
                _loadReport();
              },
            ),
            IconButton(
              icon: const Icon(Icons.groups_outlined),
              tooltip: 'Manage office roster',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RosterScreen()),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _buildReport(),
          ),
        ),
      ),
    );
  }

  Widget _buildReport() {
    final label = _mode == _Mode.day
        ? DateFormat('EEE d MMMM yyyy').format(_selectedDay)
        : DateFormat('MMMM yyyy').format(_selectedMonth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_Mode>(
          segments: const [
            ButtonSegment(value: _Mode.day, label: Text('One day')),
            ButtonSegment(value: _Mode.month, label: Text('Whole month')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            setState(() => _mode = s.first);
            _loadReport();
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: GiColors.primary),
              onPressed: () => _step(-1),
            ),
            TextButton(
              onPressed: _mode == _Mode.day ? _pickDay : null,
              child: Text(label,
                  style: GoogleFonts.publicSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: GiColors.ink)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: GiColors.primary),
              onPressed: () => _step(1),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading ? null : _print,
                icon: const Icon(Icons.print),
                label: const Text('Print / save PDF'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: GiColors.primaryDark,
                  side: const BorderSide(color: GiColors.primary),
                ),
                onPressed: _loading ? null : _share,
                icon: const Icon(Icons.share),
                label: const Text('Send / share'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: Text(_loadError!,
                          style: const TextStyle(color: GiColors.red)))
                  : _mode == _Mode.day
                      ? _buildDay()
                      : _buildMonth(),
        ),
      ],
    );
  }

  Widget _buildDay() {
    final report = _day;
    if (report == null) return const SizedBox.shrink();

    final rows = report.rows
        .where((r) => switch (_filter) {
              _DayFilter.all => true,
              _DayFilter.ate => r.ate,
              _DayFilter.didNotEat => !r.ate,
              _DayFilter.noShow => r.noShow,
              _DayFilter.ateSaidNo => r.ateSaidNo,
              _DayFilter.unregistered => r.ateUnregistered,
            })
        .toList();
    final expected = report.rows.where((row) => row.saidYes).toList();
    final notComing = report.rows.where((row) => row.saidNo).toList();

    Widget chip(_DayFilter f, String text, int count) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: ChoiceChip(
            label: Text('$text ($count)'),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );

    return ListView(
      children: [
        _DaySummary(report, _guests),
        Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExpansionTile(
            title: Text('Expected to eat: ${expected.length}',
                style: GoogleFonts.publicSans(fontWeight: FontWeight.w700)),
            children: [
              for (final row in expected)
                ListTile(
                  dense: true,
                  title: Text(row.employee.name),
                  subtitle: Text(row.employee.department),
                ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text('Said they will not eat: ${notComing.length}',
                style: GoogleFonts.publicSans(fontWeight: FontWeight.w700)),
            children: [
              for (final row in notComing)
                ListTile(
                  dense: true,
                  title: Text(row.employee.name),
                  subtitle: Text(row.employee.department),
                  trailing: row.ate
                      ? Text('Came anyway',
                          style: GoogleFonts.publicSans(
                              color: GiColors.primaryDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w600))
                      : null,
                ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text('Look up a person (${report.total})',
                style: GoogleFonts.publicSans(fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              Wrap(children: [
                chip(_DayFilter.all, 'Everyone', report.total),
                chip(_DayFilter.ate, 'Ate', report.ate),
                chip(_DayFilter.didNotEat, 'Did not eat', report.didNotEat),
                chip(
                    _DayFilter.noShow, 'Said yes, did not eat', report.noShows),
                chip(
                    _DayFilter.ateSaidNo, 'Said no, but ate', report.ateSaidNo),
                chip(_DayFilter.unregistered, 'Did not register, but ate',
                    report.ateUnregistered),
              ]),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('Nobody in this list',
                          style:
                              GoogleFonts.publicSans(color: GiColors.muted))),
                ),
              for (final r in rows)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    leading: Icon(
                      r.ate ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: r.ate ? GiColors.green : GiColors.muted,
                    ),
                    title: Text(r.employee.name,
                        style: GoogleFonts.publicSans(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (r.employee.department.isNotEmpty)
                        r.employee.department,
                      'Said coming: ${r.comingLabel}',
                      if (r.meal != null)
                        r.meal!.fromPaper
                            ? 'Ate (${r.meal!.methodLabel})'
                            : 'Ate ${DateFormat('h:mm a').format(r.meal!.timestamp.toDate())} (${r.meal!.methodLabel})',
                    ].join(' · ')),
                    trailing: r.note.isEmpty
                        ? null
                        : Text(r.note,
                            style: GoogleFonts.publicSans(
                                color: r.noShow
                                    ? GiColors.red
                                    : GiColors.primaryDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
        _AddedList(report.added),
        _CorrectionsList(report.corrections),
      ],
    );
  }

  Widget _buildMonth() {
    final report = _month;
    if (report == null) return const SizedBox.shrink();
    if (report.days.isEmpty) {
      return Center(
          child: Text('No meals logged for this month',
              style: GoogleFonts.publicSans(color: GiColors.muted)));
    }

    TableRow row(List<String> cells, {bool header = false}) => TableRow(
          decoration: BoxDecoration(
            color: header ? GiColors.paper : null,
            border: header
                ? null
                : const Border(top: BorderSide(color: GiColors.line)),
          ),
          children: [
            for (final c in cells)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(c,
                    style: GoogleFonts.publicSans(
                        fontWeight:
                            header ? FontWeight.w600 : FontWeight.normal)),
              ),
          ],
        );

    return ListView(
      children: [
        Wrap(children: [
          _StatTile('Days served', report.days.length),
          _StatTile('Meals eaten', report.totalMeals, color: GiColors.green),
          _StatTile('Guest meals', _guests.length),
          _StatTile('Meals booked', report.totalBooked),
          _StatTile('Booked, not eaten', report.totalNoShows,
              color: GiColors.red),
          _StatTile('Corrections', report.corrections.length),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: GiColors.card,
            border: Border.all(color: GiColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1.3),
              4: FlexColumnWidth(1.3),
            },
            children: [
              row([
                'Employee',
                'Ate',
                'Booked',
                'Booked, not eaten',
                'Ate, not booked'
              ], header: true),
              for (final r in report.rows)
                row([
                  r.employee.name,
                  '${r.meals}',
                  '${r.booked}',
                  '${r.noShows}',
                  '${r.unplanned}',
                ]),
              row([
                'Total',
                '${report.totalMeals}',
                '${report.totalBooked}',
                '${report.totalNoShows}',
                '${report.totalUnplanned}',
              ], header: true),
            ],
          ),
        ),
        _AddedList(report.added),
        _CorrectionsList(report.corrections),
      ],
    );
  }
}

/// The day as the office writes it: the total who ate, then each
/// exception with its names and count. Nobody else is listed here.
class _DaySummary extends StatelessWidget {
  final DayReport report;
  final List<GuestMeal> guests;

  const _DaySummary(this.report, this.guests);

  @override
  Widget build(BuildContext context) {
    final groups = [
      (
        'Not on the list, but came',
        report.rows.where((r) => r.ateUnregistered)
      ),
      (
        'Had blue (said they would not come), but came',
        report.rows.where((r) => r.ateSaidNo)
      ),
      ('Registered but did not come', report.rows.where((r) => r.noShow)),
    ];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total who ate: ${report.ate + guests.length}',
                style: giHeading(size: 22)),
            Text('Staff ${report.ate} + guests ${guests.length}',
                style: giBody(size: 14, color: GiColors.muted)),
            for (final (title, rows) in groups) ...[
              const SizedBox(height: 12),
              Text('$title: ${rows.length}',
                  style: giBody(size: 15, weight: FontWeight.w700)),
              if (rows.isEmpty)
                Text('None', style: giBody(size: 14, color: GiColors.muted))
              else
                for (final (i, r) in rows.indexed)
                  Text(
                      '${i + 1}. ${r.employee.name}'
                      '${r.employee.department.isEmpty ? '' : ' (${r.employee.department})'}',
                      style: giBody(size: 14)),
            ],
            const SizedBox(height: 12),
            Text('Guests: ${guests.length}',
                style: giBody(size: 15, weight: FontWeight.w700)),
            if (guests.isEmpty)
              Text('None', style: giBody(size: 14, color: GiColors.muted))
            else
              for (final (i, g) in guests.indexed)
                Text(
                    '${i + 1}. ${g.name}${g.note.isEmpty ? '' : ' (${g.note})'}',
                    style: giBody(size: 14)),
          ],
        ),
      ),
    );
  }
}

/// Meals the restaurant removed, with who, when and why — so a removal
/// can never go unnoticed by the office.
class _CorrectionsList extends StatelessWidget {
  final List<VoidedCheckIn> corrections;

  const _CorrectionsList(this.corrections);

  @override
  Widget build(BuildContext context) {
    if (corrections.isEmpty) return const SizedBox.shrink();
    String time(Timestamp t) => DateFormat('d MMM h:mm a').format(t.toDate());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text('Corrections (meals removed by the restaurant)',
              style: GoogleFonts.publicSans(
                  fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        for (final c in corrections)
          Card(
            color: GiColors.redBg,
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ListTile(
              leading: const Icon(Icons.edit_note, color: GiColors.red),
              title: Text(c.original.employeeName,
                  style: GoogleFonts.publicSans(fontWeight: FontWeight.w600)),
              subtitle: Text('Recorded ${time(c.original.timestamp)} · '
                  'removed ${time(c.voidedAt)} by ${c.voidedBy}\n${c.reason}'),
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatTile(this.label, this.value, {this.color = GiColors.ink});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GiColors.card,
        border: Border.all(color: GiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: GoogleFonts.publicSans(
                  fontSize: 28, fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style:
                  GoogleFonts.publicSans(fontSize: 12, color: GiColors.muted)),
        ],
      ),
    );
  }
}

/// People the restaurant added who weren't on the office's list, with who
/// added them and when, so the office can confirm they are real staff.
class _AddedList extends StatelessWidget {
  final List<Employee> added;

  const _AddedList(this.added);

  @override
  Widget build(BuildContext context) {
    if (added.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child:
              Text('People added at the counter', style: giHeading(size: 18)),
        ),
        for (final e in added)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ListTile(
              leading:
                  const Icon(Icons.person_add_alt_1, color: GiColors.accent),
              title: Text(e.name),
              subtitle: Text([
                if (e.department.isNotEmpty) e.department,
                'Added ${DateFormat('d MMM h:mm a').format(e.addedAt!)} '
                    'by ${e.addedBy ?? ''}',
              ].join('  |  ')),
            ),
          ),
      ],
    );
  }
}
