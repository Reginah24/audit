import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../auth.dart';
import '../l10n.dart';
import '../dates.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../models/check_in.dart';
import '../models/attendance.dart';
import '../services/firestore_service.dart';
import '../widgets/formal.dart';
import 'role_login_screen.dart';

/// Lets an employee see their meal pass and meals this month. Meals can only be
/// recorded at the restaurant. Two steps: find their name, then their PIN
/// (created on the first visit). The PIN is checked by Firebase
/// Authentication and never stored in the database.
class MyRecordScreen extends StatefulWidget {
  const MyRecordScreen({super.key});

  @override
  State<MyRecordScreen> createState() => _MyRecordScreenState();
}

class _MyRecordScreenState extends State<MyRecordScreen> {
  final _service = FirestoreService(employeeDb);
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  Employee? _foundEmployee;

  /// Several people match what was typed; they pick themselves.
  List<Employee> _candidates = const [];
  bool _searching = false;
  bool _resuming = false;
  bool _unlocking = false;
  String? _error;
  List<CheckIn>? _checkIns;
  String? _badgeKey;
  Map<String, Attendance> _attendance = {};
  Map<String, bool> _planChoices = {};
  bool _savingPlan = false;
  late final List<DateTime> _planningDays = _nextWorkingDays();

  int _tab = 0;

  DateTime _historyMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<DayHistory>? _history;
  String? _historyError;

  Future<void> _loadHistory() async {
    final employee = _foundEmployee;
    if (employee == null) return;
    setState(() {
      _history = null;
      _historyError = null;
    });
    try {
      final history = await _service.fetchMyMonth(employee.id, _historyMonth);
      if (mounted) setState(() => _history = history);
    } catch (e) {
      if (mounted) {
        setState(() => _historyError =
            tr('Could not load your record: {error}', {'error': '$e'}));
      }
    }
  }

  void _stepHistoryMonth(int delta) {
    _historyMonth = DateTime(_historyMonth.year, _historyMonth.month + delta);
    _loadHistory();
  }

  List<DateTime> _nextWorkingDays() {
    final days = <DateTime>[];
    var day = nextServiceDay(DateTime.now());
    while (days.length < 5) {
      days.add(day);
      day = nextServiceDay(day);
    }
    return days;
  }

  @override
  void initState() {
    super.initState();
    _resumeSignedIn();
  }

  /// Someone who signed in on this phone before goes straight to their
  /// page, without typing their name and PIN every day.
  Future<void> _resumeSignedIn() async {
    final id = signedInEmployeeId();
    if (id == null) return;
    setState(() => _resuming = true);
    try {
      final employee = await _service.fetchEmployee(id);
      if (employee != null) {
        _foundEmployee = employee;
        await _loadRecord(employee.id);
      }
    } catch (_) {
      // Fall back to the name screen.
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  Future<void> _searchName() async {
    setState(() {
      _searching = true;
      _error = null;
      _foundEmployee = null;
      _candidates = const [];
      _checkIns = null;
    });

    try {
      final matches = await _service.findEmployeesByName(_nameController.text);
      setState(() {
        if (matches.isEmpty) {
          _error = tr('Name not found. Check the spelling and try again, '
              'or ask at the restaurant.');
        } else if (matches.length == 1) {
          _foundEmployee = matches.single;
        } else if (matches.length > 8) {
          _error = tr('Many people match. Please type more of your name.');
        } else {
          _candidates = matches;
        }
      });
    } catch (e) {
      setState(() => _error = tr('No connection. Please try again.'));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submitPin() async {
    final employee = _foundEmployee;
    if (employee == null) return;

    final pin = _pinController.text.trim();
    if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      setState(() => _error = tr('The PIN is 4 numbers'));
      return;
    }

    setState(() {
      _error = null;
      _unlocking = true;
    });

    try {
      await employeeSignOut();
      var ok = false;
      if (!employee.pinSet) {
        ok = await employeeCreatePin(employee, pin);
        if (!ok) {
          // A PIN was already made for this name (e.g. on another phone).
          ok = await employeeSignIn(employee, pin);
          if (!ok) {
            setState(() {
              _foundEmployee = Employee(
                  id: employee.id,
                  name: employee.name,
                  department: employee.department,
                  pinSet: true);
              _error = tr('This name already has a PIN. Enter that PIN.');
            });
          }
        }
      } else {
        ok = await employeeSignIn(employee, pin);
        if (!ok) setState(() => _error = tr('Wrong PIN. Please try again.'));
      }
      if (ok) await _loadRecord(employee.id);
    } on SignInProblem catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(
          () => _error = tr('Something went wrong: {error}', {'error': '$e'}));
    } finally {
      _pinController.clear();
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _loadRecord(String employeeId) async {
    final dates = _planningDays.map((day) => dateKey(day)).toList();
    final (checkIns, badgeKey, attendance) = await (
      _service.fetchMyCheckInsThisMonth(employeeId),
      _service.fetchBadgeKey(employeeId),
      _service.fetchAttendanceForDates(employeeId, dates),
    ).wait;
    if (!mounted) return;
    setState(() {
      _checkIns = checkIns;
      _badgeKey = badgeKey;
      _attendance = attendance;
      _planChoices = {
        for (final date in dates) date: attendance[date]?.coming == true
      };
    });
  }

  Future<void> _signOut() async {
    await employeeSignOut();
    setState(() {
      _foundEmployee = null;
      _candidates = const [];
      _checkIns = null;
      _badgeKey = null;
      _attendance = {};
      _planChoices = {};
      _tab = 0;
      _history = null;
      _historyMonth = DateTime(DateTime.now().year, DateTime.now().month);
      _error = null;
      _nameController.clear();
      _pinController.clear();
    });
  }

  Future<void> _changeRole() async {
    await employeeSignOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleLoginScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _checkIns != null && _foundEmployee != null;
    final titles = [tr('MY MEALS'), tr('MEAL PASS'), tr('MY PROFILE')];

    return Scaffold(
      appBar: AppBar(
        title: Text(signedIn ? titles[_tab] : tr('MY MEALS')),
        actions: [
          const LanguageSwitch(),
          TextButton(
            onPressed: _changeRole,
            child: Text(tr('Change role')),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: _resuming
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()))
                    : signedIn
                        ? [_buildHome, _buildPass, _buildProfile][_tab]()
                        : _foundEmployee != null
                            ? _buildPinEntry()
                            : _buildNameSearch(),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: signedIn
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                if (i == 2) _loadHistory();
              },
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: const Icon(Icons.home),
                    label: tr('Home')),
                NavigationDestination(
                    icon: const Icon(Icons.qr_code_2),
                    selectedIcon: const Icon(Icons.qr_code_2),
                    label: tr('Pass')),
                NavigationDestination(
                    icon: const Icon(Icons.person_outline),
                    selectedIcon: const Icon(Icons.person),
                    label: tr('Profile')),
              ],
            )
          : null,
    );
  }

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 14),
          child: StatusLine(
              icon: Icons.error_outline, text: _error!, color: GiColors.red),
        );

  Widget _buildNameSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('STEP 1 OF 2'), style: giLabel()),
        const SizedBox(height: 8),
        Text(tr('Find your name'), style: giHeading(size: 28)),
        const SizedBox(height: 8),
        Text(tr('Type your name. Capital letters do not matter.'),
            style: giBody(color: GiColors.muted)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: giBody(size: 20),
          decoration: InputDecoration(labelText: tr('Your name')),
          onSubmitted: (_) => _searchName(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _searching ? null : _searchName,
          child: _searching
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(tr('Continue')),
        ),
        _errorText(),
        if (_candidates.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(tr('WHICH ONE ARE YOU?'), style: giLabel()),
          const SizedBox(height: 8),
          for (final e in _candidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MenuCard(
                icon: Icons.person_outline,
                title: e.name,
                description: e.department,
                onTap: () => setState(() {
                  _foundEmployee = e;
                  _candidates = const [];
                }),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPinEntry() {
    final isNewPin = !_foundEmployee!.pinSet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('STEP 2 OF 2'), style: giLabel()),
        const SizedBox(height: 8),
        Text(isNewPin ? tr('Create your PIN') : tr('Enter your PIN'),
            style: giHeading(size: 28)),
        const SizedBox(height: 8),
        Text(
          isNewPin
              ? tr(
                  'Welcome, {name}. Choose 4 numbers and remember them. '
                  'Do not share your PIN with anyone.',
                  {'name': _foundEmployee!.name})
              : tr('{name}, enter your 4-number PIN.',
                  {'name': _foundEmployee!.name}),
          style: giBody(color: GiColors.muted),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _pinController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: giHeading(size: 30).copyWith(letterSpacing: 16),
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (_) => _submitPin(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _unlocking ? null : _submitPin,
          child: _unlocking
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isNewPin ? tr('Save PIN and continue') : tr('Sign in')),
        ),
        _errorText(),
        const SizedBox(height: 8),
        TextButton(onPressed: _signOut, child: Text(tr('Not you? Go back'))),
        if (!isNewPin)
          Text(tr('Forgotten your PIN? The restaurant manager can reset it.'),
              textAlign: TextAlign.center,
              style: giBody(size: 15, color: GiColors.muted)),
      ],
    );
  }

  CheckIn? get _todaysMeal {
    final key = FirestoreService.todayKey();
    for (final c in _checkIns ?? const <CheckIn>[]) {
      if (c.date == key) return c;
    }
    return null;
  }

  String get _greeting {
    final h = DateTime.now().hour;
    final part = tr(
        h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening'));
    return '$part, ${_foundEmployee!.name.split(' ').first}';
  }

  Widget _buildHome() {
    final meal = _todaysMeal;
    final count = _checkIns!.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_greeting, style: giHeading(size: 26)),
        const SizedBox(height: 4),
        Text(fullDate(DateTime.now()), style: giBody(color: GiColors.muted)),
        const SizedBox(height: 22),
        _buildWeeklyPlan(),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr("TODAY'S STATUS"), style: giLabel()),
              const SizedBox(height: 10),
              meal != null
                  ? StatusLine(
                      icon: Icons.check_circle,
                      text: tr('Meal taken at {time}',
                          {'time': clockTime(meal.timestamp.toDate())}),
                      color: GiColors.primary)
                  : StatusLine(
                      icon: Icons.schedule,
                      text: tr('Not yet checked in'),
                      color: GiColors.muted),
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(tr('Meals this month'),
                        style: giBody(color: GiColors.muted)),
                  ),
                  Text('$count', style: giHeading(size: 24)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A day the customer answered themselves can't be changed. One the
  /// office or restaurant filled in for them, they can still answer.
  bool _ownAnswer(String date) => _attendance[date]?.setBy == 'employee';

  Widget _buildWeeklyPlan() {
    final locked = _planningDays.every((d) => _ownAnswer(dateKey(d)));
    return SectionCard(
      header: tr('Meal plan  |  next five working days'),
      headerColor: GiColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            locked
                ? tr('Your plan has been submitted and is locked.')
                : tr('Tick the days you will eat here, then submit. Days you '
                    'have already submitted cannot be changed.'),
            style: giBody(size: 16, color: GiColors.muted),
          ),
          const SizedBox(height: 10),
          for (final day in _planningDays)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(dayAndDate(day)),
              subtitle: switch (_attendance[dateKey(day)]?.setBy) {
                null => null,
                'employee' => Text(tr('Submitted')),
                'office' =>
                  Text(tr('Entered by the office. You can change it.')),
                _ => Text(tr('Entered by the restaurant. You can change it.')),
              },
              value: _planChoices[dateKey(day)] == true,
              onChanged: _ownAnswer(dateKey(day))
                  ? null
                  : (value) => setState(() {
                        _planChoices[dateKey(day)] = value == true;
                      }),
            ),
          if (!locked)
            FilledButton(
              onPressed: _savingPlan ? null : _savePlan,
              child: Text(tr('Submit meal plan')),
            ),
        ],
      ),
    );
  }

  Future<void> _savePlan() async {
    final employee = _foundEmployee;
    if (employee == null) return;
    setState(() => _savingPlan = true);
    try {
      await _service.saveAttendancePlan(employee, _planChoices);
      await _loadRecord(employee.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  tr('Could not submit the plan: {error}', {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPlan = false);
    }
  }

  Widget _buildPass() {
    final employee = _foundEmployee!;
    final key = _badgeKey;
    final meal = _todaysMeal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            children: [
              if (key == null) ...[
                const Icon(Icons.qr_code_2, size: 64, color: GiColors.line),
                const SizedBox(height: 12),
                Text(tr('Your pass has not been issued yet.'),
                    textAlign: TextAlign.center, style: giHeading(size: 20)),
                const SizedBox(height: 6),
                Text(tr('Please ask at the restaurant counter.'),
                    textAlign: TextAlign.center,
                    style: giBody(color: GiColors.muted)),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: GiColors.greenBg, width: 10),
                  ),
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: QrImageView(
                      data: badgeCodeFor(employee.id, key),
                      padding: EdgeInsets.zero,
                      eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square, color: GiColors.ink),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: GiColors.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(employee.name,
                    textAlign: TextAlign.center, style: giHeading(size: 24)),
                if (employee.department.isNotEmpty)
                  Text(employee.department,
                      style: giBody(color: GiColors.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(tr('Scan on arrival'),
            textAlign: TextAlign.center, style: giHeading(size: 24)),
        const SizedBox(height: 4),
        Text(
            tr('Hold this screen, or your printed pass, to the counter camera.'),
            textAlign: TextAlign.center,
            style: giBody(size: 16, color: GiColors.muted)),
        const SizedBox(height: 18),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('CHECK-IN STATUS'), style: giLabel()),
              const SizedBox(height: 10),
              meal != null
                  ? StatusLine(
                      icon: Icons.check_circle,
                      text: tr('Checked in at {time}',
                          {'time': clockTime(meal.timestamp.toDate())}),
                      color: GiColors.primary)
                  : StatusLine(
                      icon: Icons.radio_button_unchecked,
                      text: tr('Awaiting scan'),
                      color: GiColors.accent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfile() {
    final employee = _foundEmployee!;
    final initials = employee.name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: GiColors.primary),
              child: Text(initials,
                  style: giHeading(size: 24, color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.name, style: giHeading(size: 24)),
                  if (employee.department.isNotEmpty)
                    Text(employee.department,
                        style: giBody(color: GiColors.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: GiColors.primary),
              tooltip: 'Previous month',
              onPressed: () => _stepHistoryMonth(-1),
            ),
            Expanded(
              child: Text(monthAndYear(_historyMonth),
                  textAlign: TextAlign.center, style: giHeading(size: 20)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: GiColors.primary),
              tooltip: 'Next month',
              onPressed: _historyMonth.year == DateTime.now().year &&
                      _historyMonth.month == DateTime.now().month
                  ? null
                  : () => _stepHistoryMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildHistory(),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: Text(tr('Sign out')),
        ),
      ],
    );
  }

  /// Every working day of the month: whether they ate, and what they had
  /// said — the customer's own record if a meal is ever questioned.
  Widget _buildHistory() {
    if (_historyError != null) {
      return StatusLine(
          icon: Icons.error_outline, text: _historyError!, color: GiColors.red);
    }
    final history = _history;
    if (history == null) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()));
    }
    final ate = history.where((d) => d.meal != null).length;

    return SectionCard(
      header: tr('Ate on {n} of {total} days',
          {'n': '$ate', 'total': '${history.length}'}),
      headerColor: GiColors.primary,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: history.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(tr('No working days yet this month.'),
                  style: giBody(color: GiColors.muted)),
            )
          : Column(
              children: [
                for (final d in history)
                  ListTile(
                    leading: d.meal != null
                        ? const Icon(Icons.check_circle,
                            color: GiColors.primary)
                        : const Icon(Icons.cancel_outlined,
                            color: GiColors.muted),
                    title: Text(dayAndDate(parseDateKey(d.date))),
                    subtitle: Text([
                      d.meal != null
                          ? (d.meal!.fromPaper
                              ? tr('Ate (signed paper list)')
                              : tr('Ate at {time}', {
                                  'time': clockTime(d.meal!.timestamp.toDate())
                                }))
                          : tr('Did not eat'),
                      tr(switch (d.answer?.coming) {
                        true => 'said coming',
                        false => 'said not coming',
                        null => 'no answer',
                      }),
                    ].join('  ·  ')),
                  ),
              ],
            ),
    );
  }
}
