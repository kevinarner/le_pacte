import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/message.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';

/// Fil de discussion privé entre le titulaire et l'un de ses
/// remplaçants (ou l'inverse, vu du remplaçant). Se met à jour en
/// direct pendant que l'écran est ouvert.
class ChatScreen extends StatefulWidget {
  final String remplacantId;
  final String nomInterlocuteur;

  const ChatScreen({super.key, required this.remplacantId, required this.nomInterlocuteur});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final Stream<List<Message>> _messages;
  bool enCours = false;

  String get _monId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _messages = PacteRepository.abonnementMessages(widget.remplacantId);
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.nomInterlocuteur)),
      body: Column(
        children: [
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
                      decoration: const InputDecoration(hintText: 'Écrire un message…'),
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: estMoi ? AppColors.terracottaClair : AppColors.neutre,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(m.contenu),
      ),
    );
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
