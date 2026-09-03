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
  int? pactesRealises;
  int? remplacementsEffectues;
  int? fiabilite;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final pactes = await PacteRepository.mesPactes();
      final termines = pactes
          .where((p) =>
              p.statut == StatutPacte.maintenu ||
              p.statut == StatutPacte.confirme ||
              p.statut == StatutPacte.annule ||
              p.statut == StatutPacte.annuleDoubleAbsence)
          .toList();
      final honores =
          termines.where((p) => p.statut == StatutPacte.maintenu || p.statut == StatutPacte.confirme);
      if (!mounted) return;
      setState(() {
        pactesRealises = pactes.where((p) => p.statut == StatutPacte.maintenu).length;
        fiabilite = termines.isEmpty
            ? null
            : (honores.length / termines.length * 100).round();
      });
    } catch (_) {
      // Purement indicatif : on laisse simplement vide si ça échoue.
    }
    try {
      final n = await PacteRepository.nombreRemplacementsEffectues();
      if (!mounted) return;
      setState(() => remplacementsEffectues = n);
    } catch (_) {
      // Idem.
    }
  }

  @override
  Widget build(BuildContext context) {
    final utilisateur = AppStore.moi;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Image.asset('assets/images/logo_mains.png'),
          tooltip: 'Menu principal',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Profil'),
      ),
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
                Text(utilisateur.email, style: const TextStyle(color: AppColors.texteAttenue)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _statTuile(pactesRealises, 'pactes réalisés')),
              const SizedBox(width: 10),
              Expanded(child: _statTuile(remplacementsEffectues, 'remplacements')),
              const SizedBox(width: 10),
              Expanded(
                child: _statTuile(fiabilite, 'fiabilité', suffixe: '%'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                _ligneReglage('Nom', _bientotDisponible),
                _separateur(),
                _ligneReglage('Téléphone', _bientotDisponible),
                _separateur(),
                _ligneReglage('Email', _bientotDisponible),
                _separateur(),
                _ligneReglage('Mot de passe', _bientotDisponible),
                _separateur(),
                _ligneReglage('Notifications', _bientotDisponible),
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

  Widget _statTuile(int? valeur, String label, {String suffixe = ''}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      child: Column(
        children: [
          Text(
            valeur == null ? '—' : '$valeur$suffixe',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: AppColors.texteAttenue, height: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _separateur() => const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _ligneReglage(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  void _bientotDisponible() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bientôt disponible.')),
    );
  }
}
