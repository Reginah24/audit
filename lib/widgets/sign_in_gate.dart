import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../auth.dart';
import '../theme.dart';
import '../screens/role_login_screen.dart';

/// Shows a sign-in form until someone with the right account is signed in,
/// then shows [builder]. "Right account" is decided by the database rules:
/// [probe] runs a read that only allowed accounts may do, so the list of
/// who's allowed lives in one place (firestore.rules), not in the app.
class SignInGate extends StatefulWidget {
  final String title;
  final String explanation;
  final Future<void> Function() probe;
  final WidgetBuilder builder;

  const SignInGate({
    super.key,
    required this.title,
    required this.explanation,
    required this.probe,
    required this.builder,
  });

  @override
  State<SignInGate> createState() => _SignInGateState();
}

enum _Access { checking, allowed, denied, failed }

class _SignInGateState extends State<SignInGate> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _signingIn = false;
  String? _error;

  String? _checkedUid;
  _Access _access = _Access.checking;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await staffSignIn(_email.text, _password.text);
      _password.clear();
    } on SignInProblem catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _backToRoleSelection() {
    FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleLoginScreen()),
      (route) => false,
    );
  }

  Future<void> _check(String uid) async {
    _checkedUid = uid;
    _access = _Access.checking;
    try {
      await widget.probe();
      if (mounted && _checkedUid == uid) {
        setState(() => _access = _Access.allowed);
      }
    } on FirebaseException catch (e) {
      if (mounted && _checkedUid == uid) {
        setState(() => _access =
            e.code == 'permission-denied' ? _Access.denied : _Access.failed);
      }
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
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          _checkedUid = null;
          return _buildForm();
        }
        if (_checkedUid != user.uid) _check(user.uid);

        return switch (_access) {
          _Access.allowed => widget.builder(context),
          _Access.checking => Scaffold(
              backgroundColor: GiColors.paper,
              appBar: _buildAppBar(),
              body: const Center(child: CircularProgressIndicator()),
            ),
          _Access.denied => _buildMessage(
              'The account ${user.email} is not allowed to open this page.'),
          _Access.failed => _buildMessage(
              'Could not reach the database. Check the internet connection.',
              retry: () => setState(() => _check(user.uid))),
        };
      },
    );
  }

  Widget _buildMessage(String message, {VoidCallback? retry}) {
    return Scaffold(
      backgroundColor: GiColors.paper,
      appBar: _buildAppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.publicSans(fontSize: 17)),
                const SizedBox(height: 20),
                if (retry != null) ...[
                  FilledButton(
                      onPressed: retry, child: const Text('Try again')),
                  const SizedBox(height: 10),
                ],
                OutlinedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign in with a different account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Scaffold(
      backgroundColor: GiColors.paper,
      appBar: _buildAppBar(),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(Icons.lock_outline,
                          color: GiColors.ink, size: 40),
                    ),
                    const SizedBox(height: 12),
                    Text('Sign in', style: giHeading(size: 34)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                          height: 5, width: 56, color: GiColors.accent),
                    ),
                    const SizedBox(height: 16),
                    Text(widget.explanation, style: giBody(size: 18)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _signIn(),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _signingIn ? null : _signIn,
                      child: _signingIn
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Sign in'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: GiColors.red)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(widget.title.toUpperCase()),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back to role selection',
        onPressed: _backToRoleSelection,
      ),
    );
  }
}
