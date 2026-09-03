import 'package:flutter/material.dart';

import '../../models/statut_pacte.dart';
import '../../theme/app_theme.dart';

/// Card centrée affichée une fois le pacte arrivé à son terme
/// (maintenu ou annulé) — aucune information supplémentaire n'est
/// débloquée à ce stade, tout était déjà visible depuis l'acceptation.
class BlocEpilogue extends StatelessWidget {
  final StatutPacte statut;
  const BlocEpilogue({super.key, required this.statut});

  @override
  Widget build(BuildContext context) {
    final maintenu = statut == StatutPacte.maintenu;
    final doubleAbsence = statut == StatutPacte.annuleDoubleAbsence;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              maintenu ? Icons.celebration_outlined : Icons.event_busy_outlined,
              color: maintenu ? AppColors.accent : Colors.black45,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              maintenu ? 'Rendez-vous maintenu' : 'Pacte annulé',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              maintenu
                  ? "Quelqu'un — titulaire ou remplaçant, tu ne le sauras qu'en arrivant — "
                      "sera présent en face de toi."
                  : doubleAbsence
                      ? "Vous avez chacun dû faire appel à un remplaçant : le pacte est "
                          "annulé. Vous pouvez en créer un nouveau quand vous voulez."
                      : "Personne n'a pu être trouvé côté partenaire à temps. Le mystère "
                          "s'arrête ici, pour cette fois.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
