import 'package:flutter/material.dart';

import '../../models/annulation_swend.dart';
import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';

/// Parcours d'annulation d'un Swend scellé par un titulaire (D-022) :
/// confirmation adaptée à l'état de son côté, puis annulation par la base
/// (annuler_swend). Renvoie true si le Swend a été annulé.
///
/// [onTrouverQuelquun] : « Trouver quelqu'un pour me remplacer » (cas sans
/// imprévu) et « Continuer à chercher » (cas en recherche) ; null quand on
/// est déjà sur l'écran « Un imprévu ? » (la boîte se ferme simplement).
Future<bool> lancerAnnulationSwend(
  BuildContext context, {
  required Pacte pacte,
  required bool jeSuisInitiateur,
  VoidCallback? onTrouverQuelquun,
}) async {
  final monCote = jeSuisInitiateur ? pacte.initiateur : pacte.destinataire;
  final confirmation = ConfirmationAnnulation.pour(monCote);

  if (confirmation.cas == CasAnnulation.normal) {
    final choix = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AvantAnnulation.titre),
        content: const Text(AvantAnnulation.corps),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, 'trouver'),
            child: const Text(AvantAnnulation.actionTrouver),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.erreur),
            onPressed: () => Navigator.pop(context, 'annuler'),
            child: const Text(AvantAnnulation.actionAnnuler),
          ),
        ],
      ),
    );
    if (choix == 'trouver') onTrouverQuelquun?.call();
    if (choix != 'annuler' || !context.mounted) return false;
  }

  final confirme = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(confirmation.titre),
      content: Text(confirmation.corps),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(confirmation.actionGarder),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmation.actionAnnuler),
        ),
      ],
    ),
  );
  if (confirme != true) {
    if (confirme == false && confirmation.cas == CasAnnulation.enRecherche) {
      onTrouverQuelquun?.call();
    }
    return false;
  }

  try {
    await PacteRepository.annulerSwend(pacte.id);
    pacte.statut = StatutPacte.annule;
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageErreurAnnulation(e))));
    }
    return false;
  }
}
