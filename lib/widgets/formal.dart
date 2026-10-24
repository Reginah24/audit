import 'package:flutter/material.dart';
import '../theme.dart';

/// A white card with an optional coloured header band, e.g. the
/// "TOMORROW · MONDAY 26 OCTOBER" strip above the attendance question.
class SectionCard extends StatelessWidget {
  final String? header;
  final Color headerColor;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    this.header,
    this.headerColor = GiColors.accent,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GiColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GiColors.line),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F1E2A26), blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Container(
              color: headerColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(header!.toUpperCase(),
                  style: giLabel(color: Colors.white)),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// One choice on a menu screen: icon tile, title, one-line description,
/// chevron. The whole card is the button.
class MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const MenuCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $description',
      excludeSemantics: true,
      child: Material(
        color: GiColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: GiColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: GiColors.greenBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: GiColors.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: giHeading(size: 20)),
                      const SizedBox(height: 4),
                      Text(description,
                          style: giBody(size: 16, color: GiColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    color: GiColors.muted, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small status line with a coloured dot: "Confirmed", "Awaiting scan".
class StatusLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const StatusLine(
      {super.key, required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: giBody(size: 18, color: color, weight: FontWeight.w700)),
        ),
      ],
    );
  }
}
