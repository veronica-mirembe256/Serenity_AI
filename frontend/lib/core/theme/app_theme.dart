import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg         = Color(0xFFF5F3EF);
  static const surface    = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF0EDE8);
  static const border     = Color(0xFFE4DED6);
  static const sidebar    = Color(0xFF1C2B1E);
  static const sidebarHov = Color(0xFF2A3D2C);
  static const sidebarAct = Color(0xFF3A5440);
  static const sidebarTxt = Color(0xFF8FA88F);
  static const sage       = Color(0xFF6B9E6B);
  static const sageDk     = Color(0xFF4A7A4A);
  static const sageLt     = Color(0xFFB8D4B8);
  static const sageSurf   = Color(0xFFEEF7EE);
  static const ink        = Color(0xFF1A2B1A);
  static const inkMid     = Color(0xFF5A6B5A);
  static const inkLt      = Color(0xFF8FA48F);
  static const amber      = Color(0xFFE8A855);
  static const rose       = Color(0xFFD46B6B);
  static const mist       = Color(0xFF6B9EC7);
  static const peach      = Color(0xFFE8906B);
  static const List<Color> moods = [
    Color(0xFFB0A0C8), Color(0xFF6B9EC7),
    Color(0xFFB8C8B8), Color(0xFF6B9E6B), Color(0xFF4A7A4A),
  ];
}

class AppSpacing {
  static const sidebarW    = 240.0;
  static const sidebarWMin = 64.0;
  static const topbarH     = 60.0;
  static const r           = 12.0;
  static const rLg         = 20.0;
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.light(
      primary: AppColors.sage,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      outline: AppColors.border,
      error: AppColors.rose,
    ),
    textTheme: TextTheme(
      displayLarge:  GoogleFonts.fraunces(fontSize: 48, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -1.5),
      displayMedium: GoogleFonts.fraunces(fontSize: 36, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -1.0),
      displaySmall:  GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.5),
      headlineLarge: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.ink),
      headlineMedium:GoogleFonts.fraunces(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink),
      headlineSmall: GoogleFonts.fraunces(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
      titleLarge:    GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
      titleMedium:   GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
      titleSmall:    GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
      bodyLarge:     GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.ink, height: 1.65),
      bodyMedium:    GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.ink, height: 1.6),
      bodySmall:     GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.inkMid, height: 1.5),
      labelLarge:    GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
      labelMedium:   GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkMid),
      labelSmall:    GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.inkLt),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.r),
        side: const BorderSide(color: AppColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.sage,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.sage,
        side: const BorderSide(color: AppColors.sage),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.sage, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: GoogleFonts.dmSans(color: AppColors.inkLt, fontSize: 14),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
  );
}
