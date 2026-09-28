// D-022 — ANNULATION EN COURS DE RECHERCHE, PUIS APRÈS ACCEPTATION —
// Eliot a une demande en attente : pas de nouvelle proposition d'imprévu,
// « Continuer à chercher ». Puis Kevin accepte : Eliot peut quand même
// annuler ; Kevin est prévenu et garde le Swend annulé dans son historique ;
// David n'apprend jamais qui remplaçait Eliot.
import * as A from '../lib/actions.mjs';
import { sql } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

const IMPREVU = /Qui peut prendre votre place|Personne n'est encore prévu|Aucune des personnes prévues|prendra votre place\./;
const notifs = (nom) => sql(`select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);
const quand = () => sql(`select date_rappel_fr(p.date_retenue) || ' à ' || heure_rappel_fr(p.date_retenue) || ' · ' || r.nom from pactes p join restaurants r on r.id = p.restaurant_id`);

export default {
  nom: 'annulation_recherche_remplace',
  titre: 'Annulation : demande en cours (« Continuer à chercher »), puis après acceptation de Kevin',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();

    await ex.etape('Demande en attente : confirmation "en recherche"', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Annuler le Swend');
      await ex.verifierAbsent(eliot, 'Vous ne pouvez plus être là ?', 'Eliot : l\'imprévu n\'est pas reproposé');
      await ex.verifierTexte(eliot, 'Les demandes de remplacement en cours seront annulées et le Swend prendra fin pour vous deux.', 'Eliot : "demandes en cours annulées"');
      await eliot.cliquer('Continuer à chercher');
      await ex.verifierTexte(eliot, IMPREVU, 'Eliot : "Continuer à chercher" ramène à "Un imprévu ?"');
      await ex.verifier('Swend toujours scellé, demande toujours en attente',
        () => sql('select statut from pactes') === 'confirme' && sql(`select demande_statut from remplacants where prenom = 'Kevin'`) === 'envoyee');
    });

    await ex.etape('Kevin accepte : confirmation "Kevin a accepté"', async () => {
      await A.repondre(kevin, true);
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Annuler le Swend');
      await ex.verifierTexte(eliot, 'Kevin a accepté de prendre votre place.', 'Eliot : "Kevin a accepté de prendre votre place."');
      await ex.verifierTexte(eliot, 'Si vous annulez, le Swend prendra fin pour tout le monde.', 'Eliot : "fin pour tout le monde"');
      await eliot.cliquer('Ne pas annuler');
      await ex.verifier('"Ne pas annuler" : Swend toujours scellé', () => sql('select statut from pactes') === 'confirme');
    });

    await ex.etape('Eliot annule quand même', async () => {
      await eliot.cliquer('Annuler le Swend');
      await eliot.cliquer('Annuler le Swend');
      await ex.verifier('Swend annulé en base', () => sql('select statut from pactes') === 'annule', { obtenu: () => sql('select statut from pactes') });
      await ex.verifierTexte(eliot, 'Votre Swend avec David est annulé.', 'Eliot : "Votre Swend avec David est annulé."');
      await ex.verifier('Kevin : "Le Swend est annulé" (« la place d’Eliot »)',
        () => notifs('kevin').endsWith(`Le Swend est annulé|Le Swend pour lequel tu devais prendre la place d’Eliot, ${quand()}, est annulé.`),
        { obtenu: () => notifs('kevin') });
      await ex.verifier('David : "Eliot a annulé votre Swend", sans nom de remplaçant',
        () => notifs('david') === `Ton Swend est annulé|Eliot a annulé votre Swend du ${quand()}.`, { obtenu: () => notifs('david') });
    });

    await ex.etape('Kevin garde le Swend annulé dans son historique', async () => {
      await A.ouvrirMesSwends(kevin);
      await ex.verifierTexte(kevin, 'Passés et annulés', 'Kevin : section "Passés et annulés"');
      await ex.verifierTexte(kevin, /Swend d'Eliot avec David\s+Annulé/, 'Kevin : carte "Annulé"');
      await A.ouvrirSwend(kevin, /Swend d'Eliot avec David/);
      await ex.verifierTexte(kevin, 'Ce Swend a été annulé.', 'Kevin : "Ce Swend a été annulé."');
      await kevin.accueil();
      await ex.verifierAbsent(kevin, 'Eliot compte sur toi', 'Kevin : plus "On compte sur toi"');
    });

    await ex.etape('David ne sait pas que c\'était Kevin', async () => {
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierTexte(david, 'Votre Swend avec Eliot est annulé.', 'David : "Votre Swend avec Eliot est annulé."');
      await ex.verifierAbsent(david, 'Kevin', 'David : aucune mention de Kevin');
    });
  },
};
