import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../auth.dart';
import '../dates.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../models/check_in.dart';
import '../services/firestore_service.dart';
import '../widgets/coming_buttons.dart';
import '../widgets/formal.dart';

/// Lets an employee answer "will you eat here tomorrow?" from their own
/// phone and see their meals this month. Meals themselves can only be
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

  final _nextDay = nextServiceDay(DateTime.now());
  bool? _comingNextDay;
  bool _savingComing = false;
  int _tab = 0;

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
          _error = 'Name not found. Check the spelling and try again, '
              'or ask at the restaurant.';
        } else if (matches.length == 1) {
          _foundEmployee = matches.single;
        } else if (matches.length > 8) {
          _error = 'Many people match. Please type more of your name.';
        } else {
          _candidates = matches;
        }
      });
    } catch (e) {
      setState(() => _error = 'No connection. Please try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submitPin() async {
    final employee = _foundEmployee;
    if (employee == null) return;

    final pin = _pinController.text.trim();
    if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      setState(() => _error = 'The PIN is 4 numbers');
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
              _error = 'This name already has a PIN. Enter that PIN.';
            });
          }
        }
      } else {
        ok = await employeeSignIn(employee, pin);
        if (!ok) setState(() => _error = 'Wrong PIN. Please try again.');
      }
      if (ok) await _loadRecord(employee.id);
    } on SignInProblem catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      _pinController.clear();
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _loadRecord(String employeeId) async {
    final (checkIns, answer, badgeKey) = await (
      _service.fetchMyCheckInsThisMonth(employeeId),
      _service.fetchAttendance(employeeId, dateKey(_nextDay)),
      _service.fetchBadgeKey(employeeId),
    ).wait;
    if (!mounted) return;
    setState(() {
      _checkIns = checkIns;
      _comingNextDay = answer?.coming;
      _badgeKey = badgeKey;
    });
  }

  Future<void> _answerComing(bool coming) async {
    final employee = _foundEmployee;
    if (employee == null) return;

    setState(() => _savingComing = true);
    try {
      await _service.setAttendance(
          employee, dateKey(_nextDay), coming, 'employee');
      if (mounted) setState(() => _comingNextDay = coming);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Could not save. Check the internet and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingComing = false);
    }
  }

  Future<void> _signOut() async {
    await employeeSignOut();
    setState(() {
      _foundEmployee = null;
      _candidates = const [];
      _checkIns = null;
      _comingNextDay = null;
      _badgeKey = null;
      _tab = 0;
      _error = null;
      _nameController.clear();
      _pinController.clear();
    });
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
    const titles = ['DAILY PLANNER', 'MEAL PASS', 'MY PROFILE'];

    return Scaffold(
      appBar: AppBar(title: Text(signedIn ? titles[_tab] : 'MY MEALS')),
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
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home'),
                NavigationDestination(
                    icon: Icon(Icons.qr_code_2),
                    selectedIcon: Icon(Icons.qr_code_2),
                    label: 'Pass'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profile'),
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
        Text('STEP 1 OF 2', style: giLabel()),
        const SizedBox(height: 8),
        Text('Find your name', style: giHeading(size: 28)),
        const SizedBox(height: 8),
        Text('Type your name. Capital letters do not matter.',
            style: giBody(color: GiColors.muted)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: giBody(size: 20),
          decoration: const InputDecoration(labelText: 'Your name'),
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
              : const Text('Continue'),
        ),
        _errorText(),
        if (_candidates.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('WHICH ONE ARE YOU?', style: giLabel()),
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
        Text('STEP 2 OF 2', style: giLabel()),
        const SizedBox(height: 8),
        Text(isNewPin ? 'Create your PIN' : 'Enter your PIN',
            style: giHeading(size: 28)),
        const SizedBox(height: 8),
        Text(
          isNewPin
              ? 'Welcome, ${_foundEmployee!.name}. Choose 4 numbers and '
                  'remember them. Do not share your PIN with anyone.'
              : '${_foundEmployee!.name}, enter your 4-number PIN.',
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
              : Text(isNewPin ? 'Save PIN and continue' : 'Sign in'),
        ),
        _errorText(),
        const SizedBox(height: 8),
        TextButton(onPressed: _signOut, child: const Text('Not you? Go back')),
        if (!isNewPin)
          Text('Forgotten your PIN? The restaurant manager can reset it.',
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
    final part =
        h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
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
        Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: giBody(color: GiColors.muted)),
        const SizedBox(height: 22),
        SectionCard(
          header: 'Next service  |  '
              '${DateFormat('EEEE d MMMM').format(_nextDay)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Will you eat here ${friendlyDayName(_nextDay)}?',
                  style: giHeading(size: 24)),
              const SizedBox(height: 6),
              Text('Your answer tells the kitchen how many meals to prepare.',
                  style: giBody(size: 16, color: GiColors.muted)),
              const SizedBox(height: 18),
              ComingButtons(
                selected: _comingNextDay,
                busy: _savingComing,
                onChanged: _answerComing,
              ),
              if (_comingNextDay != null) ...[
                const SizedBox(height: 14),
                StatusLine(
                  icon: Icons.check_circle,
                  text: _comingNextDay!
                      ? 'Confirmed: you will eat here'
                      : 'Recorded: you will not eat here',
                  color: _comingNextDay! ? GiColors.primary : GiColors.accent,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("TODAY'S STATUS", style: giLabel()),
              const SizedBox(height: 10),
              meal != null
                  ? StatusLine(
                      icon: Icons.check_circle,
                      text: 'Meal taken at '
                          '${DateFormat('h:mm a').format(meal.timestamp.toDate())}',
                      color: GiColors.primary)
                  : const StatusLine(
                      icon: Icons.schedule,
                      text: 'Not yet checked in',
                      color: GiColors.muted),
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text('Meals this month',
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
                Text('Your pass has not been issued yet.',
                    textAlign: TextAlign.center, style: giHeading(size: 20)),
                const SizedBox(height: 6),
                Text('Please ask at the restaurant counter.',
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
        Text('Scan on arrival',
            textAlign: TextAlign.center, style: giHeading(size: 24)),
        const SizedBox(height: 4),
        Text('Hold this screen, or your printed pass, to the counter camera.',
            textAlign: TextAlign.center,
            style: giBody(size: 16, color: GiColors.muted)),
        const SizedBox(height: 18),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CHECK-IN STATUS', style: giLabel()),
              const SizedBox(height: 10),
              meal != null
                  ? StatusLine(
                      icon: Icons.check_circle,
                      text: 'Checked in at '
                          '${DateFormat('h:mm a').format(meal.timestamp.toDate())}',
                      color: GiColors.primary)
                  : const StatusLine(
                      icon: Icons.radio_button_unchecked,
                      text: 'Awaiting scan',
                      color: GiColors.accent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfile() {
    final employee = _foundEmployee!;
    final checkIns = _checkIns!;
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
        SectionCard(
          header: 'Meal history  |  '
              '${DateFormat('MMMM yyyy').format(DateTime.now())}',
          headerColor: GiColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: checkIns.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No meals recorded yet this month.',
                      style: giBody(color: GiColors.muted)),
                )
              : Column(
                  children: [
                    for (final c in checkIns.reversed)
                      ListTile(
                        leading: const Icon(Icons.check_circle_outline,
                            color: GiColors.primary),
                        title: Text(DateFormat('EEEE d MMMM')
                            .format(parseDateKey(c.date))),
                        trailing: Text(
                            DateFormat('h:mm a').format(c.timestamp.toDate()),
                            style: giBody(size: 15, color: GiColors.muted)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
