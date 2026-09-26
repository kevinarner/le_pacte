import 'package:flutter/material.dart';

import '../../models/demande_statut.dart';
import '../../models/fil_de_discussion.dart';
import '../../models/pacte.dart';
import '../../models/perspective_pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../../utils/noms.dart';
import '../accueil/accueil_screen.dart';
import '../creer_pacte/creer_pacte_screen.dart';
import '../detail_pacte/chat_screen.dart';
import '../detail_pacte/detail_pacte_screen.dart';
import '../profil/profil_screen.dart';

/// Écran d'accueil général après connexion. Chaque Swend est pensé comme
/// un objet autonome qui porte lui-même sa messagerie (voir le détail
/// d'un pacte) : cet écran ne propose donc plus de section Messagerie
/// indépendante, seulement le prochain rendez-vous, une éventuelle
/// notification de message, la liste des Swends et un accès discret au
/// profil.
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
  List<FilDeDiscussion>? mesFils;

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
      setState(() => mesFils = fils);
    } catch (_) {
      // Idem.
    }
  }

  PerspectivePacte? _perspective(Pacte p) =>
      PerspectivePacte.de(p, AppStore.moi.id);

  /// Je serai réellement présent à ce Swend : titulaire, ou personne
  /// tierce qui a accepté de prendre une place. Une personne seulement
  /// "prévue en cas d'imprévu" n'y va pas.
  bool _jyVais(Pacte p) {
    final v = _perspective(p);
    if (v == null) return false;
    return v.estTitulaire || v.maFiche!.selectionne;
  }

  /// Un pacte attend une action de ma part : c'est mon tour de choisir
  /// une date ou de répondre (titulaire), ou une demande "Un imprévu ?"
  /// m'attend (personne tierce).
  bool _actionRequise(Pacte p) {
    final v = _perspective(p);
    if (v == null) return false;
    if (!v.estTitulaire) {
      return p.statut == StatutPacte.confirme &&
          !v.maFiche!.selectionne &&
          v.maFiche!.demandeStatut == DemandeStatut.envoyee;
    }
    return pacteEstMonTour(p.statut, v.jeSuisInitiateur);
  }

  Pacte? get _prochainPacte {
    final liste = mesPactes;
    if (liste == null) return null;
    final maintenant = DateTime.now();
    final confirmes =
        liste
            .where(
              (p) =>
                  p.statut == StatutPacte.confirme &&
                  _jyVais(p) &&
                  p.dateRetenue != null &&
                  p.dateRetenue!.isAfter(maintenant),
            )
            .toList()
          ..sort((a, b) => a.dateRetenue!.compareTo(b.dateRetenue!));
    return confirmes.isEmpty ? null : confirmes.first;
  }

  int get _pactesAVenir =>
      mesPactes
          ?.where(
            (p) =>
                _jyVais(p) &&
                p.statut != StatutPacte.maintenu &&
                p.statut != StatutPacte.annule &&
                p.statut != StatutPacte.annuleDoubleAbsence,
          )
          .length ??
      0;

  int get _nombreActionsRequises =>
      mesPactes?.where(_actionRequise).length ?? 0;

  /// Mes rôles de personne de confiance encore d'actualité (Swend ni
  /// passé ni annulé, et pas "indisponible" : refusé, clôturé, désisté),
  /// du plus proche au plus lointain. Un rôle n'est pas un Swend "à
  /// venir" tant que je n'ai pas accepté de prendre la place.
  List<(Pacte, PerspectivePacte)> get _rolesTiers {
    final liste = mesPactes;
    if (liste == null) return [];
    final maintenant = DateTime.now();
    final roles = [
      for (final p in liste)
        if (_perspective(p) case final v? when !v.estTitulaire)
          if (p.statut != StatutPacte.maintenu &&
              p.statut != StatutPacte.annule &&
              p.statut != StatutPacte.annuleDoubleAbsence &&
              (p.dateRetenue == null || p.dateRetenue!.isAfter(maintenant)) &&
              !v.maFiche!.demandeStatut.estIndisponible)
            (p, v),
    ];
    roles.sort((a, b) {
      final da = a.$1.dateRetenue;
      final db = b.$1.dateRetenue;
      if (da == null || db == null) return da == null ? 1 : -1;
      return da.compareTo(db);
    });
    return roles;
  }

  /// Demandes "Un imprévu ?" qui attendent ma réponse : en tête d'accueil.
  List<(Pacte, PerspectivePacte)> get _demandesTiers => [
    for (final (p, v) in _rolesTiers)
      if (_actionRequise(p)) (p, v),
  ];

  /// Rôles sans action à faire : prévu (pas encore sollicité) ou ayant
  /// accepté de prendre la place.
  List<(Pacte, PerspectivePacte)> get _onCompteSurMoi => [
    for (final (p, v) in _rolesTiers)
      if (!_actionRequise(p) &&
          (v.maFiche!.selectionne || v.maFiche!.demandeStatut == null))
        (p, v),
  ];

  /// Le message le plus récent qui ne vient pas de moi, tous fils
  /// confondus — pas un vrai suivi lu/non-lu (aucun état n'est
  /// persisté), juste "le dernier mot n'est pas de moi".
  FilDeDiscussion? get _messageAmeSignaler {
    final fils = mesFils;
    if (fils == null) return null;
    final candidats =
        fils
            .where(
              (f) => !f.dernierMessageDeMoi && f.dateDernierMessage != null,
            )
            .toList()
          ..sort(
            (a, b) => b.dateDernierMessage!.compareTo(a.dateDernierMessage!),
          );
    return candidats.isEmpty ? null : candidats.first;
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ecran));
    widget.onChanged();
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final prochain = _prochainPacte;
    final message = _messageAmeSignaler;
    final demandes = _demandesTiers;
    final onCompteSurMoi = _onCompteSurMoi;

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
              Text(
                'Bonjour ${AppStore.moi.prenom}',
                style: const TextStyle(color: AppColors.texteAttenue),
              ),
              const SizedBox(height: 20),
              for (final (p, v) in demandes) ...[
                _carteDemande(p, v),
                const SizedBox(height: 12),
              ],
              if (prochain != null) ...[
                _cartePlusProche(prochain),
                const SizedBox(height: 12),
              ],
              if (message != null) ...[
                _carteMessage(message),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: () => _ouvrir(const CreerPacteScreen()),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Créer un Swend'),
              ),
              const SizedBox(height: 18),
              _tuilePrincipale(
                icone: Icons.favorite_outline,
                fond: AppColors.accentClair,
                iconeColor: AppColors.accentFonce,
                label: 'Mes Swends',
                sousLabel: mesPactes == null ? '...' : '$_pactesAVenir à venir',
                badge: _nombreActionsRequises > 0
                    ? _nombreActionsRequises
                    : null,
                onTap: () =>
                    _ouvrir(AccueilScreen(onChanged: widget.onChanged)),
              ),
              if (onCompteSurMoi.isNotEmpty) ...[
                const SizedBox(height: 22),
                _etiquette('ON COMPTE SUR TOI'),
                const SizedBox(height: 8),
                for (final (p, v) in onCompteSurMoi) ...[
                  _carteOnCompteSurMoi(p, v),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 18),
              _lignProfil(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartePlusProche(Pacte pacte) {
    final v = _perspective(pacte)!;
    final autreNom = v.estTitulaire
        ? (v.jeSuisInitiateur
              ? pacte.destinataire.nomTitulaire
              : pacte.initiateur.nomTitulaire)
        : v.coteAutreParticipant!.nomTitulaire;
    return FractionallySizedBox(
      widthFactor: 0.82,
      child: Card(
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
                  'TON PROCHAIN SWEND',
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.accentClair,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _etiquette(String texte) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      texte,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.texteAttenue,
        letterSpacing: 0.06,
      ),
    ),
  );

  /// "Swend avec David · Mercredi 25 novembre · 19h30"
  String _contexteTiers(Pacte p, PerspectivePacte v) {
    final autre = prenomDe(v.coteAutreParticipant!.nomTitulaire);
    final date = p.dateRetenue;
    return 'Swend avec $autre · '
        '${date != null ? formaterJourEtHeureCourt(date) : 'date à confirmer'}';
  }

  /// Une demande "Un imprévu ?" en attente de ma réponse : l'élément le
  /// plus visible de l'accueil. Ouvre la fiche du Swend (vue tiers), d'où
  /// l'on répond.
  Widget _carteDemande(Pacte p, PerspectivePacte v) {
    final titulaire = prenomDe(v.coteTitulaire!.nomTitulaire);
    final autre = prenomDe(v.coteAutreParticipant!.nomTitulaire);
    return SizedBox(
      width: double.infinity,
      child: Card(
        color: AppColors.pecheClair,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: AppColors.peche, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "UNE DEMANDE T'ATTEND",
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.texteAttenue,
                  letterSpacing: 0.06,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$titulaire a un imprévu',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$titulaire te demande de prendre sa place pour son Swend avec $autre.',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(
                _contexteTiers(p, v),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.texteAttenue,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _ouvrir(DetailPacteScreen(pacte: p)),
                  child: const Text('Répondre à la demande'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rôle sans action à faire : "X compte sur toi" (prévu) ou "Tu prends
  /// la place de X" (accepté). Ouvre la fiche du Swend (vue tiers).
  Widget _carteOnCompteSurMoi(Pacte p, PerspectivePacte v) {
    final titulaire = prenomDe(v.coteTitulaire!.nomTitulaire);
    final autre = prenomDe(v.coteAutreParticipant!.nomTitulaire);
    final accepte = v.maFiche!.selectionne;
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accepte
                    ? 'Tu prends la place ${deNom(titulaire)}'
                    : '$titulaire compte sur toi pour un Swend',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _contexteTiers(p, v),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.texteAttenue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                accepte
                    ? "$autre ne saura pas que c'est toi."
                    : "Tu pourrais prendre sa place en cas d'imprévu.",
                style: const TextStyle(fontSize: 13),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _ouvrir(DetailPacteScreen(pacte: p)),
                  child: const Text('Voir le Swend'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carteMessage(FilDeDiscussion fil) {
    final avecQui = fil.autrePartieNom;
    final base = avecQui != null && avecQui.trim().isNotEmpty
        ? 'Swend avec ${prenomDe(avecQui)}'
        : 'Ton Swend';
    final contexte = fil.dateConcernee != null
        ? '$base · ${_libelleDateCourt(fil.dateConcernee!)} à ${formaterHeure(heureDe(fil.dateConcernee!))}'
        : base;
    return Card(
      color: AppColors.pecheClair,
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusLg),
        onTap: () => _ouvrir(
          ChatScreen(
            remplacantId: fil.remplacantId,
            nomInterlocuteur: fil.nomInterlocuteur,
            telephoneInterlocuteur: fil.telephoneInterlocuteur,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.mail_outline, color: AppColors.peche, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${fil.nomInterlocuteur} vous a écrit',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      contexte,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.texteAttenue,
                      ),
                    ),
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

  String _libelleDateCourt(DateTime date) =>
      '${date.day} ${moisAnnee[date.month - 1]}';

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
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      sousLabel,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.texteAttenue,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
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

  /// Profil est volontairement discret : plus de tuile-carte pleine
  /// largeur comme les Swends, une simple ligne.
  Widget _lignProfil() {
    return InkWell(
      borderRadius: BorderRadius.circular(radiusLg),
      onTap: () => _ouvrir(
        ProfilScreen(
          onDeconnexion: widget.onDeconnexion,
          onChanged: widget.onChanged,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_outline,
              color: AppColors.texteAttenue,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              'Profil',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.texteAttenue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
