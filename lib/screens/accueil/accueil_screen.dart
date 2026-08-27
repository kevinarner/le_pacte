import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/remplacant_invitation.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../creer_pacte/creer_pacte_screen.dart';
import '../detail_pacte/chat_screen.dart';
import '../detail_pacte/detail_pacte_screen.dart';

class AccueilScreen extends StatefulWidget {
  final VoidCallback onChanged;

  const AccueilScreen({super.key, required this.onChanged});

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends State<AccueilScreen> {
  List<Pacte>? pactes;
  List<RemplacantInvitation> invitations = [];
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
      if (!mounted) return;
      setState(() => pactes = resultat);
    } catch (e) {
      if (!mounted) return;
      setState(() => erreur = e.toString());
    }
    try {
      final resultat = await PacteRepository.mesInvitationsRemplacant();
      if (!mounted) return;
      setState(() => invitations = resultat);
    } catch (_) {
      // Section secondaire : on la laisse simplement vide si elle échoue.
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = pactes;

    return Scaffold(
      appBar: AppBar(title: const Text('Le Pacte')),
      body: Column(
        children: [
          Expanded(
            child: erreur != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.terracotta, size: 32),
                          const SizedBox(height: 12),
                          Text(
                            "Impossible de charger tes pactes.\n$erreur",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.terracotta, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _charger, child: const Text('Réessayer')),
                        ],
                      ),
                    ),
                  )
                : liste == null
                    ? const Center(child: CircularProgressIndicator())
                    : liste.isEmpty && invitations.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                "Aucun pacte pour l'instant.\nAppuie sur + pour en créer un.",
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            children: [
                              for (final p in liste) _cardPacte(p),
                              if (invitations.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    "Pactes où on t'a ajouté comme remplaçant",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                for (final inv in invitations) _cardInvitation(inv),
                              ],
                            ],
                          ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreerPacteScreen()),
                );
                widget.onChanged();
                await _charger();
              },
              icon: const Icon(Icons.add),
              label: const Text('Nouveau pacte'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardPacte(Pacte pacte) {
    final estInitiateur = pacte.initiateur.idTitulaire == AppStore.moi.id;
    final autreNom =
        estInitiateur ? pacte.destinataire.nomTitulaire : pacte.initiateur.nomTitulaire;
    final tag = statutTag(pacte.statut);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
                      child: Text('Pacte avec $autreNom',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
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
                const SizedBox(height: 6),
                if (pacte.dateRetenue != null)
                  Text(
                    '${pacte.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner'} · '
                    '${pacte.dateRetenue!.day}/${pacte.dateRetenue!.month}/${pacte.dateRetenue!.year} '
                    'à ${formaterHeure(heureDe(pacte.dateRetenue!))}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  )
                else if (pacte.datesProposees.isNotEmpty)
                  Text(
                    '${pacte.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner'} · '
                    '${pacte.datesProposees.length} date${pacte.datesProposees.length > 1 ? 's' : ''} proposée${pacte.datesProposees.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                if (pacte.dateRetenue != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Colors.black45),
                      const SizedBox(width: 4),
                      Text(_libelleRelatif(pacte.dateRetenue!),
                          style: const TextStyle(color: Colors.black45, fontSize: 12)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardInvitation(RemplacantInvitation inv) {
    final tag = statutTag(inv.statutPacte);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusLg),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                remplacantId: inv.remplacantId,
                nomInterlocuteur: inv.nomTitulaire,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, color: AppColors.terracotta),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remplaçant de ${inv.nomTitulaire}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        inv.dateRetenue != null
                            ? '${inv.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner'} · '
                                '${inv.dateRetenue!.day}/${inv.dateRetenue!.month}/${inv.dateRetenue!.year}'
                            : (inv.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner'),
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tag.fond,
                    borderRadius: BorderRadius.circular(999),
                    border: tag.bordure != null ? Border.all(color: tag.bordure!) : null,
                  ),
                  child: Text(inv.statutPacte.libelle,
                      style: TextStyle(fontSize: 11.5, color: tag.texte)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
