import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../auth.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'govt_report_screen.dart';
import 'my_record_screen.dart';

enum _LoginRole { customer, restaurant, audit }

class RoleLoginScreen extends StatefulWidget {
  const RoleLoginScreen({super.key});

  @override
  State<RoleLoginScreen> createState() => _RoleLoginScreenState();
}

class _RoleLoginScreenState extends State<RoleLoginScreen> {
  _LoginRole _role = _LoginRole.customer;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _signInStaff() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await staffSignIn(_email.text, _password.text);
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      final role = staffRoleForEmail(email);
      if ((_role == _LoginRole.restaurant && role != StaffRole.restaurant) ||
          (_role == _LoginRole.audit && role != StaffRole.audit)) {
        await FirebaseAuth.instance.signOut();
        throw SignInProblem('This account is not permitted for that role.');
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _role == _LoginRole.restaurant
              ? const HomeScreen()
              : const GovtReportScreen(),
        ),
      );
    } on SignInProblem catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customer = _role == _LoginRole.customer;
    return Scaffold(
      backgroundColor: GiColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('STAFF MEAL SERVICE', style: giLabel()),
                  const SizedBox(height: 8),
                  Text('Sign in', style: giHeading(size: 34)),
                  const SizedBox(height: 24),
                  SegmentedButton<_LoginRole>(
                    segments: const [
                      ButtonSegment(
                          value: _LoginRole.customer,
                          label: Text('Customer'),
                          icon: Icon(Icons.badge_outlined)),
                      ButtonSegment(
                          value: _LoginRole.restaurant,
                          label: Text('Restaurant'),
                          icon: Icon(Icons.storefront_outlined)),
                      ButtonSegment(
                          value: _LoginRole.audit,
                          label: Text('Audit'),
                          icon: Icon(Icons.assessment_outlined)),
                    ],
                    selected: {_role},
                    onSelectionChanged: (value) =>
                        setState(() => _role = value.first),
                  ),
                  const SizedBox(height: 24),
                  if (customer) ...[
                    Text(
                        'Returning customer: use your name and PIN. '
                        'First time here? Create your PIN below.',
                        style: giBody(size: 18)),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MyRecordScreen())),
                      child: const Text('Open My Meals'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MyRecordScreen())),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('First time? Create customer PIN'),
                    ),
                  ] else ...[
                    Text(
                        _role == _LoginRole.restaurant
                            ? 'Restaurant staff sign in to manage the counter.'
                            : 'Audit officials sign in to view reports.',
                        style: giBody(size: 18)),
                    const SizedBox(height: 8),
                    Text(
                      'These are managed accounts. Restaurant and Audit '
                      'users cannot create public accounts here.',
                      style: giBody(size: 14, color: GiColors.muted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _signInStaff(),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _signInStaff,
                      child: _busy
                          ? const CircularProgressIndicator()
                          : const Text('Sign in'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: GiColors.red)),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
