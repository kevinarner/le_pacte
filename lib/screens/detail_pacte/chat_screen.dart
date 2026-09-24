import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/demande_statut.dart';
import '../../models/message.dart';
import '../../models/pacte.dart';
import '../../models/remplacant.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';

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

  const ChatScreen({
    super.key,
    required this.remplacantId,
    required this.nomInterlocuteur,
    this.telephoneInterlocuteur,
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

  /// Ma propre fiche remplaçant dans ce fil, si j'en suis moi-même le
  /// destinataire (pour savoir si une demande "Un imprévu ?" m'attend).
  /// Reste null tant qu'elle n'a pas fini de charger, ou si je suis le
  /// titulaire de ce côté (pas concerné).
  Remplacant? _maFiche;
  bool _enCoursReponse = false;
  Pacte? _pacteAccepte;

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

  /// Vérifie si une demande "Un imprévu ?" me concerne dans ce fil — je
  /// ne suis le destinataire d'une telle demande que si c'est bien ma
  /// fiche remplaçant (`profil_id = moi`), jamais côté titulaire.
  Future<void> _chargerDemande() async {
    final fiche = await PacteRepository.remplacantParId(widget.remplacantId);
    if (!mounted || fiche == null || fiche.profilId != _monId) return;
    setState(() => _maFiche = fiche);
    if (fiche.selectionne) _chargerPacteAccepte();
  }

  Future<void> _chargerPacteAccepte() async {
    final pacte = await PacteRepository.pacteDuRemplacant(widget.remplacantId);
    if (!mounted) return;
    setState(() => _pacteAccepte = pacte);
  }

  Future<void> _appeler() async {
    final tel = _telephone?.trim();
    if (tel == null || tel.isEmpty) return;
    await launchUrl(Uri.parse('tel:${tel.replaceAll(RegExp(r'\s+'), '')}'));
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

  /// Le bandeau lié à une demande "Un imprévu ?" éventuellement en jeu
  /// dans ce fil, du point de vue de la personne sollicitée — null s'il
  /// n'y a rien à montrer (je suis le titulaire, ou aucune demande).
  Widget? _bandeauImprevu() {
    final fiche = _maFiche;
    if (fiche == null) return null;

    if (fiche.selectionne) {
      final pacte = _pacteAccepte;
      return _bandeau(
        couleur: AppColors.accentClair,
        enfants: [
          const Text(
            'Tu prends la place pour ce Swend.',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          const Text(
            'Il reste scellé.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          if (pacte?.dateRetenue != null) ...[
            const SizedBox(height: 6),
            Text(
              formaterDateEtHeure(pacte!.dateRetenue!),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (pacte?.restaurantRetenu != null)
            Text(
              pacte!.restaurantRetenu!.nom,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
        ],
      );
    }

    if (fiche.demandeStatut == DemandeStatut.envoyee) {
      return _bandeau(
        couleur: AppColors.pecheClair,
        enfants: [
          const Text(
            'On te demande de prendre la place pour ce Swend.',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _enCoursReponse ? null : () => _repondre(false),
                  child: const Text('Refuser'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
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
    }

    if (fiche.demandeStatut == DemandeStatut.cloturee) {
      return _bandeau(
        couleur: AppColors.neutre,
        enfants: const [
          Text(
            "C'est bon, quelqu'un a pu prendre la place.",
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ],
      );
    }

    return null;
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

  Future<void> _repondre(bool accepte) async {
    final fiche = _maFiche;
    if (fiche == null) return;
    setState(() => _enCoursReponse = true);
    try {
      await PacteRepository.repondreDemandeRemplacement(
        widget.remplacantId,
        accepte,
      );
      if (!mounted) return;
      setState(() {
        fiche.demandeStatut = accepte
            ? DemandeStatut.acceptee
            : DemandeStatut.refusee;
        fiche.selectionne = accepte;
        _enCoursReponse = false;
      });
      if (accepte) {
        _chargerPacteAccepte();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Réponse envoyée.')));
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final placeDejaPrise = e.message.contains('place_deja_prise');
      setState(() {
        _enCoursReponse = false;
        if (placeDejaPrise) fiche.demandeStatut = DemandeStatut.cloturee;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            placeDejaPrise
                ? 'La place vient déjà d\'être prise.'
                : 'Impossible de répondre pour le moment. Réessaie.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _enCoursReponse = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de répondre pour le moment. Réessaie.'),
        ),
      );
    }
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
