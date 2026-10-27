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
import '../models/guest_meal.dart';
import '../services/firestore_service.dart';
import '../widgets/meal_result_dialog.dart';
import '../widgets/sign_in_gate.dart';
import '../widgets/add_person_dialog.dart';
import 'badges_screen.dart';
import 'govt_report_screen.dart';
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

  /// This week's roster from the office; null if none is set. The manual
  /// list shows only these people until a name is typed.
  Set<String>? _weekRoster;
  bool _loadingEmployees = true;
  String? _employeeLoadError;
  DateTime _planDay = nextServiceDay(DateTime.now());
  late final Stream<List<GuestMeal>> _todayGuests =
      _service.streamTodayGuests();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadEmployees();
    _service.removeLegacyPins().catchError((_) {});
  }

  Future<void> _loadEmployees() async {
    try {
      final (employees, roster) = await (
        _service.fetchEmployees(),
        _service.fetchWeekRoster(dateKey(mondayOf(today()))),
      ).wait.timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _allEmployees = employees;
        _weekRoster = roster;
        _loadingEmployees = false;
        _employeeLoadError = null;
      });
      _onSearchChanged();

      // Badge creation is not needed to display the roster or search names.
      // Finish it in the background so the counter becomes usable sooner.
      try {
        final keys = await _service
            .ensureBadgeKeys(employees)
            .timeout(const Duration(seconds: 30));
        if (mounted) setState(() => _badgeKeys = keys);
      } catch (_) {
        // The roster and name search remain usable if badge setup is slow.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEmployees = false;
        _employeeLoadError =
            'Could not load the customer list. Check the internet connection and try again.';
      });
    }
  }

  void _onSearchChanged() {
    // Capitals, accents, extra spaces and word order don't matter:
    // "PRINCESS", "princess" and "uwase prin" all find "Princess Uwase".
    final query = _searchController.text;
    final roster = _weekRoster;
    setState(() {
      _filteredEmployees = query.trim().isEmpty && roster != null
          ? _allEmployees.where((e) => roster.contains(e.id)).toList()
          : _allEmployees.where((e) => nameMatches(e.name, query)).toList();
    });
  }

  void _openScanner() {
    if (_badgeKeys.length < _allEmployees.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Meal passes are still loading. Please try again.')));
      return;
    }
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

  /// A visitor who isn't office staff. Counted in the day's total, and
  /// listed by name on the report as a guest.
  Future<void> _addGuest() async {
    final name = TextEditingController();
    final note = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a guest'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Guest name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Who invited them, organisation…'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (name.text.trim().length >= 2) Navigator.pop(ctx, true);
              },
              child: const Text('Record guest meal')),
        ],
      ),
    );
    final guestName = name.text, guestNote = note.text;
    name.dispose();
    note.dispose();
    if (saved != true) return;
    try {
      await _service.addGuestMeal(guestName, guestNote);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Guest meal recorded for $guestName')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not record the guest: $e')));
      }
    }
  }

  Future<void> _removeGuest(GuestMeal g) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove the guest meal for ${g.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) await _service.deleteGuestMeal(g.id);
  }

  /// Someone who isn't on the office's list at all. They get a meal pass,
  /// and the office report lists them as added at the counter.
  Future<void> _addWalkIn() async {
    final added = await showAddPerson(context,
        existing: _allEmployees, initialName: _searchController.text.trim());
    // Reload so the new person is searchable and their pass scans.
    await _loadEmployees();
    if (added == null || !mounted) return;
    final result = await _service.recordMeal(added, 'tap');
    if (!mounted) return;
    _searchController.clear();
    await showMealResult(context, employee: added, result: result);
  }

  Future<void> _confirmAndLog(Employee employee) async {
    // They may still eat after saying no, or without answering — the
    // report shows it either way. This just tells the cashier.
    Attendance? answer;
    try {
      answer = await _service.fetchAttendance(
          employee.id, FirestoreService.todayKey());
    } catch (_) {}
    if (!mounted) return;
    final note = switch (answer?.coming) {
      true => 'Said they would eat today.',
      false => 'Said they would NOT eat today. '
          'The report will show "Said no, but ate".',
      null => 'Did not say whether they would eat today. '
          'The report will show "Did not register, but ate".',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm meal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Record a meal for ${employee.name}?',
                style: GoogleFonts.publicSans(fontSize: 20)),
            const SizedBox(height: 12),
            Text(note,
                style: giBody(
                    size: 15,
                    color: answer?.coming == true
                        ? GiColors.muted
                        : GiColors.accent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
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
              icon: const Icon(Icons.assessment_outlined),
              tooltip: 'Reports',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GovtReportScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              tooltip: 'Meal passes',
              onPressed: _loadingEmployees ? null : _openBadges,
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
              Tab(text: 'Meal plan'),
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

  Widget _buildPlanTab() {
    final date = dateKey(_planDay);
    return StreamBuilder<Map<String, Attendance>>(
      stream: _service.streamAttendance(date),
      builder: (context, snapshot) {
        final booked = (snapshot.data ?? {})
            .values
            .where((answer) => answer.coming)
            .toList()
          ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        setState(() => _planDay = previousServiceDay(_planDay)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(DateFormat('EEEE d MMMM').format(_planDay),
                        textAlign: TextAlign.center,
                        style: giHeading(size: 20)),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _planDay = nextServiceDay(_planDay)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                _HeaderStat('Expected meals', booked.length),
                _HeaderStat(
                    'Said not coming',
                    (snapshot.data ?? {})
                        .values
                        .where((answer) => !answer.coming)
                        .length),
              ]),
            ),
            Expanded(
              child: booked.isEmpty
                  ? Center(
                      child: Text('Nobody has selected this day yet.',
                          style: giBody(color: GiColors.muted)))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final answer in booked)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.event_available,
                                  color: GiColors.primary),
                              title: Text(answer.employeeName),
                              subtitle: Text(_allEmployees
                                      .where((e) => e.id == answer.employeeId)
                                      .map((e) => e.department)
                                      .firstOrNull ??
                                  ''),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCheckInTab(List<CheckIn> todaysCheckins) {
    final loggedIds = todaysCheckins.map((c) => c.employeeId).toSet();
    final notYetLogged =
        _filteredEmployees.where((e) => !loggedIds.contains(e.id)).toList();
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: _loadingEmployees ? null : _addWalkIn,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Not on the list? Add person'),
              ),
              TextButton.icon(
                onPressed: _addGuest,
                icon: const Icon(Icons.card_travel),
                label: const Text('Add guest'),
              ),
            ]),
          ),
        ),
        Expanded(
          child: _loadingEmployees
              ? const Center(child: CircularProgressIndicator())
              : _employeeLoadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_employeeLoadError!,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _loadEmployees,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    )
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
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: notYetLogged.length,
                          itemBuilder: (context, index) {
                            final employee = notYetLogged[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                title: Text(employee.name,
                                    style: GoogleFonts.publicSans(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text([
                                  if (employee.department.isNotEmpty)
                                    employee.department,
                                  if (_weekRoster != null &&
                                      !_weekRoster!.contains(employee.id))
                                    "Not on this week's roster",
                                ].join(' · ')),
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
    return StreamBuilder<List<GuestMeal>>(
      stream: _todayGuests,
      builder: (context, snapshot) =>
          _buildLoggedList(todaysCheckins, snapshot.data ?? const []),
    );
  }

  Widget _buildLoggedList(
      List<CheckIn> todaysCheckins, List<GuestMeal> guests) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderStat(
                  'Meals served', todaysCheckins.length + guests.length),
              _HeaderStat('Scanned pass',
                  todaysCheckins.where((c) => c.method == 'scan').length),
              _HeaderStat('Found by name',
                  todaysCheckins.where((c) => c.method != 'scan').length),
              _HeaderStat('Guests', guests.length),
            ],
          ),
        ),
        for (final g in guests)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: ListTile(
              leading: const Icon(Icons.card_travel, color: GiColors.accent),
              title: Text(g.name,
                  style: GoogleFonts.publicSans(fontWeight: FontWeight.w600)),
              subtitle: Text([
                DateFormat('h:mm a').format(g.timestamp.toDate()),
                'Guest',
                if (g.note.isNotEmpty) g.note,
              ].join(' · ')),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: GiColors.muted),
                tooltip: 'Remove guest (added by mistake)',
                onPressed: () => _removeGuest(g),
              ),
            ),
          ),
        if (todaysCheckins.isEmpty && guests.isEmpty)
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
              leading: const Icon(Icons.check_circle, color: GiColors.green),
              title: Text(c.employeeName,
                  style: GoogleFonts.publicSans(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${DateFormat('h:mm a').format(c.timestamp.toDate())} · ${c.methodLabel}'),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: GiColors.muted),
                tooltip: 'Remove (wrong person)',
                onPressed: () => _correct(c),
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Someone whose pass was scanned (or name tapped) a second time today.
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
