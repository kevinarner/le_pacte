// D-025 — DÉLAI MINIMUM : pour un Swend créé par un utilisateur standard,
// aucune date proposée ni retenue avant le jour de création (Paris) + 15.
//  - la base calcule seule date_minimale (valeur envoyée par l'app ignorée) ;
//  - J+14 refusé (date_trop_proche), J+15 accepté, par l'API ;
//  - parcours réel : création, contre-proposition, calendrier limité, message
//    de refus avec la première date possible donnée par la base ;
//  - compte fondateur (email confirmé) : exempté pour toute la négociation de
//    SES Swends, jamais pour ceux qu'il reçoit ; table illisible par l'app.
// Les dates sont relatives au jour de Paris d'aujourd'hui.
import * as A from '../lib/actions.mjs';
import { sql, chargerFixture, appelerComme, lireComme, insererComme, modifierComme } from '../lib/donnees.mjs';
import { COMPTES, CONTACTS_SANS_COMPTE as C } from '../lib/config.mjs';
import { numerosNonAutorises, reponses } from '../lib/numeros.mjs';

const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
// Jour de Paris d'aujourd'hui + n ("2026-10-16"), et instant à l'heure h ce jour-là.
const jourParis = (n) => sql(`select ((now() at time zone 'Europe/Paris')::date + ${n})::text`);
const instant = (n, h = '20:00') =>
  sql(`select to_json((((now() at time zone 'Europe/Paris')::date + ${n}) + time '${h}') at time zone 'Europe/Paris') #>> '{}'`);
const message = (jour) => {
  const [, m, d] = jour.split('-').map(Number);
  return `Choisissez une date au moins 15 jours à l’avance. Première date possible : ${d} ${MOIS[m - 1]}.`;
};
const restaurant = () => sql(`select id from restaurants limit 1`);
const creer = (nom, dates, dest, extra = {}) => insererComme(nom, 'pactes', {
  type: 'diner', statut: 'enAttenteChoixDateDestinataire', dates_proposees: dates, restaurant_id: restaurant(),
  initiateur_id: COMPTES[nom].id, initiateur_nom: COMPTES[nom].nomComplet,
  destinataire_nom: COMPTES[dest].nomComplet, destinataire_telephone: COMPTES[dest].tel, ...extra,
});
const contreProposer = (nom, id, dates) => modifierComme(nom, 'pactes', `id=eq.${id}`,
  { dates_proposees: dates, nombre_echanges_date: 1, statut: 'enAttenteChoixDateInitiateur' });
const dernier = (initiateur, dest) => sql(`select id from pactes where initiateur_id = '${COMPTES[initiateur].id}'
  and destinataire_id = '${COMPTES[dest].id}' order by created_at desc limit 1`);
const minimale = (id) => sql(`select coalesce(date_minimale::text, 'null') from pactes where id = '${id}'`);
const refuse = (r) => !r.ok && r.corps.includes('date_trop_proche');

export default {
  nom: 'delai_minimum',
  titre: 'D-025 : aucune date avant J+15 (Paris) pour un Swend standard ; comptes fondateurs exemptés',
  suites: ['full'],
  fixture: 'comptes',
  async executer(ex) {
    const j15 = jourParis(15);

    await ex.etape('API : Eliot (standard) — J+14 refusé, J+15 accepté, date calculée par la base', async () => {
      const rpc = await appelerComme('eliot', 'date_minimale_nouveau_swend', {});
      await ex.verifier('première date possible pour Eliot : J+15 (Paris)', () => rpc.ok && rpc.corps === `"${j15}"`,
        { attendu: j15, obtenu: () => rpc.corps });
      const j14 = await creer('eliot', [instant(14, '23:30')], 'david');
      await ex.verifier('J+14 à 23h30 (Paris) : refusé, avec la première date possible', () => refuse(j14) && j14.corps.includes(j15),
        { obtenu: () => j14.corps });
      const mixte = await creer('eliot', [instant(30), instant(14)], 'david');
      await ex.verifier('une seule date trop proche suffit au refus', () => refuse(mixte), { obtenu: () => mixte.corps });
      const ok = await creer('eliot', [instant(15, '00:30')], 'david', { date_minimale: '2000-01-01' });
      await ex.verifier('J+15 à 00h30 (Paris) : accepté', () => ok.ok, { obtenu: () => ok.corps });
      await ex.verifier('date_minimale posée par la base (valeur envoyée ignorée)', () => minimale(dernier('eliot', 'david')) === j15,
        { obtenu: () => minimale(dernier('eliot', 'david')) });
      const lu = await lireComme('david', 'pactes', 'select=id,date_minimale');
      await ex.verifier('David lit la date minimale du Swend', () => lu.length === 1 && lu[0].date_minimale === j15,
        { obtenu: () => JSON.stringify(lu) });
      const triche = await modifierComme('david', 'pactes', `id=eq.${dernier('eliot', 'david')}`, { date_minimale: '2000-01-01' });
      await ex.verifier('date_minimale non modifiable par l\'app', () => !triche.ok && minimale(dernier('eliot', 'david')) === j15,
        { obtenu: () => triche.corps });
      const choix = await modifierComme('david', 'pactes', `id=eq.${dernier('eliot', 'david')}`,
        { date_retenue: instant(10), statut: 'enAttenteReponse' });
      await ex.verifier('date retenue avant J+15 : refusée', () => refuse(choix), { obtenu: () => choix.corps });
      chargerFixture('comptes');
    });

    await ex.etape('App : Eliot crée un Swend, David contre-propose (dates par défaut, inchangé)', async () => {
      const eliot = await ex.eliot();
      await A.creerSwend(eliot, { prenom: 'David', nom: 'Schlang', tel: COMPTES.david.tel, personnes: [C.tom, C.nina] });
      const id = dernier('eliot', 'david');
      await ex.verifier('Swend créé, date minimale J+15', () => id !== '' && minimale(id) === j15, { obtenu: () => minimale(id) });
      await ex.verifier('l\'app a demandé la première date possible à la base',
        () => reponses(eliot, /\/rpc\/date_minimale_nouveau_swend/).some((r) => r.corps.includes(j15)));
      await ex.verifier('D-024 : aucun numéro de David reçu par Eliot',
        () => numerosNonAutorises(eliot, { eliot: true, tom: true, nina: true }).length === 0,
        { obtenu: () => numerosNonAutorises(eliot, { eliot: true, tom: true, nina: true }).join(' | ') });
      const david = await ex.david();
      await A.contreProposer(david, /Swend avec Eliot/);
      const etat = () => sql(`select statut || '|' || nombre_echanges_date from pactes where id = '${id}'`);
      await ex.verifier('contre-proposition de David acceptée', () => etat() === 'enAttenteChoixDateInitiateur|1', { obtenu: etat });
    });

    await ex.etape('App : le calendrier ne propose rien avant la date minimale', async () => {
      // Date minimale repoussée (SQL Editor, hors app) : le calendrier d'Eliot
      // part de là, même si son départ habituel (+60 j) est plus tôt.
      const id = dernier('eliot', 'david');
      const j120 = jourParis(120);
      sql(`update pactes set date_minimale = '${j120}' where id = '${id}'`);
      const eliot = await ex.eliot();
      await A.contreProposer(eliot, /Swend avec David/);
      const premiere = () => sql(`select min((d at time zone 'Europe/Paris')::date)::text from pactes, unnest(instants_proposes(dates_proposees)) d where id = '${id}'`);
      const etat = () => sql(`select statut || '|' || nombre_echanges_date from pactes where id = '${id}'`);
      await ex.verifier('contre-proposition d\'Eliot acceptée', () => etat() === 'enAttenteChoixDateDestinataire|2', { obtenu: etat });
      await ex.verifier('date proposée par le calendrier : pas avant la date minimale', () => premiere() >= j120,
        { attendu: `>= ${j120}`, obtenu: premiere });
    });

    await ex.etape('App : refus de la base → message avec la première date possible', async () => {
      // David a la fiche ouverte ; la date minimale change entre-temps : la
      // base refuse son choix et l'app affiche la date qu'elle a donnée.
      const id = dernier('eliot', 'david');
      const david = await ex.david();
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await david.page.getByRole('button', { name: /\d{4} à \d{1,2}h\d{2}/ }).first().waitFor({ timeout: 15000 });
      const j400 = jourParis(400);
      sql(`update pactes set date_minimale = '${j400}' where id = '${id}'`);
      await david.page.getByRole('button', { name: /\d{4} à \d{1,2}h\d{2}/ }).first().click();
      await ex.verifierTexte(david, message(j400), `David : « ${message(j400)} »`);
      await ex.verifier('rien n\'a changé en base', () => sql(`select statut || '|' || (date_retenue is null) from pactes where id = '${id}'`)
        === 'enAttenteChoixDateDestinataire|true');
    });

    await ex.etape('Compte fondateur (email confirmé) : exempté pour SES Swends seulement', async () => {
      chargerFixture('comptes');
      sql(`insert into comptes_fondateurs (email) values ('kevin@swend.test') on conflict do nothing`);
      const rpc = await appelerComme('kevin', 'date_minimale_nouveau_swend', {});
      await ex.verifier('Kevin (fondateur) : aucune limite', () => rpc.ok && rpc.corps === 'null', { obtenu: () => rpc.corps });
      let refus = '';
      try { await lireComme('kevin', 'comptes_fondateurs', 'select=email'); } catch (e) { refus = e.message; }
      await ex.verifier('comptes_fondateurs illisible par l\'app (même par un fondateur)', () => /permission denied|42501/.test(refus),
        { obtenu: () => refus || 'lecture acceptée' });

      const k = await creer('kevin', [instant(2)], 'eliot');
      await ex.verifier('Kevin crée un Swend à J+2 : accepté, sans date minimale',
        () => k.ok && minimale(dernier('kevin', 'eliot')) === 'null', { obtenu: () => k.corps });
      const cp = await contreProposer('eliot', dernier('kevin', 'eliot'), [instant(3)]);
      await ex.verifier('Eliot (standard) contre-propose J+3 sur le Swend de Kevin : accepté (exemption du Swend)',
        () => cp.ok, { obtenu: () => cp.corps });

      // Un seul Swend en cours par paire (D-023c) : le Swend de Kevin est
      // annulé avant qu'Eliot n'en crée un avec lui.
      sql(`update pactes set statut = 'annule' where id = '${dernier('kevin', 'eliot')}'`);
      const e14 = await creer('eliot', [instant(14)], 'kevin');
      await ex.verifier('Eliot crée un Swend avec Kevin à J+14 : refusé (le destinataire fondateur n\'exempte pas)',
        () => refuse(e14), { obtenu: () => e14.corps });
      const e15 = await creer('eliot', [instant(15)], 'kevin');
      await ex.verifier('… à J+15 : accepté', () => e15.ok, { obtenu: () => e15.corps });
      const kcp = await contreProposer('kevin', dernier('eliot', 'kevin'), [instant(3)]);
      await ex.verifier('Kevin contre-propose J+3 sur le Swend d\'Eliot : refusé', () => refuse(kcp), { obtenu: () => kcp.corps });

      sql(`update auth.users set email_confirmed_at = null where email = 'kevin@swend.test'`);
      const nc = await appelerComme('kevin', 'date_minimale_nouveau_swend', {});
      await ex.verifier('email non confirmé : plus d\'exemption', () => nc.corps === `"${j15}"`, { obtenu: () => nc.corps });
      sql(`update auth.users set email_confirmed_at = now() where email = 'kevin@swend.test'`);

      const kevin = await ex.kevin();
      await kevin.accueil();
      await kevin.cliquer('Créer un Swend');
      await kevin.attendreCalme();
      await ex.verifier('app de Kevin : la base lui répond « aucune limite »',
        () => reponses(kevin, /\/rpc\/date_minimale_nouveau_swend/).some((r) => r.corps.trim() === 'null'));
      sql(`delete from comptes_fondateurs`);
    });
  },
};
