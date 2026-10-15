// D-023a, révisé par D-027 (lots 2 et 3b) — CONVERSATION APRÈS ANNULATION.
// Eliot et Kevin (seulement prévu) discutent ; Eliot annule le Swend.
// Base avec D-027-02 : des messages ont été échangés, la conversation est
// conservée et écrivable des deux côtés (P1) : Kevin, conversation ouverte,
// envoie son message ; Eliot « Reprend la conversation ». Base sans
// D-027-02 : la base refuse le message de Kevin (conversation terminée
// affichée), Eliot relit seulement. L'écriture est décidée par la base
// (`fil_ecriture_ouverte`), jamais par une règle locale.
import * as A from '../lib/actions.mjs';
import { sql, FICHES, insererComme, appelerComme, baseAvecLot2 } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

export default {
  nom: 'gel_conversation_annulation',
  titre: 'Swend annulé : conversation existante conservée et écrivable (P1), relecture seule sans D-027-02',
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

    // Le parcours d'annulation lui-même (« Un imprévu ? » → « Je n'ai
    // personne d'autre ») est testé dans 19 et 20.
    await ex.etape('Eliot annule le Swend', async () => {
      const r = await appelerComme('eliot', 'annuler_swend', { p_pacte_id: sql('select id from pactes') });
      await ex.verifier('Swend annulé', () => r.ok && sql('select statut from pactes') === 'annule', { obtenu: () => `${r.statut} ${r.corps}` });
    });

    await ex.etape('Kevin écrit dans la conversation restée ouverte', async () => {
      const champ = kevin.page.getByRole('textbox', { name: 'Écrire un message…' });
      await kevin.saisir(champ, 'Oui bien sûr');
      await kevin.page.keyboard.press('Enter');
      await kevin.attendreCalme();
      const n = () => sql(`select count(*) from messages where expediteur_id = '${COMPTES.kevin.id}'`);
      if (baseAvecLot2()) {
        await ex.verifier('message de Kevin enregistré (conversation conservée, P1)', () => n() === '1', { obtenu: n });
        await ex.verifierAbsent(kevin, 'Cette conversation est terminée', 'Kevin : conversation toujours ouverte');
      } else {
        await ex.verifier('base sans D-027-02 : message refusé', () => n() === '0', { obtenu: n });
        await ex.verifierTexte(kevin, 'Cette conversation est terminée. Elle reste consultable.', 'Kevin : conversation terminée affichée');
        await ex.verifier('Kevin : plus de zone de saisie', async () => (await kevin.page.getByRole('textbox', { name: 'Écrire un message…' }).count()) === 0);
      }
      const t = await appelerComme('kevin', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.kevin });
      await ex.verifier('aucun numéro pour Kevin (D-024 inchangé)', () => !t.corps.includes('06'), { obtenu: () => t.corps });
    });

    await ex.etape('Eliot ouvre la conversation depuis la fiche du Swend annulé (une seule : ouverte directement)', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Ton Swend avec David est annulé.', 'Eliot : « Ton Swend avec David est annulé. »');
      if (baseAvecLot2()) {
        await eliot.cliquer('Reprendre une conversation');
        await eliot.attendreTexte('Oui bien sûr');
        await ex.verifierTexte(eliot, 'Tu seras dispo ?', 'Eliot : historique');
        await ex.verifierAbsent(eliot, 'Reprendre la conversation avec…', 'Eliot : pas de choix (une seule conversation active)');
        await A.envoyerMessage(eliot, 'Désolé');
        await ex.verifier('message d\'Eliot enregistré', () => sql(`select count(*) from messages where expediteur_id = '${COMPTES.eliot.id}'`) === '2');
      } else {
        await eliot.cliquer('Relire une conversation');
        await eliot.attendreTexte('Cette conversation est terminée. Elle reste consultable.');
        await ex.verifierTexte(eliot, 'Tu seras dispo ?', 'Eliot : historique relu');
        await ex.verifierAbsent(eliot, 'Relire la conversation avec…', 'Eliot : pas de choix (une seule conversation active)');
        await ex.verifier('Eliot : aucune zone de saisie',
          async () => (await eliot.page.getByRole('textbox', { name: 'Écrire un message…' }).count()) === 0);
        const r = await insererComme('eliot', 'messages', { remplacant_id: FICHES.kevin, expediteur_id: COMPTES.eliot.id, contenu: 'Désolé' });
        await ex.verifier('API : écriture d\'Eliot refusée (base sans D-027-02)', () => !r.ok, { obtenu: () => `${r.statut} ${r.corps}` });
      }
    });

    await ex.etape('Rien d\'autre n\'est créé', async () => {
      await ex.verifier('pas d\'événement de fin pour un Swend annulé',
        () => sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '0');
      sql(`select qa.deplacer_swend(id, now() - interval '1 minute') from pactes`);
      sql('select figer_swends_passes()');
      await ex.verifier('Swend annulé puis passé : ignoré par le moteur',
        () => sql(`select count(*) from swends_figes`) === '0' && sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '0');
      if (baseAvecLot2()) {
        await ex.verifier('chat d\'annulation entre titulaires, jamais de chat après le Swend',
          () => sql(`select string_agg(nature, ',') from chats_apres_swend`) === 'annulation', { obtenu: () => sql(`select string_agg(nature, ',') from chats_apres_swend`) });
      } else {
        await ex.verifier('aucun chat', () => sql('select count(*) from chats_apres_swend') === '0');
      }
    });
  },
};
