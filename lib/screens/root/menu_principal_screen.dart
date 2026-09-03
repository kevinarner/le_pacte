import 'package:flutter/material.dart';

import '../../models/statut_pacte.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../accueil/accueil_screen.dart';
import '../contact/contact_screen.dart';
import '../messagerie/messagerie_screen.dart';
import '../profil/profil_screen.dart';

/// Écran d'accueil général après connexion : donne accès aux trois
/// grandes sections (Mes Pactes, Messagerie, Profil) plutôt que
/// d'atterrir directement sur l'une d'elles. Chacune ramène ici d'un tap
/// sur son logo, ce qui remplace l'ancienne barre de navigation basse.
class MenuPrincipalScreen extends StatefulWidget {
  final VoidCallback onDeconnexion;
  final VoidCallback onChanged;

  const MenuPrincipalScreen({
    super.key,
    required this.onDeconnexion,
    required this.onChanged,
  });

  @override
  State<MenuPrincipalScreen> createState() => _MenuPrincipalScreenState();
}

class _MenuPrincipalScreenState extends State<MenuPrincipalScreen> {
  int? pactesEnCours;
  int? nombreConversations;

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
      // Purement indicatif : on laisse simplement vide si ça échoue.
    }
    try {
      final fils = await PacteRepository.mesFilsDeDiscussion();
      if (!mounted) return;
      setState(() => nombreConversations = fils.length);
    } catch (_) {
      // Idem.
    }
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ecran));
    widget.onChanged();
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo_mains.png', width: 52),
              const SizedBox(height: 8),
              Text('Pakt', style: Theme.of(context).textTheme.titleLarge),
              Text('Bonjour ${AppStore.moi.prenom}',
                  style: const TextStyle(color: AppColors.texteAttenue)),
              const SizedBox(height: 28),
              _tuile(
                icone: Icons.favorite_outline,
                fond: AppColors.accentClair,
                iconeColor: AppColors.accentFonce,
                label: 'Mes Pactes',
                sousLabel: pactesEnCours == null
                    ? '...'
                    : '$pactesEnCours en cours',
                onTap: () => _ouvrir(AccueilScreen(onChanged: widget.onChanged)),
              ),
              const SizedBox(height: 10),
              _tuile(
                icone: Icons.mail_outline,
                fond: AppColors.pecheClair,
                iconeColor: AppColors.peche,
                label: 'Messagerie',
                sousLabel: nombreConversations == null
                    ? '...'
                    : nombreConversations == 0
                        ? 'Aucune conversation'
                        : '$nombreConversations conversation${nombreConversations! > 1 ? 's' : ''}',
                onTap: () => _ouvrir(const MessagerieScreen()),
              ),
              const SizedBox(height: 10),
              _tuile(
                icone: Icons.person_outline,
                fond: AppColors.neutre,
                iconeColor: AppColors.texteAttenue,
                label: 'Profil',
                sousLabel: AppStore.moi.nomComplet,
                onTap: () => _ouvrir(ProfilScreen(
                  onDeconnexion: widget.onDeconnexion,
                  onChanged: widget.onChanged,
                )),
              ),
              const SizedBox(height: 10),
              _tuile(
                icone: Icons.chat_bubble_outline,
                fond: AppColors.outline,
                iconeColor: AppColors.texte,
                label: 'Nous contacter',
                sousLabel: 'Suggérer un restaurant, nous écrire',
                onTap: () => _ouvrir(const ContactScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tuile({
    required IconData icone,
    required Color fond,
    required Color iconeColor,
    required String label,
    required String sousLabel,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icone, color: iconeColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(sousLabel,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.texteAttenue)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
