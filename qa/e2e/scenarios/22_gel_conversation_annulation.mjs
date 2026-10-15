// D-023a, révisé par D-027 lot 2 — CONVERSATION APRÈS ANNULATION. Eliot et
// Kevin discutent ; Eliot annule le Swend. La conversation existe : la base
// la garde accessible et ouverte à l'écriture pour Eliot et Kevin (seulement
// prévu). Ce scénario tourne avec l'app publiée (lot 1), qui ne connaît pas
// encore cette règle : Kevin, conversation ouverte, envoie son message (la
// base l'accepte) ; Eliot ne voit qu'une relecture sans zone de saisie
// (règle locale de l'app). C'est la fenêtre « base avant app » décrite dans
// le paquet D-027-02 : l'app du lot 3 doit être publiée d'abord.
import * as A from '../lib/actions.mjs';
import { sql, FICHES, insererComme, appelerComme } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

export default {
  nom: 'gel_conversation_annulation',
  titre: 'Swend annulé : conversation existante conservée et écrivable (base D-027 lot 2, app du lot 1)',
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

    await ex.etape('Kevin écrit dans la conversation restée ouverte : la base accepte (conversation conservée)', async () => {
      const champ = kevin.page.getByRole('textbox', { name: 'Écrire un message…' });
      await kevin.saisir(champ, 'Oui bien sûr');
      await kevin.page.keyboard.press('Enter');
      await ex.verifier('message de Kevin enregistré (D-027 lot 2)',
        () => sql(`select count(*) from messages where expediteur_id = '${COMPTES.kevin.id}'`) === '1',
        { obtenu: () => sql(`select count(*) from messages where expediteur_id = '${COMPTES.kevin.id}'`) });
      await ex.verifier('aucun numéro pour Kevin (D-024 inchangé)',
        () => sql(`select coalesce(telephone_titulaire_accessible(id), '') from remplacants where prenom = 'Kevin'`) === '');
    });

    await ex.etape('Eliot relit la conversation depuis la fiche du Swend annulé (une seule : ouverte directement)', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Votre Swend avec David est annulé.', 'Eliot : fiche du Swend annulé');
      await eliot.cliquer('Relire une conversation');
      await eliot.attendreTexte('Cette conversation est terminée. Elle reste consultable.');
      await ex.verifierTexte(eliot, 'Tu seras dispo ?', 'Eliot : historique relu');
      await ex.verifierAbsent(eliot, 'Relire la conversation avec…', 'Eliot : pas de choix (une seule conversation active)');
      await ex.verifier('Eliot : aucune zone de saisie',
        async () => (await eliot.page.getByRole('textbox', { name: 'Écrire un message…' }).count()) === 0);
    });

    await ex.etape('Eliot peut écrire (API), rien d\'autre n\'est créé', async () => {
      const r = await insererComme('eliot', 'messages', { remplacant_id: FICHES.kevin, expediteur_id: COMPTES.eliot.id, contenu: 'Désolé' });
      await ex.verifier('API : écriture d\'Eliot acceptée (conversation conservée)', () => r.ok, { obtenu: () => `${r.statut} ${r.corps}` });
      await ex.verifier('pas d\'événement de fin pour un Swend annulé',
        () => sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '0');
      sql(`select qa.deplacer_swend(id, now() - interval '1 minute') from pactes`);
      sql('select figer_swends_passes()');
      await ex.verifier('Swend annulé puis passé : ignoré par le moteur',
        () => sql(`select count(*) from swends_figes`) === '0' && sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '0');
      await ex.verifier('chat d\'annulation entre titulaires, jamais de chat après le Swend',
        () => sql(`select string_agg(nature, ',') from chats_apres_swend`) === 'annulation', { obtenu: () => sql(`select string_agg(nature, ',') from chats_apres_swend`) });
    });
  },
};
