import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/classement_service.dart';

/// Bloc de classement des 3 restaurants proposés, une fois le pacte accepté.
class BlocClassement extends StatelessWidget {
  final Pacte pacte;
  final bool jeSuisInitiateur;
  final VoidCallback onChanged;
  const BlocClassement({
    super.key,
    required this.pacte,
    required this.jeSuisInitiateur,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final monClassement =
        jeSuisInitiateur ? pacte.classementInitiateur : pacte.classementDestinataire;

    if (monClassement != null) {
      return const Text("Classement envoyé. En attente de l'autre participant...",
          style: TextStyle(fontStyle: FontStyle.italic));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Classe les 3 restaurants (1 = préféré)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (int i = 0; i < pacte.restaurantsProposes.length; i++)
          Text('${i + 1}. ${pacte.restaurantsProposes[i].nom}'),
        const SizedBox(height: 8),
        const Text(
          "Version test : le classement est simulé aléatoirement au clic ci-dessous. "
          "On pourra brancher un vrai glisser-déposer une fois l'UX validée.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _envoyerClassement,
          child: const Text('Envoyer mon classement (simulation)'),
        ),
      ],
    );
  }

  void _envoyerClassement() {
    final classement = List<int>.generate(pacte.restaurantsProposes.length, (i) => i)
      ..shuffle();
    if (jeSuisInitiateur) {
      pacte.classementInitiateur = classement;
    } else {
      pacte.classementDestinataire = classement;
    }

    if (pacte.classementInitiateur != null && pacte.classementDestinataire != null) {
      pacte.restaurantRetenu = calculerRestaurantElu(pacte);
      pacte.statut = StatutPacte.confirme;
    }
    onChanged();
  }
}
