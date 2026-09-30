import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../models/check_in.dart';
import '../services/firestore_service.dart';

/// Lets an employee look up their own attendance record and log today's
/// meal themselves. Two steps: find their name, then unlock with a PIN.
/// First-time users are asked to create a PIN instead of entering one.
class MyRecordScreen extends StatefulWidget {
  const MyRecordScreen({super.key});

  @override
  State<MyRecordScreen> createState() => _MyRecordScreenState();
}

class _MyRecordScreenState extends State<MyRecordScreen> {
  final _service = FirestoreService();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  Employee? _foundEmployee;
  bool _searching = false;
  bool _loggingMeal = false;
  String? _error;
  List<CheckIn>? _checkIns;

  Future<void> _searchName() async {
    setState(() {
      _searching = true;
      _error = null;
      _foundEmployee = null;
      _checkIns = null;
    });

    final employee = await _service.findEmployeeByName(_nameController.text);

    setState(() {
      _searching = false;
      if (employee == null) {
        _error = "Name not found — check the spelling and try again";
      } else {
        _foundEmployee = employee;
      }
    });
  }

  bool _unlocking = false;

  Future<void> _submitPin() async {
    final employee = _foundEmployee;
    if (employee == null) return;

    final enteredPin = _pinController.text.trim();
    if (enteredPin.length != 4) {
      setState(() => _error = 'Enter a 4-digit PIN');
      return;
    }

    setState(() {
      _error = null;
      _unlocking = true;
    });

    try {
      if (employee.pin == null) {
        await _service.setPin(employee.id, enteredPin);
        await _loadRecord(employee.id);
      } else if (employee.pin != enteredPin) {
        setState(() => _error = 'Incorrect PIN');
      } else {
        await _loadRecord(employee.id);
      }
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _loadRecord(String employeeId) async {
    final checkIns = await _service.fetchMyCheckInsThisMonth(employeeId);
    setState(() => _checkIns = checkIns);
  }

  Future<void> _markEaten() async {
    final employee = _foundEmployee;
    if (employee == null) return;

    setState(() => _loggingMeal = true);
    final logged = await _service.selfLogMeal(employee);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(logged
            ? "You're logged for today"
            : "You're already logged for today"),
      ),
    );

    await _loadRecord(employee.id);
    setState(() => _loggingMeal = false);
  }

  void _reset() {
    setState(() {
      _foundEmployee = null;
      _checkIns = null;
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
    return Scaffold(
      backgroundColor: GiColors.beige,
      appBar: AppBar(title: const Text('My meals')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _checkIns != null
                ? _buildRecordView()
                : _foundEmployee != null
                    ? _buildPinEntry()
                    : _buildNameSearch(),
          ),
        ),
      ),
    );
  }

  Widget _buildNameSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Type your full name as it appears on the roster',
          style: GoogleFonts.workSans(fontSize: 16),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(fontSize: 20),
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
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: GiColors.clay)),
        ],
      ],
    );
  }

  Widget _buildPinEntry() {
    final isNewPin = _foundEmployee!.pin == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isNewPin
              ? 'Create a 4-digit PIN for ${_foundEmployee!.name}'
              : 'Enter your PIN, ${_foundEmployee!.name}',
          style: GoogleFonts.workSans(fontSize: 16),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          onSubmitted: (_) => _submitPin(),
        ),
        FilledButton(
          onPressed: _unlocking ? null : _submitPin,
          child: _unlocking
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isNewPin ? 'Save PIN and continue' : 'Unlock'),
        ),
        TextButton(onPressed: _reset, child: const Text('Not you? Go back')),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: GiColors.clay)),
        ],
      ],
    );
  }

  Widget _buildRecordView() {
    final checkIns = _checkIns!;
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final loggedToday = checkIns.any((c) => c.date == todayKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_foundEmployee!.name,
            style: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w600)),
        Text(monthLabel, style: GoogleFonts.workSans(color: GiColors.muted)),
        const SizedBox(height: 16),
        if (loggedToday)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GiColors.oliveBg,
              border: Border.all(color: GiColors.olive.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: GiColors.olive),
                SizedBox(width: 10),
                Text("You're logged for today",
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else
          FilledButton.icon(
            onPressed: _loggingMeal ? null : _markEaten,
            icon: _loggingMeal
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.restaurant),
            label: const Text('I ate today'),
          ),
        const SizedBox(height: 20),
        Text('${checkIns.length} meals logged this month',
            style: GoogleFonts.workSans(fontSize: 16)),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: checkIns.isEmpty
              ? Center(
                  child: Text('No meals logged yet this month',
                      style: GoogleFonts.workSans(color: GiColors.muted)))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: checkIns.length,
                  itemBuilder: (context, index) {
                    final c = checkIns[index];
                    return ListTile(
                      leading: const Icon(Icons.check_circle_outline,
                          color: GiColors.olive),
                      title: Text(c.date),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _reset, child: const Text('Check another name')),
      ],
    );
  }
}
