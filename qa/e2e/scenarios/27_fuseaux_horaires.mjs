// R2 — FUSEAUX HORAIRES : une heure choisie à Paris reste la même heure
// partout, quel que soit le fuseau de l'appareil.
//  - Eliot utilise un appareil à New York, David un appareil à Paris ;
//  - parcours réel : création, choix de la date, scellement ; en base, un
//    instant (forme canonique UTC « …Z ») qui vaut 19:30 à Paris ;
//  - affichage à 19h30 chez les deux, jamais l'heure de l'appareil ;
//  - Swends scellés en hiver, en été, et au lendemain des deux changements
//    d'heure : « Mes Swends » affiche le bon jour et 19h30 ;
//  - vue des réservations à 19:30 ;
//  - API (comme une ancienne app) : dates sans fuseau refusées, date retenue
//    hors des dates proposées refusée (D-025b).
import * as A from '../lib/actions.mjs';
import { sql, insererComme, modifierComme } from '../lib/donnees.mjs';
import { COMPTES, CONTACTS_SANS_COMPTE as C } from '../lib/config.mjs';

const restaurant = () => sql(`select id from restaurants limit 1`);
// Premier jour (Paris) dans [J+16, J+380] qui vérifie la condition SQL sur d.
const jour = (condition) => sql(`select d::text from generate_series(
    (now() at time zone 'Europe/Paris')::date + 16, (now() at time zone 'Europe/Paris')::date + 380, interval '1 day') g,
    lateral (select g::date as d) x where ${condition} order by d limit 1`);
const instantParis = (j, h = '19:30') => sql(`select to_json(('${j} ${h}'::timestamp at time zone 'Europe/Paris')) #>> '{}'`);
const jjmmaaaa = (j) => { const [a, m, d] = j.split('-').map(Number); return `${d}/${m}/${a}`; };
const parisDe = (expr) => `to_char((${expr}) at time zone 'Europe/Paris', 'YYYY-MM-DD HH24:MI')`;

export default {
  nom: 'fuseaux_horaires',
  titre: 'R2 : une heure choisie à Paris reste la même partout (appareils à New York et à Paris)',
  suites: ['full'],
  fixture: 'comptes',
  async executer(ex) {
    const eliot = await ex.acteur('eliot', { fuseau: 'America/New_York' });
    const david = await ex.acteur('david', { fuseau: 'Europe/Paris' });

    await ex.etape('Eliot (appareil à New York) crée un Swend : créneau 19:30 de Paris, instant canonique en base', async () => {
      await A.creerSwend(eliot, { prenom: 'David', nom: 'Schlang', tel: COMPTES.david.tel, personnes: [C.tom, C.nina] });
      await ex.verifier('date proposée enregistrée sous forme canonique UTC (…Z)',
        () => /^\["\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00\.000Z"\]$/.test(sql(`select dates_proposees::text from pactes`)),
        { obtenu: () => sql(`select dates_proposees::text from pactes`) });
      await ex.verifier('cet instant vaut 19:30 à Paris (pas 19:30 à New York ni en UTC)',
        () => sql(`select ${parisDe(`(instants_proposes(dates_proposees))[1]`)} from pactes`).endsWith(' 19:30'),
        { obtenu: () => sql(`select ${parisDe(`(instants_proposes(dates_proposees))[1]`)} from pactes`) });
    });

    await ex.etape('David (appareil à Paris) choisit la date et scelle : même instant, 19:30 à Paris', async () => {
      await A.accepterSwend(david, { avec: /Swend avec Eliot/, personnes: [C.leo, C.nina] });
      await ex.verifier('date retenue = la date proposée (D-025b), 19:30 à Paris',
        () => sql(`select (date_retenue = (instants_proposes(dates_proposees))[1])::text || ' ' || ${parisDe('date_retenue')} from pactes`)
          .match(/^true \d{4}-\d{2}-\d{2} 19:30$/) !== null,
        { obtenu: () => sql(`select date_retenue::text || ' / ' || dates_proposees::text from pactes`) });
      ex.memo.jour = sql(`select (date_retenue at time zone 'Europe/Paris')::date::text from pactes`);
    });

    await ex.etape('Affichage : 19h30 chez Eliot (New York) comme chez David (Paris)', async () => {
      for (const a of [eliot, david]) {
        await A.ouvrirMesSwends(a);
        await ex.verifierTexte(a, `Dîner · ${jjmmaaaa(ex.memo.jour)} à 19h30`, `${a.compte.prenom} (${a.fuseau}) : « ${jjmmaaaa(ex.memo.jour)} à 19h30 »`);
        await ex.verifierAbsent(a, /à (13|18|20|21)h30/, `${a.compte.prenom} : aucune autre heure (appareil, UTC, ancien décalage)`);
      }
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, /19h30/, 'Eliot (New York) : fiche du Swend à 19h30');
      await ex.verifierAbsent(eliot, /13h30/, 'Eliot (New York) : jamais l’heure de New York');
    });

    await ex.etape('Vue des réservations : même jour, 19:30', async () => {
      await ex.verifier('heure_rdv = 19:30, date_rdv = jour de Paris',
        () => sql(`select date_rdv::text || ' ' || heure_rdv from reservations_a_suivre`) === `${ex.memo.jour} 19:30`,
        { obtenu: () => sql(`select date_rdv::text || ' ' || heure_rdv from reservations_a_suivre`) });
    });

    await ex.etape('Hiver, été et lendemains des changements d’heure : « Mes Swends » à 19h30, bon jour', async () => {
      const cas = {
        hiver: jour(`extract(isodow from d) = 2 and extract(month from d) in (11, 12, 1, 2)`),
        'été': jour(`extract(isodow from d) = 2 and extract(month from d) in (6, 7, 8)`),
        'lendemain du passage à l’heure d’hiver': jour(`extract(isodow from d) = 1 and extract(month from d - 1) = 10 and extract(day from d - 1) >= 25`),
        'lendemain du passage à l’heure d’été': jour(`extract(isodow from d) = 1 and extract(month from d - 1) = 3 and extract(day from d - 1) >= 25`),
      };
      for (const [nom, j] of Object.entries(cas)) {
        const i = instantParis(j);
        sql(`insert into pactes (type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
               destinataire_id, destinataire_nom, destinataire_telephone)
             values ('diner', 'confirme', to_jsonb(array['${i}'::timestamptz]), '${i}', '${restaurant()}', '${COMPTES.eliot.id}',
               '${COMPTES.eliot.nomComplet}', '${COMPTES.david.id}', '${COMPTES.david.nomComplet}', '${COMPTES.david.tel}')`);
        ex.memo[nom] = j;
      }
      for (const a of [eliot, david]) {
        await A.ouvrirMesSwends(a);
        for (const [nom, j] of Object.entries(cas)) {
          await ex.verifierTexte(a, `Dîner · ${jjmmaaaa(j)} à 19h30`, `${a.compte.prenom} (${a.fuseau}) : ${nom} (${j}) à 19h30`);
        }
        await ex.verifierAbsent(a, /à (12|13|18|20|21)h30/, `${a.compte.prenom} : aucune autre heure, quelle que soit la saison`);
      }
    });

    await ex.etape('Ancienne app (API) : dates sans fuseau et date retenue décalée refusées', async () => {
      const j = jour(`extract(isodow from d) = 3`);
      const sansFuseau = await insererComme('eliot', 'pactes', {
        type: 'diner', statut: 'enAttenteChoixDateDestinataire', dates_proposees: [`${j}T19:30:00.000`],
        restaurant_id: restaurant(), initiateur_id: COMPTES.eliot.id, initiateur_nom: COMPTES.eliot.nomComplet,
        destinataire_nom: COMPTES.david.nomComplet, destinataire_telephone: COMPTES.david.tel,
      });
      await ex.verifier('création avec une date sans fuseau : refus date_sans_fuseau',
        () => !sansFuseau.ok && sansFuseau.corps.includes('date_sans_fuseau'), { obtenu: () => sansFuseau.corps });
      // Un seul Swend en cours par paire (D-023c) : le Swend scellé des étapes
      // précédentes est annulé avant cette nouvelle création.
      sql(`update pactes set statut = 'annule' where statut <> 'annule'`);
      const cree = await insererComme('eliot', 'pactes', {
        type: 'diner', statut: 'enAttenteChoixDateDestinataire', dates_proposees: [instantParis(j)],
        restaurant_id: restaurant(), initiateur_id: COMPTES.eliot.id, initiateur_nom: COMPTES.eliot.nomComplet,
        destinataire_nom: COMPTES.david.nomComplet, destinataire_telephone: COMPTES.david.tel,
      });
      await ex.verifier('création avec un instant explicite : acceptée', () => cree.ok, { obtenu: () => cree.corps });
      const id = sql(`select id from pactes where statut = 'enAttenteChoixDateDestinataire' order by created_at desc limit 1`);
      const decale = await modifierComme('david', 'pactes', `id=eq.${id}`, { date_retenue: `${j}T19:30:00.000`, statut: 'enAttenteReponse' });
      await ex.verifier('choix « 19:30 » sans fuseau (lu 19:30 UTC) : refus date_non_proposee, rien ne change',
        () => !decale.ok && decale.corps.includes('date_non_proposee')
          && sql(`select statut || coalesce(date_retenue::text, '') from pactes where id = '${id}'`) === 'enAttenteChoixDateDestinataire',
        { obtenu: () => decale.corps });
      const juste = await modifierComme('david', 'pactes', `id=eq.${id}`, { date_retenue: instantParis(j), statut: 'enAttenteReponse' });
      await ex.verifier('choix de l’instant proposé : accepté', () => juste.ok, { obtenu: () => juste.corps });
    });
  },
};
