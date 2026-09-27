import '../constants.dart';
import '../models/cote_pacte.dart';
import '../models/pacte.dart';
import '../models/remplacant.dart';
import '../models/type_repas.dart';
import 'date_fr.dart';
import 'noms.dart';

/// Textes envoyés par Messages ou WhatsApp — fonctions pures, testées dans
/// test/textes_invitation_test.dart. Le texte ne dépend jamais du canal.

/// Invitation à faire un Swend (étape "Avec qui ?").
String texteInvitationSwend(String prenomDestinataire) {
  final prenom = prenomDestinataire.trim();
  final salutation = prenom.isNotEmpty ? 'Hello $prenom' : 'Hello';
  return "$salutation, je t'invite à faire un Swend avec moi !\n"
      "Le principe : on choisit une date pour dîner ensemble, puis on n'en reparle plus "
      "jusqu'au jour J. Et si l'un de nous a un imprévu, quelqu'un de confiance peut prendre "
      "sa place. On se lance ?\n"
      "Je te laisse en découvrir plus sur Swend :)\n"
      "$lienTelechargementApp";
}

/// Invitation d'une personne de confiance (préparation, sans demande).
String texteInvitationPersonneDeConfiance(
  String prenomPersonne,
  String nomAutrePartie,
) {
  final prenom = prenomPersonne.trim();
  final salutation = prenom.isNotEmpty ? 'Hello $prenom' : 'Hello';
  final autreComplet = nomAutrePartie.trim();
  final autre = autreComplet.isNotEmpty ? prenomDe(autreComplet) : 'mon ami';
  return "$salutation, j'ai proposé un Swend à $autre et j'aimerais pouvoir compter sur toi "
      "en cas d'imprévu.\n"
      "Si finalement je ne peux pas être là et que tu es dispo, tu pourrais prendre ma place. "
      "Ça te dit ?\n"
      "Je te laisse en découvrir plus sur Swend :)\n"
      "$lienTelechargementApp";
}

/// Le message envoyé à quelqu'un qui n'a pas encore Swend, quand on lui
/// demande réellement de prendre sa place.
String messageUrgence(Pacte pacte, Remplacant r, CotePacte autreCote) {
  final repas = pacte.type == TypeRepas.dejeuner ? 'un déjeuner' : 'un dîner';
  final date = pacte.dateRetenue;
  final quand = date == null
      ? ''
      : ' le ${date.day} ${moisAnnee[date.month - 1]} à ${formaterHeure(heureDe(date))}';
  final autre = prenomDe(autreCote.nomTitulaire);
  final restaurant = pacte.restaurantRetenu?.nom;
  final ou = restaurant == null ? '' : ', au restaurant $restaurant';
  return "Hello ${r.prenom}, j'ai $repas prévu$quand avec $autre$ou, mais j'ai un imprévu. "
      "Est-ce que tu pourrais prendre ma place ?\n"
      "C'est le principe de Swend : $autre ne saura pas que c'est toi qui me remplaces. "
      "Tu peux accepter ou refuser directement sur l'app.\n"
      "Pour retrouver cette demande dans Swend, crée ton compte avec ce numéro de téléphone.\n"
      "$lienTelechargementApp";
}
