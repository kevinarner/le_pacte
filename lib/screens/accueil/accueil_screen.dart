import 'package:flutter/material.dart';

import '../../models/demande_statut.dart';
import '../../models/pacte.dart';
import '../../models/perspective_pacte.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../../utils/noms.dart';
import '../detail_pacte/detail_pacte_screen.dart';

class AccueilScreen extends StatefulWidget {
  final VoidCallback onChanged;

  const AccueilScreen({super.key, required this.onChanged});

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends State<AccueilScreen> {
  List<Pacte>? pactes;
  String? erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      erreur = null;
      pactes = null;
    });
    try {
      final resultat = await PacteRepository.mesPactes();
      _trierParPriorite(resultat);
      if (!mounted) return;
      setState(() => pactes = resultat);
    } catch (e) {
      if (!mounted) return;
      setState(() => erreur = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = pactes;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Image.asset('assets/images/logo_mains.png'),
          tooltip: 'Menu principal',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mes Swends'),
      ),
      body: erreur != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.erreur,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Impossible de charger tes Swends.\n$erreur",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.erreur,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _charger,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : liste == null
          ? const Center(child: CircularProgressIndicator())
          : liste.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Aucun Swend pour l'instant.\nCrée-en un depuis l'accueil.",
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              children: [for (final p in liste) _cardPacte(p)],
            ),
    );
  }

  /// Priorité d'affichage : mon tour à moi (0) < scellé, trié
  /// chronologiquement dans ce groupe (1) < j'attends l'autre partie,
  /// visible mais pas plus urgent qu'un scellé à venir (2) <
  /// terminé/annulé (3). Une seule solution de tri, pas de sections.
  int _priorite(Pacte p) {
    final perspective = PerspectivePacte.de(p, AppStore.moi.id);
    if (perspective == null) return 3;
    if (!perspective.estTitulaire) {
      final fiche = perspective.maFiche!;
      if (p.statut != StatutPacte.confirme) {
        return p.statut == StatutPacte.maintenu ||
                p.statut == StatutPacte.annule ||
                p.statut == StatutPacte.annuleDoubleAbsence
            ? 3
            : 2;
      }
      if (fiche.demandeStatut == DemandeStatut.envoyee) return 0;
      if (fiche.selectionne) return 1;
      return fiche.demandeStatut.estIndisponible ? 3 : 2;
    }
    final jeSuisInitiateur = perspective.jeSuisInitiateur;
    final enNegociation =
        p.statut == StatutPacte.enAttenteChoixDateInitiateur ||
        p.statut == StatutPacte.enAttenteChoixDateDestinataire ||
        p.statut == StatutPacte.enAttenteReponse;
    if (enNegociation) {
      return pacteEstMonTour(p.statut, jeSuisInitiateur) ? 0 : 2;
    }
    if (p.statut == StatutPacte.confirme) return 1;
    return 3;
  }

  /// Tri stable même à priorité et date égales (ou absentes) : l'id
  /// départage en dernier recours pour un ordre déterministe.
  void _trierParPriorite(List<Pacte> pactes) {
    pactes.sort((a, b) {
      final pa = _priorite(a);
      final pb = _priorite(b);
      if (pa != pb) return pa.compareTo(pb);
      final da = a.dateRetenue;
      final db = b.dateRetenue;
      if (da != null && db != null && da != db) return da.compareTo(db);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return a.id.compareTo(b.id);
    });
  }

  Widget _cardPacte(Pacte pacte) {
    final perspective = PerspectivePacte.de(pacte, AppStore.moi.id);
    final estTiers = perspective != null && !perspective.estTitulaire;
    final String autreNom;
    final String titre;
    final StatutAffichage affichage;
    if (estTiers) {
      autreNom = perspective.coteAutreParticipant!.nomTitulaire;
      titre =
          'Swend ${deNom(prenomDe(perspective.coteTitulaire!.nomTitulaire))} '
          'avec ${prenomDe(autreNom)}';
      affichage = statutAffichageTiers(pacte.statut, perspective.maFiche!);
    } else {
      final estInitiateur = perspective?.jeSuisInitiateur ?? false;
      autreNom = estInitiateur
          ? pacte.destinataire.nomTitulaire
          : pacte.initiateur.nomTitulaire;
      titre = 'Swend avec $autreNom';
      affichage = statutAffichagePourMoi(
        pacte.statut,
        jeSuisInitiateur: estInitiateur,
        autrePrenom: prenomDe(autreNom),
      );
    }
    final tag = affichage.style;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(pacte.id),
        // Seuls les titulaires peuvent supprimer un Swend.
        direction: estTiers
            ? DismissDirection.none
            : DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.erreur,
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (_) => _confirmerSuppression(autreNom),
        onDismissed: (_) => _supprimer(pacte),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(radiusLg),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailPacteScreen(pacte: pacte),
                ),
              );
              widget.onChanged();
              await _charger();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          titre,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
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
                  const SizedBox(height: 6),
                  if (pacte.dateRetenue != null)
                    Text(
                      '${pacte.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner'} · '
                      '${pacte.dateRetenue!.day}/${pacte.dateRetenue!.month}/${pacte.dateRetenue!.year} '
                      'à ${formaterHeure(heureDe(pacte.dateRetenue!))}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    )
                  else if (pacte.datesProposees.isNotEmpty)
                    Text(
                      '${pacte.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner'} · '
                      '${pacte.datesProposees.length} date${pacte.datesProposees.length > 1 ? 's' : ''} proposée${pacte.datesProposees.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  if (pacte.dateRetenue != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _libelleRelatif(pacte.dateRetenue!),
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmerSuppression(String autreNom) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce Swend ?'),
        content: Text(
          'Le Swend avec $autreNom et toute sa messagerie seront supprimés définitivement. '
          'Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return confirme ?? false;
  }

  Future<void> _supprimer(Pacte pacte) async {
    setState(() => pactes!.remove(pacte));
    try {
      await PacteRepository.supprimerPacte(pacte.id);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => pactes!.add(pacte));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible de supprimer ce Swend pour le moment. Réessaie.',
          ),
        ),
      );
    }
  }

  String _libelleRelatif(DateTime date) {
    final aujourdhui = DateTime.now();
    final jours = DateTime(date.year, date.month, date.day)
        .difference(DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day))
        .inDays;
    if (jours < 0) return 'Passé';
    if (jours == 0) return "Aujourd'hui";
    if (jours == 1) return 'Demain';
    return 'Dans $jours jours';
  }
}
