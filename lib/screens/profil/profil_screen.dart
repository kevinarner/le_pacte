import 'package:flutter/material.dart';

import '../../models/statut_pacte.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_avatar.dart';

class ProfilScreen extends StatefulWidget {
  final VoidCallback onDeconnexion;
  final VoidCallback onChanged;

  const ProfilScreen({
    super.key,
    required this.onDeconnexion,
    required this.onChanged,
  });

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  int? pactesEnCours;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final pactes = await PacteRepository.mesPactes();
      if (!mounted) return;
      setState(() {
        pactesEnCours = pactes
            .where((p) =>
                p.statut != StatutPacte.maintenu &&
                p.statut != StatutPacte.annule &&
                p.statut != StatutPacte.annuleDoubleAbsence)
            .length;
      });
    } catch (_) {
      // Reste à 0 si le chargement échoue : la stat n'est qu'indicative.
    }
  }

  @override
  Widget build(BuildContext context) {
    final utilisateur = AppStore.moi;

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
                  nom: utilisateur.nomComplet,
                  taille: 76,
                  libellePlaceholder: utilisateur.photo == null ? 'Ta photo' : null,
                  onPhotoChoisie: (octets) => setState(() {
                    utilisateur.photo = octets;
                    widget.onChanged();
                  }),
                ),
                const SizedBox(height: 12),
                Text(utilisateur.nomComplet, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                _ligneStat('Pactes en cours', pactesEnCours ?? 0),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
              color: AppColors.pecheClair,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$valeur', style: const TextStyle(color: AppColors.peche)),
          ),
        ],
      ),
    );
  }
}
