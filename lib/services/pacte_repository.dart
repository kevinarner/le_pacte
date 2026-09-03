import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cote_pacte.dart';
import '../models/fil_de_discussion.dart';
import '../models/message.dart';
import '../models/pacte.dart';
import '../models/remplacant.dart';
import '../models/restaurant.dart';
import '../models/statut_pacte.dart';
import '../models/statut_presence.dart';
import '../models/type_repas.dart';

/// Accès aux pactes, remplaçants et au restaurant stockés dans Supabase.
/// Les colonnes de suivi interne (historique des remplaçants) ne sont
/// jamais lues ni écrites ici — elles vivent uniquement côté serveur,
/// remplies automatiquement par un déclencheur.
class PacteRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  static const _colonnesPacte = 'id, type, statut, dates_proposees, date_retenue, '
      'nombre_echanges_date, restaurant_id, initiateur_id, initiateur_nom, '
      'destinataire_id, destinataire_nom, destinataire_telephone, created_at';

  static Restaurant? _restaurantCache;

  /// Le seul restaurant proposé aujourd'hui. Chargé une fois et mis en
  /// cache pour le reste de la session.
  static Future<Restaurant> restaurant() async {
    final cache = _restaurantCache;
    if (cache != null) return cache;
    final row = await _client.from('restaurants').select().limit(1).single();
    final restau = _restaurantDe(row);
    _restaurantCache = restau;
    return restau;
  }

  static Restaurant _restaurantDe(Map<String, dynamic> row) {
    return Restaurant(
      id: row['id'] as String,
      nom: row['nom'] as String,
      lien: row['lien'] as String? ?? '',
      creneauxDejeuner: _creneauxDe(row['creneaux_dejeuner']),
      creneauxDiner: _creneauxDe(row['creneaux_diner']),
    );
  }

  static List<TimeOfDay> _creneauxDe(dynamic valeur) {
    if (valeur == null) return [];
    return (valeur as List).map((s) {
      final parts = (s as String).split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }).toList();
  }

  /// Retrouve l'id du profil correspondant à un numéro de téléphone, ou
  /// null si personne n'a encore de compte avec ce numéro. Passe par une
  /// fonction serveur dédiée : impossible de parcourir les profils des
  /// autres directement.
  static Future<String?> trouverProfilParTelephone(String telephone) async {
    if (telephone.trim().isEmpty) return null;
    final result = await _client.rpc<String?>(
      'trouver_profil_par_telephone',
      params: {'p_telephone': telephone.trim()},
    );
    return result;
  }

  /// Le téléphone du titulaire d'un pacte, du point de vue de son
  /// remplaçant (pour pouvoir l'appeler) — ne renvoie quelque chose que
  /// si l'appelant est bien ce remplaçant, jamais pour un tiers.
  static Future<String?> telephoneTitulaireDuPacte(String remplacantId) async {
    final result = await _client.rpc<String?>(
      'telephone_titulaire_du_pacte',
      params: {'p_remplacant_id': remplacantId},
    );
    return result;
  }

  /// Les pactes où je suis impliqué (initiateur ou destinataire), du
  /// plus récent au plus ancien. La sécurité côté base ne renvoie de
  /// toute façon que ceux-là.
  static Future<List<Pacte>> mesPactes() async {
    final rows = await _client
        .from('pactes')
        .select(_colonnesPacte)
        .order('created_at', ascending: false);
    final restau = await restaurant();
    final pactes = <Pacte>[];
    for (final row in rows as List) {
      pactes.add(await _pacteDe(row as Map<String, dynamic>, restau));
    }
    return pactes;
  }

  /// Un pacte précis par son id — utilisé pour ouvrir directement le
  /// bon pacte au clic sur une notification.
  static Future<Pacte?> pacteParId(String id) async {
    final rows = await _client.from('pactes').select(_colonnesPacte).eq('id', id).limit(1);
    if (rows.isEmpty) return null;
    final restau = await restaurant();
    return _pacteDe(rows.first, restau);
  }

  static Future<Pacte> _pacteDe(Map<String, dynamic> row, Restaurant restau) async {
    final id = row['id'] as String;
    final statut = StatutPacte.values.byName(row['statut'] as String);
    final remplacantsInitiateur = await remplacantsDe(id, 'initiateur');
    final remplacantsDestinataire = await remplacantsDe(id, 'destinataire');
    final confirmeOuPlus = statut == StatutPacte.confirme || statut == StatutPacte.maintenu;

    final pacte = Pacte(
      id: id,
      type: TypeRepas.values.byName(row['type'] as String),
      datesProposees:
          (row['dates_proposees'] as List).map((s) => DateTime.parse(s as String)).toList(),
      dateRetenue:
          row['date_retenue'] != null ? DateTime.parse(row['date_retenue'] as String) : null,
      nombreEchangesDate: row['nombre_echanges_date'] as int,
      restaurantsProposes: [restau],
      statut: statut,
      initiateur: CotePacte(
        idTitulaire: row['initiateur_id'] as String,
        nomTitulaire: row['initiateur_nom'] as String,
        listeRemplacants: remplacantsInitiateur,
        statutPresence: _presenceDe(remplacantsInitiateur),
      ),
      destinataire: CotePacte(
        idTitulaire: row['destinataire_id'] as String? ?? '',
        nomTitulaire: row['destinataire_nom'] as String,
        listeRemplacants: remplacantsDestinataire,
        statutPresence: _presenceDe(remplacantsDestinataire),
      ),
    );
    if (confirmeOuPlus) pacte.restaurantRetenu = restau;
    return pacte;
  }

  static StatutPresence _presenceDe(List<Remplacant> remplacants) {
    return remplacants.any((r) => r.selectionne)
        ? StatutPresence.remplacantSollicite
        : StatutPresence.titulaire;
  }

  /// Les remplaçants d'un côté d'un pacte. La sécurité côté base ne
  /// renvoie que ceux du côté auquel j'appartiens.
  static Future<List<Remplacant>> remplacantsDe(String pacteId, String cote) async {
    final rows = await _client
        .from('remplacants')
        .select()
        .eq('pacte_id', pacteId)
        .eq('cote', cote)
        .order('id');
    return (rows as List)
        .map((row) => _remplacantDe(row as Map<String, dynamic>))
        .toList();
  }

  static Remplacant _remplacantDe(Map<String, dynamic> row) => Remplacant(
        id: row['id'] as String,
        prenom: row['prenom'] as String? ?? '',
        nom: row['nom'] as String? ?? '',
        telephone: row['telephone'] as String? ?? '',
        email: row['email'] as String? ?? '',
        selectionne: row['selectionne'] as bool? ?? false,
        profilId: row['profil_id'] as String?,
      );

  /// Crée un nouveau pacte avec les remplaçants de l'initiateur.
  static Future<Pacte> creerPacte({
    required TypeRepas type,
    required List<DateTime> datesProposees,
    required String initiateurId,
    required String initiateurNom,
    required String destinataireNom,
    required String destinataireTelephone,
    required List<Remplacant> remplacantsInitiateur,
  }) async {
    final restau = await restaurant();
    final destinataireId = await trouverProfilParTelephone(destinataireTelephone);

    final row = await _client
        .from('pactes')
        .insert({
          'type': type.name,
          'statut': StatutPacte.enAttenteChoixDateDestinataire.name,
          'dates_proposees': datesProposees.map((d) => d.toIso8601String()).toList(),
          'restaurant_id': restau.id,
          'initiateur_id': initiateurId,
          'initiateur_nom': initiateurNom,
          if (destinataireId != null) 'destinataire_id': destinataireId,
          'destinataire_nom': destinataireNom,
          'destinataire_telephone': destinataireTelephone,
        })
        .select(_colonnesPacte)
        .single();

    final pacteId = row['id'] as String;
    for (final r in remplacantsInitiateur.where((r) => r.estRempli)) {
      await _insererRemplacant(pacteId, 'initiateur', r);
    }

    return _pacteDe(row, restau);
  }

  static Future<Remplacant> _insererRemplacant(
      String pacteId, String cote, Remplacant r) async {
    // Si cette personne a déjà un compte, on la relie tout de suite —
    // sinon, c'est handle_new_user() qui fera le lien plus tard, à son
    // inscription.
    final profilId = await trouverProfilParTelephone(r.telephone);
    final row = await _client
        .from('remplacants')
        .insert({
          'pacte_id': pacteId,
          'cote': cote,
          'prenom': r.prenom,
          'nom': r.nom,
          'telephone': r.telephone,
          'email': r.email,
          if (profilId != null) 'profil_id': profilId,
        })
        .select()
        .single();
    r.id = row['id'] as String;
    r.profilId = row['profil_id'] as String?;
    return r;
  }

  /// Enregistre les remplaçants sans id (nouveaux) d'un côté d'un pacte
  /// déjà existant — utilisé lors d'une délégation après confirmation.
  static Future<void> synchroniserRemplacants(
      String pacteId, String cote, List<Remplacant> remplacants) async {
    for (final r in remplacants.where((r) => r.estRempli && r.id == null)) {
      await _insererRemplacant(pacteId, cote, r);
    }
  }

  /// Marque ce remplaçant comme celui délégué pour son côté du pacte.
  static Future<void> selectionnerRemplacant(String remplacantId) async {
    await _client.from('remplacants').update({'selectionne': true}).eq('id', remplacantId);
  }

  /// Relit uniquement le statut actuel d'un pacte — utilisé après une
  /// délégation pour savoir si le déclencheur côté base vient
  /// d'annuler le pacte (l'autre côté avait déjà délégué).
  static Future<StatutPacte> statutActuel(String pacteId) async {
    final row = await _client.from('pactes').select('statut').eq('id', pacteId).single();
    return StatutPacte.values.byName(row['statut'] as String);
  }

  static Future<void> choisirDate(String pacteId, DateTime date) async {
    await _client.from('pactes').update({
      'date_retenue': date.toIso8601String(),
      'statut': StatutPacte.enAttenteReponse.name,
    }).eq('id', pacteId);
  }

  static Future<void> contreProposerDates(
    String pacteId,
    List<DateTime> dates,
    int nombreEchangesDate,
    bool jeSuisInitiateur,
  ) async {
    await _client.from('pactes').update({
      'dates_proposees': dates.map((d) => d.toIso8601String()).toList(),
      'nombre_echanges_date': nombreEchangesDate,
      'statut': (jeSuisInitiateur
              ? StatutPacte.enAttenteChoixDateDestinataire
              : StatutPacte.enAttenteChoixDateInitiateur)
          .name,
    }).eq('id', pacteId);
  }

  static Future<void> mettreAJourStatut(String pacteId, StatutPacte statut) async {
    await _client.from('pactes').update({'statut': statut.name}).eq('id', pacteId);
  }

  static Message _messageDe(Map<String, dynamic> row) => Message(
        id: row['id'] as String,
        remplacantId: row['remplacant_id'] as String,
        expediteurId: row['expediteur_id'] as String,
        contenu: row['contenu'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  static Future<List<Message>> messagesDe(String remplacantId) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('remplacant_id', remplacantId)
        .order('created_at');
    return (rows as List).map((r) => _messageDe(r as Map<String, dynamic>)).toList();
  }

  static Future<void> envoyerMessage(String remplacantId, String contenu) async {
    final texte = contenu.trim();
    if (texte.isEmpty) return;
    await _client.from('messages').insert({
      'remplacant_id': remplacantId,
      'expediteur_id': _client.auth.currentUser!.id,
      'contenu': texte,
    });
  }

  /// Flux en direct des messages d'un fil — se met à jour tout seul
  /// tant que l'écran de discussion est ouvert.
  static Stream<List<Message>> abonnementMessages(String remplacantId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('remplacant_id', remplacantId)
        .order('created_at')
        .map((rows) => rows.map(_messageDe).toList());
  }

  /// Tous les fils de discussion où je suis impliqué — que je sois
  /// titulaire (je parle à mon remplaçant) ou remplaçant (je parle à mon
  /// titulaire), peu importe le pacte d'origine. La RLS de `remplacants`
  /// renvoie déjà l'union des deux cas pour une même requête : mes
  /// propres remplaçants (je suis titulaire) et mes fiches de remplaçant
  /// (`profil_id = moi`), donc pas besoin de deux requêtes séparées.
  static Future<List<FilDeDiscussion>> mesFilsDeDiscussion() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _client
        .from('remplacants')
        .select('id, cote, prenom, nom, telephone, profil_id, '
            'pactes(initiateur_nom, destinataire_nom)')
        .not('profil_id', 'is', null);

    final fils = <FilDeDiscussion>[];
    for (final row in rows as List) {
      final r = row as Map<String, dynamic>;
      final pacteRow = r['pactes'] as Map<String, dynamic>?;
      if (pacteRow == null) continue;

      final remplacantId = r['id'] as String;
      final estMoiLeRemplacant = r['profil_id'] == userId;
      final String nomInterlocuteur;
      final String? telephoneInterlocuteur;
      if (estMoiLeRemplacant) {
        nomInterlocuteur = r['cote'] == 'initiateur'
            ? pacteRow['initiateur_nom'] as String
            : pacteRow['destinataire_nom'] as String;
        telephoneInterlocuteur = null;
      } else {
        nomInterlocuteur = [r['prenom'], r['nom']]
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .join(' ');
        telephoneInterlocuteur = r['telephone'] as String?;
      }

      final messages = await messagesDe(remplacantId);
      final dernier = messages.isNotEmpty ? messages.last : null;
      fils.add(FilDeDiscussion(
        remplacantId: remplacantId,
        nomInterlocuteur: nomInterlocuteur,
        telephoneInterlocuteur: telephoneInterlocuteur,
        dernierMessage: dernier?.contenu,
        dateDernierMessage: dernier?.createdAt,
      ));
    }

    fils.sort((a, b) {
      final da = a.dateDernierMessage;
      final db = b.dateDernierMessage;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return fils;
  }

  /// Nombre de fois où j'ai été désigné comme remplaçant (délégation
  /// reçue), toutes affaires confondues — utilisé pour la stat de profil.
  static Future<int> nombreRemplacementsEffectues() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    final rows = await _client
        .from('remplacants')
        .select('id')
        .eq('profil_id', userId)
        .eq('selectionne', true);
    return (rows as List).length;
  }
}
