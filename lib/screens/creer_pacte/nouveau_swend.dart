import 'package:flutter/material.dart';

import '../../models/chat_apres_swend.dart';
import '../../models/nouveau_swend.dart';
import '../../services/chat_apres_swend_repository.dart';
import 'choix_nouveau_swend_screen.dart';
import 'creer_pacte_screen.dart';

/// « Faire un nouveau Swend » depuis la fiche d'un Swend passé dont le chat
/// est ouvert (D-023c). Chat à 2 : directement « Quand et où ? » avec
/// l'autre personne, ou « Un Swend est déjà en cours entre vous. ». Chat à
/// 3 : choix entre les deux autres personnes. La base revérifie tout à la
/// création. Renvoie `true` si un Swend a été créé.
Future<bool> faireUnNouveauSwend(
  BuildContext context,
  ChatApresSwend chat,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void dire(String texte) =>
      messenger.showSnackBar(SnackBar(content: Text(texte)));

  final List<OptionNouveauSwend> options;
  try {
    options = await ChatApresSwendRepository.optionsNouveauSwend(chat.id);
  } catch (e) {
    dire(
      ChatApresSwendRepository.codeErreur(e) == 'chat_ferme'
          ? texteChatFermeNouveauSwend
          : 'Impossible pour le moment. Réessaie.',
    );
    return false;
  }
  if (!context.mounted) return false;

  if (!chat.aTrois) {
    final autre = options.firstOrNull;
    if (autre == null) {
      dire('Impossible pour le moment. Réessaie.');
      return false;
    }
    if (autre.dejaEnCours) {
      dire(texteSwendDejaEnCoursEntreVous);
      return false;
    }
    return creerNouveauSwendAvec(context, chat, autre);
  }

  final cree = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (choix) => ChoixNouveauSwendScreen(
        options: options,
        onChoisir: (o) => creerNouveauSwendAvec(choix, chat, o),
      ),
    ),
  );
  return cree == true;
}

/// Création avec cette personne : « Avec qui ? » est sauté.
Future<bool> creerNouveauSwendAvec(
  BuildContext context,
  ChatApresSwend chat,
  OptionNouveauSwend avec,
) async {
  final cree = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => CreerPacteScreen(
        depuisChat: AvecQuiDepuisChat(
          chatId: chat.id,
          participantId: avec.participantId,
          prenom: avec.prenom,
        ),
      ),
    ),
  );
  return cree == true;
}
