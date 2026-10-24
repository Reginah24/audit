import 'package:flutter/material.dart';
import '../theme.dart';

/// The two large answers to "Will you eat here tomorrow?". Each is half the
/// width, with an icon and words (never colour alone), and the chosen one
/// is filled in so it is obvious what was picked.
class ComingButtons extends StatelessWidget {
  final bool? selected;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const ComingButtons({
    super.key,
    required this.selected,
    required this.onChanged,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    // Equal heights even when a label wraps on a narrow phone.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Choice(
              label: 'Yes, I will eat',
              icon: Icons.check,
              color: GiColors.primary,
              filled: selected == true,
              onTap: busy ? null : () => onChanged(true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Choice(
              label: 'No, I will not',
              icon: Icons.close,
              color: GiColors.accent,
              filled: selected == false,
              onTap: busy ? null : () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  const _Choice({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Semantics(
      button: true,
      selected: filled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled ? color : GiColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Colors.white.withValues(alpha: 0.2) : null,
                    border: Border.all(color: fg, width: 2),
                  ),
                  child: Icon(icon, color: fg, size: 28),
                ),
                const SizedBox(height: 10),
                Text(label,
                    textAlign: TextAlign.center,
                    style:
                        giBody(size: 17, color: fg, weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
