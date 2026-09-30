import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../models/check_in.dart';
import '../services/firestore_service.dart';
import '../employee_roster.dart';
import '../admin_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = FirestoreService();
  final _searchController = TextEditingController();
  final _passcodeController = TextEditingController();

  bool _unlocked = false;
  String? _passcodeError;

  List<Employee> _allEmployees = [];
  List<Employee> _filteredEmployees = [];
  bool _loadingEmployees = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _checkPasscode() {
    if (_passcodeController.text.trim() == managerPasscode) {
      setState(() {
        _unlocked = true;
        _passcodeError = null;
      });
      _loadEmployees();
    } else {
      setState(() => _passcodeError = 'Incorrect passcode');
    }
  }

  Future<void> _loadEmployees() async {
    final employees = await _service.fetchEmployees();
    setState(() {
      _allEmployees = employees;
      _filteredEmployees = employees;
      _loadingEmployees = false;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredEmployees = query.isEmpty
          ? _allEmployees
          : _allEmployees
              .where((e) => e.name.toLowerCase().contains(query))
              .toList();
    });
  }

  Future<void> _confirmAndLog(Employee employee, List<CheckIn> today) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm meal'),
        content: Text('Log a meal for ${employee.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final logged = await _service.logMeal(employee, today);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          logged
              ? '${employee.name} logged'
              : '${employee.name} already logged today',
        ),
      ),
    );

    _searchController.clear();
  }

  Future<void> _seedRoster() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load employee roster?'),
        content: Text(
          'This will add ${employeeRoster.length} employees from '
          'employee_roster.dart to Firestore. Only do this once — '
          'running it again will create duplicates.',
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
      SnackBar(content: Text('Loaded $count employees')),
    );
    await _loadEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return Scaffold(
        backgroundColor: GiColors.beige,
        appBar: AppBar(title: const Text('Staff sign-in')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter the staff passcode to continue',
                      style: GoogleFonts.workSans(fontSize: 15)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passcodeController,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    onSubmitted: (_) => _checkPasscode(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _checkPasscode,
                    child: const Text('Continue'),
                  ),
                  if (_passcodeError != null) ...[
                    const SizedBox(height: 12),
                    Text(_passcodeError!,
                        style: const TextStyle(color: GiColors.clay)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: GiColors.beige,
        appBar: AppBar(
          title: const Text('Giraphe'),
          actions: [
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Load employee roster (one-time)',
              onPressed: _seedRoster,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Check in'),
              Tab(text: 'Logged today'),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(
              hintText: 'Type a name',
              prefixIcon: Icon(Icons.search, color: GiColors.rust),
            ),
          ),
        ),
        Expanded(
          child: _loadingEmployees
              ? const Center(child: CircularProgressIndicator())
              : notYetLogged.isEmpty
                  ? Center(
                      child: Text('No matching name found',
                          style: GoogleFonts.workSans(color: GiColors.muted)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: notYetLogged.length,
                      itemBuilder: (context, index) {
                        final employee = notYetLogged[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(employee.name,
                                style: GoogleFonts.workSans(
                                    fontSize: 17, fontWeight: FontWeight.w600)),
                            subtitle: Text(employee.department),
                            trailing: const Icon(Icons.chevron_right,
                                color: GiColors.rust),
                            onTap: () => _confirmAndLog(employee, todaysCheckins),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildLoggedTodayTab(List<CheckIn> todaysCheckins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: GiColors.espresso,
          child: Text(
            "Today's count: ${todaysCheckins.length}",
            style: GoogleFonts.fraunces(
              color: GiColors.cream,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: todaysCheckins.isEmpty
              ? Center(
                  child: Text('No one logged yet today',
                      style: GoogleFonts.workSans(color: GiColors.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: todaysCheckins.length,
                  itemBuilder: (context, index) {
                    final c = todaysCheckins[index];
                    final time = DateFormat('h:mm a').format(c.timestamp.toDate());
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.check_circle, color: GiColors.olive),
                        title: Text(c.employeeName,
                            style: GoogleFonts.workSans(fontWeight: FontWeight.w600)),
                        subtitle: Text('Logged at $time'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: GiColors.muted),
                          tooltip: 'Undo',
                          onPressed: () => _service.deleteCheckIn(c.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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
                style: GoogleFonts.workSans(color: GiColors.muted, fontSize: 16),
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
            final time = ts is Timestamp
                ? DateFormat('h:mm a').format(ts.toDate())
                : '';
            final source = a['source'] == 'self-service'
                ? 'Scanned own phone'
                : 'Tapped at till';

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: GiColors.clayBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: GiColors.clay),
              ),
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: GiColors.clay),
                title: Text('${a['employeeName']} tried to log a second meal',
                    style: GoogleFonts.workSans(fontWeight: FontWeight.w600)),
                subtitle: Text('$source · $time'),
              ),
            );
          },
        );
      },
    );
  }
}
