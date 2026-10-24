import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import '../services/pdf_service.dart';

/// Print everyone's badges, or replace one that was lost. Replacing gives
/// the person a new secret key, so the lost card stops working at once.
class BadgesScreen extends StatefulWidget {
  final List<Employee> employees;

  const BadgesScreen({super.key, required this.employees});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  final _service = FirestoreService();
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printAll() => _run(() async {
        final keys = await _service.ensureBadgeKeys(widget.employees);
        final bytes = await buildBadgesPdf(widget.employees, keys);
        await printPdf(bytes, 'meal-passes.pdf');
      });

  Future<void> _replace(Employee e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New meal pass for ${e.name}?'),
        content: const Text(
            'Their old pass will stop working immediately. Only do this '
            'if the pass was lost or someone else may have a copy.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Issue new pass'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final key = await _service.replaceBadgeKey(e.id);
      final bytes = await buildBadgesPdf([e], {e.id: key});
      await printPdf(bytes, 'meal-pass.pdf');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GiColors.paper,
      appBar: AppBar(title: const Text('MEAL PASSES')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton.icon(
                onPressed: _busy || widget.employees.isEmpty ? null : _printAll,
                icon: const Icon(Icons.print),
                label: Text('Print passes for everyone',
                    style: GoogleFonts.publicSans(
                        fontSize: 19, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Printing is optional: anyone with a smartphone can show the '
              'same pass from My meals > Pass. Print cards for people without '
              'a smartphone. Printing again gives the same passes. If a pass '
              'is lost or a phone is stolen, tap "Lost": the old pass stops '
              'working and the phone shows the new one next time it opens.',
              style: GoogleFonts.publicSans(color: GiColors.muted),
            ),
          ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.employees.length,
              itemBuilder: (context, i) {
                final e = widget.employees[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(e.name,
                        style: GoogleFonts.publicSans(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(e.department),
                    trailing: OutlinedButton(
                      onPressed: _busy ? null : () => _replace(e),
                      child: const Text('Lost'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
