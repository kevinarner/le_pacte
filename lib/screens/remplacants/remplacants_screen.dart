import 'package:flutter/material.dart';

import '../../models/remplacant.dart';
import '../../services/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_avatar.dart';

const int _minimumRemplacants = 3;

class RemplacantsScreen extends StatefulWidget {
  final bool perspectiveMoi;
  final VoidCallback onChanged;
  const RemplacantsScreen({super.key, required this.perspectiveMoi, required this.onChanged});

  @override
  State<RemplacantsScreen> createState() => _RemplacantsScreenState();
}

class _RemplacantsScreenState extends State<RemplacantsScreen> {
  final nouveauController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final utilisateur = AppStore.utilisateurCourant(widget.perspectiveMoi);
    final remplacants = utilisateur.remplacants;
    final manquants = _minimumRemplacants - remplacants.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Mes remplaçants')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Les personnes de confiance qui peuvent te représenter le jour J, si tu ne peux "
            "pas venir. Minimum 3, pour pouvoir créer ou recevoir un pacte.",
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          if (manquants > 0) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.terracottaClair,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Encore $manquants pour débloquer les pactes',
                  style: const TextStyle(fontSize: 12, color: AppColors.terracotta),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (int i = 0; i < remplacants.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ligneRemplacant(remplacants[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nouveauController,
                  decoration: const InputDecoration(hintText: 'Nom du remplaçant'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _ajouter,
                style: IconButton.styleFrom(backgroundColor: AppColors.terracotta),
                icon: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ligneRemplacant(Remplacant remplacant) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          PhotoAvatar(
            photo: remplacant.photo,
            nom: remplacant.nom,
            taille: 32,
            onPhotoChoisie: (octets) => setState(() {
              remplacant.photo = octets;
              widget.onChanged();
            }),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(remplacant.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            onPressed: () => setState(() {
              AppStore.utilisateurCourant(widget.perspectiveMoi).remplacants.remove(remplacant);
              widget.onChanged();
            }),
            icon: const Icon(Icons.close, color: AppColors.terracotta),
          ),
        ],
      ),
    );
  }

  void _ajouter() {
    final nom = nouveauController.text.trim();
    if (nom.isEmpty) return;
    setState(() {
      AppStore.utilisateurCourant(widget.perspectiveMoi).remplacants.add(Remplacant(nom: nom));
      nouveauController.clear();
      widget.onChanged();
    });
  }
}
