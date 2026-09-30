import 'package:flutter/material.dart';

import '../../models/chat_apres_swend.dart';
import '../../models/pacte.dart';
import '../../services/chat_apres_swend_repository.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';

/// Le chat après le Swend (D-023b) : entre les deux titulaires et, s'il
/// existe, le remplaçant — ouvert par la base après un Swend qui a eu lieu.
/// Plus d'imprévu ici : écran léger et aéré, texte et emoji seulement, ni
/// « Vu », ni « en train d'écrire », ni badge « remplaçant ». Si le chat
/// n'est plus accessible (ancienne notification), un message simple.
class ChatApresSwendScreen extends StatefulWidget {
  final String chatId;
  const ChatApresSwendScreen({super.key, required this.chatId});

  @override
  State<ChatApresSwendScreen> createState() => _ChatApresSwendScreenState();
}

class _ChatApresSwendScreenState extends State<ChatApresSwendScreen> {
  static const _fond = Color(0xFFFFF7EE);
  static const _limite = 2000;

  ChatApresSwend? _chat;
  Pacte? _pacte;
  bool _charge = false;
  Stream<List<MessageApresSwend>>? _messages;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _enCours = false;
  DateTime? _luJusqua;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    ChatApresSwend? chat;
    Pacte? pacte;
    try {
      chat = await ChatApresSwendRepository.chatParId(widget.chatId);
      if (chat != null) pacte = await PacteRepository.pacteParId(chat.pacteId);
    } catch (_) {
      chat = null;
    }
    if (!mounted) return;
    setState(() {
      _chat = chat;
      _pacte = pacte;
      _charge = true;
      if (chat != null) {
        _messages = ChatApresSwendRepository.abonnementMessages(chat.id);
      }
    });
    if (chat != null) {
      ChatApresSwendRepository.marquerLu(chat.id).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Un message reçu pendant que le chat est ouvert : il reste lu.
  void _marquerLuSiNouveau(List<MessageApresSwend> messages) {
    final chat = _chat;
    if (chat == null || messages.isEmpty) return;
    final dernier = messages.last.createdAt;
    final lu = _luJusqua;
    if (lu != null && !dernier.isAfter(lu)) return;
    _luJusqua = dernier;
    ChatApresSwendRepository.marquerLu(chat.id).catchError((_) {});
  }

  void _defilerVersLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _envoyer() async {
    final chat = _chat;
    final texte = _controller.text.trim();
    if (chat == null || texte.isEmpty || _enCours) return;
    setState(() => _enCours = true);
    try {
      await ChatApresSwendRepository.envoyer(chat.id, texte);
      _controller.clear();
    } catch (e) {
      final code = ChatApresSwendRepository.codeErreur(e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageErreurEnvoi(code))));
      }
      if (code == 'chat_ferme' || code == 'non_autorise') await _charger();
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final restaurant = _pacte?.restaurantRetenu?.nom;
    final date = _pacte?.dateRetenue;
    return Scaffold(
      backgroundColor: _fond,
      appBar: AppBar(
        backgroundColor: _fond,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titreSwendAuRestaurant(restaurant),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const Text(
              'Après le Swend',
              style: TextStyle(fontSize: 12, color: AppColors.texteAttenue),
            ),
          ],
        ),
        bottom: chat == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(34),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.enteteParticipants,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentFonce,
                          ),
                        ),
                      ),
                      if (date != null)
                        Text(
                          '${date.toLocal().day} ${moisAnnee[date.toLocal().month - 1]}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.texteAttenue,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      body: !_charge
          ? const Center(child: CircularProgressIndicator())
          : chat == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Cette conversation n'est plus accessible.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(child: _liste(chat)),
                if (chat.ferme) _bandeauFerme(chat) else _saisie(),
              ],
            ),
    );
  }

  Widget _liste(ChatApresSwend chat) {
    return StreamBuilder<List<MessageApresSwend>>(
      stream: _messages,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data!;
        _marquerLuSiNouveau(messages);
        if (messages.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                texteChatVide,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.texteAttenue,
                ),
              ),
            ),
          );
        }
        _defilerVersLeBas();
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          itemCount: messages.length,
          itemBuilder: (context, i) => _message(chat, messages[i]),
        );
      },
    );
  }

  Widget _message(ChatApresSwend chat, MessageApresSwend m) {
    if (m.systeme) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          child: Text(
            m.contenu,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: AppColors.texteAttenue,
            ),
          ),
        ),
      );
    }
    final estMoi =
        m.participantId != null &&
        chat.participant(m.participantId!)?.estMoi == true;
    final auteur = auteurAffiche(chat, m);
    return Align(
      alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: estMoi
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (auteur != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, bottom: 2),
              child: Text(
                auteur,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.texteAttenue,
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: estMoi ? AppColors.pecheClair : Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(m.contenu, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _bandeauFerme(ChatApresSwend chat) => SafeArea(
    top: false,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      color: AppColors.neutre,
      child: Text(
        chat.motifFermeture == 'nouveau_swend'
            ? texteChatFermeNouveauSwend
            : 'Cette conversation est terminée.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: AppColors.texteAttenue),
      ),
    ),
  );

  Widget _saisie() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLength: _limite,
              decoration: const InputDecoration(
                hintText: 'Écrire un message…',
                counterText: '',
              ),
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _envoyer(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _enCours ? null : _envoyer,
            icon: const Icon(Icons.send, color: AppColors.accentFonce),
            tooltip: 'Envoyer',
          ),
        ],
      ),
    ),
  );
}
