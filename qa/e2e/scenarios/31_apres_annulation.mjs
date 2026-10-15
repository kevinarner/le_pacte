// D-027 lot 3b — APRÈS L'ANNULATION, À L'ÉCRAN, SUR LES DEUX BASES.
// Eliot sollicite Kevin (ils échangent) ; Sylvain et Tom sont seulement
// prévus. David annule (le parcours d'annulation est testé dans 19 et 20).
// Base avec D-027-02 :
//  - chat d'annulation entre Eliot et David (« Après l'annulation »,
//    « Discuter », « Faire un nouveau Swend »), jamais « Alors, ce Swend ? »,
//    push « Swend annulé · » pour un message ;
//  - conversation d'Eliot et Kevin conservée et écrivable des deux côtés
//    (« Reprendre une conversation », « Écrire à Eliot ») ; Sylvain,
//    seulement prévu, ne gagne aucun accès (P1) ; aucun numéro (D-024) ;
//  - un nouveau Swend scellé entre Eliot et Kevin ferme leur conversation
//    (P2) : « Un nouveau Swend a été scellé entre vous. », lecture seule.
// Base sans D-027-02 (production actuelle) : relecture seule pour Eliot,
// aucun chat d'annulation, Kevin (non sélectionné) n'a plus le Swend, et
// l'app fonctionne sans erreur. David ne voit rien des coulisses.
import * as A from '../lib/actions.mjs';
import { sql, lireComme, appelerComme, insererComme, FICHES, baseAvecLot2 } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

const champSaisie = (a) => a.page.getByRole('textbox', { name: 'Écrire un message…' }).count();
const messagesDe = (nom) => sql(`select count(*) from messages where expediteur_id = '${COMPTES[nom].id}'`);
const derniereNotif = (nom) => sql(`select coalesce((select titre || '|' || corps from notifications_log
  where profile_id = '${COMPTES[nom].id}' order by id desc limit 1), '')`);

export default {
  nom: 'apres_annulation',
  titre: 'Après l’annulation : chat entre titulaires, conversations conservées (P1), fermées par un nouveau Swend (P2), base sans D-027-02',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const david = await ex.david();
    const lot2 = baseAvecLot2();

    await ex.etape('Eliot sollicite Kevin, ils échangent ; Sylvain et Tom seulement prévus', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await A.envoyerMessage(eliot, 'Tu pourrais me remplacer ?');
    });

    await ex.etape('David annule le Swend', async () => {
      const r = await appelerComme('david', 'annuler_swend', { p_pacte_id: sql('select id from pactes') });
      await ex.verifier('Swend annulé', () => r.ok && sql('select statut from pactes') === 'annule', { obtenu: () => `${r.statut} ${r.corps}` });
    });

    await ex.etape('Eliot : fiche du Swend annulé', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Ton Swend avec David est annulé.', 'Eliot : « Ton Swend avec David est annulé. »');
      await ex.verifierAbsent(eliot, 'APRÈS LE SWEND', 'Eliot : jamais de bloc « Après le Swend »');
      await ex.verifier('Eliot : ni « Un imprévu ? » ni « Annuler le Swend »', async () =>
        (await eliot.nombreDeBoutons('Un imprévu ?')) === 0 && (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
      if (lot2) {
        await ex.verifierTexte(eliot, 'APRÈS L’ANNULATION', 'Eliot : bloc « Après l’annulation »');
        await ex.verifierTexte(eliot, 'Avec David', 'Eliot : « Avec David »');
        await ex.verifier('Eliot : « Discuter » puis « Faire un nouveau Swend »', async () =>
          (await eliot.nombreDeBoutons('Discuter')) === 1 && (await eliot.nombreDeBoutons('Faire un nouveau Swend')) === 1);
        await ex.verifierTexte(eliot, 'Reprendre une conversation', 'Eliot : « Reprendre une conversation »');
      } else {
        await ex.verifierAbsent(eliot, 'APRÈS L’ANNULATION', 'Eliot : pas de chat d’annulation (base sans D-027-02)');
        await ex.verifierTexte(eliot, 'Relire une conversation', 'Eliot : « Relire une conversation »');
      }
      await eliot.accueil();
      await ex.verifierAbsent(eliot, 'Alors, ce Swend ?', 'Eliot : jamais « Alors, ce Swend ? »');
    });

    if (lot2) {
      await ex.etape('Chat d’annulation : textes propres, message de David notifié « Swend annulé · »', async () => {
        await A.ouvrirSwend(eliot, /Swend avec David/);
        await eliot.cliquer('Discuter');
        await eliot.attendreTexte('Vous pouvez en reparler ici.');
        await ex.verifierTexte(eliot, 'Swend annulé', 'chat : sous-titre « Swend annulé »');
        await ex.verifierAbsent(eliot, 'À vous de débriefer.', 'chat : pas le texte du chat après le Swend');
        await eliot.accueil(); // chat quitté : le message de David reste non lu
        const chat = sql(`select id from chats_apres_swend where nature = 'annulation'`);
        const r = await appelerComme('david', 'envoyer_message_apres_swend', { p_chat_id: chat, p_contenu: 'Une autre fois ?' });
        await ex.verifier('push à Eliot : « David t’a écrit » / « Swend annulé · Au père Lapin »',
          () => r.ok && derniereNotif('eliot') === 'David t’a écrit|Swend annulé · Au père Lapin', { obtenu: () => `${r.corps} ${derniereNotif('eliot')}` });
        await eliot.accueil();
        await ex.verifierTexte(eliot, 'David t’a écrit', 'Eliot : carte « David t’a écrit »');
        // Swend annulé : l'app ne garde pas le restaurant retenu (date seulement).
        await ex.verifierTexte(eliot, /David t’a écrit\s+Swend annulé · \d+ /, 'Eliot : carte « Swend annulé · <date> »');
        await eliot.cliquerTexte('David t’a écrit');
        await eliot.attendreTexte('Une autre fois ?');
      });

      await ex.etape('Eliot reprend sa conversation avec Kevin (conservée, écrivable)', async () => {
        await A.ouvrirSwend(eliot, /Swend avec David/);
        await eliot.cliquer('Reprendre une conversation');
        await eliot.attendreTexte('Tu pourrais me remplacer ?');
        await ex.verifierAbsent(eliot, 'Cette conversation est terminée', 'Eliot : pas de bandeau de fin');
        await A.envoyerMessage(eliot, 'Finalement c’est annulé, merci quand même');
        await ex.verifier('message d’Eliot enregistré', () => messagesDe('eliot') === '2', { obtenu: () => messagesDe('eliot') });
      });

      await ex.etape('Kevin (sollicité, non sélectionné) : Swend annulé, conversation écrivable, sans numéro', async () => {
        await A.ouvrirSwend(kevin, /Swend d'Eliot avec David/);
        await ex.verifierTexte(kevin, 'Ce Swend a été annulé.', 'Kevin : « Ce Swend a été annulé. »');
        await ex.verifierAbsent(kevin, 'Tu n’auras finalement pas besoin', 'Kevin : pas le texte du remplaçant sélectionné');
        await ex.verifierAbsent(kevin, /Sylvain|Tom/, 'Kevin : aucune autre personne de confiance');
        await kevin.cliquer('Écrire à Eliot', { exact: false });
        await kevin.attendreTexte('Finalement c’est annulé, merci quand même');
        await A.envoyerMessage(kevin, 'Pas de souci');
        await ex.verifier('message de Kevin enregistré', () => messagesDe('kevin') === '1', { obtenu: () => messagesDe('kevin') });
        const t = await appelerComme('kevin', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.kevin });
        await ex.verifier('API : aucun numéro d’Eliot pour Kevin (D-024)', () => t.ok && !t.corps.includes('06'), { obtenu: () => t.corps });
      });

      await ex.etape('Sylvain, seulement prévu, ne gagne aucun accès (P1)', async () => {
        const [p, f] = [await lireComme('sylvain', 'pactes', 'select=id'), await lireComme('sylvain', 'remplacants')];
        await ex.verifier('API : Sylvain ne lit ni le Swend ni sa fiche', () => p.length === 0 && f.length === 0, { obtenu: () => `${p.length}/${f.length}` });
        const sylvain = await ex.sylvain();
        await A.ouvrirMesSwends(sylvain);
        await ex.verifierAbsent(sylvain, /Swend d'Eliot/, 'Sylvain : aucun Swend d’Eliot');
      });

      await ex.etape('Nouveau Swend scellé entre Eliot et Kevin : leur conversation se ferme (P2)', async () => {
        sql(`insert into pactes (statut, type, date_retenue, dates_proposees, restaurant_id, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone)
             values ('confirme', 'diner', now() + interval '50 days', to_jsonb(array[now() + interval '50 days']), (select id from restaurants limit 1),
                     '${COMPTES.eliot.id}', 'Eliot Martin', '${COMPTES.kevin.id}', 'Kevin Arner', '${COMPTES.kevin.tel}')`);
        await ex.verifier('événement fil_ferme sur la conversation de Kevin',
          () => sql(`select count(*) from evenements_fil where code = 'fil_ferme' and remplacant_id = '${FICHES.kevin}'`) === '1');
        await A.ouvrirSwend(kevin, /Swend d'Eliot avec David/);
        await kevin.cliquer('Relire la conversation');
        await kevin.attendreTexte('Pas de souci');
        await ex.verifierTexte(kevin, 'Un nouveau Swend a été scellé entre vous.', 'Kevin : « Un nouveau Swend a été scellé entre vous. »');
        await ex.verifierTexte(kevin, 'Cette conversation est fermée. Elle reste consultable.', 'Kevin : bandeau « fermée »');
        await ex.verifier('Kevin : aucune zone de saisie', async () => (await champSaisie(kevin)) === 0);
        await A.ouvrirSwend(eliot, /Swend avec David/);
        await ex.verifierTexte(eliot, 'Relire une conversation', 'Eliot : de nouveau « Relire une conversation »');
        const r = await insererComme('kevin', 'messages', { remplacant_id: FICHES.kevin, expediteur_id: COMPTES.kevin.id, contenu: 'Encore là ?' });
        await ex.verifier('API : écriture de Kevin refusée', () => !r.ok, { obtenu: () => `${r.statut} ${r.corps}` });
        await ex.verifier('chat d’annulation Eliot–David toujours ouvert', () => sql(`select ferme_le is null from chats_apres_swend where nature = 'annulation'`) === 't');
      });
    } else {
      await ex.etape('Base sans D-027-02 : relecture seule, Kevin n’a plus le Swend', async () => {
        await A.ouvrirSwend(eliot, /Swend avec David/);
        await eliot.cliquer('Relire une conversation');
        await eliot.attendreTexte('Tu pourrais me remplacer ?');
        await ex.verifierTexte(eliot, 'Cette conversation est terminée. Elle reste consultable.', 'Eliot : lecture seule');
        await ex.verifier('Eliot : aucune zone de saisie', async () => (await champSaisie(eliot)) === 0);
        const p = await lireComme('kevin', 'pactes', 'select=id');
        await ex.verifier('API : Kevin (non sélectionné) ne lit plus le Swend (règle D-023a)', () => p.length === 0, { obtenu: () => `${p.length}` });
        await A.ouvrirMesSwends(kevin);
        await ex.verifierAbsent(kevin, /Swend d'Eliot avec David/, 'Kevin : Swend absent de Mes Swends');
        await ex.verifier('aucun chat d’annulation', () => sql('select count(*) from chats_apres_swend') === '0');
      });
    }

    await ex.etape('David ne voit rien des coulisses', async () => {
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierTexte(david, 'Ton Swend avec Eliot est annulé.', 'David : « Ton Swend avec Eliot est annulé. »');
      await ex.verifierAbsent(david, /Kevin|Sylvain|Tom/, 'David : aucune personne de confiance d’Eliot');
      const [m, e] = [await lireComme('david', 'messages'), await lireComme('david', 'evenements_fil')];
      await ex.verifier('API : David ne lit aucun message ni événement', () => m.length === 0 && e.length === 0, { obtenu: () => `${m.length}/${e.length}` });
    });
  },
};
