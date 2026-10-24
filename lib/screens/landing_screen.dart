import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../admin_config.dart';
import '../theme.dart';
import '../widgets/formal.dart';
import 'home_screen.dart';
import 'my_record_screen.dart';
import 'govt_report_screen.dart';

/// First screen anyone sees, whether on the tablet or the public web link.
/// Three destinations, each named for what the person is there to do.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 36, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: GiColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.restaurant,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(restaurantName, style: giHeading(size: 18)),
                              Text(officeName,
                                  style:
                                      giBody(size: 14, color: GiColors.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text('STAFF MEAL SERVICE', style: giLabel()),
                    const SizedBox(height: 8),
                    Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                        style: giHeading(size: 30)),
                    const SizedBox(height: 32),
                    MenuCard(
                      icon: Icons.storefront_outlined,
                      title: 'Restaurant counter',
                      description: 'Record meals and see how many to prepare',
                      onTap: () => _open(context, const HomeScreen()),
                    ),
                    const SizedBox(height: 14),
                    MenuCard(
                      icon: Icons.badge_outlined,
                      title: 'My meals',
                      description: 'Confirm tomorrow and show your meal pass',
                      onTap: () => _open(context, const MyRecordScreen()),
                    ),
                    const SizedBox(height: 14),
                    MenuCard(
                      icon: Icons.assessment_outlined,
                      title: 'Reports',
                      description: 'Daily and monthly records for the office',
                      onTap: () => _open(context, const GovtReportScreen()),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        const Icon(Icons.verified_user_outlined,
                            color: GiColors.muted, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Records are signed in, time-stamped by the '
                              'server and cannot be altered.',
                              style: giBody(size: 14, color: GiColors.muted)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
