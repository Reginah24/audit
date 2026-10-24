import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'models/employee.dart';

/// Employees sign in through a second, separate Firebase app so that an
/// employee checking their meals on the restaurant tablet never signs the
/// restaurant account out (and vice versa).
const _employeeAppName = 'employee';

Future<void> initEmployeeApp() => Firebase.initializeApp(
      name: _employeeAppName,
      options: DefaultFirebaseOptions.currentPlatform,
    );

FirebaseAuth get employeeAuth =>
    FirebaseAuth.instanceFor(app: Firebase.app(_employeeAppName));

FirebaseFirestore get employeeDb =>
    FirebaseFirestore.instanceFor(app: Firebase.app(_employeeAppName));

/// Behind the scenes an employee's login is "<their id>@this domain" with
/// a password built from their PIN. Must match isEmployee() in
/// firestore.rules. Nobody ever types or sees this.
String _employeeEmail(String employeeId) =>
    '${employeeId.toLowerCase()}@employees.giraphe.app';

/// Firebase needs at least six characters; employees only remember four
/// digits. Firebase Auth locks the login after repeated wrong tries, which
/// is what stops someone guessing all 10,000 PINs.
String _pinPassword(String pin) => 'giraphe-meal-$pin';

/// Thrown with a message that can be shown on screen as-is.
class SignInProblem implements Exception {
  final String message;
  SignInProblem(this.message);
  @override
  String toString() => message;
}

String _friendly(FirebaseAuthException e) => switch (e.code) {
      'too-many-requests' =>
        'Too many wrong tries. Please wait a few minutes and try again.',
      'network-request-failed' =>
        'No internet connection. Please check the connection and try again.',
      'user-disabled' => 'This account has been switched off.',
      'operation-not-allowed' =>
        'Sign-in is not switched on yet. Ask the restaurant manager.',
      _ => 'Could not sign in (${e.code}).',
    };

/// Signs an employee in with their PIN. Returns false for a wrong PIN.
Future<bool> employeeSignIn(Employee employee, String pin) async {
  try {
    await employeeAuth.signInWithEmailAndPassword(
        email: _employeeEmail(employee.id), password: _pinPassword(pin));
    return true;
  } on FirebaseAuthException catch (e) {
    if (const [
      'wrong-password',
      'invalid-credential',
      'user-not-found',
      'invalid-login-credentials'
    ].contains(e.code)) {
      return false;
    }
    throw SignInProblem(_friendly(e));
  }
}

/// First visit: creates the employee's login with the PIN they chose.
/// Returns false if a PIN already exists for this person.
Future<bool> employeeCreatePin(Employee employee, String pin) async {
  try {
    final cred = await employeeAuth.createUserWithEmailAndPassword(
        email: _employeeEmail(employee.id), password: _pinPassword(pin));
    // Keeps the exact (case-sensitive) employee id, so a returning visitor
    // can be recognised without typing their name again.
    await cred.user?.updateDisplayName(employee.id);
  } on FirebaseAuthException catch (e) {
    if (e.code == 'email-already-in-use') return false;
    throw SignInProblem(_friendly(e));
  }
  await employeeDb
      .collection('employees')
      .doc(employee.id)
      .update({'pinSet': true});
  return true;
}

/// The employee already signed in on this device, if any.
String? signedInEmployeeId() => employeeAuth.currentUser?.displayName;

Future<void> employeeSignOut() => employeeAuth.signOut();

/// Restaurant and office accounts (the main Firebase app).
Future<void> staffSignIn(String email, String password) async {
  try {
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email.trim(), password: password);
  } on FirebaseAuthException catch (e) {
    if (const [
      'wrong-password',
      'invalid-credential',
      'user-not-found',
      'invalid-email',
      'invalid-login-credentials'
    ].contains(e.code)) {
      throw SignInProblem('Wrong email or password.');
    }
    throw SignInProblem(_friendly(e));
  }
}
