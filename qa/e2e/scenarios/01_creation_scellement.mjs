// CRÉATION / SCELLEMENT — création par Eliot, réponse de David, statuts et
// compteurs des deux côtés, refus d'un Swend.
import { CONTACTS_SANS_COMPTE as C, COMPTES } from '../lib/config.mjs';
import * as A from '../lib/actions.mjs';
import { sql } from '../lib/donnees.mjs';

export default {
  nom: 'creation_scellement',
  titre: 'Création, statuts, scellement, refus, compteurs',
  suites: ['full'],
  fixture: 'comptes',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const sylvain = await ex.sylvain();

    await ex.etape('Eliot crée un Swend avec David (numéro saisi dans un autre format)', async () => {
      await A.creerSwend(eliot, { prenom: 'David', nom: 'Schlang', tel: '06 02 03 04 05',
        personnes: [{ prenom: 'Kevin', nom: 'Arner', tel: COMPTES.kevin.tel }, C.tom] });
      await ex.verifier('Swend rattaché au compte de David malgré le format du numéro',
        () => sql(`select count(*) from pactes where destinataire_id = '${COMPTES.david.id}' and statut = 'enAttenteChoixDateDestinataire'`) === '1',
        { obtenu: () => sql(`select statut || ' / ' || coalesce(destinataire_id::text, 'non rattaché') from pactes`) });
      await ex.verifier('Kevin rattaché à son compte, Tom sans compte',
        () => sql(`select string_agg(prenom || ':' || (profil_id is not null), ',' order by prenom) from remplacants`) === 'Kevin:true,Tom:false');
      await A.ouvrirMesSwends(eliot);
      await ex.verifierTexte(eliot, /Swend avec David Schlang\s+En attente de David/, 'Eliot : "En attente de David"');
    });

    await ex.etape('Avant scellement : compteurs et badge', async () => {
      await eliot.accueil();
      await ex.verifierTexte(eliot, /Mes Swends\s+1 à venir/, 'Eliot : 1 Swend à venir');
      await david.accueil();
      await ex.verifierTexte(david, /Mes Swends\s+1 à venir\s+1/, 'David : 1 à venir, pastille "1 action"');
    });

    await ex.etape('David répond : date choisie, personnes de confiance, Swend scellé', async () => {
      await A.ouvrirMesSwends(david);
      await ex.verifierTexte(david, /Swend avec Eliot Martin\s+À vous de répondre/, 'David : "À vous de répondre"');
      await A.accepterSwend(david, { avec: /Swend avec Eliot/, personnes: [C.leo, C.nina] });
      await ex.verifier('statut "confirme" et date retenue en base',
        () => sql('select statut || (date_retenue is not null) from pactes') === 'confirmetrue');
      await ex.verifier('personnes de David enregistrées de son côté',
        () => sql(`select string_agg(prenom, ',' order by prenom) from remplacants where cote = 'destinataire'`) === 'Léo,Nina');
    });

    await ex.etape('Les deux voient "Scellé" et "Ton prochain Swend"', async () => {
      for (const [a, autre] of [[eliot, 'David'], [david, 'Eliot']]) {
        await A.ouvrirMesSwends(a);
        await ex.verifierTexte(a, new RegExp(`Swend avec ${autre}[^\\n]*\\s+Scellé`), `${a.compte.prenom} : "Scellé"`);
        await a.accueil();
        await ex.verifierTexte(a, 'TON PROCHAIN SWEND', `${a.compte.prenom} : "Ton prochain Swend"`);
        await ex.verifierTexte(a, `Avec ${autre}`, `${a.compte.prenom} : prochain Swend "Avec ${autre}"`);
        await ex.verifierTexte(a, /Mes Swends\s+1 à venir/, `${a.compte.prenom} : 1 Swend à venir`);
      }
    });

    await ex.etape('Chacun ne voit que ses propres personnes de confiance', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, "EN CAS D'IMPRÉVU", 'Eliot : bloc "En cas d\'imprévu"');
      await ex.verifierTexte(eliot, 'Kevin, Tom', 'Eliot : "Kevin, Tom" (comptes d\'abord)');
      await ex.verifierAbsent(eliot, 'Léo', 'Eliot ne voit pas les personnes de David');
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierTexte(david, /Léo, Nina|Nina, Léo/, 'David : "Léo, Nina"');
      await ex.verifierAbsent(david, 'Kevin', 'David ne voit pas les personnes d\'Eliot');
    });

    await ex.etape('Refus : Eliot propose un Swend à Sylvain, qui le refuse', async () => {
      await A.creerSwend(eliot, { prenom: 'Sylvain', nom: 'Landiech', tel: '0655443322',
        personnes: [{ prenom: 'Kevin', nom: 'Arner', tel: COMPTES.kevin.tel }, C.tom] });
      await A.ouvrirSwend(sylvain, /Swend avec Eliot/);
      await A.choisirPremiereDate(sylvain);
      await sylvain.cliquer('Refuser le Swend');
      await ex.verifier('Swend refusé : statut "annule" en base',
        () => sql(`select statut from pactes where destinataire_id = '${COMPTES.sylvain.id}'`) === 'annule',
        { obtenu: () => sql(`select statut from pactes where destinataire_id = '${COMPTES.sylvain.id}'`) });
      await A.ouvrirMesSwends(eliot);
      await ex.verifierTexte(eliot, /Swend avec Sylvain Landiech\s+Annulé/, 'Eliot : Swend avec Sylvain "Annulé"');
      await eliot.accueil();
      await ex.verifierTexte(eliot, /Mes Swends\s+1 à venir/, 'Eliot : le Swend refusé ne compte pas (toujours 1 à venir)');
    });
  },
};
