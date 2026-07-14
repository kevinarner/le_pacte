import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/classement_service.dart';

/// Bloc de classement des 3 restaurants proposés, une fois le pacte accepté.
/// Réordonnable via flèches haut/bas (le drag & drop natif est laissé pour V2).
class BlocClassement extends StatefulWidget {
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
  State<BlocClassement> createState() => _BlocClassementState();
}

class _BlocClassementState extends State<BlocClassement> {
  late List<int> ordre;

  @override
  void initState() {
    super.initState();
    ordre = List<int>.generate(widget.pacte.restaurantsProposes.length, (i) => i);
  }

  @override
  Widget build(BuildContext context) {
    final pacte = widget.pacte;
    final monClassement =
        widget.jeSuisInitiateur ? pacte.classementInitiateur : pacte.classementDestinataire;

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
        for (int position = 0; position < ordre.length; position++)
          _ligneRestaurant(position),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _envoyerClassement,
          child: const Text('Envoyer mon classement'),
        ),
      ],
    );
  }

  Widget _ligneRestaurant(int position) {
    final indexRestaurant = ordre[position];
    final restaurant = widget.pacte.restaurantsProposes[indexRestaurant];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('${position + 1}.', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(restaurant.nom)),
          IconButton(
            onPressed: position == 0 ? null : () => setState(() => _permuter(position, position - 1)),
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            onPressed: position == ordre.length - 1
                ? null
                : () => setState(() => _permuter(position, position + 1)),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }

  void _permuter(int a, int b) {
    final temp = ordre[a];
    ordre[a] = ordre[b];
    ordre[b] = temp;
  }

  void _envoyerClassement() {
    final pacte = widget.pacte;
    setState(() {
      if (widget.jeSuisInitiateur) {
        pacte.classementInitiateur = ordre;
      } else {
        pacte.classementDestinataire = ordre;
      }

      if (pacte.classementInitiateur != null && pacte.classementDestinataire != null) {
        pacte.restaurantRetenu = calculerRestaurantElu(pacte);
        pacte.statut = StatutPacte.confirme;
      }
    });
    widget.onChanged();
  }
}
