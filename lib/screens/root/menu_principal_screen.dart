import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../accueil/accueil_screen.dart';
import '../contact/contact_screen.dart';
import '../detail_pacte/detail_pacte_screen.dart';
import '../messagerie/messagerie_screen.dart';
import '../profil/profil_screen.dart';

/// Écran d'accueil général après connexion : donne accès aux quatre
/// sections (Mes Pactes, Messagerie, Profil, Nous contacter) plutôt que
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
  List<Pacte>? mesPactes;
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
      setState(() => mesPactes = pactes);
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

  bool _jeSuisInitiateur(Pacte p) => p.initiateur.idTitulaire == AppStore.moi.id;

  /// Un pacte attend une action de ma part : c'est mon tour de choisir
  /// une date, ou (côté destinataire) de répondre — même logique que
  /// `DetailPacteScreen`.
  bool _actionRequise(Pacte p) {
    final initiateur = _jeSuisInitiateur(p);
    final estMonTourDate =
        (initiateur && p.statut == StatutPacte.enAttenteChoixDateInitiateur) ||
            (!initiateur && p.statut == StatutPacte.enAttenteChoixDateDestinataire);
    final estMonTourReponse = !initiateur && p.statut == StatutPacte.enAttenteReponse;
    return estMonTourDate || estMonTourReponse;
  }

  Pacte? get _prochainPacte {
    final liste = mesPactes;
    if (liste == null) return null;
    final maintenant = DateTime.now();
    final confirmes = liste
        .where((p) =>
            p.statut == StatutPacte.confirme &&
            p.dateRetenue != null &&
            p.dateRetenue!.isAfter(maintenant))
        .toList()
      ..sort((a, b) => a.dateRetenue!.compareTo(b.dateRetenue!));
    return confirmes.isEmpty ? null : confirmes.first;
  }

  int get _pactesEnCours =>
      mesPactes
          ?.where((p) =>
              p.statut != StatutPacte.maintenu &&
              p.statut != StatutPacte.annule &&
              p.statut != StatutPacte.annuleDoubleAbsence)
          .length ??
      0;

  int get _nombreActionsRequises => mesPactes?.where(_actionRequise).length ?? 0;

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ecran));
    widget.onChanged();
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final prochain = _prochainPacte;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo_mains.png', width: 52),
              const SizedBox(height: 8),
              Image.asset('assets/images/logo_swend_wordmark.png', width: 140),
              const SizedBox(height: 4),
              Text('Bonjour ${AppStore.moi.prenom}',
                  style: const TextStyle(color: AppColors.texteAttenue)),
              const SizedBox(height: 20),
              if (prochain != null) ...[
                _cartePlusProche(prochain),
                const SizedBox(height: 16),
              ],
              _tuilePrincipale(
                icone: Icons.favorite_outline,
                fond: AppColors.accentClair,
                iconeColor: AppColors.accentFonce,
                label: 'Mes Pactes',
                sousLabel: mesPactes == null ? '...' : '$_pactesEnCours en cours',
                badge: _nombreActionsRequises > 0 ? _nombreActionsRequises : null,
                onTap: () => _ouvrir(AccueilScreen(onChanged: widget.onChanged)),
              ),
              const SizedBox(height: 10),
              _tuilePrincipale(
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _tuileSecondaire(
                      icone: Icons.person_outline,
                      label: 'Profil',
                      onTap: () => _ouvrir(ProfilScreen(
                        onDeconnexion: widget.onDeconnexion,
                        onChanged: widget.onChanged,
                      )),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tuileSecondaire(
                      icone: Icons.chat_bubble_outline,
                      label: 'Nous contacter',
                      onTap: () => _ouvrir(const ContactScreen()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartePlusProche(Pacte pacte) {
    final autreNom = _jeSuisInitiateur(pacte)
        ? pacte.destinataire.nomTitulaire
        : pacte.initiateur.nomTitulaire;
    return Card(
      color: AppColors.accentFonce,
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusLg),
        onTap: () => _ouvrir(DetailPacteScreen(pacte: pacte)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TON PROCHAIN PACTE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentClair,
                  letterSpacing: 0.06,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formaterDateEtHeure(pacte.dateRetenue!),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Avec $autreNom'
                '${pacte.restaurantRetenu != null ? ' · ${pacte.restaurantRetenu!.nom}' : ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.accentClair),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tuilePrincipale({
    required IconData icone,
    required Color fond,
    required Color iconeColor,
    required String label,
    required String sousLabel,
    required VoidCallback onTap,
    int? badge,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icone, color: iconeColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(sousLabel,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.texteAttenue)),
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.erreur,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tuileSecondaire({
    required IconData icone,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              Icon(icone, color: AppColors.texteAttenue, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
