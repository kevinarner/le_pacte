import 'pacte.dart';
import 'statut_pacte.dart';

/// Annulation d'un Swend scellé par un titulaire (D-022, révisée par D-027) :
/// seulement depuis « Un imprévu ? » → « Je n'ai personne d'autre » →
/// « Annuler le Swend » ; jusqu'à l'heure du rendez-vous ; jamais par un
/// titulaire dont la place a déjà été prise (refus serveur
/// `remplacement_accepte` à partir de D-027-02, action masquée par l'app sur
/// les deux bases).
bool peutAnnulerSwend(
  Pacte pacte, {
  required bool estTitulaire,
  required DateTime maintenant,
  bool remplace = false,
}) =>
    estTitulaire &&
    !remplace &&
    pacte.statut == StatutPacte.confirme &&
    pacte.dateRetenue != null &&
    pacte.dateRetenue!.isAfter(maintenant);

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
