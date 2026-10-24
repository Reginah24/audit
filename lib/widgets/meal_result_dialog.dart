import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../dates.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import 'coming_buttons.dart';

/// Shown right after a badge scan or a name tap. Confirms the meal in big
/// letters, then asks the one question the kitchen needs answered: will
/// this person eat here on the next working day? Closes by itself so the
/// queue keeps moving even if nobody presses anything.
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
  static const _idleTimeout = Duration(seconds: 15);

  final _service = FirestoreService();
  final _nextDay = nextServiceDay(DateTime.now());

  bool? _coming;
  bool _saving = false;
  bool _answered = false;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _closeTimer = Timer(_idleTimeout, _close);
    _service.fetchAttendance(widget.employee.id, dateKey(_nextDay)).then((a) {
      if (mounted && a != null && _coming == null) {
        setState(() => _coming = a.coming);
      }
    }).catchError((_) {});
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _answer(bool coming) async {
    _closeTimer?.cancel();
    setState(() {
      _coming = coming;
      _saving = true;
    });
    try {
      await _service.setAttendance(
          widget.employee, dateKey(_nextDay), coming, 'employee');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _answered = true;
      });
      _closeTimer = Timer(const Duration(milliseconds: 1600), _close);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the answer: $e')),
      );
    }
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
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: logged ? GiColors.greenBg : GiColors.redBg,
                      ),
                      child: Icon(
                          logged ? Icons.check_rounded : Icons.block_rounded,
                          color: statusColor,
                          size: 44),
                    ),
                    const SizedBox(height: 16),
                    Text(
                        logged
                            ? 'CHECK-IN CONFIRMED'
                            : 'ALREADY RECORDED TODAY',
                        style: giLabel(color: statusColor)),
                    const SizedBox(height: 8),
                    Text(widget.employee.name,
                        textAlign: TextAlign.center,
                        style: giHeading(size: 30)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (widget.employee.department.isNotEmpty)
                          widget.employee.department,
                        DateFormat('EEEE d MMMM, h:mm a')
                            .format(DateTime.now()),
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
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: GiColors.paper,
                  border: Border(top: BorderSide(color: GiColors.line)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        'NEXT SERVICE  |  '
                        '${DateFormat('EEEE d MMMM').format(_nextDay).toUpperCase()}',
                        textAlign: TextAlign.center,
                        style: giLabel()),
                    const SizedBox(height: 8),
                    Text(
                      _answered
                          ? (_coming == true
                              ? 'Thank you. Your place is reserved.'
                              : 'Thank you. Your answer is recorded.')
                          : 'Will you eat here ${friendlyDayName(_nextDay)}?',
                      textAlign: TextAlign.center,
                      style: giHeading(size: 24),
                    ),
                    const SizedBox(height: 18),
                    ComingButtons(
                      selected: _coming,
                      busy: _saving,
                      onChanged: _answer,
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _close, child: const Text('Close')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
