import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A restrained, formal palette: warm off-white page, white cards, deep
/// green for "yes" and main actions, terracotta for "no" and attention.
/// Every text colour passes WCAG AA contrast on [paper] and [card], because
/// many users are in their fifties and sixties.
class GiColors {
  static const ink = Color(0xFF1E2A26); // text
  static const primary = Color(0xFF2E5A4B); // main actions, "yes"
  static const primaryDark = Color(0xFF214235); // pressed / links
  static const accent = Color(0xFFB5532B); // "no", highlights
  static const accentBg = Color(0xFFF7E8DF);
  static const paper = Color(0xFFF5F1EA); // page background
  static const card = Color(0xFFFFFFFF); // cards
  static const line = Color(0xFFE2DACD); // borders
  static const muted = Color(0xFF5E655F); // secondary text
  static const green = primary; // eaten / confirmed
  static const greenBg = Color(0xFFE4EDE8);
  static const red = Color(0xFFA3402A); // alerts, refused
  static const redBg = Color(0xFFF7E3DB);
}

/// Public Sans throughout — the typeface the US government commissioned
/// for public services: neutral, formal, and very legible at large sizes.
TextStyle giHeading({double size = 22, Color color = GiColors.ink}) =>
    GoogleFonts.publicSans(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.15,
        letterSpacing: -0.3);

TextStyle giBody(
        {double size = 17,
        Color color = GiColors.ink,
        FontWeight weight = FontWeight.w400}) =>
    GoogleFonts.publicSans(fontSize: size, fontWeight: weight, color: color);

/// Small upper-case label used above sections ("TOMORROW", "STATUS").
TextStyle giLabel({Color color = GiColors.muted}) => GoogleFonts.publicSans(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: 1.2);

ThemeData buildGiTheme() {
  final base = GoogleFonts.publicSansTextTheme()
      .apply(bodyColor: GiColors.ink, displayColor: GiColors.ink);
  final textTheme = base.copyWith(
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 18),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 17),
    bodySmall: base.bodySmall?.copyWith(fontSize: 15, color: GiColors.muted),
  );

  final buttonText =
      GoogleFonts.publicSans(fontWeight: FontWeight.w700, fontSize: 17);
  const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)));
  const fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: GiColors.line, width: 1.5),
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: GiColors.paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: GiColors.primary,
      brightness: Brightness.light,
      primary: GiColors.primary,
      secondary: GiColors.accent,
      surface: GiColors.card,
      error: GiColors.red,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: GiColors.paper,
      foregroundColor: GiColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      shape: const Border(bottom: BorderSide(color: GiColors.line)),
      titleTextStyle: GoogleFonts.publicSans(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: GiColors.ink,
          letterSpacing: 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GiColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GiColors.primary,
        backgroundColor: GiColors.card,
        minimumSize: const Size(64, 52),
        side: const BorderSide(color: GiColors.line, width: 1.5),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GiColors.primaryDark,
        minimumSize: const Size(48, 48),
        textStyle:
            GoogleFonts.publicSans(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GiColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: GoogleFonts.publicSans(color: GiColors.muted),
      hintStyle: GoogleFonts.publicSans(color: GiColors.muted),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: GiColors.primary, width: 2.5),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: GiColors.primary,
      unselectedLabelColor: GiColors.muted,
      indicatorColor: GiColors.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelStyle:
          GoogleFonts.publicSans(fontWeight: FontWeight.w700, fontSize: 16),
      unselectedLabelStyle:
          GoogleFonts.publicSans(fontWeight: FontWeight.w600, fontSize: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GiColors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: GiColors.greenBg,
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          GoogleFonts.publicSans(
              fontSize: 14,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? GiColors.primary
                  : GiColors.muted)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 26,
          color: states.contains(WidgetState.selected)
              ? GiColors.primary
              : GiColors.muted)),
    ),
    cardTheme: const CardThemeData(
      color: GiColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: GiColors.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: giBody(size: 17, weight: FontWeight.w600),
      subtitleTextStyle: giBody(size: 15, color: GiColors.muted),
      minVerticalPadding: 12,
    ),
    chipTheme: ChipThemeData(
      labelStyle: giBody(size: 15, weight: FontWeight.w600),
      selectedColor: GiColors.greenBg,
      backgroundColor: GiColors.card,
      checkmarkColor: GiColors.primary,
      side: const BorderSide(color: GiColors.line),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: GiColors.primary,
        selectedForegroundColor: Colors.white,
        backgroundColor: GiColors.card,
        foregroundColor: GiColors.ink,
        side: const BorderSide(color: GiColors.line, width: 1.5),
        textStyle: giBody(size: 16, weight: FontWeight.w700),
        minimumSize: const Size(48, 52),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: GiColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20))),
    ),
    dividerTheme: const DividerThemeData(color: GiColors.line, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GiColors.ink,
      contentTextStyle: giBody(size: 16, color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
