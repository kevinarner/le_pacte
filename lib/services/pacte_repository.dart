import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cote_pacte.dart';
import '../models/delai_minimum.dart';
import '../models/demande_statut.dart';
import '../models/evenement_fil.dart';
import '../models/fil_de_discussion.dart';
import '../models/message.dart';
import '../models/pacte.dart';
import '../models/remplacant.dart';
import '../models/restaurant.dart';
import '../models/statut_pacte.dart';
import '../models/statut_presence.dart';
import '../models/type_repas.dart';
import '../utils/heure_paris.dart';

/// Accès aux pactes, remplaçants et au restaurant stockés dans Supabase.
/// Les colonnes de suivi interne (historique des remplaçants) ne sont
/// jamais lues ni écrites ici — elles vivent uniquement côté serveur,
/// remplies automatiquement par un déclencheur.
class PacteRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Colonnes d'un Swend relues par l'app. Jamais `destinataire_telephone`
  /// (D-024) : l'app l'écrit à la création mais ne le relit pas — sinon
  /// chaque personne de confiance recevrait le numéro de l'autre titulaire.
  static const colonnesPacte =
      'id, type, statut, dates_proposees, date_retenue, '
      'nombre_echanges_date, restaurant_id, initiateur_id, initiateur_nom, '
      'destinataire_id, destinataire_nom, date_minimale, created_at';

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

  /// Le numéro que l'utilisateur vient de saisir pour une personne qu'il
  /// ajoute (destinataire, personne de confiance) a-t-il déjà un compte ?
  /// Oui / non seulement ; null = pas de réponse (numéro invalide, le
  /// sien, ou quota de vérifications atteint côté serveur). N'est appelé
  /// que par le widget StatutSwend.
  static Future<bool?> destinataireAUnCompte(String telephone) =>
      _client.rpc<bool?>(
        'destinataire_a_un_compte',
        params: {'p_telephone': telephone},
      );

  /// Première date possible pour un Swend que je créerais maintenant
  /// (D-025) : calculée par la base (heure de Paris + 15 jours) ; null si
  /// mon compte en est exempté.
  static Future<DateTime?> dateMinimaleNouveauSwend() async =>
      dateMinimaleDepuis(await _client.rpc('date_minimale_nouveau_swend'));

  /// Le téléphone du titulaire d'un pacte, du point de vue de son
  /// remplaçant (pour pouvoir l'appeler) — ne renvoie quelque chose que
  /// si l'appelant est bien ce remplaçant et qu'il a encore accès au Swend
  /// (avant l'heure du Swend, ou remplaçant sélectionné : D-023a), jamais
  /// pour un tiers.
  static Future<String?> telephoneTitulaireDuPacte(String remplacantId) async {
    final result = await _client.rpc<String?>(
      'telephone_titulaire_accessible',
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
        .select(colonnesPacte)
        .order('created_at', ascending: false);
    final restau = await restaurant();
    final pactes = <Pacte>[];
    for (final row in rows as List) {
      pactes.add(await _pacteDe(row as Map<String, dynamic>, restau));
    }
    return pactes;
  }

  /// Supprime définitivement un pacte (et sa messagerie, ses remplaçants
  /// des deux côtés) — passe par une fonction SECURITY DEFINER côté base
  /// car les remplaçants sont cloisonnés par côté via RLS.
  static Future<void> supprimerPacte(String pacteId) async {
    await _client.rpc('supprimer_pacte', params: {'p_pacte_id': pacteId});
  }

  /// Annule un Swend scellé (D-022) : seul un des deux titulaires, jusqu'à
  /// l'heure du rendez-vous. La base clôt les demandes en attente et
  /// prévient les personnes concernées, en une seule opération.
  static Future<void> annulerSwend(String pacteId) async {
    await _client.rpc('annuler_swend', params: {'p_pacte_id': pacteId});
  }

  /// Mes Swends déjà scellés (actifs, passés ou annulés) : ils restent dans
  /// l'historique et ne peuvent pas être supprimés (D-022).
  static Future<Set<String>> mesSwendsScelles() async {
    final rows = await _client.rpc('mes_swends_scelles') as List<dynamic>;
    return {for (final r in rows) (r is Map ? r.values.first : r) as String};
  }

  /// Un pacte précis par son id — utilisé pour ouvrir directement le
  /// bon pacte au clic sur une notification.
  static Future<Pacte?> pacteParId(String id) async {
    final rows = await _client
        .from('pactes')
        .select(colonnesPacte)
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    final restau = await restaurant();
    return _pacteDe(rows.first, restau);
  }

  /// Où ouvrir un rappel (D-021), calculé par la base à l'instant du clic
  /// selon l'état ACTUEL du Swend : 'imprevu' (titulaire qui cherche
  /// encore quelqu'un), 'fiche', ou null (plus d'accès, ex. désisté).
  static Future<String?> destinationRappel(String pacteId) async {
    final res = await _client.rpc(
      'destination_rappel',
      params: {'p_pacte_id': pacteId},
    );
    return res as String?;
  }

  static Future<Pacte> _pacteDe(
    Map<String, dynamic> row,
    Restaurant restau,
  ) async {
    final id = row['id'] as String;
    final statut = StatutPacte.values.byName(row['statut'] as String);
    final remplacantsInitiateur = await remplacantsDe(id, 'initiateur');
    final remplacantsDestinataire = await remplacantsDe(id, 'destinataire');
    final confirmeOuPlus =
        statut == StatutPacte.confirme || statut == StatutPacte.maintenu;

    final pacte = Pacte(
      id: id,
      type: TypeRepas.values.byName(row['type'] as String),
      datesProposees: (row['dates_proposees'] as List)
          .map((s) => lireInstant(s as String))
          .toList(),
      dateRetenue: row['date_retenue'] != null
          ? lireInstant(row['date_retenue'] as String)
          : null,
      nombreEchangesDate: row['nombre_echanges_date'] as int,
      dateMinimale: dateMinimaleDepuis(row['date_minimale']),
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
  static Future<List<Remplacant>> remplacantsDe(
    String pacteId,
    String cote,
  ) async {
    final rows = await _client
        .from('remplacants')
        .select()
        .eq('pacte_id', pacteId)
        .eq('cote', cote)
        // Une personne retirée de la liste reste en base avec sa
        // conversation (D-023a), mais n'est plus présentée.
        .isFilter('retire_le', null)
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
    demandeStatut: row['demande_statut'] != null
        ? DemandeStatut.values.byName(row['demande_statut'] as String)
        : null,
    indisponibleSpontanement:
        row['indisponible_spontanement'] as bool? ?? false,
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

    // Le destinataire (s'il a déjà un compte) est retrouvé par la base à
    // partir du numéro canonique : l'app n'envoie jamais destinataire_id.
    final row = await _client
        .from('pactes')
        .insert({
          'type': type.name,
          'statut': StatutPacte.enAttenteChoixDateDestinataire.name,
          'dates_proposees': datesProposees.map(isoInstant).toList(),
          'restaurant_id': restau.id,
          'initiateur_id': initiateurId,
          'initiateur_nom': initiateurNom,
          'destinataire_nom': destinataireNom,
          'destinataire_telephone': destinataireTelephone,
        })
        .select(colonnesPacte)
        .single();

    final pacteId = row['id'] as String;
    for (final r in remplacantsInitiateur.where((r) => r.estRempli)) {
      await _insererRemplacant(pacteId, 'initiateur', r);
    }

    return _pacteDe(row, restau);
  }

  static Future<Remplacant> _insererRemplacant(
    String pacteId,
    String cote,
    Remplacant r,
  ) async {
    // Le lien vers un compte existant (profil_id) est calculé par la base
    // à partir du numéro canonique — ou à l'inscription de la personne.
    final row = await _client
        .from('remplacants')
        .insert({
          'pacte_id': pacteId,
          'cote': cote,
          'prenom': r.prenom,
          'nom': r.nom,
          'telephone': r.telephone,
          'email': r.email,
        })
        .select()
        .single();
    // La base recalcule le lien de compte et peut faire naître la fiche
    // "indisponible" (personne déjà engagée de l'autre côté) : on reprend
    // sa version à elle, pas celle envoyée.
    final enBase = _remplacantDe(row);
    r.id = enBase.id;
    r.profilId = enBase.profilId;
    r.selectionne = enBase.selectionne;
    r.demandeStatut = enBase.demandeStatut;
    return r;
  }

  /// Enregistre les remplaçants sans id (nouveaux) d'un côté d'un pacte
  /// déjà existant — utilisé lors d'une délégation après confirmation.
  static Future<void> synchroniserRemplacants(
    String pacteId,
    String cote,
    List<Remplacant> remplacants,
  ) async {
    for (final r in remplacants.where((r) => r.estRempli && r.id == null)) {
      await _insererRemplacant(pacteId, cote, r);
    }
  }

  /// Envoie une demande "Un imprévu ?" à cette personne (titulaire
  /// uniquement). Rien n'est transféré tant qu'elle n'a pas accepté.
  /// Toutes les transitions d'une demande passent par des fonctions
  /// serveur : l'app n'a plus le droit d'écrire directement dans
  /// `remplacants` (hors ajout d'une personne).
  static Future<void> envoyerDemandeRemplacement(String remplacantId) async {
    await _client.rpc(
      'envoyer_demande_remplacement',
      params: {'p_remplacant_id': remplacantId},
    );
  }

  /// Annule une demande encore en attente — impossible dès que la
  /// personne a accepté (transfert définitif).
  static Future<void> annulerDemandeRemplacement(String remplacantId) async {
    await _client.rpc(
      'annuler_demande_remplacement',
      params: {'p_remplacant_id': remplacantId},
    );
  }

  /// Appelé par la personne qui avait accepté : rouvre la recherche côté
  /// titulaire.
  static Future<void> seDesister(String remplacantId) async {
    await _client.rpc(
      'se_desister_du_remplacement',
      params: {'p_remplacant_id': remplacantId},
    );
  }

  /// Appelé par une personne de confiance simplement prévue : "Je ne
  /// serai pas disponible" (son titulaire est prévenu). Réversible.
  static Future<void> signalerIndisponibilite(String remplacantId) async {
    await _client.rpc(
      'signaler_indisponibilite',
      params: {'p_remplacant_id': remplacantId},
    );
  }

  /// "Je suis finalement disponible" : annule l'indisponibilité spontanée.
  static Future<void> signalerDisponibilite(String remplacantId) async {
    await _client.rpc(
      'signaler_disponibilite',
      params: {'p_remplacant_id': remplacantId},
    );
  }

  /// Retire une personne de la liste (et son fil de discussion) — refusé
  /// par la base si une demande est en attente ou si elle a accepté.
  static Future<void> retirerRemplacant(String remplacantId) async {
    await _client.rpc(
      'retirer_remplacant',
      params: {'p_remplacant_id': remplacantId},
    );
  }

  /// Ajoute quelqu'un pendant un imprévu ET lui envoie la demande, en une
  /// seule opération côté base (tout ou rien).
  static Future<String> ajouterEtDemanderRemplacement({
    required String pacteId,
    required String cote,
    required String prenom,
    required String nom,
    required String telephone,
  }) async {
    final id = await _client.rpc<String>(
      'ajouter_et_demander_remplacement',
      params: {
        'p_pacte_id': pacteId,
        'p_cote': cote,
        'p_prenom': prenom,
        'p_nom': nom,
        'p_telephone': telephone,
      },
    );
    return id;
  }

  /// Le code métier levé par une fonction serveur (`place_deja_prise`,
  /// `personne_indisponible`...), ou null pour une erreur technique.
  static String? codeErreurMetier(Object erreur) {
    if (erreur is! PostgrestException) return null;
    const codes = [
      'place_deja_prise',
      'personne_indisponible',
      'deja_remplacant_autre_cote',
      'demande_non_active',
      'deja_acceptee',
      'retrait_impossible',
      'swend_inactif',
      'champs_manquants',
      'telephone_invalide',
      'personne_est_participant',
      'personne_deja_prevue',
      'destinataire_est_initiateur',
      'telephone_fige',
      'modification_interdite',
      'swend_passe',
      'date_trop_proche',
      'date_sans_fuseau',
      'date_non_proposee',
    ];
    for (final code in codes) {
      if (erreur.message.contains(code)) return code;
    }
    return null;
  }

  /// Refus `date_trop_proche` (D-025) : la première date possible, telle que
  /// la base l'a calculée (détail de l'erreur), ou null.
  static DateTime? dateMinimaleDeErreur(Object erreur) =>
      erreur is PostgrestException ? dateMinimaleDepuis(erreur.details) : null;

  /// Répond à une demande reçue — appelé par la personne sollicitée
  /// elle-même. Passe par une fonction serveur car elle doit, en cas
  /// d'acceptation, clôturer les autres demandes en attente du même
  /// côté (des fiches qu'elle n'a normalement pas le droit de voir), et
  /// garantir qu'une seule personne peut accepter même en cas de double
  /// acceptation presque simultanée. Lève une [PostgrestException] dont
  /// le message contient `place_deja_prise` si quelqu'un d'autre a déjà
  /// accepté entre-temps.
  static Future<void> repondreDemandeRemplacement(
    String remplacantId,
    bool accepte,
  ) async {
    await _client.rpc(
      'repondre_demande_remplacement',
      params: {'p_remplacant_id': remplacantId, 'p_accepte': accepte},
    );
  }

  /// Une fiche remplaçant précise par son id — utilisé par `ChatScreen`
  /// pour savoir, à l'ouverture d'un fil, si une demande "Un imprévu ?"
  /// est en attente pour la personne qui regarde.
  static Future<Remplacant?> remplacantParId(String id) async {
    final rows = await _client
        .from('remplacants')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    return _remplacantDe(rows.first);
  }

  /// Le pacte concerné par une fiche remplaçant — utilisé une fois une
  /// demande acceptée pour donner à la personne qui prend la place la
  /// date, l'heure et le restaurant. La RLS de `pactes` laisse déjà un
  /// remplaçant lire le pacte concerné (voir `est_remplacant_du_pacte`).
  static Future<Pacte?> pacteDuRemplacant(String remplacantId) async {
    final row = await _client
        .from('remplacants')
        .select('pacte_id')
        .eq('id', remplacantId)
        .limit(1);
    if (row.isEmpty) return null;
    final pacteId = row.first['pacte_id'] as String?;
    if (pacteId == null) return null;
    return pacteParId(pacteId);
  }

  /// Relit uniquement le statut actuel d'un pacte — utilisé après une
  /// délégation pour savoir si le déclencheur côté base vient
  /// d'annuler le pacte (l'autre côté avait déjà délégué).
  static Future<StatutPacte> statutActuel(String pacteId) async {
    final row = await _client
        .from('pactes')
        .select('statut')
        .eq('id', pacteId)
        .single();
    return StatutPacte.values.byName(row['statut'] as String);
  }

  static Future<void> choisirDate(String pacteId, DateTime date) async {
    await _client
        .from('pactes')
        .update({
          'date_retenue': isoInstant(date),
          'statut': StatutPacte.enAttenteReponse.name,
        })
        .eq('id', pacteId);
  }

  static Future<void> contreProposerDates(
    String pacteId,
    List<DateTime> dates,
    int nombreEchangesDate,
    bool jeSuisInitiateur,
  ) async {
    await _client
        .from('pactes')
        .update({
          'dates_proposees': dates.map(isoInstant).toList(),
          'nombre_echanges_date': nombreEchangesDate,
          'statut':
              (jeSuisInitiateur
                      ? StatutPacte.enAttenteChoixDateDestinataire
                      : StatutPacte.enAttenteChoixDateInitiateur)
                  .name,
        })
        .eq('id', pacteId);
  }

  static Future<void> mettreAJourStatut(
    String pacteId,
    StatutPacte statut,
  ) async {
    await _client
        .from('pactes')
        .update({'statut': statut.name})
        .eq('id', pacteId);
  }

  static Message _messageDe(Map<String, dynamic> row) => Message(
    id: row['id'] as String,
    remplacantId: row['remplacant_id'] as String,
    expediteurId: row['expediteur_id'] as String,
    contenu: row['contenu'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  /// Du plus ancien au plus récent (attention : `order()` trie par défaut
  /// du plus récent au plus ancien).
  static Future<List<Message>> messagesDe(String remplacantId) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('remplacant_id', remplacantId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => _messageDe(r as Map<String, dynamic>))
        .toList();
  }

  static Future<void> envoyerMessage(
    String remplacantId,
    String contenu,
  ) async {
    final texte = contenu.trim();
    if (texte.isEmpty) return;
    await _client.from('messages').insert({
      'remplacant_id': remplacantId,
      'expediteur_id': _client.auth.currentUser!.id,
      'contenu': texte,
    });
  }

  /// Les événements d'un fil (demande envoyée, acceptée...), du plus
  /// ancien au plus récent — lisibles seulement par le titulaire de ce
  /// côté et la personne de confiance elle-même.
  static Future<List<EvenementFil>> evenementsDe(String remplacantId) async {
    final rows = await _client
        .from('evenements_fil')
        .select()
        .eq('remplacant_id', remplacantId)
        .order('created_at', ascending: true);
    return (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return EvenementFil(
        id: row['id'] as String,
        remplacantId: row['remplacant_id'] as String,
        code: row['code'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  /// Parmi ces conversations, celles qui ont eu une activité (au moins un
  /// message ou un événement) — les seules proposées à la relecture une
  /// fois le Swend passé ou annulé (D-023a). La RLS ne renvoie que ce que
  /// je peux déjà lire.
  static Future<Set<String>> filsAvecActivite(
    List<String> remplacantIds,
  ) async {
    if (remplacantIds.isEmpty) return {};
    final messages = await _client
        .from('messages')
        .select('remplacant_id')
        .inFilter('remplacant_id', remplacantIds);
    final evenements = await _client
        .from('evenements_fil')
        .select('remplacant_id')
        .inFilter('remplacant_id', remplacantIds);
    return {
      for (final r in [...messages as List, ...evenements as List])
        (r as Map<String, dynamic>)['remplacant_id'] as String,
    };
  }

  /// Marque une conversation comme lue par moi (jusqu'à maintenant).
  static Future<void> marquerFilLu(String remplacantId) async {
    await _client.rpc(
      'marquer_fil_lu',
      params: {'p_remplacant_id': remplacantId},
    );
  }

  /// Jusqu'à quand j'ai lu chaque conversation (remplacant_id → date).
  static Future<Map<String, DateTime>> mesLectures() async {
    final rows = await _client
        .from('lectures_fil')
        .select('remplacant_id, lu_le');
    return {
      for (final r in rows as List)
        (r as Map<String, dynamic>)['remplacant_id'] as String: DateTime.parse(
          r['lu_le'] as String,
        ),
    };
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
        .select(
          'id, cote, prenom, nom, telephone, profil_id, '
          'pactes(initiateur_nom, destinataire_nom, date_retenue)',
        )
        .not('profil_id', 'is', null)
        .isFilter('retire_le', null);
    final restau = await restaurant();
    Map<String, DateTime> lectures;
    try {
      lectures = await mesLectures();
    } catch (_) {
      lectures = {};
    }
    // Tous les événements que la RLS me laisse lire, en une requête.
    final evenementsParFil = <String, List<EvenementFil>>{};
    try {
      final evts = await _client
          .from('evenements_fil')
          .select()
          .order('created_at', ascending: true);
      for (final e in evts as List) {
        final row = e as Map<String, dynamic>;
        final evt = EvenementFil(
          id: row['id'] as String,
          remplacantId: row['remplacant_id'] as String,
          code: row['code'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
        evenementsParFil.putIfAbsent(evt.remplacantId, () => []).add(evt);
      }
    } catch (_) {
      // Sans événements : les boxes ne reposent que sur les messages.
    }

    final fils = <FilDeDiscussion>[];
    for (final row in rows as List) {
      final r = row as Map<String, dynamic>;
      final pacteRow = r['pactes'] as Map<String, dynamic>?;
      if (pacteRow == null) continue;
      final dateRetenue = pacteRow['date_retenue'] as String?;

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
        nomInterlocuteur = [
          r['prenom'],
          r['nom'],
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
        telephoneInterlocuteur = r['telephone'] as String?;
      }

      final messages = await messagesDe(remplacantId);
      final dernier = messages.isNotEmpty ? messages.last : null;
      final luLe = lectures[remplacantId];
      bool apresLecture(DateTime d) => luLe == null || d.isAfter(luLe);
      final messagesNonLus = messages.where(
        (m) => m.expediteurId != userId && apresLecture(m.createdAt),
      );
      final evenementsNonLus = (evenementsParFil[remplacantId] ?? const [])
          .where(
            (e) =>
                e.concerneLecteur(vuParTiers: estMoiLeRemplacant) &&
                apresLecture(e.createdAt),
          );
      final dernierMessageNonLu = messagesNonLus.isEmpty
          ? null
          : messagesNonLus.last.createdAt;
      final dernierEvenementNonLu = evenementsNonLus.isEmpty
          ? null
          : evenementsNonLus.last;
      final evenementEnTete =
          dernierEvenementNonLu != null &&
              (dernierMessageNonLu == null ||
                  dernierEvenementNonLu.createdAt.isAfter(dernierMessageNonLu))
          ? dernierEvenementNonLu
          : null;
      final nonLu =
          dernierMessageNonLu != null || dernierEvenementNonLu != null;
      final autrePartieNom = r['cote'] == 'initiateur'
          ? pacteRow['destinataire_nom'] as String?
          : pacteRow['initiateur_nom'] as String?;
      fils.add(
        FilDeDiscussion(
          remplacantId: remplacantId,
          nomInterlocuteur: nomInterlocuteur,
          telephoneInterlocuteur: telephoneInterlocuteur,
          dernierMessage: dernier?.contenu,
          dateDernierMessage: dernier?.createdAt,
          dernierMessageDeMoi:
              dernier == null || dernier.expediteurId == userId,
          nonLu: nonLu,
          evenementNonLu: evenementEnTete,
          dateNonLu: evenementEnTete?.createdAt ?? dernierMessageNonLu,
          jeSuisLeTiers: estMoiLeRemplacant,
          dateConcernee: dateRetenue != null
              ? lireInstant(dateRetenue)
              : null,
          restaurantNom: restau.nom,
          autrePartieNom: autrePartieNom,
        ),
      );
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
