// D-022 révisé par D-027 — ANNULATION EN COURS DE RECHERCHE, PUIS APRÈS
// ACCEPTATION. Eliot a une demande en attente : aucune annulation possible
// pendant l'attente (l'annulation reste le dernier recours). Kevin accepte :
// Eliot, remplacé, n'a plus aucune action d'annulation (ni fiche, ni « Un
// imprévu ? ») ; la base la refuserait aussi (lot 2). David, sans personne
// à solliciter, annule depuis son « Un imprévu ? » ; Kevin est prévenu et
// garde le Swend annulé dans son historique ; David n'apprend jamais qui
// remplaçait Eliot.
import * as A from '../lib/actions.mjs';
import { sql, baseAvecLot2, appelerComme } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

const notifs = (nom) => sql(`select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);
const quand = () => sql(`select date_rappel_fr(p.date_retenue) || ' à ' || heure_rappel_fr(p.date_retenue) || ' · ' || r.nom from pactes p join restaurants r on r.id = p.restaurant_id`);

export default {
  nom: 'annulation_recherche_remplace',
  titre: 'Annulation : impossible pendant l’attente et pour le titulaire remplacé ; David annule',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();

    await ex.etape('Demande en attente : aucune annulation possible', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await ex.verifierTexte(eliot, 'C’est envoyé.', 'Eliot : « C’est envoyé. »');
      await ex.verifier('attente : ni « Je n’ai personne d’autre » ni « Annuler le Swend »', async () =>
        (await eliot.nombreDeBoutons('Je n’ai personne d’autre')) === 0 && (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifier('fiche : pas de « Annuler le Swend »', async () => (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
    });

    await ex.etape('Kevin accepte : Eliot remplacé, plus aucune annulation', async () => {
      await A.repondre(kevin, true);
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Kevin a accepté.', 'Eliot : « Kevin a accepté. »');
      await ex.verifier('Un imprévu ? : ni retour, ni dernier recours, ni annulation', async () =>
        (await eliot.nombreDeBoutons('Je peux finalement venir')) === 0
        && (await eliot.nombreDeBoutons('Je n’ai personne d’autre')) === 0
        && (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifier('fiche : pas de « Annuler le Swend »', async () => (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
      if (baseAvecLot2()) {
        const r = await appelerComme('eliot', 'annuler_swend', { p_pacte_id: sql('select id from pactes') });
        await ex.verifier('API : la base refuse aussi (remplacement_accepte)', () => !r.ok && r.corps.includes('remplacement_accepte'),
          { obtenu: () => `${r.statut} ${r.corps}` });
      }
      await ex.verifier('Swend toujours scellé', () => sql('select statut from pactes') === 'confirme');
    });

    await ex.etape('David, sans personne à solliciter, annule depuis « Un imprévu ? »', async () => {
      await A.retirerPersonne(david, 'Léo Blanc', /Swend avec Eliot/);
      await A.retirerPersonne(david, 'Nina Roy', /Swend avec Eliot/);
      await A.ouvrirImprevu(david, /Swend avec Eliot/);
      await ex.verifierTexte(david, 'Tu n’as encore prévu personne', 'David : liste vide');
      await ex.verifierAbsent(david, /Kevin|Sylvain|Tom/, 'David : aucune personne de confiance d’Eliot');
      await A.annulerDepuisImprevu(david);
      await ex.verifier('Swend annulé en base par David', () => sql('select statut from pactes') === 'annule',
        { obtenu: () => sql('select statut from pactes') });
      if (baseAvecLot2()) {
        await ex.verifier('motif titulaire', () => sql('select annule_motif from pactes') === 'titulaire');
      }
      await ex.verifierTexte(david, 'Swend annulé', 'David : « Swend annulé »');
    });

    await ex.etape('Notifications : Kevin et Eliot prévenus, rien pour David (auteur)', async () => {
      const lot2 = baseAvecLot2();
      await ex.verifier('Kevin (remplaçant) prévenu',
        () => notifs('kevin').endsWith(lot2
          ? 'Le Swend est annulé|Tu n’auras finalement pas besoin de prendre la place d’Eliot.'
          : `Le Swend est annulé|Le Swend pour lequel tu devais prendre la place d’Eliot, ${quand()}, est annulé.`),
        { obtenu: () => notifs('kevin') });
      await ex.verifier('Eliot prévenu, sans coulisse',
        () => notifs('eliot').endsWith(lot2
          ? 'Le Swend est annulé|David ne pourra finalement pas être là.'
          : `Ton Swend est annulé|David a annulé votre Swend du ${quand()}.`),
        { obtenu: () => notifs('eliot') });
      await ex.verifier('David : aucune push d’annulation', () => !notifs('david').includes('annulé'), { obtenu: () => notifs('david') });
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
      await ex.verifierAbsent(david, 'Kevin', 'David : aucune mention de Kevin');
    });
  },
};
