import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/role_login_screen.dart';
import 'screens/govt_report_screen.dart';
import 'screens/my_record_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initEmployeeApp();
  runApp(const GiraphApp());
}

class GiraphApp extends StatelessWidget {
  const GiraphApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Giraphe Meal App',
      theme: buildGiTheme(),
      initialRoute: '/',
      routes: {
        '/': (context) => const RoleLoginScreen(),
        '/report': (context) => const GovtReportScreen(),
        '/my-record': (context) => const MyRecordScreen(),
      },
    );
  }
}
