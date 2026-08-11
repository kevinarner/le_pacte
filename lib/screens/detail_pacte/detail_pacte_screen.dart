import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../../widgets/ligne_info.dart';
import 'bloc_cascade.dart';
import 'bloc_choix_date.dart';
import 'bloc_epilogue.dart';
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
    final tag = statutTag(pacte.statut);

    return Scaffold(
      appBar: AppBar(title: Text('Pacte avec ${cotePartenaire.nomTitulaire}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pacte.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: tag.fond,
                          borderRadius: BorderRadius.circular(999),
                          border: tag.bordure != null ? Border.all(color: tag.bordure!) : null,
                        ),
                        child: Text(pacte.statut.libelle,
                            style: TextStyle(fontSize: 11.5, color: tag.texte)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LigneInfo(label: 'Avec', valeur: cotePartenaire.nomTitulaire),
                  if (pacte.dateRetenue != null)
                    LigneInfo(
                      label: 'Date',
                      valeur: formaterDateEnToutesLettres(pacte.dateRetenue!),
                    )
                  else if (pacte.datesProposees.isNotEmpty)
                    LigneInfo(
                      label: 'Dates proposées',
                      valeur: pacte.datesProposees.map(formaterDateEnToutesLettres).join(', '),
                    ),
                  if (pacte.restaurantRetenu != null) ...[
                    const Divider(height: 24),
                    LigneInfo(label: 'Lieu', valeur: pacte.restaurantRetenu!.nom),
                    if (pacte.restaurantRetenu!.lien.isNotEmpty)
                      LigneInfo(label: 'Lien', valeur: pacte.restaurantRetenu!.lien),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- Cas : c'est mon tour de choisir (ou contre-proposer) une date ---
          if ((jeSuisInitiateur && pacte.statut == StatutPacte.enAttenteChoixDateInitiateur) ||
              (!jeSuisInitiateur && pacte.statut == StatutPacte.enAttenteChoixDateDestinataire))
            BlocChoixDate(
              pacte: pacte,
              jeSuisInitiateur: jeSuisInitiateur,
              onChanged: () => setState(() {}),
            ),

          // --- Cas : je suis le destinataire et le pacte attend ma réponse ---
          if (!jeSuisInitiateur && pacte.statut == StatutPacte.enAttenteReponse)
            BlocReponse(pacte: pacte, onChanged: () => setState(() {})),

          // --- Cas : le pacte est confirmé, on peut simuler la cascade J-7/J-3/J-1 ---
          if (pacte.statut == StatutPacte.confirme)
            BlocCascade(pacte: pacte, onChanged: () => setState(() {})),

          // --- Cas : le pacte est arrivé à son terme ---
          if (pacte.statut == StatutPacte.maintenu || pacte.statut == StatutPacte.annule)
            BlocEpilogue(statut: pacte.statut),
        ],
      ),
    );
  }
}
