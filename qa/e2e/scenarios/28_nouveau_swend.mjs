// D-023c — FAIRE UN NOUVEAU SWEND ET FERMETURE DU CHAT APRÈS LE SWEND.
//  - chat à 2 : « Discuter » puis « Faire un nouveau Swend » ; « Avec qui ? »
//    sauté, aucun numéro reçu (D-024) ; « Un Swend est déjà en cours entre
//    vous. » ; au scellement, chat fermé (message système unique, aucune
//    push) ; fiche « Voir la conversation » / « Conversation fermée » ;
//    annulation juste après : rien ne rouvre ;
//  - création depuis l'accueil puis scellement : même fermeture ;
//  - chat à 3 : choix entre les deux autres personnes, Swend en cours avec
//    une seule (sa carte désactivée, refus serveur) ; scellement
//    remplaçant ↔ titulaire : fermeture ;
//  - chat pas encore ouvert : un nouveau Swend scellé avant l'heure
//    d'ouverture → le chat ne s'ouvre jamais, la fiche reste consultable.
import * as A from '../lib/actions.mjs';
import { sql, FICHES, appelerComme, insererComme, chargerFixture } from '../lib/donnees.mjs';
import { COMPTES, CONTACTS_SANS_COMPTE as C } from '../lib/config.mjs';
import { numerosNonAutorises } from '../lib/numeros.mjs';

const SYSTEME = 'Un nouveau Swend a été scellé.\nCe chat est désormais fermé pour préserver le silence.';
const SYSTEME_UNE_LIGNE = 'Un nouveau Swend a été scellé. Ce chat est désormais fermé pour préserver le silence.';
const n0 = () => sql('select coalesce(max(id), 0) from notifications_log');
// Moteur d'ouverture à l'heure d'ouverture du Swend passé (figé) + décalage.
const moteur = (decalage) => sql(`select ouvrir_chats_apres_swend(ouverture_chat_apres_swend(p.date_retenue) + interval '${decalage}')
  from pactes p join swends_figes f on f.pacte_id = p.id`);
const chatId = () => sql('select coalesce(max(id::text), \'\') from chats_apres_swend');
const etatChat = () => sql(`select coalesce((select case when ferme_le is null then 'ouvert' else 'ferme:' || motif_fermeture end
  || '|systeme=' || (select count(*) from messages_apres_swend m where m.chat_id = c.id and m.genre = 'systeme')
  || '|messages=' || (select count(*) from messages_apres_swend m where m.chat_id = c.id) from chats_apres_swend c), 'aucun')`);
const pushChat = (n) => sql(`select count(*) from notifications_log where id > ${n}
  and (data->>'type' = 'chat_apres_swend' or data ? 'chat_id')`);
const restaurant = () => sql('select id from restaurants limit 1');
const instant = (n, h = '20:00') =>
  sql(`select to_json((((now() at time zone 'Europe/Paris')::date + ${n}) + time '${h}') at time zone 'Europe/Paris') #>> '{}'`);
const nouveauEntre = (a, b) => sql(`select coalesce((select id::text from pactes where
  ((initiateur_id = '${COMPTES[a].id}' and destinataire_id = '${COMPTES[b].id}') or (initiateur_id = '${COMPTES[b].id}' and destinataire_id = '${COMPTES[a].id}'))
  and not exists (select 1 from swends_figes f where f.pacte_id = pactes.id) order by created_at desc limit 1), '')`);
const participant = (nom) => sql(`select id from participants_chat_apres_swend where profil_id = '${COMPTES[nom].id}'`);

// Swend de la fixture passé (il y a [age]) et figé ; mise en service du chat
// avant (la fixture vide toutes les tables).
function swendPasseEtFige(age = '2 days') {
  sql(`select qa.deplacer_swend(id, now() - interval '${age}') from pactes`);
  sql(`insert into chat_apres_swend_service (id, mise_en_service) values (true, now() - interval '30 days')
       on conflict (id) do update set mise_en_service = excluded.mise_en_service`);
  sql('select figer_swends_passes()');
}
// La carte du Swend passé dans Mes Swends (celle qui porte la ligne du chat,
// ou la dernière s'il n'y en a pas).
async function ouvrirSwendPasse(a, motif) {
  await A.ouvrirMesSwends(a);
  const cartes = a.page.getByRole('button', { name: motif });
  await cartes.first().waitFor({ timeout: 15000 });
  await cartes.last().click();
  await a.attendreCalme();
}
async function verifierFermeSurFiche(ex, a, motif) {
  await ouvrirSwendPasse(a, motif);
  await ex.verifierTexte(a, 'Voir la conversation', `${a.compte.prenom} : « Voir la conversation »`);
  await ex.verifierTexte(a, 'Conversation fermée', `${a.compte.prenom} : « Conversation fermée »`);
  await ex.verifierTexte(a, SYSTEME_UNE_LIGNE, `${a.compte.prenom} : texte de fermeture sur la fiche`);
  await ex.verifierAbsent(a, 'Faire un nouveau Swend', `${a.compte.prenom} : plus de « Faire un nouveau Swend »`);
  await ex.verifierAbsent(a, 'Discuter', `${a.compte.prenom} : plus de « Discuter »`);
}

export default {
  nom: 'nouveau_swend',
  titre: 'D-023c : « Faire un nouveau Swend », fermeture du chat au scellement, chat à 3, chat jamais ouvert',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();

    await ex.etape('Chat à 2 ouvert : « Discuter » puis « Faire un nouveau Swend »', async () => {
      swendPasseEtFige();
      moteur('0 minute');
      await ex.verifier('chat ouvert entre Eliot et David', () => etatChat() === 'ouvert|systeme=0|messages=0', { obtenu: etatChat });
      await ouvrirSwendPasse(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Discuter', 'Eliot : « Discuter »');
      await ex.verifierTexte(eliot, 'Faire un nouveau Swend', 'Eliot : « Faire un nouveau Swend »');
      const b1 = await eliot.page.getByRole('button', { name: /Discuter|David vous a écrit/ }).first().boundingBox();
      const b2 = await eliot.page.getByRole('button', { name: 'Faire un nouveau Swend' }).boundingBox();
      await ex.verifier('« Faire un nouveau Swend » sous l\'accès au chat', () => b1 && b2 && b2.y > b1.y);
      // Un message, pour l'historique conservé à la fermeture.
      await appelerComme('david', 'envoyer_message_apres_swend', { p_chat_id: chatId(), p_contenu: 'Merci pour la soirée !' });
      await ouvrirSwendPasse(eliot, /Swend avec David/);
      await eliot.attendreTexte('David vous a écrit');
    });

    await ex.etape('« Avec qui ? » sauté : directement « Quand et où ? » avec David, puis envoi', async () => {
      await eliot.cliquer('Faire un nouveau Swend');
      await eliot.attendreTexte('Quand et où ?');
      await ex.verifierAbsent(eliot, 'Avec qui ?', 'Eliot : pas d\'étape « Avec qui ? »');
      await ex.verifierAbsent(eliot, 'Numéro de mobile', 'Eliot : aucun numéro demandé');
      await ex.verifierTexte(eliot, 'Swend avec David', 'Eliot : « Swend avec David »');
      await ex.verifierTexte(eliot, 'Étape 1 sur 2', 'Eliot : « Étape 1 sur 2 »');
      await eliot.cliquer('Ajouter une date');
      await eliot.cliquer('OK');
      await eliot.cliquer('Suivant');
      await A.remplirPersonnes(eliot, [C.tom, C.nina]);
      await eliot.cliquer('Envoyer le Swend');
      await eliot.attendreTexte('APRÈS LE SWEND');
      const id = nouveauEntre('eliot', 'david');
      await ex.verifier('Swend créé : Eliot → David (retrouvé par la base), en attente, D-025 posée, 2 personnes de confiance',
        () => id !== '' && sql(`select statut || '|' || (destinataire_id = '${COMPTES.david.id}') || '|' || (date_minimale is not null)
          || '|' || (select count(*) from remplacants r where r.pacte_id = p.id and r.cote = 'initiateur') from pactes p where id = '${id}'`)
          === 'enAttenteChoixDateDestinataire|true|true|2',
        { obtenu: () => sql(`select row_to_json(p)::text from pactes p where id = '${id || '00000000-0000-0000-0000-000000000000'}'`) });
      await ex.verifier('une invitation ne ferme rien', () => etatChat() === 'ouvert|systeme=0|messages=1', { obtenu: etatChat });
      await ex.verifier('Eliot n\'a reçu aucun numéro de David (D-024)',
        () => numerosNonAutorises(eliot, { eliot: true, kevin: true, sylvain: true, tom: true, nina: true }).length === 0,
        { obtenu: () => numerosNonAutorises(eliot, { eliot: true, kevin: true, sylvain: true, tom: true, nina: true }).join(' | ') });
    });

    await ex.etape('Swend déjà en cours entre eux : message, refus serveur', async () => {
      await eliot.cliquer('Faire un nouveau Swend');
      await ex.verifierTexte(eliot, 'Un Swend est déjà en cours entre vous.', 'Eliot : « Un Swend est déjà en cours entre vous. »');
      await ex.verifierAbsent(eliot, 'Quand et où ?', 'Eliot : pas de création');
      const r = await appelerComme('david', 'creer_swend_depuis_chat', {
        p_chat_id: chatId(), p_participant_id: participant('eliot'), p_type: 'diner',
        p_dates_proposees: [instant(20)], p_restaurant_id: restaurant(), p_remplacants: [],
      });
      await ex.verifier('API : David ne peut pas en créer un second (swend_deja_en_cours)',
        () => !r.ok && r.corps.includes('swend_deja_en_cours'), { obtenu: () => r.corps });
    });

    await ex.etape('David accepte : scellé → chat fermé, un message système, aucune push', async () => {
      const n = n0();
      await A.accepterSwend(david, { avec: /Swend avec Eliot/, personnes: [C.leo, C.nina] });
      await ex.verifier('nouveau Swend scellé', () => sql(`select scelle_le is not null from pactes where id = '${nouveauEntre('eliot', 'david')}'`) === 't');
      await ex.verifier('chat fermé (nouveau_swend), un seul message système, historique conservé',
        () => etatChat() === 'ferme:nouveau_swend|systeme=1|messages=2', { obtenu: etatChat });
      await ex.verifier('texte exact du message système',
        () => sql(`select contenu from messages_apres_swend where genre = 'systeme'`) === SYSTEME);
      await ex.verifier('aucune push de fermeture', () => pushChat(n) === '0', { obtenu: () => pushChat(n) });
      await verifierFermeSurFiche(ex, eliot, /Swend avec David/);
      await verifierFermeSurFiche(ex, david, /Swend avec Eliot/);
    });

    await ex.etape('Conversation fermée : historique lisible, message système, aucune saisie', async () => {
      await eliot.cliquer('Voir la conversation');
      await eliot.attendreTexte('Merci pour la soirée !');
      await ex.verifierTexte(eliot, 'Un nouveau Swend a été scellé.', 'message système dans le fil');
      await ex.verifierTexte(eliot, 'Conversation fermée', 'état « Conversation fermée » à la place de la saisie');
      await ex.verifier('aucune zone de saisie',
        async () => (await eliot.page.getByRole('textbox', { name: 'Écrire un message…' }).count()) === 0);
      const r = await appelerComme('eliot', 'envoyer_message_apres_swend', { p_chat_id: chatId(), p_contenu: 'encore ?' });
      await ex.verifier('API : écriture refusée (chat_ferme)', () => !r.ok && r.corps.includes('chat_ferme'), { obtenu: () => r.corps });
      await A.ouvrirMesSwends(eliot);
      await ex.verifierTexte(eliot, 'Voir la conversation', 'Mes Swends : « Voir la conversation » (pas de statut lourd)');
      await ex.verifierAbsent(eliot, 'Conversation terminée', 'Mes Swends : pas de « Conversation terminée »');
    });

    await ex.etape('Annulation du nouveau Swend juste après : rien ne rouvre, aucun message', async () => {
      const r = await appelerComme('eliot', 'annuler_swend', { p_pacte_id: nouveauEntre('eliot', 'david') });
      await ex.verifier('nouveau Swend annulé', () => r.ok && sql(`select statut from pactes where id = '${nouveauEntre('eliot', 'david')}'`) === 'annule',
        { obtenu: () => r.corps });
      await ex.verifier('chat toujours fermé, toujours un seul message système, rien ajouté',
        () => etatChat() === 'ferme:nouveau_swend|systeme=1|messages=2', { obtenu: etatChat });
      const e2 = await ex.redemarrer('eliot');
      await verifierFermeSurFiche(ex, e2, /Swend avec David[\s\S]*Voir la conversation/);
    });

    await ex.etape('Création depuis l\'accueil (« Créer un Swend »), puis scellement : même fermeture', async () => {
      chargerFixture('scelle');
      swendPasseEtFige();
      moteur('0 minute');
      await ex.verifier('chat ouvert', () => etatChat() === 'ouvert|systeme=0|messages=0', { obtenu: etatChat });
      const e3 = await ex.redemarrer('eliot');
      await A.creerSwend(e3, { prenom: 'David', nom: 'Schlang', tel: COMPTES.david.tel, personnes: [C.tom, C.nina] });
      await ex.verifier('invitation depuis l\'accueil : rien ne ferme', () => etatChat() === 'ouvert|systeme=0|messages=0', { obtenu: etatChat });
      const n = n0();
      const d2 = await ex.redemarrer('david');
      await A.accepterSwend(d2, { avec: /Swend avec Eliot/, personnes: [C.leo, C.nina] });
      await ex.verifier('scellé depuis l\'accueil : chat fermé, un message système', () => etatChat() === 'ferme:nouveau_swend|systeme=1|messages=1',
        { obtenu: etatChat });
      await ex.verifier('aucune push de fermeture', () => pushChat(n) === '0', { obtenu: () => pushChat(n) });
      await verifierFermeSurFiche(ex, e3, /Swend avec David[\s\S]*Voir la conversation/);
    });

    await ex.etape('Chat à 3 : choix entre les deux autres personnes, Swend en cours avec Kevin seulement', async () => {
      chargerFixture('scelle');
      for (const f of [FICHES.kevin]) await appelerComme('eliot', 'envoyer_demande_remplacement', { p_remplacant_id: f });
      await appelerComme('kevin', 'repondre_demande_remplacement', { p_remplacant_id: FICHES.kevin, p_accepte: true });
      swendPasseEtFige();
      moteur('0 minute');
      await ex.verifier('chat à 3 ouvert (Eliot, David, Kevin)',
        () => sql('select string_agg(prenom_affiche, \',\' order by role) from participants_chat_apres_swend') === 'David,Eliot,Kevin');
      // Swend en cours Eliot ↔ Kevin (invitation depuis l'accueil, par l'API).
      const r = await insererComme('eliot', 'pactes', {
        type: 'diner', statut: 'enAttenteChoixDateDestinataire', dates_proposees: [instant(20)], restaurant_id: restaurant(),
        initiateur_id: COMPTES.eliot.id, initiateur_nom: COMPTES.eliot.nomComplet,
        destinataire_nom: COMPTES.kevin.nomComplet, destinataire_telephone: COMPTES.kevin.tel,
      });
      await ex.verifier('invitation Eliot → Kevin créée', () => r.ok, { obtenu: () => r.corps });
      const e4 = await ex.redemarrer('eliot');
      await ouvrirSwendPasse(e4, /Swend avec David[\s\S]*Discuter/);
      await e4.cliquer('Faire un nouveau Swend');
      await e4.attendreTexte('Avec qui veux-tu faire un nouveau Swend ?');
      await ex.verifierTexte(e4, 'David', 'choix : David');
      await ex.verifierTexte(e4, 'Kevin', 'choix : Kevin');
      await ex.verifierTexte(e4, 'Tu as déjà un Swend en cours avec Kevin.', 'carte de Kevin désactivée : « Tu as déjà un Swend en cours avec Kevin. »');
      await ex.verifierAbsent(e4, 'avec David.', 'carte de David disponible');
      for (const t of ['titulaire', 'remplaçant', 'Continuer', 'Numéro de mobile', 'Choisir dans mes contacts']) {
        await ex.verifierAbsent(e4, t, `choix : pas de « ${t} »`);
      }
      await ex.verifier('seule la carte de David est un bouton (Kevin : désactivée)',
        async () => (await e4.page.getByRole('button', { name: /David/ }).count()) === 1
          && (await e4.page.getByRole('button', { name: /Kevin/ }).count()) === 0);
      await e4.cliquer(/David/, { exact: false });
      await e4.attendreTexte('Quand et où ?');
      await ex.verifierTexte(e4, 'Swend avec David', 'toucher David : directement « Quand et où ? » avec David');
      const refus = await appelerComme('eliot', 'creer_swend_depuis_chat', {
        p_chat_id: chatId(), p_participant_id: participant('kevin'), p_type: 'diner',
        p_dates_proposees: [instant(20)], p_restaurant_id: restaurant(), p_remplacants: [],
      });
      await ex.verifier('API : création avec Kevin refusée (swend_deja_en_cours)',
        () => !refus.ok && refus.corps.includes('swend_deja_en_cours'), { obtenu: () => refus.corps });
      const kevin = await ex.kevin();
      const ok = await appelerComme('kevin', 'options_nouveau_swend', { p_chat_id: chatId() });
      await ex.verifier('vu par Kevin : Eliot en cours, David libre ; aucun numéro',
        () => ok.ok && JSON.stringify(JSON.parse(ok.corps).map((o) => `${o.prenom}:${o.deja_en_cours}`).sort()) === '["David:false","Eliot:true"]'
          && numerosNonAutorises(kevin, { kevin: true, eliot: /\/rpc\/telephone_titulaire_accessible/ }).length === 0,
        { obtenu: () => ok.corps });
    });

    await ex.etape('Chat à 3 : un Swend scellé entre David et Kevin (remplaçant) ferme le chat', async () => {
      const n = n0();
      sql(`insert into pactes (type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
             destinataire_nom, destinataire_telephone)
           values ('diner', 'confirme', jsonb_build_array('${instant(25)}'), '${instant(25)}'::timestamptz, '${restaurant()}',
             '${COMPTES.david.id}', 'David Schlang', 'Kevin Arner', '${COMPTES.kevin.tel}')`);
      await ex.verifier('chat à 3 fermé, un message système', () => etatChat() === 'ferme:nouveau_swend|systeme=1|messages=1', { obtenu: etatChat });
      await ex.verifier('aucune push de fermeture', () => pushChat(n) === '0', { obtenu: () => pushChat(n) });
      const k2 = await ex.redemarrer('kevin');
      await verifierFermeSurFiche(ex, k2, /Swend d'Eliot avec David/);
    });

    await ex.etape('Chat pas encore ouvert : nouveau Swend scellé avant l\'heure → jamais de chat', async () => {
      chargerFixture('scelle');
      swendPasseEtFige('1 hour');
      moteur('-1 minute');
      await ex.verifier('Swend passé, chat pas encore ouvert', () => chatId() === '', { obtenu: chatId });
      const r = await insererComme('eliot', 'pactes', {
        type: 'diner', statut: 'enAttenteChoixDateDestinataire', dates_proposees: [instant(20)], restaurant_id: restaurant(),
        initiateur_id: COMPTES.eliot.id, initiateur_nom: COMPTES.eliot.nomComplet,
        destinataire_nom: COMPTES.david.nomComplet, destinataire_telephone: COMPTES.david.tel,
      });
      await ex.verifier('invitation Eliot → David', () => r.ok, { obtenu: () => r.corps });
      const n = n0();
      const d3 = await ex.redemarrer('david');
      await A.accepterSwend(d3, { avec: /Swend avec Eliot/, personnes: [C.leo, C.nina] });
      await ex.verifier('nouveau Swend scellé', () => sql(`select scelle_le is not null from pactes where id = '${nouveauEntre('eliot', 'david')}'`) === 't');
      moteur('0 minute');
      moteur('1 day');
      await ex.verifier('heure d\'ouverture passée : aucun chat, aucune anomalie',
        () => chatId() === '' && sql('select count(*) from anomalies_chat_apres_swend') === '0', { obtenu: chatId });
      await ex.verifier('aucune push « Alors, ce Swend ? » ni de fermeture', () => pushChat(n) === '0', { obtenu: () => pushChat(n) });
      const e5 = await ex.redemarrer('eliot');
      await e5.accueil();
      await ex.verifierAbsent(e5, 'Alors, ce Swend ?', 'Eliot : aucune carte « Alors, ce Swend ? »');
      await ouvrirSwendPasse(e5, /Swend avec David/);
      await ex.verifierTexte(e5, 'Au père Lapin', 'le Swend passé reste consultable');
      await ex.verifierAbsent(e5, 'APRÈS LE SWEND', 'pas de bloc « Après le Swend »');
      await ex.verifierAbsent(e5, 'Discuter', 'aucun CTA de conversation');
      await ex.verifierAbsent(e5, 'Conversation fermée', 'pas de faux chat fermé');
    });
  },
};
