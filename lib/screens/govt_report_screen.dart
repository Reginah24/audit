import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../services/firestore_service.dart';
import '../admin_config.dart';

/// Read-only summary for the government office: how many meals each
/// employee had in a given month, so their leaders know what to deduct.
/// Gated by a single shared passcode (see admin_config.dart).
class GovtReportScreen extends StatefulWidget {
  const GovtReportScreen({super.key});

  @override
  State<GovtReportScreen> createState() => _GovtReportScreenState();
}

class _GovtReportScreenState extends State<GovtReportScreen> {
  final _service = FirestoreService();
  final _passcodeController = TextEditingController();

  bool _unlocked = false;
  String? _passcodeError;

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, int>? _summary;
  bool _loading = false;

  void _checkPasscode() {
    if (_passcodeController.text.trim() == govtReportPasscode) {
      setState(() {
        _unlocked = true;
        _passcodeError = null;
      });
      _loadReport();
    } else {
      setState(() => _passcodeError = 'Incorrect passcode');
    }
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);

    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final grouped = await _service.fetchCheckInsForRange(start, end);

    setState(() {
      _summary = {
        for (final entry in grouped.entries) entry.key: entry.value.length
      };
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadReport();
  }

  @override
  void dispose() {
    _passcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GiColors.beige,
      appBar: AppBar(title: const Text('Monthly report')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _unlocked ? _buildReport() : _buildPasscodeGate(),
          ),
        ),
      ),
    );
  }

  Widget _buildPasscodeGate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enter the passcode given to you by the restaurant to view this report.',
          style: GoogleFonts.workSans(fontSize: 16),
        ),
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
        FilledButton(onPressed: _checkPasscode, child: const Text('View report')),
        if (_passcodeError != null) ...[
          const SizedBox(height: 12),
          Text(_passcodeError!, style: const TextStyle(color: GiColors.clay)),
        ],
      ],
    );
  }

  Widget _buildReport() {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final summary = _summary ?? {};
    final sortedNames = summary.keys.toList()..sort();
    final total = summary.values.fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: GiColors.rust),
              onPressed: () => _changeMonth(-1),
            ),
            Text(monthLabel,
                style: GoogleFonts.fraunces(
                    fontSize: 22, fontWeight: FontWeight.w600)),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: GiColors.rust),
              onPressed: () => _changeMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (sortedNames.isEmpty)
          Expanded(
              child: Center(
                  child: Text('No meals logged for this month',
                      style: GoogleFonts.workSans(color: GiColors.muted))))
        else
          Expanded(
            child: ListView(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: GiColors.cream,
                    border: Border.all(color: GiColors.hairline),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: GiColors.beige),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('Employee',
                                style: GoogleFonts.workSans(
                                    fontWeight: FontWeight.w600)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('Meals',
                                style: GoogleFonts.workSans(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      for (final name in sortedNames)
                        TableRow(
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: GiColors.hairline),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(name, style: GoogleFonts.workSans()),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('${summary[name]}',
                                  style: GoogleFonts.workSans()),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Total meals: $total',
                    style: GoogleFonts.fraunces(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}
