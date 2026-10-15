import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_apres_swend.dart';

/// Accès au chat après le Swend (D-023b). La base décide de tout : qui
/// participe, quand le chat s'ouvre, ce que chacun peut lire. L'app lit
/// (RLS) et écrit uniquement par des fonctions serveur.
class ChatApresSwendRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Base sans D-027-02 : `mes_chats_swend()` n'existe pas (on ne la
  /// redemande pas pendant la session).
  static bool _sansChatsAnnulation = false;

  /// Mes chats ouverts (les plus récents d'abord) : participants, non-lus,
  /// dernier expéditeur — jamais le contenu d'un message. Chats après le
  /// Swend et chats d'annulation (`mes_chats_swend()`, D-027 lot 2) ; sur
  /// une base qui ne la connaît pas encore, repli sur
  /// `mes_chats_apres_swend()` (chats après le Swend seulement).
  static Future<List<ChatApresSwend>> mesChats() async {
    List<dynamic> rows;
    if (_sansChatsAnnulation) {
      rows = await _client.rpc('mes_chats_apres_swend') as List<dynamic>;
    } else {
      try {
        rows = await _client.rpc('mes_chats_swend') as List<dynamic>;
      } on PostgrestException catch (e) {
        if (!fonctionAbsente(e)) rethrow;
        _sansChatsAnnulation = true;
        rows = await _client.rpc('mes_chats_apres_swend') as List<dynamic>;
      }
    }
    return [
      for (final r in rows) ChatApresSwend.depuis(r as Map<String, dynamic>),
    ];
  }

  /// PostgREST : fonction inconnue de la base (PGRST202).
  static bool fonctionAbsente(PostgrestException e) =>
      e.code == 'PGRST202' || e.message.contains('Could not find the function');

  /// Le chat de ce Swend, s'il est ouvert et que j'y participe.
  static Future<ChatApresSwend?> chatDuPacte(String pacteId) async =>
      (await mesChats()).where((c) => c.pacteId == pacteId).firstOrNull;

  /// Ce chat, s'il est ouvert et que j'y participe (sinon null).
  static Future<ChatApresSwend?> chatParId(String chatId) async =>
      (await mesChats()).where((c) => c.id == chatId).firstOrNull;

  /// Les messages du chat, du plus ancien au plus récent, en direct.
  static Stream<List<MessageApresSwend>> abonnementMessages(String chatId) =>
      _client
          .from('messages_apres_swend')
          .stream(primaryKey: ['id'])
          .eq('chat_id', chatId)
          .order('created_at', ascending: true)
          .map(
            (rows) =>
                rows.map(MessageApresSwend.depuis).toList()
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
          );

  static Future<void> envoyer(String chatId, String texte) async {
    await _client.rpc(
      'envoyer_message_apres_swend',
      params: {'p_chat_id': chatId, 'p_contenu': texte},
    );
  }

  /// Marque le chat comme lu par moi seulement.
  static Future<void> marquerLu(String chatId) async {
    await _client.rpc(
      'marquer_chat_apres_swend_lu',
      params: {'p_chat_id': chatId},
    );
  }

  /// « Faire un nouveau Swend » (D-023c) : les autres participants de ce
  /// chat ouvert, et si un Swend est déjà en cours avec chacun.
  static Future<List<OptionNouveauSwend>> optionsNouveauSwend(
    String chatId,
  ) async {
    final rows =
        await _client.rpc(
              'options_nouveau_swend',
              params: {'p_chat_id': chatId},
            )
            as List<dynamic>;
    return [
      for (final r in rows)
        OptionNouveauSwend.depuis(r as Map<String, dynamic>),
    ];
  }

  /// Code métier d'un refus de la base, ou null (erreur technique).
  static String? codeErreur(Object erreur) {
    if (erreur is! PostgrestException) return null;
    for (final code in const [
      'message_vide',
      'message_trop_long',
      'chat_ferme',
      'non_autorise',
    ]) {
      if (erreur.message.contains(code)) return code;
    }
    return null;
  }
}
