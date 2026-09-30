import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'my_record_screen.dart';
import 'govt_report_screen.dart';

/// First screen anyone sees, whether on the tablet or the public web link.
/// Three destinations, each named for what the person is there to do —
/// not for who they are.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GiColors.beige,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Giraphe',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fraunces(
                      fontSize: 44,
                      fontWeight: FontWeight.w600,
                      color: GiColors.espresso,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Meal check-in',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.workSans(
                      fontSize: 15,
                      color: GiColors.muted,
                    ),
                  ),
                  const SizedBox(height: 44),
                  _RoleCard(
                    icon: Icons.storefront_outlined,
                    title: 'Log meals',
                    subtitle: 'For restaurant staff at the till',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.badge_outlined,
                    title: 'Check my meals',
                    subtitle: 'See your own record and log today',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MyRecordScreen()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.summarize_outlined,
                    title: 'View the report',
                    subtitle: 'Monthly summary for the office',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const GovtReportScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GiColors.cream,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GiColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: GiColors.beige,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: GiColors.rust, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.fraunces(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: GiColors.espresso,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.workSans(
                          fontSize: 13,
                          color: GiColors.muted,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: GiColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
