import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../dates.dart';
import '../text_match.dart';
import '../theme.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/check_in.dart';
import '../services/firestore_service.dart';
import '../employee_roster.dart';
import '../widgets/add_person_dialog.dart';
import '../widgets/formal.dart';
import '../widgets/meal_result_dialog.dart';
import '../widgets/sign_in_gate.dart';
import 'badges_screen.dart';
import 'scan_screen.dart';

/// The restaurant's screen. Only accounts listed as restaurant staff in
/// firestore.rules get past the sign-in.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SignInGate(
      title: 'Restaurant sign-in',
      explanation: 'Sign in with the restaurant account.',
      // Badge keys are readable by restaurant accounts only.
      probe: () =>
          FirebaseFirestore.instance.collection('badges').limit(1).get(),
      builder: (_) => const _StaffHome(),
    );
  }
}

class _StaffHome extends StatefulWidget {
  const _StaffHome();

  @override
  State<_StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<_StaffHome> {
  final _service = FirestoreService();
  final _searchController = TextEditingController();

  List<Employee> _allEmployees = [];
  Map<String, String> _badgeKeys = {};
  List<Employee> _filteredEmployees = [];
  bool _loadingEmployees = true;

  DateTime _planDay = nextServiceDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadEmployees();
    _service.removeLegacyPins().catchError((_) {});
  }

  Future<void> _loadEmployees() async {
    final employees = await _service.fetchEmployees();
    // Everyone gets a pass as soon as they're on the list, so the Pass tab
    // on their phone works without anything being printed.
    final keys = await _service.ensureBadgeKeys(employees);
    if (!mounted) return;
    setState(() {
      _allEmployees = employees;
      _badgeKeys = keys;
      _loadingEmployees = false;
    });
    _onSearchChanged();
  }

  void _onSearchChanged() {
    // Capitals, accents, extra spaces and word order don't matter:
    // "PRINCESS", "princess" and "uwase prin" all find "Princess Uwase".
    final query = _searchController.text;
    setState(() {
      _filteredEmployees =
          _allEmployees.where((e) => nameMatches(e.name, query)).toList();
    });
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              ScanScreen(employees: _allEmployees, badgeKeys: _badgeKeys)),
    );
  }

  Future<void> _openBadges() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BadgesScreen(employees: _allEmployees)),
    );
    // New or replaced badges must be recognised by the scanner straight away.
    final keys = await _service.fetchBadgeKeys();
    if (mounted) setState(() => _badgeKeys = keys);
  }

  /// Removing a meal leaves a permanent correction on the office's report,
  /// so the restaurant is asked why.
  Future<void> _correct(CheckIn c) async {
    const reasons = [
      'Wrong person was recorded',
      'Recorded by mistake - did not eat',
    ];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Remove the meal for ${c.employeeName}?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'This will be shown on the office report as a correction. '
              'Choose the reason:',
              style: GoogleFonts.publicSans(color: GiColors.muted),
            ),
          ),
          for (final r in reasons)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: () => Navigator.pop(ctx, r),
              child: Text(r, style: GoogleFonts.publicSans(fontSize: 17)),
            ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel - keep the meal',
                style: GoogleFonts.publicSans(
                    fontSize: 17, color: GiColors.primaryDark)),
          ),
        ],
      ),
    );
    if (reason == null) return;

    try {
      await _service.voidCheckIn(c, reason);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove the meal: $e')),
      );
    }
  }

  Future<void> _confirmAndLog(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm meal'),
        content: Text('Record a meal for ${employee.name}?',
            style: GoogleFonts.publicSans(fontSize: 20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, record'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await _service.recordMeal(employee, 'tap');
    if (!mounted) return;

    _searchController.clear();
    await showMealResult(context, employee: employee, result: result);
  }

  /// Someone who isn't on the office's list. If the cashier picks "Record
  /// meal now", it's recorded straight away (they already confirmed it).
  Future<void> _addPerson([String initialName = '']) async {
    final person = await showAddPerson(context,
        existing: _allEmployees, initialName: initialName);
    await _loadEmployees();
    if (person == null || !mounted) return;

    _searchController.clear();
    final result = await _service.recordMeal(person, 'tap');
    if (!mounted) return;
    await showMealResult(context, employee: person, result: result);
  }

  Future<void> _seedRoster() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load employee roster?'),
        content: const Text(
          'This adds the people from employee_roster.dart who are not '
          'in the app yet. Names already in the app are skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Load roster'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final count = await _service.seedEmployees(employeeRoster);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(count == 0
              ? 'Everyone is already loaded'
              : 'Added $count new employees')),
    );
    await _loadEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: GiColors.paper,
        appBar: AppBar(
          title: const Text('RESTAURANT COUNTER'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Add a person',
              onPressed: _loadingEmployees ? null : () => _addPerson(),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              tooltip: 'Meal passes',
              onPressed: _loadingEmployees ? null : _openBadges,
            ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Load employee roster',
              onPressed: _seedRoster,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Check in'),
              Tab(text: 'Today'),
              Tab(text: 'Plan'),
              Tab(text: 'Alerts'),
            ],
          ),
        ),
        body: StreamBuilder<List<CheckIn>>(
          stream: _service.streamTodayCheckins(),
          builder: (context, snapshot) {
            final todaysCheckins = snapshot.data ?? [];
            return TabBarView(
              children: [
                _buildCheckInTab(todaysCheckins),
                _buildLoggedTodayTab(todaysCheckins),
                _buildPlanTab(),
                _buildAlertsTab(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCheckInTab(List<CheckIn> todaysCheckins) {
    final loggedIds = todaysCheckins.map((c) => c.employeeId).toSet();
    final notYetLogged =
        _filteredEmployees.where((e) => !loggedIds.contains(e.id)).toList();
    final query = _searchController.text.trim();

    final addButton = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: OutlinedButton.icon(
        onPressed: () => _addPerson(query),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(query.isEmpty
            ? 'Not on the list? Add a person'
            : 'Not on the list? Add "$query"'),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SizedBox(
            width: double.infinity,
            height: 80,
            child: FilledButton.icon(
              onPressed: _loadingEmployees ? null : _openScanner,
              icon: const Icon(Icons.qr_code_scanner, size: 34),
              label: Text('Scan meal pass',
                  style: giBody(
                      size: 22, color: Colors.white, weight: FontWeight.w700)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('NO PASS? SEARCH BY NAME', style: giLabel()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(
              hintText: 'Type a name',
              prefixIcon: Icon(Icons.search, color: GiColors.primary),
            ),
          ),
        ),
        Expanded(
          child: _loadingEmployees
              ? const Center(child: CircularProgressIndicator())
              : notYetLogged.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        const SizedBox(height: 24),
                        Text(
                            _filteredEmployees.isEmpty
                                ? 'No one with that name is on the list.'
                                : 'Everyone with that name has already '
                                    'eaten today.',
                            textAlign: TextAlign.center,
                            style: giBody(color: GiColors.muted)),
                        if (_filteredEmployees.isEmpty) addButton,
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: notYetLogged.length + 1,
                      itemBuilder: (context, index) {
                        if (index == notYetLogged.length) return addButton;
                        final employee = notYetLogged[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            title: Text(employee.name,
                                style: GoogleFonts.publicSans(
                                    fontSize: 19, fontWeight: FontWeight.w600)),
                            subtitle: Text(employee.department),
                            trailing: const Icon(Icons.chevron_right,
                                color: GiColors.primary),
                            onTap: () => _confirmAndLog(employee),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildLoggedTodayTab(List<CheckIn> todaysCheckins) {
    return StreamBuilder<Map<String, Attendance>>(
      stream: _service.streamAttendance(FirestoreService.todayKey()),
      builder: (context, snapshot) {
        final answers = snapshot.data ?? {};
        final ateIds = todaysCheckins.map((c) => c.employeeId).toSet();
        final booked = answers.values.where((a) => a.coming).toList();
        final waiting = booked
            .where((a) => !ateIds.contains(a.employeeId))
            .toList()
          ..sort((a, b) => a.employeeName.compareTo(b.employeeName));

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderStat('Meals served', todaysCheckins.length),
                  _HeaderStat('Confirmed', booked.length),
                  _HeaderStat('Confirmed, not yet arrived', waiting.length),
                ],
              ),
            ),
            if (todaysCheckins.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text('No one logged yet today',
                      style: GoogleFonts.publicSans(color: GiColors.muted)),
                ),
              ),
            for (final c in todaysCheckins)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: ListTile(
                  leading:
                      const Icon(Icons.check_circle, color: GiColors.green),
                  title: Text(c.employeeName,
                      style:
                          GoogleFonts.publicSans(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${DateFormat('h:mm a').format(c.timestamp.toDate())} · ${c.methodLabel}'
                      '${answers[c.employeeId]?.coming == true ? '' : ' · not booked'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: GiColors.muted),
                    tooltip: 'Remove (wrong person)',
                    onPressed: () => _correct(c),
                  ),
                ),
              ),
            if (waiting.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
                child: Text('Booked but not here yet',
                    style: GoogleFonts.publicSans(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              for (final a in waiting)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.schedule, color: GiColors.muted),
                    title: Text(a.employeeName),
                  ),
                ),
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  /// "How many do I cook for?" — the answers for one service day, with
  /// a Yes / No switch on every name so the restaurant can enter what the
  /// office tells them (leave, travel, meetings) for people without phones.
  Widget _buildPlanTab() {
    final dayKey = dateKey(_planDay);

    return StreamBuilder<Map<String, Attendance>>(
      stream: _service.streamAttendance(dayKey),
      builder: (context, snapshot) {
        final answers = snapshot.data ?? {};
        final yes =
            _allEmployees.where((e) => answers[e.id]?.coming == true).length;
        final no =
            _allEmployees.where((e) => answers[e.id]?.coming == false).length;
        final none = _allEmployees.length - yes - no;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SectionCard(
                header: 'Kitchen plan',
                headerColor: GiColors.primary,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Previous day',
                          onPressed: () => setState(
                              () => _planDay = previousServiceDay(_planDay)),
                        ),
                        Text(DateFormat('EEEE d MMMM').format(_planDay),
                            style: giHeading(size: 19)),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next day',
                          onPressed: () => setState(
                              () => _planDay = nextServiceDay(_planDay)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('MEALS TO PREPARE', style: giLabel()),
                    Text('$yes',
                        style: giHeading(size: 64, color: GiColors.primary)),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        none > 0
                            ? '$no declined  |  $none not yet answered '
                                '(up to ${yes + none} if all attend)'
                            : '$no declined',
                        textAlign: TextAlign.center,
                        style: giBody(size: 16, color: GiColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loadingEmployees
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _allEmployees.length,
                      itemBuilder: (context, index) {
                        final e = _allEmployees[index];
                        final answer = answers[e.id];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(e.name,
                                          style: GoogleFonts.publicSans(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600)),
                                      Text(
                                        answer == null
                                            ? 'No answer'
                                            : answer.setBy == 'staff'
                                                ? 'Set by restaurant'
                                                : 'Answered themself',
                                        style: GoogleFonts.publicSans(
                                            fontSize: 13,
                                            color: GiColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                _PlanChoice(
                                  label: 'Yes',
                                  color: GiColors.green,
                                  selected: answer?.coming == true,
                                  onTap: () =>
                                      _setPlan(e, dayKey, answer, true),
                                ),
                                const SizedBox(width: 8),
                                _PlanChoice(
                                  label: 'No',
                                  color: GiColors.red,
                                  selected: answer?.coming == false,
                                  onTap: () =>
                                      _setPlan(e, dayKey, answer, false),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Tapping the answer that's already selected clears it back to
  /// "no answer", so a mistake can always be undone.
  void _setPlan(Employee e, String dayKey, Attendance? current, bool coming) {
    if (current?.coming == coming) {
      _service.clearAttendance(e.id, dayKey);
    } else {
      _service.setAttendance(e, dayKey, coming, 'staff');
    }
  }

  Widget _buildAlertsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamTodayDuplicateAttempts(),
      builder: (context, snapshot) {
        final attempts = snapshot.data ?? [];

        if (attempts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No duplicate attempts today',
                style:
                    GoogleFonts.publicSans(color: GiColors.muted, fontSize: 16),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: attempts.length,
          itemBuilder: (context, index) {
            final a = attempts[index];
            final ts = a['timestamp'];
            final time =
                ts is Timestamp ? DateFormat('h:mm a').format(ts.toDate()) : '';
            final source = switch (a['source']) {
              'scan' => 'Scanned pass',
              'self' || 'self-service' => 'Own phone (old version)',
              _ => 'Tapped at till',
            };

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: GiColors.redBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: GiColors.red),
              ),
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: GiColors.red),
                title: Text('${a['employeeName']} tried to log a second meal',
                    style: GoogleFonts.publicSans(fontWeight: FontWeight.w600)),
                subtitle: Text('$source · $time'),
              ),
            );
          },
        );
      },
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final int value;

  const _HeaderStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GiColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GiColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: giHeading(size: 32, color: GiColors.primary)),
            const SizedBox(height: 4),
            Text(label, style: giBody(size: 14, color: GiColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _PlanChoice extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PlanChoice({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? color : Colors.transparent,
          foregroundColor: selected ? Colors.white : color,
          side: BorderSide(color: color, width: 2),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(label,
            style: GoogleFonts.publicSans(
                fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
