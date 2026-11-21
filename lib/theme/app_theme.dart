import 'package:flutter/material.dart';

import '../models/demande_statut.dart';
import '../models/remplacant.dart';
import '../models/statut_pacte.dart';

/// Palette du site vitrine swend.fr (`assets/site.css`, variables `--sw-*`),
/// reprise le 21/11 : fond crème, papier, encre brune, bordeaux pour les
/// actions principales et les temps forts. Les noms historiques des
/// constantes sont conservés pour ne pas toucher aux écrans. `accentFonce`
/// et `accentClair` sont dérivés du bordeaux (le site n'en a pas) ;
/// `erreur` est un rouge d'alerte franc, plus vif et plus chaud que le
/// bordeaux, choisi le 21/11 pour être reconnu d'emblée comme une erreur.
class AppColors {
  static const background = Color(0xFFFBF3E5); // --sw-bg
  static const backgroundOuter = Color(0xFFF0E3D0);
  static const surface = Color(0xFFFFFCF6); // --sw-paper
  static const texte = Color(0xFF39291F); // --sw-ink
  static const texteAttenue = Color(0xFF715448);
  static const accent = Color(0xFF742D43); // --sw-wine
  static const accentFonce = Color(0xFF5A2234);
  static const accentClair = Color(0xFFF2E0E3);
  static const peche = Color(0xFFBF8A73); // terre cuite des soulignés
  static const pecheClair = Color(0xFFF4E4CB); // fond du sceau
  static const neutre = Color(0xFFEEE2D0); // fond des encadrés
  static const outline = Color(0xFFDECEBA); // --sw-line
  static const erreur = Color(0xFFB42318);
}

/// Polices du site : Georgia (graisse normale) pour les titres, Arial pour
/// le texte courant. Toutes deux sont des polices système sur iOS.
const String policeTitres = 'Georgia';
const String policeTexte = 'Arial';

const double radiusLg = 16;

/// Arrondi des cartes « papier » du site (cartons d'invitation).
const double radiusCarte = 8;

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
      return const StatutTag(
        fond: AppColors.accentClair,
        texte: AppColors.accentFonce,
      );
    case StatutPacte.annule:
    case StatutPacte.annuleDoubleAbsence:
      return const StatutTag(fond: AppColors.neutre, texte: AppColors.texte);
  }
}

/// Vrai si c'est le tour de l'utilisateur courant d'agir sur ce statut
/// de négociation (choisir/contre-proposer une date, ou répondre) —
/// logique unique, réutilisée partout où l'app doit savoir qui doit
/// agir (hub, "Mes Swends", détail d'un Swend), pour ne jamais la
/// dupliquer ni la faire diverger d'un écran à l'autre.
bool pacteEstMonTour(StatutPacte statut, bool jeSuisInitiateur) {
  switch (statut) {
    case StatutPacte.enAttenteChoixDateInitiateur:
      return jeSuisInitiateur;
    case StatutPacte.enAttenteChoixDateDestinataire:
    case StatutPacte.enAttenteReponse:
      return !jeSuisInitiateur;
    case StatutPacte.confirme:
    case StatutPacte.maintenu:
    case StatutPacte.annule:
    case StatutPacte.annuleDoubleAbsence:
      return false;
  }
}

class StatutAffichage {
  final String libelle;
  final StatutTag style;
  const StatutAffichage(this.libelle, this.style);
}

/// Le badge à afficher pour un Swend du point de vue de l'utilisateur
/// courant : oriente vers l'action plutôt que de décrire l'état
/// technique — qui doit agir, ou "Scellé" quand plus rien n'est requis.
/// `autrePrenom` est le prénom de l'autre partie, affiché quand c'est
/// son tour à elle.
StatutAffichage statutAffichagePourMoi(
  StatutPacte statut, {
  required bool jeSuisInitiateur,
  required String autrePrenom,
}) {
  switch (statut) {
    case StatutPacte.enAttenteChoixDateInitiateur:
    case StatutPacte.enAttenteChoixDateDestinataire:
    case StatutPacte.enAttenteReponse:
      if (pacteEstMonTour(statut, jeSuisInitiateur)) {
        return const StatutAffichage(
          'À toi de répondre',
          StatutTag(fond: AppColors.accent, texte: Colors.white),
        );
      }
      return StatutAffichage(
        'En attente de $autrePrenom',
        const StatutTag(
          fond: Colors.transparent,
          texte: AppColors.texteAttenue,
          bordure: AppColors.outline,
        ),
      );
    case StatutPacte.confirme:
      return const StatutAffichage(
        'Scellé',
        StatutTag(fond: AppColors.accentClair, texte: AppColors.accentFonce),
      );
    case StatutPacte.maintenu:
    case StatutPacte.annule:
    case StatutPacte.annuleDoubleAbsence:
      return StatutAffichage(statut.libelle, statutTag(statut));
  }
}

/// Le badge d'un Swend vu par une personne tierce "en cas d'imprévu".
StatutAffichage statutAffichageTiers(StatutPacte statut, Remplacant fiche) {
  const discret = StatutTag(
    fond: Colors.transparent,
    texte: AppColors.texteAttenue,
    bordure: AppColors.outline,
  );
  if (statut == StatutPacte.maintenu ||
      statut == StatutPacte.annule ||
      statut == StatutPacte.annuleDoubleAbsence) {
    return StatutAffichage(statut.libelle, statutTag(statut));
  }
  if (statut != StatutPacte.confirme) {
    return const StatutAffichage("En cas d'imprévu", discret);
  }
  if (fiche.selectionne) {
    return const StatutAffichage(
      'Tu prends la place',
      StatutTag(fond: AppColors.accentClair, texte: AppColors.accentFonce),
    );
  }
  if (fiche.demandeStatut == DemandeStatut.envoyee) {
    return const StatutAffichage(
      'Demande reçue',
      StatutTag(fond: AppColors.accent, texte: Colors.white),
    );
  }
  if (fiche.indisponibleSpontanement) {
    return const StatutAffichage(
      'Indisponible',
      StatutTag(fond: AppColors.neutre, texte: AppColors.texteAttenue),
    );
  }
  if (fiche.demandeStatut.estIndisponible) {
    return const StatutAffichage(
      'Terminé',
      StatutTag(fond: AppColors.neutre, texte: AppColors.texteAttenue),
    );
  }
  return const StatutAffichage("En cas d'imprévu", discret);
}

ThemeData buildAppTheme() {
  const titre = TextStyle(
    fontFamily: policeTitres,
    fontWeight: FontWeight.w400,
    color: AppColors.texte,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
      primary: AppColors.accent,
      onPrimary: AppColors.surface,
      surface: AppColors.background,
      onSurface: AppColors.texte,
      error: AppColors.erreur,
      outline: AppColors.outline,
    ),
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: policeTexte,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.texte, displayColor: AppColors.texte)
        .copyWith(
          headlineMedium: titre.copyWith(fontSize: 29, letterSpacing: -0.5),
          headlineSmall: titre.copyWith(fontSize: 24, letterSpacing: -0.4),
          titleLarge: titre.copyWith(fontSize: 22, letterSpacing: -0.3),
          titleMedium: titre.copyWith(fontSize: 17),
          bodyLarge: const TextStyle(
            fontFamily: policeTexte,
            fontSize: 15,
            color: AppColors.texte,
          ),
          bodyMedium: const TextStyle(
            fontFamily: policeTexte,
            fontSize: 14,
            color: AppColors.texte,
          ),
          bodySmall: const TextStyle(
            fontFamily: policeTexte,
            fontSize: 12.5,
            color: AppColors.texteAttenue,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.texte,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: titre.copyWith(fontSize: 20, letterSpacing: -0.3),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1.5,
      shadowColor: Color(0x3339291F),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusCarte)),
        side: BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.surface,
        disabledBackgroundColor: AppColors.outline,
        disabledForegroundColor: AppColors.texteAttenue,
        minimumSize: const Size.fromHeight(46),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: policeTexte,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        minimumSize: const Size.fromHeight(46),
        shape: const StadiumBorder(),
        side: const BorderSide(color: AppColors.accent),
        textStyle: const TextStyle(fontFamily: policeTexte, fontSize: 15),
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
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        borderSide: const BorderSide(color: AppColors.erreur),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.background,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.texteAttenue,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}
