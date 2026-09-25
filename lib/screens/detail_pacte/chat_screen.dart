import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/cote_pacte.dart';
import '../../models/demande_statut.dart';
import '../../models/message.dart';
import '../../models/pacte.dart';
import '../../models/perspective_pacte.dart';
import '../../models/remplacant.dart';
import '../../models/statut_pacte.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../../utils/noms.dart';
import '../../utils/telephone.dart';
import 'detail_pacte_screen.dart';

/// Fil de discussion privé entre le titulaire et l'un de ses
/// remplaçants (ou l'inverse, vu du remplaçant). Se met à jour en
/// direct pendant que l'écran est ouvert.
class ChatScreen extends StatefulWidget {
  final String remplacantId;
  final String nomInterlocuteur;

  /// Connu d'avance côté titulaire (déjà dans son formulaire de
  /// remplaçants) — laissé à null côté remplaçant, qui n'a pas le
  /// droit de le lire directement : il sera alors récupéré via une
  /// fonction serveur dédiée.
  final String? telephoneInterlocuteur;

  /// Ouvert depuis la fiche du Swend elle-même : pas besoin d'y renvoyer.
  final bool depuisFiche;

  const ChatScreen({
    super.key,
    required this.remplacantId,
    required this.nomInterlocuteur,
    this.telephoneInterlocuteur,
    this.depuisFiche = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final Stream<List<Message>> _messages;
  bool enCours = false;
  String? _telephone;

  /// Ma propre fiche dans ce fil si j'y suis la personne de confiance
  /// (jamais côté titulaire), et le Swend concerné — de quoi afficher le
  /// contexte d'une éventuelle demande "Un imprévu ?" et y répondre.
  Remplacant? _maFiche;
  Pacte? _pacte;
  CotePacte? _coteTitulaire;
  CotePacte? _coteAutre;
  bool _enCoursReponse = false;

  String get _monId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _messages = PacteRepository.abonnementMessages(widget.remplacantId);
    _telephone = widget.telephoneInterlocuteur;
    if (_telephone == null) {
      _chargerTelephone();
    }
    _chargerDemande();
  }

  Future<void> _chargerTelephone() async {
    final tel = await PacteRepository.telephoneTitulaireDuPacte(
      widget.remplacantId,
    );
    if (!mounted || tel == null) return;
    setState(() => _telephone = tel);
  }

  Future<void> _chargerDemande() async {
    try {
      final fiche = await PacteRepository.remplacantParId(widget.remplacantId);
      if (fiche == null || fiche.profilId != _monId) return;
      final pacte = await PacteRepository.pacteDuRemplacant(widget.remplacantId);
      if (!mounted || pacte == null) return;
      final coteInitiateur = pacte.initiateur.listeRemplacants.any(
        (r) => r.id == fiche.id,
      );
      setState(() {
        _maFiche = fiche;
        _pacte = pacte;
        _coteTitulaire = coteInitiateur ? pacte.initiateur : pacte.destinataire;
        _coteAutre = coteInitiateur ? pacte.destinataire : pacte.initiateur;
      });
    } catch (_) {
      // Pas de bandeau si on ne peut pas charger le contexte.
    }
  }

  Future<void> _appeler() async {
    final tel = _telephone?.trim();
    if (tel == null || tel.isEmpty) return;
    final numero = normaliserTelephone(tel) ?? tel.replaceAll(RegExp(r'\s+'), '');
    await launchUrl(Uri.parse('tel:$numero'));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Toujours faire apparaître le dernier message reçu ou envoyé, sans
  /// dépendre de l'ordre exact renvoyé par le flux temps réel — les
  /// messages sont de toute façon triés explicitement avant affichage.
  void _defilerVersLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final telephone = _telephone?.trim();
    final bandeau = _bandeauImprevu();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nomInterlocuteur),
        actions: [
          if (telephone != null && telephone.isNotEmpty)
            IconButton(
              onPressed: _appeler,
              icon: const Icon(Icons.call_outlined),
              tooltip: 'Appeler',
            ),
        ],
      ),
      body: Column(
        children: [
          ?bandeau,
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _messages,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = List<Message>.of(snapshot.data!)
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        "Aucun message pour l'instant. Dis bonjour :)",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  );
                }
                _defilerVersLeBas();
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _bulle(messages[i]),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Écrire un message…',
                      ),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _envoyer(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: enCours ? null : _envoyer,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulle(Message m) {
    final estMoi = m.expediteurId == _monId;
    return Align(
      alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: estMoi ? AppColors.accentClair : AppColors.neutre,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(m.contenu),
      ),
    );
  }

  /// Le bandeau lié à ce Swend, du point de vue de la personne de
  /// confiance — null côté titulaire. Accepter/Refuser n'existent qu'ici.
  Widget? _bandeauImprevu() {
    final fiche = _maFiche;
    final pacte = _pacte;
    if (fiche == null || pacte == null) return null;
    final titulaire = prenomDe(_coteTitulaire!.nomTitulaire);
    final autre = prenomDe(_coteAutre!.nomTitulaire);

    if (pacte.statut == StatutPacte.annule ||
        pacte.statut == StatutPacte.annuleDoubleAbsence) {
      return _bandeauLeger('Ce Swend a été annulé.');
    }
    if (pacte.statut != StatutPacte.confirme) {
      return _bandeauLeger(
        "$titulaire pourra faire appel à toi en cas d'imprévu, une fois la date fixée.",
      );
    }
    if (fiche.selectionne) {
      return _bandeauLeger(
        'Tu prends la place ${deNom(titulaire)} pour ce Swend.',
        couleur: AppColors.accentClair,
      );
    }

    switch (fiche.demandeStatut) {
      case DemandeStatut.envoyee:
        return _bandeau(
          couleur: AppColors.pecheClair,
          enfants: [
            Text(
              '$titulaire a un imprévu',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              '$titulaire te demande de prendre sa place pour ce Swend.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (pacte.dateRetenue != null)
              Text(
                formaterJourEtHeureCourt(pacte.dateRetenue!),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            if (pacte.restaurantRetenu != null)
              Text(
                pacte.restaurantRetenu!.nom,
                style: const TextStyle(fontSize: 13),
              ),
            Text('Avec $autre', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.visibility_off_outlined,
                  size: 15,
                  color: AppColors.accentFonce,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$autre ne saura pas que tu prends la place ${deNom(titulaire)}.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.accentFonce,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: _enCoursReponse ? null : () => _repondre(false),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: _enCoursReponse ? null : () => _repondre(true),
                    child: _enCoursReponse
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Accepter'),
                  ),
                ),
              ],
            ),
          ],
        );
      case null:
        return _bandeauLeger("$titulaire peut faire appel à toi en cas d'imprévu.");
      case DemandeStatut.refusee:
        return _bandeauLeger('Tu as indiqué ne pas être disponible.');
      case DemandeStatut.cloturee:
        return _bandeauLeger(
          PerspectivePacte.prendUnePlaceAilleurs(pacte, _monId, fiche.id!)
              ? 'Tu prends déjà une place pour ce Swend : cette demande n\'est plus active.'
              : "C'est bon, quelqu'un a pu prendre la place.",
        );
      case DemandeStatut.desistee:
      case DemandeStatut.acceptee:
        return _bandeauLeger('Tu ne prends plus la place ${deNom(titulaire)}.');
    }
  }

  /// Rappel d'une ligne, avec un lien vers la fiche du Swend.
  Widget _bandeauLeger(String texte, {Color couleur = AppColors.neutre}) {
    return _bandeau(
      couleur: couleur,
      enfants: [
        Row(
          children: [
            Expanded(
              child: Text(texte, style: const TextStyle(fontSize: 12.5)),
            ),
            if (!widget.depuisFiche && _pacte != null)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(left: 8),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _voirLeSwend,
                child: const Text('Voir le Swend', style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bandeau({required Color couleur, required List<Widget> enfants}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: couleur,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: enfants,
      ),
    );
  }

  Future<void> _voirLeSwend() async {
    final pacte = _pacte;
    if (pacte == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailPacteScreen(pacte: pacte)),
    );
    await _chargerDemande();
  }

  Future<void> _repondre(bool accepte) async {
    final fiche = _maFiche;
    if (fiche == null) return;
    if (accepte) {
      final titulaire = prenomDe(_coteTitulaire!.nomTitulaire);
      final confirme = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Prendre la place ${deNom(titulaire)} ?'),
          content: Text(
            "$titulaire comptera sur toi. Si finalement tu ne peux plus venir, "
            "tu pourras te désister depuis la fiche du Swend.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Retour'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accepter'),
            ),
          ],
        ),
      );
      if (confirme != true || !mounted) return;
    }

    setState(() => _enCoursReponse = true);
    String message;
    try {
      await PacteRepository.repondreDemandeRemplacement(
        widget.remplacantId,
        accepte,
      );
      message = accepte ? "C'est noté : tu prends la place." : 'Réponse envoyée.';
    } catch (e) {
      message = switch (PacteRepository.codeErreurMetier(e)) {
        'place_deja_prise' => "La place vient d'être prise.",
        'deja_remplacant_autre_cote' =>
          "Tu prends déjà la place de l'autre participant de ce Swend.",
        'demande_non_active' => "Cette demande n'est plus active.",
        'swend_inactif' => "Ce Swend n'est plus actif.",
        _ => 'Impossible de répondre pour le moment. Réessaie.',
      };
    }
    await _chargerDemande();
    if (!mounted) return;
    setState(() => _enCoursReponse = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _envoyer() async {
    final texte = _controller.text.trim();
    if (texte.isEmpty) return;
    setState(() => enCours = true);
    try {
      await PacteRepository.envoyerMessage(widget.remplacantId, texte);
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Message non envoyé, réessaie.")),
        );
      }
    } finally {
      if (mounted) setState(() => enCours = false);
    }
  }
}
