import 'package:flutter/material.dart';

import '../models/statut_pacte.dart';

/// Palette pêche / bleu ardoise / crème, validée le 29/08 (voir la
/// synthèse UX). L'accent (bleu ardoise) sert aux actions principales et
/// aux temps forts ; `erreur` reste dans une famille chaude distincte,
/// pour ne jamais confondre un message d'erreur avec la couleur de marque.
class AppColors {
  static const background = Color(0xFFF5E4CB);
  static const backgroundOuter = Color(0xFFEAD5AE);
  static const surface = Color(0xFFFCF0DD);
  static const texte = Color(0xFF3C2A1B);
  static const texteAttenue = Color(0xFF93795C);
  static const accent = Color(0xFF6B7A94);
  static const accentFonce = Color(0xFF3F4C63);
  static const accentClair = Color(0xFFDEE3EA);
  static const peche = Color(0xFFE8A874);
  static const pecheClair = Color(0xFFFBE2C4);
  static const neutre = Color(0xFFF1E2C9);
  static const outline = Color(0xFFEBD8B7);
  static const erreur = Color(0xFFB3492E);
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
      return const StatutTag(fond: AppColors.accentClair, texte: AppColors.accentFonce);
    case StatutPacte.annule:
    case StatutPacte.annuleDoubleAbsence:
      return const StatutTag(fond: AppColors.neutre, texte: AppColors.texte);
  }
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
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
      bodySmall: TextStyle(fontSize: 12.5, color: AppColors.texteAttenue),
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
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
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
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        borderSide: BorderSide.none,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.background,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: Colors.black45,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline),
  );
}
