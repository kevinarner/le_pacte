import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/demande_statut.dart';
import '../../models/remplacant.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/telephone.dart';
import '../../widgets/remplacants_form.dart';
import 'chat_screen.dart';

/// Gestion des personnes prévues "en cas d'imprévu" pour ce Swend :
/// les voir, en ajouter, en retirer, discuter avec elles. C'est de la
/// préparation — aucune demande de remplacement ne part d'ici (seul le
/// parcours "Un imprévu ?" en envoie). Propre à ce pacte, jamais visible
/// par l'autre partie.
class MesRemplacantsScreen extends StatefulWidget {
  final String pacteId;
  final String cote;
  final CotePacte cotePacte;
  final String nomAutrePartie;
  final TypeRepas type;
  final List<DateTime> dates;

  const MesRemplacantsScreen({
    super.key,
    required this.pacteId,
    required this.cote,
    required this.cotePacte,
    required this.nomAutrePartie,
    required this.type,
    required this.dates,
  });

  @override
  State<MesRemplacantsScreen> createState() => _MesRemplacantsScreenState();
}

class _MesRemplacantsScreenState extends State<MesRemplacantsScreen> {
  /// Les personnes déjà enregistrées (vérité serveur).
  List<Remplacant> get _enregistrees => widget.cotePacte.listeRemplacants;

  /// Les personnes en cours de saisie, pas encore enregistrées.
  final List<Remplacant> _brouillons = [];

  Object? _enCoursPour;
  bool _enregistrementEnCours = false;
  String? _erreur;

  /// Signale à l'appelant qu'il doit rafraîchir la fiche du Swend.
  bool _quelqueChoseAChange = false;

  @override
  void initState() {
    super.initState();
    _brouillons.addAll(_enregistrees.where((r) => r.id == null));
    _enregistrees.removeWhere((r) => r.id == null);
    _rafraichir();
  }

  Future<void> _rafraichir() async {
    try {
      final liste = await PacteRepository.remplacantsDe(
        widget.pacteId,
        widget.cote,
      );
      if (!mounted) return;
      setState(() {
        _enregistrees
          ..clear()
          ..addAll(liste);
      });
    } catch (_) {
      // On garde ce qui était déjà en mémoire.
    }
  }

  /// Son propre numéro et les personnes déjà enregistrées ne peuvent pas
  /// être ajoutés (la base refuse aussi l'autre participant).
  Map<String, String> get _telephonesInterdits {
    final moi = normaliserTelephone(AppStore.moi.telephone);
    return {
      for (final r in _enregistrees)
        ?normaliserTelephone(r.telephone): 'Cette personne est déjà prévue.',
      ?moi: "C'est ton propre numéro.",
    };
  }

  @override
  Widget build(BuildContext context) {
    final aEnregistrer = _brouillons.where((r) => r.estRempli).isNotEmpty;
    final enregistrable =
        RemplacantsForm.listeValide(_brouillons, _telephonesInterdits);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _quelqueChoseAChange);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Personnes de confiance')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Propres à ce Swend : cette liste ne sera jamais visible par l'autre partie. "
              "Tu peux en ajouter ou en retirer à tout moment.",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            if (_enregistrees.isNotEmpty) ...[
              const Text(
                'Personnes prévues',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final r in _enregistrees) _carte(r),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
            ],
            RemplacantsForm(
              remplacants: _brouillons,
              minimum: 0,
              nomAutrePartie: widget.nomAutrePartie,
              type: widget.type,
              dates: widget.dates,
              telephonesInterdits: _telephonesInterdits,
              onChanged: () => setState(() {}),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(
                _erreur!,
                style: const TextStyle(color: AppColors.erreur, fontSize: 12),
              ),
            ],
            if (aEnregistrer) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _enregistrementEnCours || !enregistrable
                    ? null
                    : _enregistrer,
                child: _enregistrementEnCours
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carte(Remplacant r) {
    final aUnCompte = r.profilId != null;
    final enCours = _enCoursPour == r.id;
    final String? etat;
    if (r.selectionne) {
      etat = 'Prend ta place ✓';
    } else if (r.demandeStatut == DemandeStatut.envoyee) {
      etat = 'En attente';
    } else if (r.demandeStatut.estIndisponible) {
      etat = 'Indisponible';
    } else {
      etat = null;
    }

    const petitBouton = Size(0, 38);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.nomComplet,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (etat != null)
                  Text(
                    etat,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              aUnCompte
                  ? 'A rejoint Swend'
                  : "N'a pas encore rejoint Swend",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (aUnCompte)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: petitBouton),
                    onPressed: () => _ouvrirChat(r),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Discuter'),
                  ),
                if (!aUnCompte && !r.selectionne)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: petitBouton),
                    onPressed: () => inviterPersonneDeConfiance(
                      context,
                      r,
                      widget.nomAutrePartie,
                    ),
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text("Envoyer l'invitation"),
                  ),
                if (r.demandeStatut == DemandeStatut.envoyee)
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: petitBouton),
                    onPressed: enCours ? null : () => _annulerDemande(r),
                    child: const Text('Annuler la demande'),
                  )
                else if (!r.selectionne)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: petitBouton,
                      foregroundColor: AppColors.erreur,
                    ),
                    onPressed: enCours ? null : () => _retirer(r),
                    child: const Text('Retirer'),
                  ),
              ],
            ),
          ],
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

  Future<void> _enregistrer() async {
    setState(() {
      _enregistrementEnCours = true;
      _erreur = null;
    });
    try {
      await PacteRepository.synchroniserRemplacants(
        widget.pacteId,
        widget.cote,
        _brouillons,
      );
      if (!mounted) return;
      setState(() {
        final enregistres = _brouillons.where((r) => r.id != null).toList();
        _enregistrees.addAll(enregistres);
        _brouillons.removeWhere((r) => r.id != null);
        _enregistrementEnCours = false;
        _quelqueChoseAChange = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final enregistres = _brouillons.where((r) => r.id != null).toList();
        _enregistrees.addAll(enregistres);
        _brouillons.removeWhere((r) => r.id != null);
        _enregistrementEnCours = false;
        _erreur = switch (PacteRepository.codeErreurMetier(e)) {
          'personne_est_participant' =>
            "Une des personnes participe déjà à ce Swend : elle ne peut pas être personne de confiance.",
          'personne_deja_prevue' => 'Une des personnes est déjà prévue.',
          'telephone_invalide' => messageTelephoneInvalide,
          _ => "Impossible d'enregistrer pour le moment. Réessaie.",
        };
      });
    }
  }

  Future<void> _retirer(Remplacant r) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retirer ${r.prenom} de la liste ?'),
        content: Text(
          '${r.prenom} ne fera plus partie des personnes prévues pour ce Swend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await _action(r, () => PacteRepository.retirerRemplacant(r.id!), () {
      _enregistrees.remove(r);
    });
  }

  Future<void> _annulerDemande(Remplacant r) async {
    await _action(r, () => PacteRepository.annulerDemandeRemplacement(r.id!), () {
      r.demandeStatut = null;
    });
  }

  Future<void> _action(
    Remplacant r,
    Future<void> Function() appel,
    VoidCallback succes,
  ) async {
    setState(() {
      _enCoursPour = r.id;
      _erreur = null;
    });
    try {
      await appel();
      if (!mounted) return;
      setState(() {
        succes();
        _enCoursPour = null;
        _quelqueChoseAChange = true;
      });
    } catch (e) {
      if (!mounted) return;
      final code = PacteRepository.codeErreurMetier(e);
      setState(() {
        _enCoursPour = null;
        _erreur = switch (code) {
          'deja_acceptee' =>
            '${r.prenom} a déjà accepté de prendre ta place : le remplacement est définitif.',
          'retrait_impossible' =>
            '${r.prenom} a une demande en cours : impossible de la retirer.',
          'demande_non_active' => "Cette demande n'est plus en attente.",
          _ => 'Impossible pour le moment. Réessaie.',
        };
        _quelqueChoseAChange = true;
      });
      if (code != null) _rafraichir();
    }
  }
}
