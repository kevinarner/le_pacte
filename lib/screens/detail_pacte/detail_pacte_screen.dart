import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/pacte.dart';
import '../../models/perspective_pacte.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../../utils/noms.dart';
import '../../widgets/ligne_info.dart';
import 'bloc_attente.dart';
import 'bloc_choix_date.dart';
import 'bloc_epilogue.dart';
import 'bloc_presence.dart';
import 'bloc_reponse.dart';
import 'bloc_tiers.dart';
import 'imprevu_screen.dart';

class DetailPacteScreen extends StatefulWidget {
  final Pacte pacte;
  const DetailPacteScreen({super.key, required this.pacte});

  @override
  State<DetailPacteScreen> createState() => _DetailPacteScreenState();
}

class _DetailPacteScreenState extends State<DetailPacteScreen> {
  late Pacte _pacte = widget.pacte;

  Future<void> _recharger() async {
    try {
      final frais = await PacteRepository.pacteParId(_pacte.id);
      if (!mounted || frais == null) return;
      setState(() => _pacte = frais);
    } catch (_) {
      // On garde l'état affiché.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pacte = _pacte;
    // Qui suis-je sur CE pacte ? Déterminé explicitement (identifiants
    // internes, jamais le nom affiché) : titulaire initiateur, titulaire
    // destinataire, ou personne tierce "en cas d'imprévu" — jamais de
    // repli implicite vers "destinataire".
    final perspective = PerspectivePacte.de(pacte, AppStore.moi.id);
    if (perspective == null || !perspective.estTitulaire) {
      return _vueTiers(pacte, perspective);
    }
    final jeSuisInitiateur = perspective.jeSuisInitiateur;
    final cotePartenaire = jeSuisInitiateur
        ? pacte.destinataire
        : pacte.initiateur;
    final autrePrenom = prenomDe(cotePartenaire.nomTitulaire);
    final affichage = statutAffichagePourMoi(
      pacte.statut,
      jeSuisInitiateur: jeSuisInitiateur,
      autrePrenom: autrePrenom,
    );
    final tag = affichage.style;

    // C'est mon tour de choisir/contre-proposer une date ?
    final estMonTourDate =
        (jeSuisInitiateur &&
            pacte.statut == StatutPacte.enAttenteChoixDateInitiateur) ||
        (!jeSuisInitiateur &&
            pacte.statut == StatutPacte.enAttenteChoixDateDestinataire);
    // C'est mon tour de répondre (accepter/refuser) ?
    final estMonTourReponse =
        !jeSuisInitiateur && pacte.statut == StatutPacte.enAttenteReponse;
    // Le pacte est en cours de négociation mais ce n'est pas mon tour :
    // on attend une action de l'autre partie.
    final jAttendsLAutrePartie =
        !estMonTourDate &&
        !estMonTourReponse &&
        (pacte.statut == StatutPacte.enAttenteChoixDateDestinataire ||
            pacte.statut == StatutPacte.enAttenteChoixDateInitiateur ||
            pacte.statut == StatutPacte.enAttenteReponse);

    return Scaffold(
      appBar: AppBar(title: Text('Swend avec ${cotePartenaire.nomTitulaire}')),
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
                          pacte.type == TypeRepas.dejeuner
                              ? 'Déjeuner'
                              : 'Dîner',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tag.fond,
                          borderRadius: BorderRadius.circular(999),
                          border: tag.bordure != null
                              ? Border.all(color: tag.bordure!)
                              : null,
                        ),
                        child: Text(
                          affichage.libelle,
                          style: TextStyle(fontSize: 11.5, color: tag.texte),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pacte.dateRetenue != null)
                    Text(
                      formaterDateEtHeure(pacte.dateRetenue!),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    )
                  else if (pacte.datesProposees.isNotEmpty)
                    LigneInfo(
                      label: pacte.datesProposees.length > 1
                          ? 'Dates proposées'
                          : 'Date proposée',
                      valeur: pacte.datesProposees
                          .map(formaterDateEtHeure)
                          .join(', '),
                    ),
                  if (pacte.restaurantRetenu != null) ...[
                    const Divider(height: 24),
                    Text(
                      pacte.restaurantRetenu!.nom,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (pacte.restaurantRetenu!.lien.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () =>
                            _reserverLaTable(pacte.restaurantRetenu!.lien),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Voir le restaurant',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.north_east,
                              size: 13,
                              color: AppColors.accent,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- Cas : c'est mon tour de choisir (ou contre-proposer) une date ---
          if (estMonTourDate)
            BlocChoixDate(
              pacte: pacte,
              jeSuisInitiateur: jeSuisInitiateur,
              onChanged: () => setState(() {}),
            ),

          // --- Cas : je suis le destinataire et le pacte attend ma réponse ---
          if (estMonTourReponse)
            BlocReponse(pacte: pacte, onChanged: () => setState(() {})),

          // --- Cas : la négociation est en cours mais c'est le tour de l'autre ---
          if (jAttendsLAutrePartie)
            BlocAttente(
              texte: pacte.statut == StatutPacte.enAttenteReponse
                  ? '$autrePrenom peut accepter ce Swend ou le refuser.'
                  : pacte.datesProposees.length > 1
                  ? '$autrePrenom peut choisir une de ces dates ou en proposer d\'autres.'
                  : '$autrePrenom peut choisir cette date ou en proposer une autre.',
            ),

          // --- Cas : le pacte est confirmé, chacun peut déléguer sa présence ---
          if (pacte.statut == StatutPacte.confirme) ...[
            if (pacte.restaurantRetenu != null &&
                pacte.restaurantRetenu!.lien.isNotEmpty) ...[
              FilledButton.icon(
                onPressed: () => _reserverLaTable(pacte.restaurantRetenu!.lien),
                icon: const Icon(Icons.restaurant_menu, size: 18),
                label: const Text('Réserver la table'),
              ),
              const SizedBox(height: 16),
            ],
            BlocPresence(
              pacte: pacte,
              jeSuisInitiateur: jeSuisInitiateur,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _ouvrirImprevu(pacte, jeSuisInitiateur),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentFonce,
                side: const BorderSide(color: AppColors.accent),
              ),
              icon: const Icon(Icons.event_busy_outlined, size: 18),
              label: const Text('Un imprévu ?'),
            ),
          ],

          // --- Cas : le pacte est arrivé à son terme ---
          if (pacte.statut == StatutPacte.maintenu ||
              pacte.statut == StatutPacte.annule ||
              pacte.statut == StatutPacte.annuleDoubleAbsence)
            BlocEpilogue(statut: pacte.statut),
        ],
      ),
    );
  }

  Widget _vueTiers(Pacte pacte, PerspectivePacte? perspective) {
    if (perspective == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Swend')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Ce Swend n'est plus accessible.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final titulaire = prenomDe(perspective.coteTitulaire!.nomTitulaire);
    final autre = prenomDe(perspective.coteAutreParticipant!.nomTitulaire);
    return Scaffold(
      appBar: AppBar(title: Text('Swend ${deNom(titulaire)} avec $autre')),
      body: RefreshIndicator(
        onRefresh: _recharger,
        child: BlocTiers(
          pacte: pacte,
          perspective: perspective,
          onRecharger: _recharger,
        ),
      ),
    );
  }

  Future<void> _reserverLaTable(String lien) async {
    await launchUrl(Uri.parse(lien), webOnlyWindowName: '_blank');
  }

  Future<void> _ouvrirImprevu(Pacte pacte, bool jeSuisInitiateur) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImprevuScreen(
          pacte: pacte,
          jeSuisInitiateur: jeSuisInitiateur,
          onChanged: () => setState(() {}),
        ),
      ),
    );
    setState(() {});
  }
}
