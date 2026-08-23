import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cote_pacte.dart';
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
    r.id = row['id'] as String;
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
}
