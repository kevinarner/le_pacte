import 'demande_statut.dart';
import 'remplacant.dart';

/// « En cas d'imprévu » côté titulaire (D-027) : où en est MON côté d'un
/// Swend scellé. Calculé à partir de mes fiches (lisibles par moi seul) et
/// de l'état « cherche » de la base (`destination_rappel()`, déjà en
/// production : `imprevu` ⇔ imprévu déclaré sans remplaçant sélectionné).
/// Rien de tout cela n'est jamais visible de l'autre titulaire.
enum EtatCote { normal, cherche, remplace }

/// L'écran « Un imprévu ? » ne montre qu'une situation à la fois.
enum PhaseImprevu {
  /// Pas d'imprévu en cours : choisir une ou plusieurs personnes.
  choix,

  /// Au moins une demande attend une réponse.
  attente,

  /// Imprévu en cours, plus aucune demande en attente (tout le monde a
  /// refusé, ou la personne qui avait accepté s'est désistée sans demande à
  /// réactiver).
  personneNaPu,

  /// Quelqu'un a accepté : plus de retour en arrière.
  accepte,
}

/// État « cherche » d'après la réponse de `destination_rappel()`, avec un
/// repli sur les fiches si la base n'a pas pu répondre (réseau).
EtatCote etatCoteDepuis({
  required String? destinationRappel,
  required bool baseARepondu,
  required List<Remplacant> fiches,
}) {
  if (fiches.any((r) => r.selectionne)) return EtatCote.remplace;
  if (baseARepondu) {
    return destinationRappel == 'imprevu' ? EtatCote.cherche : EtatCote.normal;
  }
  // Repli : une demande en attente, refusée ou désistée signale un imprévu
  // (après « Je peux finalement venir », seuls les refus restent ; ce cas
  // n'est distinguable que par la base).
  return fiches.any(
        (r) =>
            r.demandeStatut == DemandeStatut.envoyee ||
            r.demandeStatut == DemandeStatut.refusee ||
            r.demandeStatut == DemandeStatut.desistee,
      )
      ? EtatCote.cherche
      : EtatCote.normal;
}

class SituationImprevu {
  final EtatCote etat;

  /// Mes fiches valides (non retirées, enregistrées), comptes d'abord.
  final List<Remplacant> fiches;

  /// Personne qui s'est désistée en dernier, si aucune nouvelle demande n'a
  /// été envoyée depuis : le titulaire voit « Kevin ne peut finalement plus
  /// venir. ».
  final Remplacant? desistementRecent;

  SituationImprevu({
    required this.etat,
    required Iterable<Remplacant> fiches,
    this.desistementRecent,
  }) : fiches = Remplacant.comptesDAbord(
         fiches.where((r) => r.estRempli && r.id != null),
       );

  Remplacant? get remplacant => fiches.where((r) => r.selectionne).firstOrNull;

  /// Peut recevoir une demande maintenant : prévue, jamais sollicitée pour
  /// l'imprévu en cours, pas indisponible d'elle-même.
  List<Remplacant> get sollicitables => fiches
      .where(
        (r) =>
            !r.selectionne &&
            r.demandeStatut == null &&
            !r.indisponibleSpontanement,
      )
      .toList();

  List<Remplacant> get enAttente =>
      fiches.where((r) => r.demandeStatut == DemandeStatut.envoyee).toList();

  /// Déjà sollicitées et sans place prise (en attente, refus, clôture,
  /// désistement) : la liste de l'attente.
  List<Remplacant> get sollicitees => fiches
      .where((r) => !r.selectionne && r.demandeStatut != null)
      .toList();

  PhaseImprevu get phase => switch (etat) {
    EtatCote.remplace => PhaseImprevu.accepte,
    EtatCote.cherche =>
      enAttente.isNotEmpty ? PhaseImprevu.attente : PhaseImprevu.personneNaPu,
    EtatCote.normal => PhaseImprevu.choix,
  };

  /// « Je peux finalement venir » : imprévu déclaré, personne n'a accepté.
  bool get peutRevenir => etat == EtatCote.cherche;

  /// « Je n'ai personne d'autre » (dernier recours, puis annulation) :
  /// personne n'a pu, ou personne à solliciter dans ma liste.
  bool get dernierRecours =>
      phase == PhaseImprevu.personneNaPu ||
      (phase == PhaseImprevu.choix && sollicitables.isEmpty);

  /// Titre et sous-titre de l'écran pour la phase en cours.
  (String, String) get entete => switch (phase) {
    PhaseImprevu.choix =>
      sollicitables.isNotEmpty
          ? (TextesImprevu.titreChoix, TextesImprevu.sousTitreChoix)
          : (
              TextesImprevu.titreChoix,
              fiches.isEmpty
                  ? TextesImprevu.personnePrevue
                  : TextesImprevu.personneDisponible,
            ),
    PhaseImprevu.attente =>
      desistementRecent != null
          ? (
              TextesImprevu.desistement(desistementRecent!.prenom.trim()),
              TextesImprevu.desistementReactivees,
            )
          : (TextesImprevu.titreAttente, TextesImprevu.sousTitreAttente),
    PhaseImprevu.personneNaPu =>
      desistementRecent != null
          ? (
              TextesImprevu.desistement(desistementRecent!.prenom.trim()),
              TextesImprevu.desistementSansReactivation,
            )
          : (TextesImprevu.titrePersonneNaPu, TextesImprevu.sousTitrePersonneNaPu),
    PhaseImprevu.accepte => (
      TextesImprevu.accepte(remplacant!.prenom.trim()),
      TextesImprevu.accepteJourJ(remplacant!.prenom.trim()),
    ),
  };
}

/// Personne qui s'est désistée en dernier, si aucune demande n'a été
/// envoyée depuis (événements du fil : `desistement`, `demande_envoyee`).
Remplacant? desistementRecent(
  List<Remplacant> fiches, {
  required Map<String, DateTime> desistements,
  required DateTime? dernierEnvoi,
}) {
  Remplacant? dernier;
  DateTime? quand;
  for (final r in fiches) {
    if (r.demandeStatut != DemandeStatut.desistee) continue;
    final t = desistements[r.id];
    if (t == null) continue;
    if (quand == null || t.isAfter(quand)) {
      dernier = r;
      quand = t;
    }
  }
  if (quand == null) return null;
  if (dernierEnvoi != null && dernierEnvoi.isAfter(quand)) return null;
  return dernier;
}

/// Textes de « Un imprévu ? » (D-027, PRODUCT_RULES §6 et §7). L'app tutoie.
abstract final class TextesImprevu {
  static const titreChoix = 'Tu ne peux plus être là ?';
  static const sousTitreChoix = 'Sollicite l’un de tes remplaçants :)';
  // Textes proposés (lot 3) : liste vide, ou personne à solliciter.
  static const personnePrevue =
      'Tu n’as encore prévu personne : ajoute une personne qui pourra prendre ta place.';
  static const personneDisponible =
      'Personne de ta liste n’est disponible : tu peux ajouter une personne.';

  static const titreAttente = 'C’est envoyé.';
  static const sousTitreAttente =
      'La première personne qui accepte prendra ta place.';

  static const titrePersonneNaPu = 'Personne n’a pu prendre ta place.';
  static const sousTitrePersonneNaPu =
      'Tu peux encore solliciter quelqu’un d’autre.';

  static String desistement(String prenom) =>
      '$prenom ne peut finalement plus venir.';
  static const desistementReactivees =
      'Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.';
  static const desistementSansReactivation =
      'Tu peux solliciter quelqu’un d’autre.';

  // « Kevin a accepté. / Kevin sera là à ta place le jour J. » : formulation
  // neutre validée le 12/10 (le genre n'est jamais déduit d'un prénom).
  static String accepte(String prenom) => '$prenom a accepté.';
  static String accepteJourJ(String prenom) =>
      '$prenom sera là à ta place le jour J.';

  // « Solliciter quelqu'un d'autre » et ajout (textes proposés, lot 3).
  static const choisisDesPersonnes =
      'Choisis une ou plusieurs personnes de ta liste.';
  static String sansCompte(String prenom) => '$prenom n’a pas encore Swend';
  static const ajoutCorps =
      'Cette personne recevra directement ta demande de prendre ta place.';
  static const ajoutAction = 'Lui demander de prendre ma place';
  static String titreMessageAEnvoyer(String prenom) =>
      'Demande envoyée à $prenom';

  static const enAttente = 'En attente';
  static const indisponible = 'Indisponible';
  static const discuter = 'Discuter';
  static const solliciterAutre = 'Solliciter quelqu’un d’autre';
  static const ajouterPersonne = 'Ajouter une personne';
  static const jePeuxVenir = 'Je peux finalement venir';
  static const jeNaiPersonne = 'Je n’ai personne d’autre';

  /// Bouton adaptatif : « Demander à Kevin », « Envoyer 2 demandes ».
  static String? boutonEnvoi(List<Remplacant> choisis) => switch (choisis
      .length) {
    0 => null,
    1 => 'Demander à ${choisis.first.prenom.trim()}',
    final n => 'Envoyer $n demandes',
  };

  /// Confirmation avant l'envoi : (titre, corps, action).
  /// Une personne : texte validé rendu neutre (« S’il accepte, il… » →
  /// « Si Kevin accepte, Kevin… », même règle que l'acceptation du 12/10).
  static (String, String, String) confirmationEnvoi(
    List<Remplacant> choisis,
  ) {
    if (choisis.length == 1) {
      final p = choisis.first.prenom.trim();
      return (
        'Envoyer la demande à $p ?',
        'Si $p accepte, $p prendra ta place et tu ne pourras plus revenir en arrière.',
        'Envoyer la demande',
      );
    }
    return (
      'Envoyer la demande ?',
      'La première personne qui accepte prendra ta place.\n'
          'Une fois ta place prise, tu ne pourras plus revenir en arrière.',
      'Envoyer les demandes',
    );
  }

  // « Je peux finalement venir » : confirmation courte (texte proposé).
  static const titreRetour = 'Tu peux finalement venir ?';
  static String corpsRetour({required bool demandesEnAttente}) =>
      demandesEnAttente
      ? 'Les personnes qui n’ont pas encore répondu seront prévenues qu’elles n’ont plus besoin de le faire.'
      : 'Tu redeviens simplement participant à ce Swend.';
  static const actionRetour = 'Je peux venir';
  static const retourEnregistre = 'C’est noté : tu seras là.';

  // « Je n'ai personne d'autre » (D-027 point 12, textes validés).
  static const titrePersonneDAutre = 'Tu n’as personne d’autre ?';
  static const corpsPersonneDAutre =
      'Sans quelqu’un pour prendre ta place, le Swend ne pourra pas avoir lieu.';
  static const annulerLeSwend = 'Annuler le Swend';
  static const titreConfirmationAnnulation = 'Annuler ce Swend ?';
  static const corpsConfirmationAnnulation =
      'Cette action est définitive. L’autre personne sera prévenue.';
  static const garderLeSwend = 'Ne pas annuler';

  // Personne sans compte : le titulaire envoie lui-même le message.
  static String messageAEnvoyer(String prenom) =>
      '$prenom n’a pas encore Swend : envoie-lui un message pour lui expliquer '
      'et lui permettre de répondre depuis l’app.';
  static const plusTard = 'Plus tard';
  static const envoyerLeMessage = 'Envoyer le message';
  static String renvoyerLeMessage(String prenom) =>
      'Renvoyer le message à $prenom';
  static const demandeAttendDeNouveau =
      'La demande attend de nouveau sa réponse.';

  static const heurePassee = 'L’heure du Swend est passée.';
  static const heurePasseeCorps =
      'Il n’est plus possible de demander à quelqu’un de prendre ta place.';

  /// Refus de la base, au tutoiement.
  static String erreur(String? code) => switch (code) {
    'place_deja_prise' => 'Quelqu’un vient d’accepter de prendre ta place.',
    'personne_indisponible' =>
      'Une des personnes choisies n’est pas disponible pour ce Swend : aucune demande n’est partie.',
    'deja_acceptee' =>
      'Cette personne a déjà accepté : le remplacement est définitif.',
    'demande_non_active' => 'Cette demande n’est plus en attente.',
    'aucun_imprevu' => 'Tu n’as plus d’imprévu en cours.',
    'aucune_personne' => 'Choisis au moins une personne.',
    'remplacement_accepte' =>
      'Quelqu’un a déjà accepté de prendre ta place : tu ne peux plus annuler ce Swend.',
    'swend_inactif' => 'Ce Swend n’est plus actif.',
    'swend_passe' =>
      'L’heure du Swend est passée : cette action n’est plus possible.',
    'champs_manquants' => 'Renseigne le prénom, le nom et le téléphone.',
    'personne_est_participant' =>
      'Cette personne participe déjà à ce Swend : elle ne peut pas prendre ta place.',
    'personne_deja_prevue' => 'Cette personne est déjà dans ta liste.',
    _ => 'Impossible pour le moment. Réessaie.',
  };
}
