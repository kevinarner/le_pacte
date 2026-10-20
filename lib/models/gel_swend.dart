import 'pacte.dart';
import 'remplacant.dart';
import 'statut_pacte.dart';

/// Gel à H (D-023a) : à l'heure prévue du Swend (`date_retenue`), l'état du
/// rendez-vous est figé — plus aucune action d'imprévu (demander, répondre,
/// se désister, signaler une disponibilité, gérer la liste, annuler). L'app
/// masque ces actions à partir de son horloge ; la base, avec l'heure du
/// serveur, reste seule juge (erreur `swend_passe`, voir
/// [messageSwendPasse]). « Passé » n'est jamais un statut enregistré : le
/// Swend reste `confirme` en base.
bool estPasse(Pacte pacte, DateTime maintenant) =>
    pacte.dateRetenue != null && !pacte.dateRetenue!.isAfter(maintenant);

/// Les actions d'imprévu sont encore possibles : Swend scellé, actif, et
/// son heure n'est pas arrivée.
bool imprevuOuvert(Pacte pacte, DateTime maintenant) =>
    pacte.statut == StatutPacte.confirme && !estPasse(pacte, maintenant);

/// Échéance H-3 (D-027, décision du 20/10) : 3 heures avant l'heure du
/// Swend, l'imprévu doit être résolu. Dès cet instant (inclus), plus aucune
/// recherche ni réponse : une recherche non résolue annule le Swend, un
/// nouvel imprévu ou le désistement du remplaçant sélectionné aussi. L'app
/// suit son horloge ; la base, avec l'heure du serveur, reste seule juge
/// (erreur `echeance_h3`, voir [messageEcheanceH3]).
DateTime? echeanceH3(Pacte pacte) =>
    pacte.dateRetenue?.subtract(const Duration(hours: 3));

bool echeanceH3Atteinte(Pacte pacte, DateTime maintenant) {
  final e = echeanceH3(pacte);
  return e != null && !maintenant.isBefore(e);
}

/// Refus de la base dès H-3 (`echeance_h3`).
const messageEcheanceH3 =
    'Il est trop tard : à moins de 3 heures du Swend, on ne peut plus chercher ni accepter de remplaçant.';

/// Une conversation titulaire ↔ personne de confiance ne s'écrit plus dès
/// que le Swend est passé ou annulé (elle reste lisible). Garanti par la
/// base (RLS) ; l'app remplace simplement la zone de saisie.
bool conversationEnLectureSeule(Pacte pacte, DateTime maintenant) =>
    !imprevuOuvert(pacte, maintenant);

/// Message affiché quand la base refuse une action parce que l'heure du
/// Swend est passée (course entre l'horloge de l'appareil et le serveur).
const messageSwendPasse =
    'L’heure du Swend est passée : cette action n’est plus possible.';

/// Conversations à relire une fois le Swend passé ou annulé : seulement
/// celles qui ont eu une activité (message ou événement), personnes ayant un
/// compte d'abord — jamais de fil vierge affiché artificiellement.
List<Remplacant> filsARelire(
  Iterable<Remplacant> fiches,
  Set<String> avecActivite,
) => Remplacant.comptesDAbord(
  fiches.where((r) => r.id != null && avecActivite.contains(r.id)),
);
