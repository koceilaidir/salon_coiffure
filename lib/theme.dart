import 'package:flutter/material.dart';

/// Couleurs reprises des maquettes. La couleur principale (prune) sera
/// ajustée quand le logo du salon sera disponible.
class AppColors {
  static const ink = Color(0xFF1C1A23);
  static const muted = Color(0xFF5E5868);
  static const line = Color(0xFFDDDAE2);
  static const lineSoft = Color(0xFFEEECF1);
  static const bg = Color(0xFFF3F3F6);
  static const sidebar = Color(0xFF1C1A23);
  static const sidebarSoft = Color(0xFF2A2733);
  static const sidebarText = Color(0xFFEDEAF0);
  static const sidebarMuted = Color(0xFFB9B3C0);
  static const accent = Color(0xFF7A2E5C);
  static const accentSoft = Color(0xFFF3EEF2);
  static const green = Color(0xFF17603F);
  static const greenBg = Color(0xFFE8F5EE);
  static const greenLine = Color(0xFFA9D8BF);
  static const orange = Color(0xFF8A3A0B);
  static const orangeBg = Color(0xFFFFF4EC);
  static const orangeLine = Color(0xFFF3C9A8);
  static const red = Color(0xFF8E1F17);
  static const redBg = Color(0xFFFDEDEC);
  static const redLine = Color(0xFFF0B9B5);
  static const badge = Color(0xFFC2410C);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    surface: Colors.white,
  );
  final radius10 = BorderRadius.circular(10);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Segoe UI',
    scaffoldBackgroundColor: AppColors.bg,
    dividerColor: AppColors.lineSoft,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
      ),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: const BorderSide(color: AppColors.line),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
