import 'package:flutter/material.dart';

import '../../models/statut_pacte.dart';
import '../../services/app_store.dart';
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
          TextButton.icon(
            onPressed: widget.onChangerPerspective,
            icon: const Icon(Icons.swap_horiz, color: Colors.white),
            label: Text('Vue : $nomMoi', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: pactes.isEmpty
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
              padding: const EdgeInsets.all(12),
              itemCount: pactes.length,
              itemBuilder: (context, i) {
                final pacte = pactes[i];
                final estInitiateur = widget.perspectiveMoi;
                final autreNom = estInitiateur
                    ? pacte.destinataire.nomTitulaire
                    : pacte.initiateur.nomTitulaire;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text('Pacte avec $autreNom'),
                    subtitle: Text(pacte.statut.libelle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailPacteScreen(
                            pacte: pacte,
                            perspectiveMoi: widget.perspectiveMoi,
                          ),
                        ),
                      );
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
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
    );
  }
}
