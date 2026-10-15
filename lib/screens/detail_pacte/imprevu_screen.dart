import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/demande_statut.dart';
import '../../models/gel_swend.dart';
import '../../models/imprevu.dart';
import '../../models/pacte.dart';
import '../../models/remplacant.dart';
import '../../services/contact_picker_service.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/telephone.dart';
import '../../utils/textes_invitation.dart';
import '../../widgets/envoi_invitation.dart';
import '../../widgets/statut_swend.dart';
import 'annulation_swend_dialogues.dart';
import 'chat_screen.dart';

/// « Un imprévu ? » (D-027), côté titulaire uniquement : choisir une ou
/// plusieurs personnes et leur envoyer la demande en une fois (personnes
/// avec ou sans compte mélangées), suivre l'attente, solliciter quelqu'un
/// d'autre, ajouter une personne, « Je peux finalement venir » avant toute
/// acceptation, et en dernier recours « Je n'ai personne d'autre » →
/// « Annuler le Swend ». La première acceptation gagne, côté base. L'autre
/// titulaire ne voit jamais rien de tout cela. Pas d'annulation demande par
/// demande.
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
  CotePacte get _autreCote => widget.jeSuisInitiateur
      ? widget.pacte.destinataire
      : widget.pacte.initiateur;
  String get _cote => widget.jeSuisInitiateur ? 'initiateur' : 'destinataire';

  SituationImprevu? _situation;

  /// « Solliciter quelqu'un d'autre » : choix parmi les personnes pas
  /// encore sollicitées, depuis l'attente ou « Personne n'a pu ».
  bool _selection = false;
  final Set<String> _choisis = {};
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  /// Toujours relu depuis le serveur : des réponses ont pu arriver pendant
  /// que cet écran n'était pas ouvert.
  Future<void> _charger() async {
    try {
      final s = await PacteRepository.situationImprevu(widget.pacte.id, _cote);
      if (!mounted) return;
      setState(() {
        _situation = s;
        _monCote.listeRemplacants
          ..clear()
          ..addAll(s.fiches);
        _choisis.removeWhere(
          (id) => !s.sollicitables.any((r) => r.id == id),
        );
        if (s.phase == PhaseImprevu.accepte || s.sollicitables.isEmpty) {
          _selection = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _situation ??= SituationImprevu(
          etat: etatCoteDepuis(
            destinationRappel: null,
            baseARepondu: false,
            fiches: _monCote.listeRemplacants,
          ),
          fiches: _monCote.listeRemplacants,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _situation;
    return Scaffold(
      appBar: AppBar(title: const Text('Un imprévu ?')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: _corps(s),
              ),
            ),
    );
  }

  List<Widget> _corps(SituationImprevu s) {
    // Gel à H (D-023a) : l'heure du Swend est passée, on ne cherche plus
    // personne (la base refuserait de toute façon).
    if (estPasse(widget.pacte, DateTime.now())) {
      return [
        _titre(TextesImprevu.heurePassee),
        const SizedBox(height: 8),
        _sousTitre(TextesImprevu.heurePasseeCorps),
      ];
    }
    if (s.phase == PhaseImprevu.accepte) return _vueAcceptee(s);
    if (_selection || s.phase == PhaseImprevu.choix) return _vueChoix(s);
    return _vueRecherche(s);
  }

  // --- Choix des personnes (pas d'imprévu, ou « Solliciter quelqu'un d'autre ») ---

  List<Widget> _vueChoix(SituationImprevu s) {
    final depuisRecherche = s.phase != PhaseImprevu.choix;
    final (titre, sousTitre) = depuisRecherche
        ? (TextesImprevu.solliciterAutre, TextesImprevu.choisisDesPersonnes)
        : s.entete;
    final choisis = s.sollicitables
        .where((r) => _choisis.contains(r.id))
        .toList();
    final bouton = TextesImprevu.boutonEnvoi(choisis);
    // En dehors de la recherche, les personnes déjà indisponibles restent
    // visibles (sans pouvoir être choisies) ; pendant la recherche, elles
    // sont déjà dans la liste de l'attente.
    final autres = depuisRecherche
        ? const <Remplacant>[]
        : s.fiches.where((r) => !s.sollicitables.contains(r)).toList();

    return [
      _titre(titre),
      const SizedBox(height: 6),
      _sousTitre(sousTitre),
      const SizedBox(height: 16),
      for (final r in s.sollicitables)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: CheckboxListTile(
            value: _choisis.contains(r.id),
            onChanged: _enCours
                ? null
                : (v) => setState(() {
                    v == true ? _choisis.add(r.id!) : _choisis.remove(r.id);
                  }),
            title: Text(
              r.nomComplet,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: r.profilId == null
                ? Text(
                    TextesImprevu.sansCompte(r.prenom.trim()),
                    style: const TextStyle(fontSize: 12.5),
                  )
                : null,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      for (final r in autres) _ligne(r, avecActions: false),
      _messageErreur(),
      if (bouton != null) ...[
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _enCours ? null : () => _envoyer(choisis),
          child: _enCours ? _petitChargement() : Text(bouton),
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _enCours ? null : _ajouterUnePersonne,
        icon: const Icon(Icons.person_add_alt_1, size: 18),
        label: const Text(TextesImprevu.ajouterPersonne),
      ),
      if (depuisRecherche)
        Center(
          child: TextButton(
            onPressed: _enCours
                ? null
                : () => setState(() {
                    _selection = false;
                    _choisis.clear();
                  }),
            child: const Text('Retour'),
          ),
        )
      else if (s.dernierRecours)
        _actionDernierRecours(),
    ];
  }

  // --- Recherche en cours : attente, ou personne n'a pu ---

  List<Widget> _vueRecherche(SituationImprevu s) {
    final (titre, sousTitre) = s.entete;
    final personneNaPu = s.phase == PhaseImprevu.personneNaPu;
    final peutSolliciter = s.sollicitables.isNotEmpty;
    return [
      _titre(titre),
      const SizedBox(height: 6),
      _sousTitre(sousTitre),
      const SizedBox(height: 16),
      for (final r in s.sollicitees) _ligne(r, avecActions: true),
      _messageErreur(),
      const SizedBox(height: 8),
      if (personneNaPu && peutSolliciter)
        FilledButton(
          onPressed: _enCours ? null : () => setState(() => _selection = true),
          child: const Text(TextesImprevu.solliciterAutre),
        )
      else if (personneNaPu)
        FilledButton.icon(
          onPressed: _enCours ? null : _ajouterUnePersonne,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text(TextesImprevu.ajouterPersonne),
        )
      else if (peutSolliciter)
        OutlinedButton(
          onPressed: _enCours ? null : () => setState(() => _selection = true),
          child: const Text(TextesImprevu.solliciterAutre),
        ),
      if (!personneNaPu || peutSolliciter) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _enCours ? null : _ajouterUnePersonne,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text(TextesImprevu.ajouterPersonne),
        ),
      ],
      const SizedBox(height: 16),
      if (s.peutRevenir)
        Center(
          child: TextButton(
            onPressed: _enCours ? null : () => _jePeuxVenir(s),
            child: const Text(TextesImprevu.jePeuxVenir),
          ),
        ),
      if (s.dernierRecours) _actionDernierRecours(),
    ];
  }

  // --- Quelqu'un a accepté ---

  List<Widget> _vueAcceptee(SituationImprevu s) {
    final r = s.remplacant!;
    final (titre, sousTitre) = s.entete;
    return [
      _titre(titre),
      const SizedBox(height: 8),
      _sousTitre(sousTitre),
      if (r.profilId != null) ...[
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => _ouvrirChat(r),
          icon: const Icon(Icons.chat_bubble_outline, size: 16),
          label: Text('Écrire à ${r.prenom.trim()}'),
        ),
      ],
    ];
  }

  // --- Éléments ---

  Widget _titre(String texte) =>
      Text(texte, style: Theme.of(context).textTheme.titleLarge);

  Widget _sousTitre(String texte) => Text(
    texte,
    style: const TextStyle(fontSize: 14, color: AppColors.texteAttenue),
  );

  Widget _petitChargement() => const SizedBox(
    height: 16,
    width: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );

  Widget _messageErreur() => _erreur == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            _erreur!,
            style: const TextStyle(color: AppColors.erreur, fontSize: 12.5),
          ),
        );

  Widget _actionDernierRecours() => Center(
    child: TextButton(
      style: TextButton.styleFrom(foregroundColor: AppColors.texteAttenue),
      onPressed: _enCours ? null : _dernierRecours,
      child: const Text(TextesImprevu.jeNaiPersonne),
    ),
  );

  /// « Kevin — En attente — Discuter » ; une personne qui a refusé ou s'est
  /// désistée : « Indisponible », sans dire pourquoi.
  Widget _ligne(Remplacant r, {required bool avecActions}) {
    final enAttente = r.demandeStatut == DemandeStatut.envoyee;
    // Demande réactivée pour une personne sans compte (D-027) : jamais en
    // silence, le titulaire lui renvoie le message.
    final aRenvoyer = r.profilId == null && r.messageARenvoyer && enAttente;
    const lien = TextStyle(fontSize: 12.5);
    final styleLien = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.nomComplet,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _badge(
                    enAttente
                        ? TextesImprevu.enAttente
                        : TextesImprevu.indisponible,
                    enAttente ? AppColors.texte : AppColors.texteAttenue,
                  ),
                ],
              ),
              if (avecActions && aRenvoyer) ...[
                const SizedBox(height: 4),
                const Text(
                  TextesImprevu.demandeAttendDeNouveau,
                  style: TextStyle(fontSize: 12.5, color: AppColors.texteAttenue),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _enCours ? null : () => _renvoyerMessage(r),
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: Text(TextesImprevu.renvoyerLeMessage(r.prenom.trim())),
                ),
              ],
              if (avecActions && (r.profilId != null || (enAttente && !aRenvoyer)))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: r.profilId != null
                      ? TextButton(
                          style: styleLien,
                          onPressed: () => _ouvrirChat(r),
                          child: const Text(TextesImprevu.discuter, style: lien),
                        )
                      : TextButton(
                          style: styleLien,
                          onPressed: () => _envoyerMessageUrgence(r),
                          child: const Text(
                            TextesImprevu.envoyerLeMessage,
                            style: lien,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String texte, Color couleurTexte) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.neutre,
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

  // --- Actions ---

  /// Exécute une action serveur ; en cas de refus (quelqu'un vient
  /// d'accepter, personne indisponible...), affiche un message clair et
  /// relit l'état réel.
  Future<bool> _action(Future<void> Function() appel) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await appel();
      if (!mounted) return true;
      setState(() => _enCours = false);
      widget.onChanged();
      return true;
    } catch (e) {
      if (!mounted) return false;
      final code = PacteRepository.codeErreurMetier(e);
      setState(() {
        _enCours = false;
        _erreur = code == 'telephone_invalide'
            ? messageTelephoneInvalide
            : TextesImprevu.erreur(code);
      });
      await _charger();
      return false;
    }
  }

  /// Confirmation (une personne / plusieurs), puis envoi groupé tout ou
  /// rien ; ensuite, pour chaque personne sans compte, le message d'urgence
  /// à envoyer soi-même (Messages ou WhatsApp).
  Future<void> _envoyer(List<Remplacant> choisis) async {
    if (choisis.isEmpty) return;
    if (!await _confirmerEnvoi(choisis)) return;
    var canaux = <String, String>{};
    final ok = await _action(() async {
      canaux = await PacteRepository.envoyerDemandes([
        for (final r in choisis) r.id!,
      ]);
    });
    if (!ok || !mounted) return;
    _choisis.clear();
    _selection = false;
    await _charger();
    final sansCompte = choisis.where(
      (r) => canaux[r.id] == 'message' || (canaux.isEmpty && r.profilId == null),
    );
    final seul = choisis.length == 1;
    for (final r in sansCompte) {
      if (!mounted) return;
      if (seul) {
        await _envoyerMessageUrgence(r);
      } else {
        await _proposerMessageUrgence(r);
      }
    }
  }

  Future<bool> _confirmerEnvoi(List<Remplacant> choisis) async {
    final (titre, corps, action) = TextesImprevu.confirmationEnvoi(choisis);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: Text(corps),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// « Ajouter une personne » : l'ajout et la demande dans un même
  /// parcours (confirmation comme pour une personne de la liste).
  Future<void> _ajouterUnePersonne() async {
    final saisie = await showModalBottomSheet<_NouvellePersonne>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => const _FormulaireAjout(),
    );
    if (saisie == null || !mounted) return;
    if (!await _confirmerEnvoi([Remplacant(prenom: saisie.prenom)])) return;

    String? nouvelId;
    final ok = await _action(() async {
      nouvelId = await PacteRepository.ajouterEtDemanderRemplacement(
        pacteId: widget.pacte.id,
        cote: _cote,
        prenom: saisie.prenom,
        nom: saisie.nom,
        telephone: saisie.telephone,
      );
    });
    if (!ok || !mounted) return;
    _selection = false;
    await _charger();
    final ajoutee = _situation?.fiches.where((r) => r.id == nouvelId).firstOrNull;
    if (ajoutee != null && ajoutee.profilId == null && mounted) {
      await _envoyerMessageUrgence(ajoutee);
    }
  }

  /// Plusieurs personnes sans compte dans un même envoi : une proposition
  /// par personne (elle ne recevra aucune notification).
  Future<void> _proposerMessageUrgence(Remplacant r) async {
    final envoyer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TextesImprevu.titreMessageAEnvoyer(r.prenom.trim())),
        content: Text(TextesImprevu.messageAEnvoyer(r.prenom.trim())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(TextesImprevu.plusTard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(TextesImprevu.envoyerLeMessage),
          ),
        ],
      ),
    );
    if (envoyer == true && mounted) await _envoyerMessageUrgence(r);
  }

  Future<bool> _envoyerMessageUrgence(Remplacant r) => envoyerInvitation(
    context,
    telephone: r.telephone,
    message: messageUrgence(widget.pacte, r, _autreCote),
    titre: 'Envoyer la demande',
  );

  /// « Renvoyer le message à … » : le message d'urgence actualisé (date,
  /// heure, lien), puis l'action disparaît une fois le message ouvert.
  Future<void> _renvoyerMessage(Remplacant r) async {
    final envoye = await _envoyerMessageUrgence(r);
    if (!envoye || !mounted) return;
    final ok = await _action(
      () => PacteRepository.marquerMessageRenvoye(r.id!),
    );
    if (ok) await _charger();
  }

  /// « Je peux finalement venir » (avant toute acceptation) : confirmation
  /// courte, les demandes en attente sont closes, retour à la fiche.
  Future<void> _jePeuxVenir(SituationImprevu s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(TextesImprevu.titreRetour),
        content: Text(
          TextesImprevu.corpsRetour(demandesEnAttente: s.enAttente.isNotEmpty),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(TextesImprevu.actionRetour),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messager = ScaffoldMessenger.of(context);
    final fait = await _action(
      () => PacteRepository.jePeuxFinalementVenir(widget.pacte.id),
    );
    if (!fait || !mounted) return;
    Navigator.pop(context);
    messager.showSnackBar(
      const SnackBar(content: Text(TextesImprevu.retourEnregistre)),
    );
  }

  /// « Je n'ai personne d'autre » : ajouter une personne, ou annuler le
  /// Swend (seul chemin d'annulation par un titulaire, D-027).
  Future<void> _dernierRecours() async {
    final choix = await jeNaiPersonneDAutre(context, pacte: widget.pacte);
    if (!mounted) return;
    switch (choix) {
      case ChoixDernierRecours.ajouter:
        await _ajouterUnePersonne();
      case ChoixDernierRecours.annule:
        widget.onChanged();
        Navigator.pop(context);
      case null:
        await _charger();
    }
  }
}

class _NouvellePersonne {
  final String prenom;
  final String nom;
  final String telephone;
  const _NouvellePersonne(this.prenom, this.nom, this.telephone);
}

/// Prénom, nom, téléphone — la validation envoie à la fois l'ajout et la
/// demande de remplacement (après confirmation).
class _FormulaireAjout extends StatefulWidget {
  const _FormulaireAjout();

  @override
  State<_FormulaireAjout> createState() => _FormulaireAjoutState();
}

class _FormulaireAjoutState extends State<_FormulaireAjout> {
  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _telephone = TextEditingController();

  bool get _complet =>
      _prenom.text.trim().isNotEmpty &&
      _nom.text.trim().isNotEmpty &&
      telephoneValide(_telephone.text);

  String? get _erreurTelephone =>
      _telephone.text.trim().isEmpty || telephoneValide(_telephone.text)
      ? null
      : messageTelephoneInvalide;

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _choisirContact() async {
    final contact = await ContactPickerService.choisirContact();
    if (contact == null || !mounted) return;
    final parts = (contact['nom'] ?? '').trim().split(RegExp(r'\s+'));
    setState(() {
      if (parts.isNotEmpty && parts.first.isNotEmpty) {
        _prenom.text = parts.first;
        _nom.text = parts.skip(1).join(' ');
      }
      final tel = contact['telephone'] ?? '';
      if (tel.isNotEmpty) _telephone.text = tel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TextesImprevu.ajouterPersonne,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            TextesImprevu.ajoutCorps,
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _prenom,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _nom,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Numéro de mobile',
              errorText: _erreurTelephone,
              errorMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          StatutSwend(prenom: _prenom.text, telephone: _telephone.text),
          if (ContactPickerService.disponible) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _choisirContact,
              icon: const Icon(Icons.contacts_outlined, size: 18),
              label: const Text('Choisir dans mes contacts'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _complet
                ? () => Navigator.pop(
                    context,
                    _NouvellePersonne(
                      _prenom.text.trim(),
                      _nom.text.trim(),
                      _telephone.text.trim(),
                    ),
                  )
                : null,
            child: const Text(TextesImprevu.ajoutAction),
          ),
        ],
      ),
    );
  }
}
