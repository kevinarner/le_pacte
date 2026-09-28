import 'cote_pacte.dart';
import 'demande_statut.dart';
import 'pacte.dart';
import 'statut_pacte.dart';

/// Annulation manuelle d'un Swend scellé (D-022), du point de vue du
/// titulaire qui annule : la confirmation dépend de l'état de SON côté.
enum CasAnnulation {
  /// Aucun imprévu lancé : on propose d'abord de trouver quelqu'un.
  normal,

  /// État D-021 « cherche » : au moins une demande envoyée, refusée ou
  /// désistée, personne n'a accepté. On ne repropose pas l'imprévu.
  enRecherche,

  /// Quelqu'un a accepté de prendre sa place.
  remplace,
}

/// Textes d'une confirmation d'annulation.
class ConfirmationAnnulation {
  final CasAnnulation cas;
  final String titre;
  final String corps;
  final String actionGarder;
  final String actionAnnuler;

  const ConfirmationAnnulation._(
    this.cas,
    this.corps, {
    this.actionGarder = 'Ne pas annuler',
  }) : titre = 'Annuler ce Swend ?',
       actionAnnuler = 'Annuler le Swend';

  /// La confirmation à afficher au titulaire de [monCote].
  factory ConfirmationAnnulation.pour(CotePacte monCote) {
    final fiches = monCote.listeRemplacants;
    final remplacant = fiches.where((r) => r.selectionne).firstOrNull;
    if (remplacant != null) {
      return ConfirmationAnnulation._(
        CasAnnulation.remplace,
        '${remplacant.prenom.trim()} a accepté de prendre votre place.\n'
        'Si vous annulez, le Swend prendra fin pour tout le monde.',
      );
    }
    final enRecherche = fiches.any(
      (r) =>
          r.demandeStatut == DemandeStatut.envoyee ||
          r.demandeStatut == DemandeStatut.refusee ||
          r.demandeStatut == DemandeStatut.desistee,
    );
    if (enRecherche) {
      final enAttente = fiches.any(
        (r) => r.demandeStatut == DemandeStatut.envoyee,
      );
      return ConfirmationAnnulation._(
        CasAnnulation.enRecherche,
        enAttente
            ? 'Les demandes de remplacement en cours seront annulées et le '
                  'Swend prendra fin pour vous deux.'
            : 'Vous avez déjà cherché quelqu’un pour vous remplacer. Si vous '
                  'annulez, le Swend prendra fin pour vous deux.',
        actionGarder: 'Continuer à chercher',
      );
    }
    return const ConfirmationAnnulation._(
      CasAnnulation.normal,
      'Cette action mettra fin au Swend pour vous deux.',
    );
  }
}

/// Étape préalable du cas « normal » : proposer d'abord un remplaçant.
abstract final class AvantAnnulation {
  static const titre = 'Vous ne pouvez plus être là ?';
  static const corps =
      'Avant d’annuler, vous pouvez demander à quelqu’un de confiance de '
      'prendre votre place.';
  static const actionTrouver = 'Trouver quelqu’un pour me remplacer';
  static const actionAnnuler = 'Annuler malgré tout';
}

/// Un titulaire peut annuler un Swend scellé jusqu'à l'heure du
/// rendez-vous (garanti aussi par la base, annuler_swend()).
bool peutAnnulerSwend(
  Pacte pacte, {
  required bool estTitulaire,
  required DateTime maintenant,
}) =>
    estTitulaire &&
    pacte.statut == StatutPacte.confirme &&
    pacte.dateRetenue != null &&
    pacte.dateRetenue!.isAfter(maintenant);

/// Message affiché si la base refuse l'annulation.
String messageErreurAnnulation(Object erreur) {
  final e = erreur.toString();
  if (e.contains('swend_passe')) {
    return 'L’heure du rendez-vous est passée : ce Swend ne peut plus être annulé.';
  }
  if (e.contains('swend_inactif')) return 'Ce Swend n’est plus actif.';
  return 'Impossible d’annuler le Swend pour le moment. Réessayez.';
}

/// Mes Swends : un Swend annulé ou dont l'heure est passée rejoint
/// « Passés et annulés » ; les autres restent « À venir ».
bool estPasseOuAnnule(Pacte pacte, DateTime maintenant) =>
    pacte.statut == StatutPacte.annule ||
    pacte.statut == StatutPacte.annuleDoubleAbsence ||
    pacte.statut == StatutPacte.maintenu ||
    (pacte.dateRetenue != null && !pacte.dateRetenue!.isAfter(maintenant));

bool estAnnule(Pacte pacte) =>
    pacte.statut == StatutPacte.annule ||
    pacte.statut == StatutPacte.annuleDoubleAbsence;
