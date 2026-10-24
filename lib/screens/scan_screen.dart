import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../dates.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import '../widgets/meal_result_dialog.dart';

/// Kiosk mode for the tablet at the counter: the camera stays on, people
/// hold up their badge, the meal is recorded and they answer "tomorrow?".
/// Nothing to type, nothing to find.
class ScanScreen extends StatefulWidget {
  /// The roster already loaded by the staff screen, so a scan doesn't wait
  /// on Firestore just to learn a name.
  final List<Employee> employees;

  /// Current badge key per employee id. A badge whose key doesn't match
  /// was replaced (lost card) and is refused.
  final Map<String, String> badgeKeys;

  const ScanScreen(
      {super.key, required this.employees, required this.badgeKeys});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _service = FirestoreService();
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  late final Map<String, Employee> _byId = {
    for (final e in widget.employees) e.id: e,
  };
  late final Map<String, String> _keys = {...widget.badgeKeys};

  bool _busy = false;
  String? _message;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || capture.barcodes.isEmpty) return;
    final badge = parseBadge(capture.barcodes.first.rawValue);

    if (badge == null) {
      setState(() => _message = 'That is not a meal pass');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final id = badge.id;
      final key = _keys[id] ?? await _service.fetchBadgeKey(id);
      if (key == null || key != badge.key) {
        if (mounted) {
          setState(() => _message =
              'This pass is no longer valid. Please ask at the counter.');
        }
        return;
      }
      _keys[id] = key;

      final employee = _byId[id] ?? await _service.fetchEmployee(id);
      if (employee == null) {
        if (mounted) {
          setState(() =>
              _message = 'Pass not recognised. Please ask at the counter.');
        }
        return;
      }
      _byId[id] = employee;

      final result = await _service.recordMeal(employee, 'scan');
      if (!mounted) return;
      await showMealResult(context, employee: employee, result: result);
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not record: $e');
    } finally {
      // A short pause so the same badge, still in front of the camera,
      // isn't read again the moment the dialog closes.
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GiColors.paper,
      appBar: AppBar(
        title: const Text('SCAN MEAL PASS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Switch camera',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Hold your meal pass in front of the camera',
              textAlign: TextAlign.center,
              style: GoogleFonts.publicSans(
                  color: GiColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(color: GiColors.primary, width: 4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Camera not available.\n'
                          'Allow camera access, or use "Find name" instead.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.publicSans(
                              color: GiColors.ink, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(16),
            color: _message == null ? GiColors.primary : GiColors.red,
            alignment: Alignment.center,
            child: Text(
              _busy ? 'One moment…' : (_message ?? 'Ready'),
              textAlign: TextAlign.center,
              style: GoogleFonts.publicSans(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
