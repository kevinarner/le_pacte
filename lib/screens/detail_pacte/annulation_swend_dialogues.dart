import 'package:flutter/material.dart';

import '../../models/imprevu.dart';
import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';

/// Ce que le titulaire a choisi dans « Je n'ai personne d'autre ».
enum ChoixDernierRecours { ajouter, annule }

/// « Je n'ai personne d'autre » (D-027 points 12 et 13) : le seul chemin
/// d'annulation par un titulaire, depuis « Un imprévu ? ». Principal
/// `Ajouter une personne`, secondaire `Annuler le Swend`, puis confirmation
/// « Annuler ce Swend ? / Cette action est définitive. L'autre personne sera
/// prévenue. » et annulation par la base (`annuler_swend`).
Future<ChoixDernierRecours?> jeNaiPersonneDAutre(
  BuildContext context, {
  required Pacte pacte,
}) async {
  final choix = await showDialog<ChoixDernierRecours>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(TextesImprevu.titrePersonneDAutre),
      content: const Text(TextesImprevu.corpsPersonneDAutre),
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, ChoixDernierRecours.ajouter),
          child: const Text(TextesImprevu.ajouterPersonne),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.erreur),
          onPressed: () => Navigator.pop(context, ChoixDernierRecours.annule),
          child: const Text(TextesImprevu.annulerLeSwend),
        ),
      ],
    ),
  );
  if (choix != ChoixDernierRecours.annule || !context.mounted) return choix;
  return await confirmerEtAnnuler(context, pacte: pacte)
      ? ChoixDernierRecours.annule
      : null;
}

/// Confirmation « Annuler ce Swend ? / Cette action est définitive. L'autre
/// personne sera prévenue. », puis annulation par la base. Aussi utilisée
/// dès H-3 (D-027, 20/10) : un nouvel imprévu ne lance plus de recherche,
/// il annule le Swend. Renvoie true si le Swend est annulé.
Future<bool> confirmerEtAnnuler(
  BuildContext context, {
  required Pacte pacte,
}) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(TextesImprevu.titreConfirmationAnnulation),
      content: const Text(TextesImprevu.corpsConfirmationAnnulation),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(TextesImprevu.garderLeSwend),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(TextesImprevu.annulerLeSwend),
        ),
      ],
    ),
  );
  if (confirme != true) return false;

  try {
    await PacteRepository.annulerSwend(pacte.id);
    pacte.statut = StatutPacte.annule;
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TextesImprevu.erreur(PacteRepository.codeErreurMetier(e)),
          ),
        ),
      );
    }
    return false;
  }
}
