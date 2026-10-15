// D-022 révisé par D-027 — ANNULATION PAR UN TITULAIRE : plus de bouton
// générique sur la fiche ; seulement « Un imprévu ? » → recherche →
// « Je n'ai personne d'autre » → « Annuler le Swend ». Eliot retire Tom
// (sans compte), sollicite Kevin et Sylvain, qui refusent ; il annule
// depuis « Personne n'a pu prendre ta place. ». David est prévenu (sans
// motif) ; le Swend reste dans l'historique des deux titulaires. Après
// l'heure du rendez-vous : plus d'action.
import * as A from '../lib/actions.mjs';
import { sql, baseAvecLot2 } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

const notifs = (nom) => sql(`select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);
const quand = () => sql(`select date_rappel_fr(p.date_retenue) || ' à ' || heure_rappel_fr(p.date_retenue) || ' · ' || r.nom from pactes p join restaurants r on r.id = p.restaurant_id`);

export default {
  nom: 'annulation_manuelle',
  titre: 'Annulation par Eliot : seulement depuis Un imprévu ? (Je n’ai personne d’autre), David prévenu, historique',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();

    await ex.etape('Après l\'heure du rendez-vous : plus aucune action', async () => {
      const date = sql('select date_retenue from pactes');
      sql(`select qa.deplacer_swend(id, now() - interval '1 minute') from pactes`);
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifier('Eliot : ni « Annuler le Swend » ni « Un imprévu ? »', async () =>
        (await eliot.nombreDeBoutons('Annuler le Swend')) === 0 && (await eliot.nombreDeBoutons('Un imprévu ?')) === 0);
      sql(`select qa.deplacer_swend(id, '${date}') from pactes`);
    });

    await ex.etape('Fiche : plus de bouton « Annuler le Swend » ; « Un imprévu ? » d’abord', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifier('Swend scellé : pas de bouton "Réserver la table" (D-020)', async () => (await eliot.nombreDeBoutons('Réserver la table')) === 0);
      await ex.verifier('fiche : pas de bouton « Annuler le Swend »', async () => (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
      await eliot.cliquer('Un imprévu ?');
      await eliot.attendreTexte('Tu ne peux plus être là ?');
      await ex.verifier('personnes encore sollicitables : pas encore de « Je n’ai personne d’autre »',
        async () => (await eliot.nombreDeBoutons('Je n’ai personne d’autre')) === 0);
    });

    await ex.etape('Recherche : Tom retiré, Kevin et Sylvain sollicités puis refusent', async () => {
      await A.retirerPersonne(eliot, 'Tom Petit');
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner', 'Sylvain Landiech');
      await A.repondre(kevin, false);
      await A.repondre(sylvain, false);
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Personne n’a pu prendre ta place.', 'Eliot : « Personne n’a pu prendre ta place. »');
      await ex.verifier('« Je n’ai personne d’autre » proposé', async () => (await eliot.nombreDeBoutons('Je n’ai personne d’autre')) === 1);
    });

    await ex.etape('« Je n’ai personne d’autre » : Ajouter une personne, ou annuler (confirmation)', async () => {
      await eliot.cliquer('Je n’ai personne d’autre');
      await ex.verifierTexte(eliot, 'Tu n’as personne d’autre ?', 'titre « Tu n’as personne d’autre ? »');
      await ex.verifierTexte(eliot, 'Sans quelqu’un pour prendre ta place, le Swend ne pourra pas avoir lieu.', 'corps validé');
      await eliot.cliquer('Ajouter une personne');
      await ex.verifierTexte(eliot, 'Cette personne recevra directement ta demande', 'principal : ouvre l’ajout d’une personne');
      await eliot.page.keyboard.press('Escape');
      await eliot.attendreCalme();
      await eliot.cliquer('Je n’ai personne d’autre');
      await eliot.cliquer('Annuler le Swend');
      await ex.verifierTexte(eliot, 'Annuler ce Swend ?', 'confirmation « Annuler ce Swend ? »');
      await ex.verifierTexte(eliot, 'Cette action est définitive. L’autre personne sera prévenue.', 'confirmation : texte validé');
      await eliot.cliquer('Ne pas annuler');
      await ex.verifier('« Ne pas annuler » : Swend toujours scellé', () => sql('select statut from pactes') === 'confirme');
    });

    await ex.etape('Eliot annule : Swend annulé, sans motif demandé', async () => {
      await A.annulerDepuisImprevu(eliot);
      await ex.verifier('Swend annulé en base', () => sql('select statut from pactes') === 'annule', { obtenu: () => sql('select statut from pactes') });
      await ex.verifierTexte(eliot, 'Swend annulé', 'Eliot : retour à la fiche, « Swend annulé »');
      await ex.verifier('Eliot : plus d\'action d\'imprévu sur le Swend', async () =>
        (await eliot.nombreDeBoutons('Annuler le Swend')) === 0 && (await eliot.nombreDeBoutons('Un imprévu ?')) === 0);
    });

    await ex.etape('Notifications : David seulement (personnes qui avaient refusé : rien)', async () => {
      await ex.verifier('David prévenu de l’annulation, sans motif',
        () => notifs('david') === (baseAvecLot2()
          ? 'Le Swend est annulé|Eliot ne pourra finalement pas être là.'
          : `Ton Swend est annulé|Eliot a annulé votre Swend du ${quand()}.`),
        { obtenu: () => notifs('david') });
      await ex.verifier('Kevin et Sylvain (avaient refusé) : aucune push d’annulation',
        () => !notifs('kevin').includes('annulé') && !notifs('sylvain').includes('annulé'),
        { obtenu: () => `${notifs('kevin')} / ${notifs('sylvain')}` });
      await ex.verifier('Eliot : aucune push d’annulation', () => !notifs('eliot').includes('annulé'), { obtenu: () => notifs('eliot') });
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
      await ex.verifierTexte(david, 'Swend annulé', 'David : « Swend annulé »');
      await ex.verifier('David : aucune action d\'annulation', async () => (await david.nombreDeBoutons('Annuler le Swend')) === 0);
      await ex.verifierAbsent(david, /Kevin|Sylvain|Tom/, 'David : aucune coulisse (personne de confiance d’Eliot)');
    });
  },
};
