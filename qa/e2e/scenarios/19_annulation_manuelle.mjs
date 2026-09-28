// D-022 — ANNULATION MANUELLE, CAS NORMAL — Eliot n'a lancé aucun imprévu :
// on lui propose d'abord de trouver quelqu'un, puis il annule. David est
// prévenu (sans motif), Kevin (seulement prévu) ne reçoit rien et ne voit
// plus le Swend ; le Swend reste dans l'historique des deux titulaires,
// sous « Passés et annulés ». Après l'heure du rendez-vous : plus d'action.
import * as A from '../lib/actions.mjs';
import { sql } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

const IMPREVU = /Qui peut prendre votre place|Personne n'est encore prévu|Aucune des personnes prévues|prendra votre place\./;
const notifs = (nom) => sql(`select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);
const quand = () => sql(`select date_rappel_fr(p.date_retenue) || ' à ' || heure_rappel_fr(p.date_retenue) || ' · ' || r.nom from pactes p join restaurants r on r.id = p.restaurant_id`);

export default {
  nom: 'annulation_manuelle',
  titre: 'Annulation par Eliot (aucun imprévu) : confirmations, David prévenu, historique',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();

    await ex.etape('Après l\'heure du rendez-vous : plus d\'annulation possible', async () => {
      const date = sql('select date_retenue from pactes');
      sql(`update pactes set date_retenue = now() - interval '1 minute'`);
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifier('Eliot : pas de bouton "Annuler le Swend"', async () => (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
      sql(`update pactes set date_retenue = '${date}'`);
    });

    await ex.etape('Cas normal : proposer d\'abord un remplaçant', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Annuler le Swend');
      await ex.verifierTexte(eliot, 'Vous ne pouvez plus être là ?', 'Eliot : "Vous ne pouvez plus être là ?"');
      await ex.verifierTexte(eliot, 'Avant d’annuler, vous pouvez demander à quelqu’un de confiance de prendre votre place.', 'Eliot : proposition de remplacement');
      await eliot.cliquer('Trouver quelqu’un pour me remplacer');
      await ex.verifierTexte(eliot, IMPREVU, 'Eliot : "Trouver quelqu\'un" ouvre "Un imprévu ?"');
      await eliot.retour();
      await eliot.cliquer('Annuler le Swend');
      await eliot.cliquer('Annuler malgré tout');
      await ex.verifierTexte(eliot, 'Annuler ce Swend ?', 'Eliot : "Annuler ce Swend ?"');
      await ex.verifierTexte(eliot, 'Cette action mettra fin au Swend pour vous deux.', 'Eliot : "fin pour vous deux"');
      await eliot.cliquer('Ne pas annuler');
      await ex.verifier('"Ne pas annuler" : Swend toujours scellé', () => sql('select statut from pactes') === 'confirme');
    });

    await ex.etape('Eliot annule : "Swend annulé", sans motif demandé', async () => {
      await eliot.cliquer('Annuler le Swend');
      await eliot.cliquer('Annuler malgré tout');
      await eliot.cliquer('Annuler le Swend');
      await ex.verifier('Swend annulé en base', () => sql('select statut from pactes') === 'annule', { obtenu: () => sql('select statut from pactes') });
      await ex.verifierTexte(eliot, 'Swend annulé', 'Eliot : "Swend annulé"');
      await ex.verifierTexte(eliot, 'Votre Swend avec David est annulé.', 'Eliot : "Votre Swend avec David est annulé."');
      await ex.verifier('Eliot : plus d\'action sur le Swend', async () =>
        (await eliot.nombreDeBoutons('Annuler le Swend')) === 0 && (await eliot.nombreDeBoutons('Un imprévu ?')) === 0);
    });

    await ex.etape('Notifications : David seulement', async () => {
      await ex.verifier('David : "Ton Swend est annulé"',
        () => notifs('david') === `Ton Swend est annulé|Eliot a annulé votre Swend du ${quand()}.`, { obtenu: () => notifs('david') });
      await ex.verifier('Kevin (seulement prévu) : aucune push', () => notifs('kevin') === '', { obtenu: () => notifs('kevin') });
      await ex.verifier('Eliot : aucune push', () => notifs('eliot') === '', { obtenu: () => notifs('eliot') });
      await ex.verifier('réservation : à annuler seulement si elle avait été faite (rien ici)',
        () => sql('select a_faire from reservations_a_suivre') === '', { obtenu: () => sql('select a_faire from reservations_a_suivre') });
    });

    await ex.etape('Historique : "Passés et annulés", carte "Annulé"', async () => {
      for (const [a, autre] of [[eliot, 'David Schlang'], [david, 'Eliot Martin']]) {
        await a.accueil();
        await ex.verifierTexte(a, /Mes Swends\s+0 à venir/, `${a.compte.prenom} : 0 à venir`);
        await A.ouvrirMesSwends(a);
        await ex.verifierTexte(a, 'Passés et annulés', `${a.compte.prenom} : section "Passés et annulés"`);
        await ex.verifierAbsent(a, 'À venir', `${a.compte.prenom} : aucune section "À venir"`);
        await ex.verifierTexte(a, new RegExp(`Swend avec ${autre}\\s+Annulé`), `${a.compte.prenom} : carte "Annulé"`);
      }
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierTexte(david, 'Votre Swend avec Eliot est annulé.', 'David : "Votre Swend avec Eliot est annulé."');
      await ex.verifier('David : aucune action d\'annulation', async () => (await david.nombreDeBoutons('Annuler le Swend')) === 0);
    });

    await ex.etape('Kevin (seulement prévu) : le Swend disparaît', async () => {
      await kevin.accueil();
      await ex.verifierAbsent(kevin, 'Eliot compte sur toi', 'Kevin : plus "On compte sur toi"');
      await A.ouvrirMesSwends(kevin);
      await ex.verifierAbsent(kevin, "Swend d'Eliot avec David", 'Kevin : Swend absent de "Mes Swends"');
    });
  },
};
