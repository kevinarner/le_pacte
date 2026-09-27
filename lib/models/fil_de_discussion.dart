import 'evenement_fil.dart';

/// Un fil de discussion vu depuis l'écran Messagerie unifié — que je sois
/// titulaire (parlant à mon remplaçant) ou remplaçant (parlant à mon
/// titulaire), peu importe le pacte d'origine.
class FilDeDiscussion {
  final String remplacantId;
  final String nomInterlocuteur;

  /// Connu d'avance côté titulaire (déjà dans son formulaire de
  /// remplaçants) — laissé à null côté remplaçant, récupéré alors par
  /// ChatScreen via une fonction serveur dédiée.
  final String? telephoneInterlocuteur;

  final String? dernierMessage;
  final DateTime? dateDernierMessage;

  /// True si c'est moi qui ai envoyé le dernier message du fil — sert à
  /// repérer un message de l'interlocuteur pas encore "vu" (au sens
  /// large : pas de vrai suivi lu/non-lu, juste "le dernier mot n'est
  /// pas de moi").
  final bool dernierMessageDeMoi;

  /// Un message de l'interlocuteur — ou un événement qui me concerne
  /// directement (acceptation, refus, annulation...) — est arrivé depuis
  /// ma dernière lecture de cette conversation (suivi enregistré en base,
  /// `lectures_fil`).
  final bool nonLu;

  /// Si l'élément non lu le plus récent est un événement (et non un
  /// message) : c'est lui que la box de l'accueil affiche.
  final EvenementFil? evenementNonLu;

  /// Date de l'élément non lu le plus récent (message ou événement) —
  /// ordonne les boxes de l'accueil.
  final DateTime? dateNonLu;

  /// Vrai si je suis la personne de confiance dans ce fil (et non le
  /// titulaire) — pour rédiger les événements selon qui lit.
  final bool jeSuisLeTiers;

  /// La date retenue du pacte concerné par ce fil, et le nom du
  /// restaurant — affichés sous le nom de l'interlocuteur pour situer la
  /// conversation. Nulle si aucune date n'est encore retenue.
  final DateTime? dateConcernee;
  final String? restaurantNom;

  /// Le nom de l'autre titulaire du Swend concerné par ce fil (distinct
  /// de [nomInterlocuteur], qui peut être la personne de confiance et
  /// non l'autre partie) — sert à situer la notification ("Swend avec
  /// David · ...") sur l'accueil.
  final String? autrePartieNom;

  FilDeDiscussion({
    required this.remplacantId,
    required this.nomInterlocuteur,
    this.telephoneInterlocuteur,
    this.dernierMessage,
    this.dateDernierMessage,
    this.dernierMessageDeMoi = true,
    this.nonLu = false,
    this.evenementNonLu,
    this.dateNonLu,
    this.jeSuisLeTiers = false,
    this.dateConcernee,
    this.restaurantNom,
    this.autrePartieNom,
  });
}
