import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';

Future<void> showMealResult(
  BuildContext context, {
  required Employee employee,
  required MealResult result,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MealResultDialog(employee: employee, result: result),
  );
}

class _MealResultDialog extends StatefulWidget {
  final Employee employee;
  final MealResult result;

  const _MealResultDialog({required this.employee, required this.result});

  @override
  State<_MealResultDialog> createState() => _MealResultDialogState();
}

class _MealResultDialogState extends State<_MealResultDialog> {
  static const _idleTimeout = Duration(seconds: 8);
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _closeTimer = Timer(_idleTimeout, _close);
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logged = widget.result == MealResult.logged;
    final statusColor = logged ? GiColors.green : GiColors.red;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(logged ? Icons.check_circle : Icons.block,
                  color: statusColor, size: 72),
              const SizedBox(height: 16),
              Text(logged ? 'CHECK-IN CONFIRMED' : 'ALREADY RECORDED TODAY',
                  style: giLabel(color: statusColor)),
              const SizedBox(height: 8),
              Text(widget.employee.name,
                  textAlign: TextAlign.center, style: giHeading(size: 30)),
              const SizedBox(height: 6),
              Text(
                [
                  if (widget.employee.department.isNotEmpty)
                    widget.employee.department,
                  DateFormat('EEEE d MMMM, h:mm a').format(DateTime.now()),
                ].join('  |  '),
                textAlign: TextAlign.center,
                style: giBody(size: 16, color: GiColors.muted),
              ),
              if (!logged) ...[
                const SizedBox(height: 14),
                Text('A second meal on the same day is not permitted.',
                    textAlign: TextAlign.center,
                    style: giBody(
                        size: 17,
                        color: GiColors.red,
                        weight: FontWeight.w600)),
              ],
              const SizedBox(height: 18),
              TextButton(onPressed: _close, child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }
}
