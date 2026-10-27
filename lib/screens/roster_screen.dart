import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../auth.dart';
import '../employee_roster.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import '../widgets/add_person_dialog.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _service = FirestoreService();
  final _search = TextEditingController();
  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    try {
      final employees = await _service.fetchEmployees();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the roster: $e';
        });
      }
    }
  }

  Future<void> _addPerson() async {
    final added =
        await showAddPerson(context, existing: _employees, rosterOnly: true);
    if (added != null) await _load();
  }

  Future<void> _editDepartment(Employee employee) async {
    final controller = TextEditingController(text: employee.department);
    final department = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Department for ${employee.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Department'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (department == null || department.isEmpty) return;
    try {
      await _service.updateEmployeeDepartment(employee, department);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save department: $e')));
      }
    }
  }

  Future<void> _editName(Employee employee) async {
    final controller = TextEditingController(text: employee.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct the name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.length < 3 || name == employee.name) return;
    try {
      await _service.renameEmployee(employee, name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is NameTaken ? '$e' : 'Could not save name: $e')));
      }
    }
  }

  Future<void> _remove(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${employee.name} from the list?'),
        content: const Text(
            'They will no longer appear at the restaurant or be able to sign '
            'in. Meals already recorded stay on the reports.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: GiColors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.removeEmployee(employee);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    }
  }

  Future<void> _usePreparedRoster() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load the prepared staff list?'),
        content: const Text(
            'Adds anyone from the prepared list who is not here yet and '
            'updates departments. Nobody is removed, and a name already on '
            'the list is never added twice.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Load list')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final added = await _service.replaceRoster(employeeRoster);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('List loaded. Added $added staff members.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load list: $e')));
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final isAudit = staffRoleForEmail(email) == StaffRole.audit;
    final query = _search.text.trim().toLowerCase();
    final filtered = _employees
        .where((e) =>
            query.isEmpty ||
            e.name.toLowerCase().contains(query) ||
            e.department.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      backgroundColor: GiColors.paper,
      appBar: AppBar(
        title: const Text('OFFICE ROSTER'),
        actions: [
          IconButton(
              onPressed: _usePreparedRoster,
              tooltip: 'Load prepared list',
              icon: const Icon(Icons.playlist_add)),
          IconButton(
              onPressed: _addPerson,
              tooltip: 'Add staff member',
              icon: const Icon(Icons.person_add_alt_1)),
          IconButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout)),
        ],
      ),
      body: !isAudit
          ? const Center(child: Text('This page is for audit-office users.'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Authoritative employee list',
                          style: giHeading(size: 24)),
                      const SizedBox(height: 6),
                      const Text(
                          'The audit office owns this list. Add missing staff, '
                          'and use the pencil to correct a name, change a '
                          'department or remove someone.',
                          style: TextStyle(color: GiColors.muted)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Search name or department'),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Text(_error!,
                            style: const TextStyle(color: GiColors.red)),
                      if (_loading)
                        const Expanded(
                            child: Center(child: CircularProgressIndicator()))
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final employee = filtered[index];
                              return Card(
                                child: ListTile(
                                  title: Text(employee.name),
                                  subtitle: Text(employee.department.isEmpty
                                      ? 'Department not set'
                                      : employee.department),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Edit',
                                    onSelected: (choice) => switch (choice) {
                                      'name' => _editName(employee),
                                      'department' => _editDepartment(employee),
                                      _ => _remove(employee),
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'name',
                                          child: Text('Correct name')),
                                      PopupMenuItem(
                                          value: 'department',
                                          child: Text('Change department')),
                                      PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove from list')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
