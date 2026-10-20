// D-023a — GEL À H. À l'heure du Swend, l'imprévu est figé : Kevin regardait
// la demande d'Eliot, H passe, son « Accepter » est refusé proprement par la
// base ; plus aucune action d'imprévu (fiche, Home, Mes Swends, API), le
// moteur clôt la demande (une push à Kevin, aucune autre), les conversations
// restent lisibles mais terminées (événement de fin), sans box non lue. David
// ne voit rien. Le Swend reste `confirme` et rejoint « Passés et annulés ».
// Base avec l'échéance H-3 (D-027-03) : la demande de Kevin encore en attente
// à H signifie que la recherche d'Eliot n'était pas résolue à H-3 et qu'aucun
// traitement n'a réussi entre H-3 et H (le Swend est déplacé d'un coup après
// H) ; à la reprise, le gel applique d'abord l'échéance : Swend annulé, jamais
// figé, demande close, push d'annulation, chat d'annulation, conversations
// conservées (règles habituelles), jamais de chat après le Swend.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES, appelerComme, lireComme, insererComme, baseAvecEcheanceH3 } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

const pushDepuis = (n0) => sql(`select coalesce(string_agg(p.prenom || '|' || n.titre || '|' || n.corps, ' ## ' order by n.id), '')
  from notifications_log n left join profiles p on p.id = n.profile_id where n.id > ${n0}`);
const n0 = () => sql('select coalesce(max(id), 0) from notifications_log');
const champSaisie = (a) => a.page.getByRole('textbox', { name: 'Écrire un message…' }).count();

export default {
  nom: 'gel_a_h',
  titre: 'Gel à H : action refusée à H, plus d\'imprévu, demande close, conversations figées',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const pacte = sql('select id from pactes');

    await ex.etape('Avant H : Eliot demande à Kevin et écrit à Sylvain', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await ex.verifier('demande envoyée à Kevin', () => demande(FICHES.kevin) === 'envoyee|f');
      await A.ouvrirConversationTitulaire(eliot, 'Sylvain Landiech');
      await A.envoyerMessage(eliot, 'Tu es dispo le 13 ?');
      const d = await appelerComme('eliot', 'destination_rappel', { p_pacte_id: pacte });
      await ex.verifier('rappel cliqué avant H : « Un imprévu ? »', () => d.corps.includes('imprevu'), { obtenu: () => d.corps });
      await kevin.accueil();
      await kevin.cliquer('Répondre à la demande');
      await kevin.cliquer('Voir la demande et répondre');
      await kevin.attendreTexte('Accepter');
      await ex.verifier('avant H : Kevin (sollicité) peut appeler Eliot (bouton « Appeler »)',
        async () => (await kevin.nombreDeBoutons('Appeler')) === 1);
      const t = await appelerComme('kevin', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.kevin });
      await ex.verifier('avant H : API → numéro d\'Eliot', () => t.ok && t.corps.includes('06 01 02 03 04'), { obtenu: () => t.corps });
    });

    await ex.etape('H passe pendant que Kevin regarde la demande : refus propre', async () => {
      sql(`select qa.deplacer_swend(id, now() - interval '1 minute') from pactes`);
      await A.validerReponse(kevin, true);
      await ex.verifierTexte(kevin, 'L’heure du Swend est passée : cette action n’est plus possible.', 'Kevin : message propre (swend_passe)');
      await ex.verifier('Kevin n\'a pas pris la place', () => demande(FICHES.kevin) === 'envoyee|f', { obtenu: () => demande(FICHES.kevin) });
      await ex.verifier('Kevin : plus de bouton Accepter / Refuser', async () =>
        (await kevin.nombreDeBoutons('Accepter')) === 0 && (await kevin.nombreDeBoutons('Refuser')) === 0);
      // Seulement sollicité : après H, il n'a plus accès à la conversation.
      await ex.verifierTexte(kevin, "Cette conversation n'est plus accessible.", 'Kevin : conversation plus accessible');
      await ex.verifier('Kevin : aucune zone de saisie',
        async () => (await kevin.page.getByRole('textbox', { name: 'Écrire un message…' }).count()) === 0);
      await ex.verifier('Kevin : plus de bouton « Appeler »', async () => (await kevin.nombreDeBoutons('Appeler')) === 0);
      const t = await appelerComme('kevin', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.kevin });
      await ex.verifier('après H : API → aucun numéro', () => t.ok && !t.corps.includes('06'), { obtenu: () => t.corps });
      const ancien = await appelerComme('kevin', 'telephone_titulaire_du_pacte', { p_remplacant_id: FICHES.kevin });
      await ex.verifier('ancienne fonction : refusée à l\'app', () => !ancien.ok, { obtenu: () => `${ancien.statut} ${ancien.corps}` });
    });

    await ex.etape('Kevin : plus rien d\'actif (Home, Mes Swends, API)', async () => {
      await kevin.accueil();
      await ex.verifierAbsent(kevin, "UNE DEMANDE T'ATTEND", 'Kevin : plus de « Une demande t\'attend »');
      await ex.verifierAbsent(kevin, 'ON COMPTE SUR TOI', 'Kevin : plus de « On compte sur toi »');
      await A.ouvrirMesSwends(kevin);
      await ex.verifierAbsent(kevin, /Swend d'Eliot avec David/, 'Kevin (seulement sollicité) : Swend absent de Mes Swends');
      const r = await appelerComme('kevin', 'repondre_demande_remplacement', { p_remplacant_id: FICHES.kevin, p_accepte: false });
      await ex.verifier('API : refuser après H → swend_passe', () => !r.ok && r.corps.includes('swend_passe'), { obtenu: () => r.corps });
      const [sw, fi] = [await lireComme('kevin', 'pactes', 'select=id'), await lireComme('kevin', 'remplacants')];
      await ex.verifier('API : Kevin (sollicité) ne lit plus ni le Swend ni sa fiche', () => sw.length === 0 && fi.length === 0,
        { obtenu: () => `${sw.length} Swend, ${fi.length} fiche` });
    });

    await ex.etape('Eliot : Swend passé, plus aucune action d\'imprévu', async () => {
      await eliot.accueil();
      await ex.verifierTexte(eliot, /Mes Swends\s+0 à venir/, 'Eliot : « 0 à venir »');
      await A.ouvrirMesSwends(eliot);
      await ex.verifierTexte(eliot, 'Passés et annulés', 'Eliot : section « Passés et annulés »');
      await ex.verifierAbsent(eliot, 'À venir', 'Eliot : aucune section « À venir »');
      await A.ouvrirSwend(eliot, /Swend avec David/);
      for (const b of ['Un imprévu ?', 'Modifier ma liste', 'Discuter', 'Annuler le Swend']) {
        await ex.verifier(`Eliot : pas de bouton « ${b} »`, async () => (await eliot.nombreDeBoutons(b)) === 0);
      }
      await ex.verifierTexte(eliot, 'Relire une conversation', 'Eliot : « Relire une conversation »');
      await ex.verifier('statut toujours « confirme » en base', () => sql('select statut from pactes') === 'confirme');
      const d = await appelerComme('eliot', 'destination_rappel', { p_pacte_id: pacte });
      await ex.verifier('ancien rappel cliqué après H : fiche (plus « Un imprévu ? »)', () => d.corps.includes('fiche'), { obtenu: () => d.corps });
      for (const [f, id] of [['envoyer_demande_remplacement', FICHES.sylvain], ['retirer_remplacant', FICHES.tom], ['annuler_swend', null]]) {
        const r = await appelerComme('eliot', f, id ? { p_remplacant_id: id } : { p_pacte_id: pacte });
        await ex.verifier(`API : ${f} après H → swend_passe`, () => !r.ok && r.corps.includes('swend_passe'), { obtenu: () => r.corps });
      }
    });

    if (baseAvecEcheanceH3()) {
      await ex.etape('Reprise du gel après H (aucun traitement entre H-3 et H) : l’échéance d’abord, Swend annulé', async () => {
        const avant = n0();
        sql('select figer_swends_passes()');
        const etat = () => sql(`select statut || '|' || coalesce(annule_motif, '-') || '|' || (select count(*) from swends_figes) from pactes`);
        await ex.verifier('Swend annulé (echeance_h3), jamais figé', () => etat() === 'annule|echeance_h3|0', { obtenu: etat });
        await ex.verifier('demande de Kevin close', () => demande(FICHES.kevin) === 'cloturee|f', { obtenu: () => demande(FICHES.kevin) });
        await ex.verifier('push de l’annulation, une par personne, jamais « La demande n’est plus d’actualité »',
          () => pushDepuis(avant) === 'Eliot|Le Swend est annulé|Personne n’a pu prendre ta place à temps. ## '
            + 'David|Le Swend est annulé|Eliot ne pourra finalement pas être là. ## Kevin|Le Swend est annulé|Tu n’as plus besoin de répondre.',
          { obtenu: () => pushDepuis(avant) });
        const apres = n0();
        sql(`insert into chat_apres_swend_service (id, mise_en_service) values (true, now() - interval '30 days')
             on conflict (id) do update set mise_en_service = excluded.mise_en_service`);
        sql('select figer_swends_passes()');
        sql('select appliquer_echeances_h3()');
        sql(`select ouvrir_chats_apres_swend(ouverture_chat_apres_swend((select date_retenue from pactes)) + interval '1 minute')`);
        const chats = () => sql(`select coalesce(string_agg(nature, ','), '') from chats_apres_swend`);
        await ex.verifier('traitements suivants (gel, échéance, chat après le Swend) : aucun doublon, seul le chat d’annulation, aucun événement de fin',
          () => pushDepuis(apres) === '' && chats() === 'annulation'
            && sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '0',
          { obtenu: () => `${pushDepuis(apres)} / ${chats()}` });
      });

      await ex.etape('Après l’annulation : écrans et conversations conservées', async () => {
        await A.ouvrirSwend(eliot, /Swend avec David/);
        await ex.verifierTexte(eliot, 'Ton Swend avec David est annulé.', 'Eliot : « Ton Swend avec David est annulé. »');
        const david = await ex.david();
        await A.ouvrirSwend(david, /Swend avec Eliot/);
        await ex.verifierTexte(david, 'Ton Swend avec Eliot est annulé.', 'David : « Ton Swend avec Eliot est annulé. »');
        await ex.verifierAbsent(david, /Kevin|Sylvain|Tom/, 'David : aucune personne de confiance d’Eliot');
        // Kevin avait perdu l'accès à H : nouvelle session pour relire sa liste.
        const k2 = await ex.redemarrer('kevin');
        await A.ouvrirSwend(k2, /Swend d'Eliot avec David/);
        await ex.verifierTexte(k2, 'Ce Swend a été annulé.', 'Kevin : « Ce Swend a été annulé. » (conversation conservée, P1)');
        const r = await insererComme('kevin', 'messages', { remplacant_id: FICHES.kevin, expediteur_id: COMPTES.kevin.id, contenu: 'Dommage' });
        await ex.verifier('conversation Eliot–Kevin conservée et écrivable (D-027, P1)', () => r.ok, { obtenu: () => `${r.statut} ${r.corps}` });
        const s2 = await insererComme('eliot', 'messages', { remplacant_id: FICHES.sylvain, expediteur_id: COMPTES.eliot.id, contenu: 'Finalement annulé' });
        await ex.verifier('conversation Eliot–Sylvain (messages échangés) conservée et écrivable', () => s2.ok, { obtenu: () => `${s2.statut} ${s2.corps}` });
      });
      return;
    }

    await ex.etape('Moteur à H : demande close, Kevin prévenu une seule fois', async () => {
      const avant = n0();
      sql('select figer_swends_passes()');
      await ex.verifier('demande de Kevin clôturée', () => demande(FICHES.kevin) === 'cloturee|f', { obtenu: () => demande(FICHES.kevin) });
      await ex.verifier('une seule push : Kevin, texte validé',
        () => pushDepuis(avant) === 'Kevin|La demande n’est plus d’actualité|L’heure du Swend est passée.', { obtenu: () => pushDepuis(avant) });
      const apres = n0();
      sql('select figer_swends_passes()');
      await ex.verifier('moteur rejoué : aucun doublon', () => pushDepuis(apres) === ''
        && sql(`select count(*) from evenements_fil where code = 'swend_commence'`) === '2',
        { obtenu: () => sql(`select count(*) from evenements_fil where code = 'swend_commence'`) });
    });

    await ex.etape('Conversations figées : lisibles, sans saisie, événement de fin', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Relire une conversation');
      await ex.verifierTexte(eliot, 'Relire la conversation avec…', 'Eliot : choix entre les conversations actives');
      await ex.verifierAbsent(eliot, 'Tom Petit', 'Eliot : fil vierge (Tom) non proposé');
      await eliot.cliquerTexte('Kevin Arner');
      await eliot.attendreTexte('Cette conversation est terminée. Elle reste consultable.');
      await ex.verifierTexte(eliot, "La demande à Kevin n'est plus d'actualité.", 'Eliot : clôture dans le fil de Kevin');
      await ex.verifierTexte(eliot, /Le Swend a commencé\.\s+Cette conversation est désormais terminée\./, 'Eliot : événement de fin');
      await ex.verifier('Eliot : plus de zone de saisie', async () => (await champSaisie(eliot)) === 0);
      await eliot.retour();
      await eliot.cliquer('Relire une conversation');
      await eliot.cliquerTexte('Sylvain Landiech');
      await eliot.attendreTexte('Tu es dispo le 13 ?');
      await ex.verifierTexte(eliot, /Le Swend a commencé\./, 'Eliot : événement de fin aussi chez Sylvain (fil avec un message)');
      const r = await insererComme('eliot', 'messages', { remplacant_id: FICHES.sylvain, expediteur_id: COMPTES.eliot.id, contenu: 'Et après ?' });
      await ex.verifier('API : écrire après H → refusé', () => !r.ok, { obtenu: () => `${r.statut} ${r.corps}` });
      await ex.verifier('fil vierge (Tom) : aucun événement créé',
        () => sql(`select count(*) from evenements_fil where remplacant_id = '${FICHES.tom}'`) === '0');
    });

    await ex.etape('Aucune box non lue ; David ne voit rien', async () => {
      await eliot.accueil();
      await ex.verifierAbsent(eliot, /t’a écrit|vous a écrit|Le Swend a commencé|n'est plus d'actualité/, 'Eliot : aucune box');
      await kevin.accueil();
      await ex.verifierAbsent(kevin, /t’a écrit|vous a écrit|Le Swend a commencé|n'est plus d'actualité/, 'Kevin : aucune box');
      await ex.verifier('David : aucune push', () => sql(`select count(*) from notifications_log where profile_id = '${COMPTES.david.id}'`) === '0');
      const evts = await lireComme('david', 'evenements_fil');
      const msgs = await lireComme('david', 'messages');
      await ex.verifier('David : aucun événement ni message lisible (API)', () => evts.length === 0 && msgs.length === 0,
        { obtenu: () => `${evts.length} événements, ${msgs.length} messages` });
    });
  },
};
