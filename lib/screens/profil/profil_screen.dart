import 'package:flutter/material.dart';

import '../../models/statut_pacte.dart';
import '../../services/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_avatar.dart';

class ProfilScreen extends StatefulWidget {
  final bool perspectiveMoi;
  final VoidCallback onChangerPerspective;
  final VoidCallback onDeconnexion;
  final VoidCallback onChanged;

  const ProfilScreen({
    super.key,
    required this.perspectiveMoi,
    required this.onChangerPerspective,
    required this.onDeconnexion,
    required this.onChanged,
  });

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  @override
  Widget build(BuildContext context) {
    final utilisateur = AppStore.utilisateurCourant(widget.perspectiveMoi);
    final autre = AppStore.utilisateurAutre(widget.perspectiveMoi);
    final pactesEnCours = AppStore.pactes.where((p) {
      final impliqueUtilisateur =
          p.initiateur.nomTitulaire == utilisateur.nom || p.destinataire.nomTitulaire == utilisateur.nom;
      return impliqueUtilisateur &&
          p.statut != StatutPacte.maintenu &&
          p.statut != StatutPacte.annule;
    }).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                PhotoAvatar(
                  photo: utilisateur.photo,
                  nom: utilisateur.nom,
                  taille: 76,
                  libellePlaceholder: utilisateur.photo == null ? 'Ta photo' : null,
                  onPhotoChoisie: (octets) => setState(() {
                    utilisateur.photo = octets;
                    widget.onChanged();
                  }),
                ),
                const SizedBox(height: 12),
                Text(utilisateur.nom, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.neutre,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Perspective de test', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                _ligneStat('Pactes en cours', pactesEnCours),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: widget.onChangerPerspective,
            child: Text('Changer de vue (${utilisateur.nom} → ${autre.nom})'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onDeconnexion,
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }

  Widget _ligneStat(String label, int valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.saugeClair,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$valeur', style: const TextStyle(color: AppColors.sauge)),
          ),
        ],
      ),
    );
  }
}
