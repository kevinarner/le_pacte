import 'package:flutter/material.dart';

import '../models/statut_pacte.dart';

/// Tokens visuels du pack de handoff design (voir docs/handoff/README.md).
class AppColors {
  static const background = Color(0xFFF5EAD8);
  static const backgroundOuter = Color(0xFFE7DDCB);
  static const texte = Color(0xFF201E1D);
  static const terracotta = Color(0xFFC67139);
  static const terracottaClair = Color(0xFFF0DAC7);
  static const sauge = Color(0xFF7A8A5E);
  static const saugeClair = Color(0xFFE1E6D6);
  static const neutre = Color(0xFFE9E4DA);
  static const outline = Color(0xFFC9BFAE);
}

const double radiusLg = 16;

class StatutTag {
  final Color fond;
  final Color texte;
  final Color? bordure;
  const StatutTag({required this.fond, required this.texte, this.bordure});
}

StatutTag statutTag(StatutPacte statut) {
  switch (statut) {
    case StatutPacte.enAttenteChoixDateDestinataire:
    case StatutPacte.enAttenteChoixDateInitiateur:
      return StatutTag(
        fond: Colors.transparent,
        texte: AppColors.texte,
        bordure: AppColors.outline,
      );
    case StatutPacte.enAttenteReponse:
      return const StatutTag(fond: AppColors.neutre, texte: AppColors.texte);
    case StatutPacte.confirme:
    case StatutPacte.maintenu:
      return const StatutTag(fond: AppColors.terracottaClair, texte: AppColors.terracotta);
    case StatutPacte.annule:
    case StatutPacte.annuleDoubleAbsence:
      return const StatutTag(fond: AppColors.neutre, texte: AppColors.texte);
  }
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.terracotta,
      brightness: Brightness.light,
      surface: AppColors.background,
    ),
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Georgia',
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      titleLarge: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 22,
        color: AppColors.texte,
      ),
      titleMedium: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 16,
        color: AppColors.texte,
      ),
      bodyMedium: const TextStyle(fontSize: 14, color: AppColors.texte),
      bodySmall: const TextStyle(fontSize: 12.5, color: Colors.black54),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.texte,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 18,
        color: AppColors.texte,
        fontFamily: 'Georgia',
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.backgroundOuter,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.texte,
        minimumSize: const Size.fromHeight(46),
        shape: const StadiumBorder(),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.terracotta),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.backgroundOuter,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        borderSide: BorderSide.none,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.background,
      selectedItemColor: AppColors.terracotta,
      unselectedItemColor: Colors.black45,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline),
  );
}
