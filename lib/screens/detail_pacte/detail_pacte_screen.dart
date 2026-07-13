import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../widgets/ligne_info.dart';
import 'bloc_cascade.dart';
import 'bloc_classement.dart';
import 'bloc_reponse.dart';

class DetailPacteScreen extends StatefulWidget {
  final Pacte pacte;
  final bool perspectiveMoi;
  const DetailPacteScreen({super.key, required this.pacte, required this.perspectiveMoi});

  @override
  State<DetailPacteScreen> createState() => _DetailPacteScreenState();
}

class _DetailPacteScreenState extends State<DetailPacteScreen> {
  @override
  Widget build(BuildContext context) {
    final pacte = widget.pacte;
    // Suis-je le destinataire de CE pacte, vu ma perspective actuelle ?
    final jeSuisInitiateur = pacte.initiateur.nomTitulaire ==
        (widget.perspectiveMoi ? 'Moi' : 'Mon ami');
    final cotePartenaire = jeSuisInitiateur ? pacte.destinataire : pacte.initiateur;

    return Scaffold(
      appBar: AppBar(title: Text('Pacte avec ${cotePartenaire.nomTitulaire}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LigneInfo(
            label: 'Type',
            valeur: pacte.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner',
          ),
          LigneInfo(label: 'Avec', valeur: cotePartenaire.nomTitulaire),
          if (pacte.date != null)
            LigneInfo(
              label: 'Date',
              valeur: '${pacte.date!.day}/${pacte.date!.month}/${pacte.date!.year}',
            ),
          LigneInfo(label: 'Statut', valeur: pacte.statut.libelle),
          if (pacte.restaurantRetenu != null) ...[
            const Divider(height: 32),
            LigneInfo(label: 'Restaurant retenu', valeur: pacte.restaurantRetenu!.nom),
            if (pacte.restaurantRetenu!.lien.isNotEmpty)
              LigneInfo(label: 'Lien', valeur: pacte.restaurantRetenu!.lien),
          ],
          const Divider(height: 32),

          // --- Cas : je suis le destinataire et le pacte attend ma réponse ---
          if (!jeSuisInitiateur && pacte.statut == StatutPacte.enAttenteReponse)
            BlocReponse(pacte: pacte, onChanged: () => setState(() {})),

          // --- Cas : le pacte est accepté mais le classement n'est pas fait ---
          if (pacte.statut == StatutPacte.accepteEnAttenteClassement)
            BlocClassement(
              pacte: pacte,
              jeSuisInitiateur: jeSuisInitiateur,
              onChanged: () => setState(() {}),
            ),

          // --- Cas : le pacte est confirmé, on peut simuler la cascade J-7/J-3/J-1 ---
          if (pacte.statut == StatutPacte.confirme)
            BlocCascade(pacte: pacte, onChanged: () => setState(() {})),
        ],
      ),
    );
  }
}
