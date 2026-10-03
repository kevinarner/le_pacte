// D-023b — CHAT APRÈS LE SWEND. Eliot a demandé à Sylvain puis à Kevin ;
// Kevin a accepté (Sylvain, sollicité, n'est pas choisi). Le Swend passe et
// est figé (D-023a). Avant l'heure d'ouverture : rien, et le mystère reste
// entier pour David. À l'ouverture (moteur appelé à l'instant exact) : une
// push « Alors, ce Swend ? » à Eliot, David et Kevin, une carte d'accueil
// persistante, le bloc « APRÈS LE SWEND » avec la révélation. Kevin écrit :
// push et carte chez Eliot et David ; David lit : lui seul passe en lu.
// Lien web direct, accès impossible pour Sylvain, Swend annulé sans chat,
// et aucun numéro inutile dans les réponses réseau (D-024).
import * as A from '../lib/actions.mjs';
import { sql, FICHES, appelerComme, lireComme, chargerFixture } from '../lib/donnees.mjs';
import { config } from '../lib/config.mjs';
import { numerosNonAutorises } from '../lib/numeros.mjs';

const OUVERTURE = 'Le silence est levé. Vous pouvez maintenant en reparler dans le chat.';
const pushDepuis = (n0) => sql(`select coalesce(string_agg(p.prenom || '|' || n.titre || '|' || n.corps, ' ## ' order by p.prenom, n.id), '')
  from notifications_log n left join profiles p on p.id = n.profile_id where n.id > ${n0} and n.data->>'type' = 'chat_apres_swend'`);
const n0 = () => sql('select coalesce(max(id), 0) from notifications_log');
const moteur = (decalage) => sql(`select ouvrir_chats_apres_swend(ouverture_chat_apres_swend(date_retenue) + interval '${decalage}') from pactes`);
const chatId = () => sql('select coalesce(max(id::text), \'\') from chats_apres_swend');
const nonLus = async (nom, id) => {
  const r = await appelerComme(nom, 'mes_chats_apres_swend', {});
  const c = JSON.parse(r.corps).find((x) => x.chat_id === id);
  return c ? c.non_lus : null;
};
// Comme un clic sur la notification web : nouvelle page sur le lien, connexion.
async function ouvrirLien(a, url) {
  await a.page.goto(url, { waitUntil: 'load' });
  await a.activerAccessibilite();
  await a.page.getByRole('textbox').first().waitFor({ timeout: 15000 });
  await a.saisir(a.page.getByRole('textbox').nth(0), a.compte.email);
  await a.saisir(a.page.getByRole('textbox').nth(1), config.QA_MOT_DE_PASSE);
  await a.cliquer('Se connecter');
  await a.attendreCalme();
}
// Swend passé depuis deux jours, figé par D-023a ; mise en service du chat
// avant (la fixture vide toutes les tables).
function swendPasseEtFige() {
  sql(`select qa.deplacer_swend(id, now() - interval '2 days') from pactes`);
  sql(`insert into chat_apres_swend_service (id, mise_en_service) values (true, now() - interval '30 days')
       on conflict (id) do update set mise_en_service = excluded.mise_en_service`);
  sql('select figer_swends_passes()');
}

export default {
  nom: 'chat_apres_swend',
  titre: 'Chat après le Swend : ouverture, carte, révélation, non-lus individuels, lien web, accès, annulé',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();

    await ex.etape('Avant H : Eliot demande à Sylvain puis à Kevin, Kevin accepte', async () => {
      for (const f of [FICHES.sylvain, FICHES.kevin]) {
        const r = await appelerComme('eliot', 'envoyer_demande_remplacement', { p_remplacant_id: f });
        await ex.verifier('demande envoyée', () => r.ok, { obtenu: () => r.corps });
      }
      const r = await appelerComme('kevin', 'repondre_demande_remplacement', { p_remplacant_id: FICHES.kevin, p_accepte: true });
      await ex.verifier('Kevin a pris la place, Sylvain clôturé',
        () => r.ok && sql(`select string_agg(prenom || ':' || coalesce(demande_statut, '-'), ',' order by prenom) from remplacants where cote = 'initiateur'`)
          === 'Kevin:acceptee,Sylvain:cloturee,Tom:-', { obtenu: () => r.corps });
    });

    await ex.etape('Swend passé et figé, avant l\'heure d\'ouverture : rien, mystère intact', async () => {
      swendPasseEtFige();
      const n = n0();
      moteur('-1 minute');
      await ex.verifier('aucun chat avant l\'heure d\'ouverture', () => chatId() === '', { obtenu: chatId });
      await ex.verifier('aucune push d\'ouverture', () => pushDepuis(n) === '');
      const r = await appelerComme('eliot', 'mes_chats_apres_swend', {});
      await ex.verifier('API : aucun chat visible', () => r.ok && r.corps.trim() === '[]', { obtenu: () => r.corps });
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierAbsent(david, 'APRÈS LE SWEND', 'David : pas de bloc « Après le Swend »');
      await ex.verifierAbsent(david, 'Kevin', 'David : aucune trace de Kevin (mystère intact)');
      await david.accueil();
      await ex.verifierAbsent(david, 'Alors, ce Swend ?', 'David : aucune carte d\'accueil');
      await A.ouvrirMesSwends(eliot);
      await ex.verifierAbsent(eliot, 'Discuter', 'Eliot : aucun « Discuter » dans Mes Swends');
    });

    await ex.etape('À l\'heure d\'ouverture : chat, push, carte d\'accueil', async () => {
      const n = n0();
      moteur('0 minute');
      await ex.verifier('chat ouvert avec Eliot, David, Kevin (pas Sylvain)',
        () => sql(`select string_agg(role || ':' || prenom_affiche, ',' order by role) from participants_chat_apres_swend`)
          === 'destinataire:David,initiateur:Eliot,remplacant:Kevin');
      await ex.verifier('une push « Alors, ce Swend ? » à chacun des trois',
        () => pushDepuis(n) === `David|Alors, ce Swend ?|${OUVERTURE} ## Eliot|Alors, ce Swend ?|${OUVERTURE} ## Kevin|Alors, ce Swend ?|${OUVERTURE}`,
        { obtenu: () => pushDepuis(n) });
      for (const a of [eliot, david, kevin]) {
        await a.accueil();
        await ex.verifierTexte(a, 'Alors, ce Swend ?', `${a.compte.prenom} : carte « Alors, ce Swend ? »`);
        await ex.verifierTexte(a, 'Le silence est levé.', `${a.compte.prenom} : « Le silence est levé. »`);
      }
    });

    await ex.etape('Révélation sur la fiche du Swend passé', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'APRÈS LE SWEND', 'Eliot : bloc « APRÈS LE SWEND »');
      await ex.verifierTexte(eliot, 'Kevin a pris votre place.', 'Eliot : « Kevin a pris votre place. »');
      await ex.verifierTexte(eliot, 'Avec David et Kevin', 'Eliot : « Avec David et Kevin »');
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierTexte(david, "Kevin a pris la place d'Eliot.", 'David : « Kevin a pris la place d\'Eliot. »');
      await ex.verifierTexte(david, 'Discuter', 'David : « Discuter »');
      await A.ouvrirSwend(kevin, /Swend d'Eliot avec David/);
      await ex.verifierTexte(kevin, "Tu as pris la place d'Eliot.", 'Kevin : « Tu as pris la place d\'Eliot. » (tutoiement)');
      await A.ouvrirMesSwends(david);
      await ex.verifierTexte(david, 'Discuter', 'David : « Discuter » dans Mes Swends');
    });

    await ex.etape('Kevin ouvre le chat depuis sa carte, puis écrit', async () => {
      await kevin.accueil();
      await kevin.cliquerTexte('Alors, ce Swend ?');
      await kevin.attendreTexte('Après le Swend');
      await ex.verifierTexte(kevin, 'Swend au père Lapin', 'en-tête « Swend au père Lapin »');
      await ex.verifierTexte(kevin, 'Eliot · David · Kevin', 'participants « Eliot · David · Kevin »');
      await ex.verifierTexte(kevin, 'À vous de débriefer.', 'état vide « À vous de débriefer. »');
      const n = n0();
      await A.envoyerMessage(kevin, 'Quelle soirée !');
      await ex.verifierAbsent(kevin, 'À vous de débriefer.', 'état vide disparu après le premier message');
      await ex.verifier('push « Kevin vous a écrit » à Eliot et David, sans contenu',
        () => pushDepuis(n) === 'David|Kevin vous a écrit|Après le Swend · Au père Lapin ## Eliot|Kevin vous a écrit|Après le Swend · Au père Lapin',
        { obtenu: () => pushDepuis(n) });
      await kevin.accueil();
      await ex.verifierAbsent(kevin, 'Alors, ce Swend ?', 'Kevin : carte disparue après sa première ouverture');
    });

    await ex.etape('Eliot et David : carte « Kevin vous a écrit » ; David lit, lui seul', async () => {
      const id = chatId();
      for (const a of [eliot, david]) {
        await a.accueil();
        await ex.verifierTexte(a, 'Kevin vous a écrit', `${a.compte.prenom} : carte « Kevin vous a écrit »`);
        await ex.verifierAbsent(a, 'Quelle soirée', `${a.compte.prenom} : jamais le contenu sur l'accueil`);
      }
      await david.cliquerTexte('Kevin vous a écrit');
      await david.attendreTexte('Quelle soirée !');
      await ex.verifierTexte(david, 'Kevin', 'chat à 3 : prénom de l\'auteur au-dessus de la bulle');
      await ex.verifier('David : 0 non lu ; Eliot : toujours 1', async () =>
        (await nonLus('david', id)) === 0 && (await nonLus('eliot', id)) === 1);
      await david.accueil();
      await ex.verifierAbsent(david, 'Kevin vous a écrit', 'David : carte disparue');
      await eliot.accueil();
      await ex.verifierTexte(eliot, 'Kevin vous a écrit', 'Eliot : carte toujours là');
      await A.ouvrirMesSwends(eliot);
      await ex.verifierTexte(eliot, '● Kevin vous a écrit', 'Eliot : « ● Kevin vous a écrit » dans Mes Swends');
    });

    await ex.etape('Lien web direct (?chat_apres=) : le chat s\'ouvre, l\'adresse est nettoyée', async () => {
      const id = chatId();
      await ouvrirLien(eliot, `${config.appUrl}/?chat_apres=${id}`);
      await eliot.attendreTexte('Après le Swend');
      await eliot.attendreTexte('Quelle soirée !');
      await ex.verifier('adresse sans ?chat_apres', () => !eliot.page.url().includes('chat_apres'), { obtenu: () => eliot.page.url() });
      await ex.verifier('Eliot : lu en ouvrant le chat', async () => (await nonLus('eliot', id)) === 0);
    });

    await ex.etape('Sylvain (sollicité, non choisi) : jamais d\'accès, même par le lien', async () => {
      const id = chatId();
      const sylvain = await ex.sylvain();
      const r = await appelerComme('sylvain', 'mes_chats_apres_swend', {});
      await ex.verifier('API : aucun chat pour Sylvain', () => r.ok && r.corps.trim() === '[]', { obtenu: () => r.corps });
      const m = await lireComme('sylvain', 'messages_apres_swend', 'select=id');
      await ex.verifier('API : aucun message lisible', () => m.length === 0);
      const e = await appelerComme('sylvain', 'envoyer_message_apres_swend', { p_chat_id: id, p_contenu: 'coucou' });
      await ex.verifier('API : écriture refusée (non_autorise)', () => !e.ok && e.corps.includes('non_autorise'), { obtenu: () => e.corps });
      await ex.verifierAbsent(sylvain, 'Alors, ce Swend ?', 'Sylvain : aucune carte');
      await ouvrirLien(sylvain, `${config.appUrl}/?chat_apres=${id}`);
      await ex.verifierTexte(sylvain, "Cette conversation n'est plus accessible.", 'Sylvain : message propre, pas d\'erreur');
      await ex.verifier('Sylvain : aucune zone de saisie',
        async () => (await sylvain.page.getByRole('textbox', { name: 'Écrire un message…' }).count()) === 0);
    });

    await ex.etape('Aucun numéro inutile dans les réponses réseau (D-024)', async () => {
      for (const [a, autorises] of [
        [eliot, { eliot: true, kevin: true, sylvain: true, tom: true }],
        [david, { david: true, leo: true, nina: true }],
        [kevin, { kevin: true, eliot: /\/rpc\/telephone_titulaire_accessible/ }],
      ]) {
        await ex.verifier(`${a.compte.prenom} : aucun numéro non autorisé reçu`, () => numerosNonAutorises(a, autorises).length === 0,
          { obtenu: () => numerosNonAutorises(a, autorises).join(' | ') });
      }
    });

    await ex.etape('Swend annulé : jamais de chat', async () => {
      chargerFixture('scelle');
      sql(`update pactes set statut = 'annule'`);
      swendPasseEtFige();
      moteur('0 minute');
      moteur('1 hour');
      await ex.verifier('aucun chat pour un Swend annulé', () => chatId() === '', { obtenu: chatId });
      const e2 = await ex.redemarrer('eliot');
      await A.ouvrirSwend(e2, /Swend avec David/);
      await ex.verifierAbsent(e2, 'APRÈS LE SWEND', 'Eliot : pas de bloc « Après le Swend » sur un Swend annulé');
      await e2.accueil();
      await ex.verifierAbsent(e2, 'Alors, ce Swend ?', 'Eliot : aucune carte');
    });
  },
};
