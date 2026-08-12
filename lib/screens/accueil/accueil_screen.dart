import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../creer_pacte/creer_pacte_screen.dart';
import '../detail_pacte/detail_pacte_screen.dart';

class AccueilScreen extends StatefulWidget {
  final bool perspectiveMoi;
  final VoidCallback onChangerPerspective;
  final VoidCallback onChanged;

  const AccueilScreen({
    super.key,
    required this.perspectiveMoi,
    required this.onChangerPerspective,
    required this.onChanged,
  });

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends State<AccueilScreen> {
  @override
  Widget build(BuildContext context) {
    final nomMoi = widget.perspectiveMoi ? 'Moi' : 'Mon ami';
    final pactes = AppStore.pactes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Le Pacte'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: widget.onChangerPerspective,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text('Vue : $nomMoi'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: pactes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        "Aucun pacte pour l'instant.\nAppuie sur + pour en créer un.",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    itemCount: pactes.length,
                    itemBuilder: (context, i) => _cardPacte(pactes[i]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreerPacteScreen(perspectiveMoi: widget.perspectiveMoi),
                  ),
                );
                widget.onChanged();
                setState(() {});
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
    final estInitiateur = widget.perspectiveMoi;
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
                builder: (_) => DetailPacteScreen(pacte: pacte, perspectiveMoi: widget.perspectiveMoi),
              ),
            );
            widget.onChanged();
            setState(() {});
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
