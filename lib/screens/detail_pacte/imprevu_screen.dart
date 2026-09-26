import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../models/cote_pacte.dart';
import '../../models/demande_statut.dart';
import '../../models/pacte.dart';
import '../../models/remplacant.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../services/contact_picker_service.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../../utils/noms.dart';
import '../../utils/telephone.dart';
import '../../widgets/envoi_invitation.dart';
import '../../widgets/statut_swend.dart';
import 'chat_screen.dart';

/// Parcours "Un imprévu ?", côté titulaire uniquement : demander à une
/// ou plusieurs personnes prévues (en parallèle, sans ordre) de prendre
/// sa place, annuler une demande en attente, ajouter quelqu'un d'autre
/// en lui envoyant directement la demande. La première acceptation
/// enregistrée gagne, côté base. L'autre participant ne voit jamais rien
/// de tout ça.
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

  List<Remplacant>? _remplacants;
  Object? _enCoursPour;
  bool _enCoursAnnulation = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  /// Toujours relu depuis le serveur : des réponses ont pu arriver
  /// pendant que cet écran n'était pas ouvert.
  Future<void> _charger() async {
    try {
      final liste = await PacteRepository.remplacantsDe(widget.pacte.id, _cote);
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
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: _corps(liste),
              ),
            ),
    );
  }

  List<Widget> _corps(List<Remplacant> liste) {
    final valides = liste.where((r) => r.estRempli && r.id != null).toList();
    final accepte = valides.where((r) => r.selectionne).toList();
    if (accepte.isNotEmpty) return _vueAcceptee(accepte.first);

    final encoreSollicitables = valides.where(
      (r) =>
          r.demandeStatut == null || r.demandeStatut == DemandeStatut.envoyee,
    );
    final personneDisponible = encoreSollicitables.isEmpty;

    return [
      Text(
        personneDisponible
            ? (valides.isEmpty
                  ? "Personne n'est encore prévu."
                  : "Aucune des personnes prévues n'est disponible.")
            : 'Qui peut prendre votre place ?',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (personneDisponible) ...[
        const SizedBox(height: 8),
        const Text(
          "Vous pouvez ajouter quelqu'un d'autre : cette personne recevra directement votre demande.",
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
      ],
      const SizedBox(height: 16),
      for (final r in valides) _cartePersonne(r),
      if (_erreur != null) ...[
        const SizedBox(height: 4),
        Text(
          _erreur!,
          style: const TextStyle(color: AppColors.erreur, fontSize: 12.5),
        ),
      ],
      const SizedBox(height: 12),
      if (personneDisponible)
        FilledButton.icon(
          onPressed: _ajouterQuelquun,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text("Ajouter quelqu'un"),
        )
      else
        OutlinedButton.icon(
          onPressed: _ajouterQuelquun,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text("Ajouter quelqu'un"),
        ),
      if (personneDisponible) ...[
        const SizedBox(height: 28),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.erreur),
            onPressed: _enCoursAnnulation ? null : _confirmerAnnulation,
            child: _enCoursAnnulation
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Annuler le Swend'),
          ),
        ),
        const Center(
          child: Text(
            'En dernier recours, si personne ne peut prendre votre place.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.texteAttenue),
          ),
        ),
      ],
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
      if (r.profilId != null) ...[
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => _ouvrirChat(r),
          icon: const Icon(Icons.chat_bubble_outline, size: 16),
          label: Text('Écrire à ${r.prenom}'),
        ),
      ],
    ];
  }

  Widget _cartePersonne(Remplacant r) {
    final enCours = _enCoursPour == r.id;
    final enAttente = r.demandeStatut == DemandeStatut.envoyee;
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
                    if (enAttente) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          if (r.profilId != null)
                            TextButton(
                              style: styleLien,
                              onPressed: () => _ouvrirChat(r),
                              child: Text('Écrire à ${r.prenom}', style: lien),
                            )
                          else
                            TextButton(
                              style: styleLien,
                              onPressed: () => _envoyerMessageUrgence(r),
                              child: const Text('Envoyer le message', style: lien),
                            ),
                          TextButton(
                            style: styleLien.copyWith(
                              foregroundColor: const WidgetStatePropertyAll(
                                AppColors.texteAttenue,
                              ),
                            ),
                            onPressed: enCours ? null : () => _annulerDemande(r),
                            child: const Text('Annuler la demande', style: lien),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (r.demandeStatut == null)
                OutlinedButton(
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
                )
              else if (enAttente)
                _badge('En attente', AppColors.neutre, AppColors.texte)
              else
                _badge('Indisponible', AppColors.neutre, AppColors.texteAttenue),
            ],
          ),
        ),
      ),
    );
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
        content: Text('${r.prenom} pourra accepter ou refuser.'),
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

    final ok = await _action(r.id, () async {
      await PacteRepository.envoyerDemandeRemplacement(r.id!);
      r.demandeStatut = DemandeStatut.envoyee;
    });
    if (ok && r.profilId == null) await _proposerMessageUrgence(r);
  }

  Future<void> _annulerDemande(Remplacant r) async {
    await _action(r.id, () async {
      await PacteRepository.annulerDemandeRemplacement(r.id!);
      r.demandeStatut = null;
    });
  }

  /// Exécute une action serveur ; en cas de refus métier (quelqu'un
  /// vient d'accepter, personne indisponible...), affiche un message
  /// clair et relit l'état réel.
  Future<bool> _action(Object? cle, Future<void> Function() appel) async {
    setState(() {
      _enCoursPour = cle;
      _erreur = null;
    });
    try {
      await appel();
      if (!mounted) return true;
      setState(() => _enCoursPour = null);
      widget.onChanged();
      return true;
    } catch (e) {
      if (!mounted) return false;
      final code = PacteRepository.codeErreurMetier(e);
      setState(() {
        _enCoursPour = null;
        _erreur = _messageErreur(code);
      });
      if (code != null) await _charger();
      return false;
    }
  }

  String _messageErreur(String? code) => switch (code) {
    'place_deja_prise' => "Quelqu'un vient d'accepter de prendre votre place.",
    'personne_indisponible' => "Cette personne n'est pas disponible pour ce Swend.",
    'deja_acceptee' => 'Cette personne a déjà accepté : le remplacement est définitif.',
    'demande_non_active' => "Cette demande n'est plus en attente.",
    'swend_inactif' => "Ce Swend n'est plus actif.",
    'champs_manquants' => 'Renseignez le prénom, le nom et le téléphone.',
    'telephone_invalide' => messageTelephoneInvalide,
    'personne_est_participant' =>
      'Cette personne participe déjà à ce Swend : elle ne peut pas prendre votre place.',
    'personne_deja_prevue' => 'Cette personne est déjà dans votre liste.',
    _ => 'Impossible pour le moment. Réessayez.',
  };

  Future<void> _ajouterQuelquun() async {
    final saisie = await showModalBottomSheet<_NouvellePersonne>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => const _FormulaireAjout(),
    );
    if (saisie == null || !mounted) return;

    String? nouvelId;
    final ok = await _action('ajout', () async {
      nouvelId = await PacteRepository.ajouterEtDemanderRemplacement(
        pacteId: widget.pacte.id,
        cote: _cote,
        prenom: saisie.prenom,
        nom: saisie.nom,
        telephone: saisie.telephone,
      );
    });
    if (!ok || !mounted) return;
    await _charger();
    final ajoutee = _remplacants?.where((r) => r.id == nouvelId).firstOrNull;
    if (ajoutee != null && ajoutee.profilId == null) {
      await _proposerMessageUrgence(ajoutee);
    }
  }

  /// La personne n'a pas encore Swend : elle ne recevra aucune
  /// notification, on propose donc le message d'urgence explicite.
  Future<void> _proposerMessageUrgence(Remplacant r) async {
    final envoyer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demande envoyée'),
        content: Text(
          "${r.prenom} n'a pas encore Swend : envoyez-lui un message pour lui expliquer "
          'et lui permettre de répondre depuis l\'app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer le message'),
          ),
        ],
      ),
    );
    if (envoyer == true && mounted) await _envoyerMessageUrgence(r);
  }

  Future<void> _envoyerMessageUrgence(Remplacant r) => envoyerInvitation(
    context,
    telephone: r.telephone,
    message: messageUrgence(widget.pacte, r, _autreCote),
    titre: 'Envoyer la demande',
  );

  Future<void> _confirmerAnnulation() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler ce Swend ?'),
        content: const Text(
          'Personne ne peut prendre votre place. Cette action est définitive.',
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
        _erreur = "Impossible d'annuler le Swend pour le moment. Réessayez.";
      });
    }
  }
}

/// Le SMS envoyé à quelqu'un qui n'a pas encore Swend, quand on lui
/// demande réellement de prendre sa place.
String messageUrgence(Pacte pacte, Remplacant r, CotePacte autreCote) {
  final repas = pacte.type == TypeRepas.dejeuner ? 'un déjeuner' : 'un dîner';
  final date = pacte.dateRetenue;
  final quand = date == null
      ? ''
      : ' le ${date.day} ${moisAnnee[date.month - 1]} à ${formaterHeure(heureDe(date))}';
  final autre = prenomDe(autreCote.nomTitulaire);
  final restaurant = pacte.restaurantRetenu?.nom;
  final ou = restaurant == null ? '' : ', au restaurant $restaurant';
  return "Hello ${r.prenom}, j'ai $repas prévu$quand avec $autre$ou, mais j'ai un imprévu. "
      "Est-ce que tu pourrais prendre ma place ?\n"
      "C'est le principe de Swend : $autre ne saura pas que c'est toi qui me remplaces. "
      "Tu peux accepter ou refuser directement sur l'app.\n"
      "$lienTelechargementApp";
}

class _NouvellePersonne {
  final String prenom;
  final String nom;
  final String telephone;
  const _NouvellePersonne(this.prenom, this.nom, this.telephone);
}

/// Prénom, nom, téléphone — la validation envoie à la fois l'ajout et la
/// demande de remplacement.
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
            "Ajouter quelqu'un",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Cette personne recevra directement votre demande de prendre votre place.',
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
            child: const Text('Lui demander de prendre ma place'),
          ),
        ],
      ),
    );
  }
}
