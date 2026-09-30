import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Giraphe's palette — warm and earthy, built for a restaurant, not a
/// generic dashboard. Rust for action, espresso for structure, beige and
/// cream for warmth, olive and clay reserved for status only.
class GiColors {
  static const rust = Color(0xFFB6531C); // primary / actions
  static const rustDark = Color(0xFF8F3F14); // pressed / emphasis
  static const espresso = Color(0xFF3A261B); // headings, app bar, ink
  static const beige = Color(0xFFF1E6D6); // page background
  static const cream = Color(0xFFFBF5EC); // card surfaces
  static const hairline = Color(0xFFD9C9AE); // borders
  static const muted = Color(0xFF8A7862); // secondary text
  static const olive = Color(0xFF5B6E45); // success / logged
  static const oliveBg = Color(0xFFEAEEDF);
  static const clay = Color(0xFFA63A2C); // alerts / warnings
  static const clayBg = Color(0xFFF3E0DB);
}

/// Fraunces carries the brand's personality in headings — warm, a little
/// characterful, like a printed menu. Work Sans stays out of the way for
/// body text and anything read quickly on a busy till.
ThemeData buildGiTheme() {
  final headingFont = GoogleFonts.frauncesTextTheme();
  final bodyFont = GoogleFonts.workSansTextTheme();

  final textTheme = bodyFont.copyWith(
    displayLarge: headingFont.displayLarge?.copyWith(color: GiColors.espresso),
    displayMedium:
        headingFont.displayMedium?.copyWith(color: GiColors.espresso),
    headlineLarge: headingFont.headlineLarge?.copyWith(
      color: GiColors.espresso,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: headingFont.headlineMedium?.copyWith(
      color: GiColors.espresso,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: headingFont.headlineSmall?.copyWith(
      color: GiColors.espresso,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: headingFont.titleLarge?.copyWith(
      color: GiColors.espresso,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: bodyFont.bodyLarge?.copyWith(color: GiColors.espresso),
    bodyMedium: bodyFont.bodyMedium?.copyWith(color: GiColors.espresso),
    bodySmall: bodyFont.bodySmall?.copyWith(color: GiColors.muted),
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: GiColors.beige,
    colorScheme: ColorScheme.fromSeed(
      seedColor: GiColors.rust,
      brightness: Brightness.light,
      primary: GiColors.rust,
      surface: GiColors.cream,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: GiColors.espresso,
      foregroundColor: GiColors.cream,
      elevation: 0,
      titleTextStyle: GoogleFonts.fraunces(
        color: GiColors.cream,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GiColors.rust,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        textStyle: GoogleFonts.workSans(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: GiColors.rustDark),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GiColors.cream,
      hintStyle: GoogleFonts.workSans(color: GiColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: GiColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: GiColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: GiColors.rust, width: 2),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: GiColors.cream,
      unselectedLabelColor: GiColors.cream.withValues(alpha: 0.6),
      indicatorColor: GiColors.rust,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: GoogleFonts.workSans(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: GiColors.cream,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: GiColors.hairline),
      ),
    ),
  );
}
