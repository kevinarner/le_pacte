import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/demande_statut.dart';
import '../../models/pacte.dart';
import '../../models/remplacant.dart';
import '../../models/statut_pacte.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';

/// Parcours "Un imprévu ?" : demander à une ou plusieurs personnes de
/// confiance prévues pour ce Swend de prendre la place, avec leur
/// accord. Rien n'est transféré tant que personne n'a accepté, et le
/// Swend reste "Scellé" — pour l'utilisateur comme pour l'autre partie,
/// qui ne voit jamais rien de cette tentative (voir `BlocPresence`,
/// dont la logique d'affichage n'a pas besoin de changer : elle ne
/// montre déjà quelqu'un que si `selectionne = true`, ce qui n'arrive
/// plus qu'après acceptation).
class ImprevuScreen extends StatefulWidget {
  final Pacte pacte;
  final bool jeSuisInitiateur;
  final VoidCallback onChanged;

  const ImprevuScreen({
    super.key,
    required this.pacte,
    required this.jeSuisInitiateur,
    required this.onChanged,
  });

  @override
  State<ImprevuScreen> createState() => _ImprevuScreenState();
}

class _ImprevuScreenState extends State<ImprevuScreen> {
  CotePacte get _monCote => widget.jeSuisInitiateur
      ? widget.pacte.initiateur
      : widget.pacte.destinataire;

  List<Remplacant>? _remplacants;
  bool _afficherListe = false;
  bool _enCoursAnnulation = false;
  Object? _enCoursPour;
  String? erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  /// Recharge depuis le serveur plutôt que de se fier uniquement à ce
  /// que `DetailPacteScreen` avait déjà en mémoire : plusieurs demandes
  /// pouvant être en cours en parallèle, une réponse a pu arriver
  /// pendant que cet écran n'était pas ouvert.
  Future<void> _charger() async {
    try {
      final liste = await PacteRepository.remplacantsDe(
        widget.pacte.id,
        widget.jeSuisInitiateur ? 'initiateur' : 'destinataire',
      );
      if (!mounted) return;
      setState(() {
        _monCote.listeRemplacants
          ..clear()
          ..addAll(liste);
        _remplacants = _monCote.listeRemplacants;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _remplacants = _monCote.listeRemplacants);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = _remplacants;
    return Scaffold(
      appBar: AppBar(title: const Text('Un imprévu ?')),
      body: liste == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: _corps(liste),
            ),
    );
  }

  List<Widget> _corps(List<Remplacant> liste) {
    final valides = liste.where((r) => r.estRempli).toList();
    final accepte = valides.where((r) => r.selectionne).toList();
    if (accepte.isNotEmpty) return _vueAcceptee(accepte.first);

    final toutesIndisponibles =
        valides.isNotEmpty &&
        valides.every((r) => r.demandeStatut == DemandeStatut.refusee);
    if (toutesIndisponibles) return _vueToutIndisponible();

    if (!_afficherListe) return _vueIntro();

    return [
      Text(
        'Qui peut prendre votre place ?',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      for (final r in valides) _cartePersonne(r),
    ];
  }

  List<Widget> _vueIntro() {
    return [
      Text(
        'Vous ne pouvez plus être là ?',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        "Pas de panique. Une des personnes choisies à l'avance peut prendre votre place.",
        style: TextStyle(fontSize: 14, color: Colors.black54),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => setState(() => _afficherListe = true),
        child: const Text('Trouver quelqu\'un pour me remplacer'),
      ),
    ];
  }

  List<Widget> _vueAcceptee(Remplacant r) {
    return [
      Text(
        '${r.prenom} prendra votre place.',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Votre Swend reste scellé.',
        style: TextStyle(fontSize: 14, color: Colors.black54),
      ),
      const SizedBox(height: 4),
      Text(
        '${r.prenom} a maintenant toutes les informations nécessaires pour le jour J.',
        style: const TextStyle(fontSize: 14, color: Colors.black54),
      ),
    ];
  }

  List<Widget> _vueToutIndisponible() {
    return [
      Text(
        "Aucune des personnes prévues n'est disponible.",
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Ce Swend doit être annulé.',
        style: TextStyle(fontSize: 14, color: Colors.black54),
      ),
      const SizedBox(height: 24),
      if (erreur != null) ...[
        Text(
          erreur!,
          style: const TextStyle(color: AppColors.erreur, fontSize: 12),
        ),
        const SizedBox(height: 8),
      ],
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
        onPressed: _enCoursAnnulation ? null : _confirmerAnnulation,
        child: _enCoursAnnulation
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Annuler le Swend'),
      ),
    ];
  }

  Widget _cartePersonne(Remplacant r) {
    final enCours = _enCoursPour == (r.id ?? r);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.nomComplet,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (r.demandeStatut == DemandeStatut.envoyee &&
                        r.profilId != null) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _ouvrirChat(r),
                        child: Text(
                          'Écrire à ${r.prenom}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _actionPersonne(r, enCours),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionPersonne(Remplacant r, bool enCours) {
    switch (r.demandeStatut) {
      case null:
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: enCours ? null : () => _confirmerDemande(r),
          child: enCours
              ? const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Lui demander'),
        );
      case DemandeStatut.envoyee:
        return _badge('En attente', AppColors.neutre, AppColors.texte);
      case DemandeStatut.refusee:
        return _badge('Indisponible', AppColors.neutre, AppColors.texteAttenue);
      case DemandeStatut.cloturee:
        return _badge('Clôturée', AppColors.neutre, AppColors.texteAttenue);
      case DemandeStatut.acceptee:
        return _badge('Accepté', AppColors.accentClair, AppColors.accentFonce);
    }
  }

  Widget _badge(String texte, Color fond, Color couleurTexte) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 12,
          color: couleurTexte,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _ouvrirChat(Remplacant r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          remplacantId: r.id!,
          nomInterlocuteur: r.nomComplet,
          telephoneInterlocuteur: r.telephone,
        ),
      ),
    );
  }

  Future<void> _confirmerDemande(Remplacant r) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Demander à ${r.prenom} de prendre votre place ?'),
        content: const Text('Elle pourra accepter ou refuser.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer la demande'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    setState(() => _enCoursPour = r.id ?? r);
    try {
      await PacteRepository.envoyerDemandeRemplacement(r.id!);
      if (!mounted) return;
      setState(() {
        r.demandeStatut = DemandeStatut.envoyee;
        _enCoursPour = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _enCoursPour = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Impossible d'envoyer la demande pour le moment. Réessaie.",
          ),
        ),
      );
    }
  }

  Future<void> _confirmerAnnulation() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler ce Swend ?'),
        content: const Text(
          'Aucune des personnes prévues ne peut prendre la place. Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler le Swend'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    setState(() => _enCoursAnnulation = true);
    try {
      await PacteRepository.mettreAJourStatut(
        widget.pacte.id,
        StatutPacte.annule,
      );
      widget.pacte.statut = StatutPacte.annule;
      widget.onChanged();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enCoursAnnulation = false;
        erreur = "Impossible d'annuler le Swend pour le moment. Réessaie.";
      });
    }
  }
}
