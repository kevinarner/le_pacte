import 'package:flutter/material.dart';

import '../models/gel_swend.dart';
import '../models/remplacant.dart';
import '../services/pacte_repository.dart';
import '../theme/app_theme.dart';

/// Action secondaire d'une personne de confiance simplement prévue
/// (aucune demande en cours) : "Je ne serai pas disponible", puis, si elle
/// change d'avis, "Je suis finalement disponible". Sans formulaire ni
/// justification ; son titulaire est prévenu par la base. N'affiche rien
/// dans les autres états (demande, place prise, refus, désistement).
class ActionDisponibilite extends StatefulWidget {
  final Remplacant fiche;
  final Future<void> Function() onChange;

  const ActionDisponibilite({
    super.key,
    required this.fiche,
    required this.onChange,
  });

  /// Affichée seulement tant que la personne est simplement prévue.
  static bool concerne(Remplacant fiche) =>
      fiche.peutSeDeclarerIndisponible ||
      (fiche.indisponibleSpontanement && fiche.demandeStatut == null);

  @override
  State<ActionDisponibilite> createState() => _ActionDisponibiliteState();
}

class _ActionDisponibiliteState extends State<ActionDisponibilite> {
  bool _enCours = false;

  Future<void> _basculer() async {
    final fiche = widget.fiche;
    setState(() => _enCours = true);
    try {
      if (fiche.indisponibleSpontanement) {
        await PacteRepository.signalerDisponibilite(fiche.id!);
      } else {
        await PacteRepository.signalerIndisponibilite(fiche.id!);
      }
    } catch (e) {
      if (mounted) {
        final code = PacteRepository.codeErreurMetier(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              code == 'swend_passe'
                  ? messageSwendPasse
                  : code == 'swend_inactif'
                  ? "Ce Swend n'est plus actif."
                  : code == 'demande_non_active'
                  ? 'Une demande est en cours : réponds-y depuis la conversation.'
                  : 'Impossible pour le moment. Réessaie.',
            ),
          ),
        );
      }
    }
    await widget.onChange();
    if (mounted) setState(() => _enCours = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!ActionDisponibilite.concerne(widget.fiche)) {
      return const SizedBox.shrink();
    }
    final indisponible = widget.fiche.indisponibleSpontanement;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: indisponible
            ? AppColors.accentFonce
            : AppColors.texteAttenue,
      ),
      onPressed: _enCours || widget.fiche.id == null ? null : _basculer,
      child: Text(
        indisponible
            ? 'Je suis finalement disponible'
            : 'Je ne serai pas disponible',
      ),
    );
  }
}
