// D-023a — CONVERSATION FIGÉE À L'ANNULATION. Eliot et Kevin discutent ; Eliot
// annule le Swend : la conversation reste lisible mais n'accepte plus aucun
// message, même avant l'heure. Kevin avait la conversation ouverte : son
// message est refusé proprement et la zone de saisie disparaît.
import * as A from '../lib/actions.mjs';
import { sql, FICHES, insererComme } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

export default {
  nom: 'gel_conversation_annulation',
  titre: 'Swend annulé : conversations immédiatement en lecture seule',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();

    await ex.etape('Eliot et Kevin discutent avant l\'annulation', async () => {
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await A.envoyerMessage(eliot, 'Tu seras dispo ?');
      await A.ouvrirConversationTiers(kevin);
      await kevin.attendreTexte('Tu seras dispo ?');
    });

    await ex.etape('Eliot annule le Swend', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Annuler le Swend');
      await eliot.cliquer('Annuler malgré tout');
      await eliot.cliquer('Annuler le Swend');
      await ex.verifier('Swend annulé', () => sql('select statut from pactes') === 'annule');
    });

    await ex.etape('Kevin écrit dans la conversation restée ouverte : refus propre', async () => {
      const champ = kevin.page.getByRole('textbox', { name: 'Écrire un message…' });
      await kevin.saisir(champ, 'Oui bien sûr');
      await kevin.page.keyboard.press('Enter');
      await ex.verifierTexte(kevin, 'Cette conversation est terminée : le message n’a pas été envoyé.', 'Kevin : message refusé proprement');
      await ex.verifierTexte(kevin, 'Cette conversation est terminée. Elle reste consultable.', 'Kevin : zone de saisie remplacée');
      await ex.verifierTexte(kevin, 'Tu seras dispo ?', 'Kevin : historique toujours lisible');
      await ex.verifier('aucun message de Kevin en base', () => sql(`select count(*) from messages where expediteur_id = '${COMPTES.kevin.id}'`) === '0');
    });

    await ex.etape('Eliot ne peut plus écrire non plus (API), rien d\'autre n\'est créé', async () => {
      const r = await insererComme('eliot', 'messages', { remplacant_id: FICHES.kevin, expediteur_id: COMPTES.eliot.id, contenu: 'Désolé' });
      await ex.verifier('API : écriture d\'Eliot refusée', () => !r.ok, { obtenu: () => `${r.statut} ${r.corps}` });
      await ex.verifier('pas d\'événement de fin pour un Swend annulé',
        () => sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '0');
      sql(`update pactes set date_retenue = now() - interval '1 minute'`);
      sql('select figer_swends_passes()');
      await ex.verifier('Swend annulé puis passé : ignoré par le moteur',
        () => sql(`select count(*) from swends_figes`) === '0' && sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '0');
    });
  },
};
