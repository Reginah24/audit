import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import '../services/pdf_service.dart';
import '../text_match.dart';
import 'formal.dart';

/// Adds someone who isn't on the office's list. Returns the new person if
/// the cashier chose "Record meal now", so the counter can record it.
Future<Employee?> showAddPerson(
  BuildContext context, {
  required List<Employee> existing,
  String initialName = '',
  bool rosterOnly = false,
}) {
  return showDialog<Employee>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddPersonDialog(
        existing: existing, initialName: initialName, rosterOnly: rosterOnly),
  );
}

class _AddPersonDialog extends StatefulWidget {
  final List<Employee> existing;
  final String initialName;
  final bool rosterOnly;

  const _AddPersonDialog(
      {required this.existing,
      required this.initialName,
      required this.rosterOnly});

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  final _service = FirestoreService();
  late final _name = TextEditingController(text: widget.initialName);
  final _department = TextEditingController();

  bool _saving = false;
  bool _printing = false;
  String? _error;
  Employee? _added;

  /// Departments already in use, most common first, offered as one-tap
  /// choices so nobody has to spell them (and they stay consistent).
  late final List<String> _departments = () {
    final counts = <String, int>{};
    for (final e in widget.existing) {
      final d = e.department.trim();
      if (d.isNotEmpty) counts[d] = (counts[d] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }();

  Employee? get _sameName {
    for (final e in widget.existing) {
      if (sameName(e.name, _name.text)) return e;
    }
    return null;
  }

  /// "finance" or "FINANCE " becomes the existing "Finance", so one
  /// department doesn't end up split under different spellings.
  String get _canonicalDepartment {
    final typed = FirestoreService.tidyName(_department.text);
    for (final d in _departments) {
      if (sameName(d, typed)) return d;
    }
    return typed;
  }

  Future<void> _save() async {
    final name = FirestoreService.tidyName(_name.text);
    if (name.length < 3) {
      setState(() => _error = 'Please enter the full name.');
      return;
    }
    if (FirestoreService.tidyName(_department.text).isEmpty) {
      setState(() => _error = 'Please choose or type the department.');
      return;
    }
    final same = _sameName;
    if (same != null) {
      setState(() =>
          _error = '${same.name} (${same.department}) is already on the list. '
              'Search for the name instead of adding it again.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final added = await _service.addEmployee(name, _canonicalDepartment,
          source: widget.rosterOnly ? 'roster' : 'counter');
      if (mounted) setState(() => _added = added);
    } on NameTaken catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not add the person: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printPass() async {
    final e = _added!;
    setState(() => _printing = true);
    try {
      // Someone just added has no pass key yet; this creates it.
      final keys = await _service.ensureBadgeKeys([e]);
      final bytes = await buildBadgesPdf([e], keys);
      await printPdf(bytes, 'meal-pass.pdf');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _department.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
          child: _added == null ? _buildForm() : _buildDone(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('NOT ON THE LIST', style: giLabel()),
        const SizedBox(height: 6),
        Text('Add a person', style: giHeading(size: 26)),
        const SizedBox(height: 6),
        Text(
            widget.rosterOnly
                ? 'Add a staff member to the official office roster.'
                : 'They will get a meal pass straight away. The office report '
                    'shows who added them and when.',
            style: giBody(size: 16, color: GiColors.muted)),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          autofocus: widget.initialName.isEmpty,
          textCapitalization: TextCapitalization.words,
          style: giBody(size: 19),
          decoration: const InputDecoration(labelText: 'Full name'),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _department,
          textCapitalization: TextCapitalization.words,
          style: giBody(size: 19),
          decoration: const InputDecoration(labelText: 'Department'),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_departments.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _departments.take(10))
                ChoiceChip(
                  label: Text(d),
                  selected: sameName(_department.text, d),
                  onSelected: (_) => setState(() {
                    _department.text = d;
                    _error = null;
                  }),
                ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          StatusLine(
              icon: Icons.error_outline, text: _error!, color: GiColors.red),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.person_add_alt_1),
          label: const Text('Add person'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildDone() {
    final e = _added!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: GiColors.greenBg),
            child: const Icon(Icons.check_rounded,
                color: GiColors.primary, size: 42),
          ),
        ),
        const SizedBox(height: 14),
        Text('PERSON ADDED',
            textAlign: TextAlign.center,
            style: giLabel(color: GiColors.primary)),
        const SizedBox(height: 6),
        Text(e.name, textAlign: TextAlign.center, style: giHeading(size: 26)),
        Text(e.department,
            textAlign: TextAlign.center, style: giBody(color: GiColors.muted)),
        const SizedBox(height: 22),
        if (!widget.rosterOnly) ...[
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, e),
            icon: const Icon(Icons.restaurant),
            label: const Text('Record meal now'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _printing ? null : _printPass,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print meal pass'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
