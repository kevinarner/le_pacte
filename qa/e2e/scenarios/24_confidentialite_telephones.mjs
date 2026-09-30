// D-024 — CONFIDENTIALITÉ DES NUMÉROS. Un numéro n'arrive jamais dans l'app
// simplement parce qu'on peut lire un Swend. On relit TOUT ce que l'API
// renvoie à chaque acteur pendant un parcours réel :
//  - Kevin (personne de confiance d'Eliot) : jamais le numéro de David ; celui
//    d'Eliot seulement par telephone_titulaire_accessible (bouton « Appeler ») ;
//  - Eliot : ses personnes de confiance, jamais le numéro de David (qu'il a
//    saisi, mais que l'app ne relit plus) ;
//  - David : ses personnes de confiance, jamais le numéro d'Eliot ;
//  - Sylvain (personne de confiance de David) : jamais le numéro d'Eliot ;
//    celui de David seulement par la fonction dédiée.
// Et la création d'un Swend écrit toujours le numéro du destinataire.
import * as A from '../lib/actions.mjs';
import { sql, FICHES, appelerComme, lireComme, chargerFixture } from '../lib/donnees.mjs';
import { COMPTES, CONTACTS_SANS_COMPTE as C } from '../lib/config.mjs';
import { numerosNonAutorises, reponses } from '../lib/numeros.mjs';

const RPC_TITULAIRE = /\/rpc\/telephone_titulaire_accessible/;

async function verifierNumeros(ex, acteur, autorises, libelle) {
  await acteur.attendreCalme();
  await ex.verifier(libelle, () => numerosNonAutorises(acteur, autorises).length === 0, {
    attendu: 'aucun numéro hors : ' + Object.keys(autorises).join(', '),
    obtenu: () => numerosNonAutorises(acteur, autorises).join(' | '),
  });
}
// La ligne Swend a bien été reçue (sinon le contrôle ne prouverait rien).
async function verifierSwendRecu(ex, acteur, nomAttendu) {
  await ex.verifier(`${acteur.compte.prenom} : ligne Swend reçue (« ${nomAttendu} »), sans numéro`,
    () => reponses(acteur, /\/rest\/v1\/pactes/).some((r) => r.corps.includes(nomAttendu)),
    { obtenu: () => `${reponses(acteur, /\/rest\/v1\/pactes/).length} réponse(s) pactes` });
}

export default {
  nom: 'confidentialite_telephones',
  titre: 'D-024 : aucun numéro inutile dans les réponses reçues par l\'app ; création et « Appeler » inchangés',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const kevin = await ex.kevin();

    await ex.etape('Kevin (prévu) : accueil, fiche, conversation avec Eliot', async () => {
      await A.ouvrirConversationTiers(kevin);
      await ex.verifier('Kevin : bouton « Appeler » (numéro d\'Eliot par la fonction dédiée)',
        async () => (await kevin.nombreDeBoutons('Appeler')) === 1);
      await verifierSwendRecu(ex, kevin, 'David Schlang');
      await ex.verifier('Kevin : le numéro d\'Eliot n\'arrive que par telephone_titulaire_accessible',
        () => reponses(kevin, RPC_TITULAIRE).some((r) => r.corps.includes(COMPTES.eliot.tel)));
      await verifierNumeros(ex, kevin, { kevin: true, eliot: RPC_TITULAIRE },
        'Kevin : jamais le numéro de David, aucun autre numéro reçu');
    });

    await ex.etape('API : la ligne Swend ne donne le numéro à personne', async () => {
      for (const nom of ['kevin', 'eliot', 'david']) {
        let refus = '';
        try { await lireComme(nom, 'pactes', 'select=id,destinataire_telephone'); } catch (e) { refus = e.message; }
        await ex.verifier(`API : ${nom} ne peut pas lire destinataire_telephone`, () => /permission denied|42501/.test(refus),
          { obtenu: () => refus || 'lecture acceptée' });
      }
      const t = await appelerComme('kevin', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.kevin });
      await ex.verifier('API : Kevin obtient le numéro de son titulaire (Eliot) par la fonction dédiée',
        () => t.ok && t.corps.includes(COMPTES.eliot.tel), { obtenu: () => t.corps });
      const autre = await appelerComme('kevin', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.leo });
      await ex.verifier('API : Kevin n\'obtient rien sur une fiche qui n\'est pas la sienne',
        () => autre.ok && !/\d{2}/.test(autre.corps.replace(/null/, '')), { obtenu: () => autre.corps });
      const eliotSurKevin = await appelerComme('eliot', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.kevin });
      await ex.verifier('API : un titulaire n\'obtient rien par cette fonction',
        () => eliotSurKevin.ok && eliotSurKevin.corps.trim() === 'null', { obtenu: () => eliotSurKevin.corps });
    });

    await ex.etape('Eliot : demande à Kevin, conversation, « Appeler »', async () => {
      const eliot = await ex.eliot();
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await ex.verifier('Eliot : bouton « Appeler » vers Kevin (numéro de sa fiche)',
        async () => (await eliot.nombreDeBoutons('Appeler')) === 1);
      await verifierSwendRecu(ex, eliot, 'David Schlang');
      await verifierNumeros(ex, eliot, { eliot: true, kevin: true, sylvain: true, tom: true },
        'Eliot : ses personnes de confiance seulement, jamais le numéro de David');
    });

    await ex.etape('Kevin (sollicité) : la demande, la conversation', async () => {
      await kevin.accueil();
      await kevin.cliquer('Répondre à la demande');
      await kevin.cliquer('Voir la demande et répondre');
      await kevin.attendreTexte('Accepter');
      await ex.verifier('Kevin (sollicité) : bouton « Appeler »', async () => (await kevin.nombreDeBoutons('Appeler')) === 1);
      await verifierNumeros(ex, kevin, { kevin: true, eliot: RPC_TITULAIRE },
        'Kevin (sollicité) : toujours aucun numéro de David');
    });

    await ex.etape('David : accueil et fiche du Swend', async () => {
      const david = await ex.david();
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await verifierSwendRecu(ex, david, 'Eliot Martin');
      await verifierNumeros(ex, david, { david: true, leo: true, nina: true },
        'David : ses personnes de confiance seulement, jamais le numéro d\'Eliot');
    });

    await ex.etape('Création d\'un Swend : le numéro du destinataire s\'écrit toujours', async () => {
      const eliot = await ex.eliot();
      await A.creerSwend(eliot, { prenom: 'Sylvain', nom: 'Landiech', tel: '06.55.44.33.22',
        personnes: [{ prenom: 'Kevin', nom: 'Arner', tel: COMPTES.kevin.tel }, C.tom] });
      const enBase = () => sql(`select destinataire_telephone || '|' || destinataire_telephone_e164 || '|' || coalesce(destinataire_id::text, '-')
                                from pactes where destinataire_nom = 'Sylvain Landiech'`);
      await ex.verifier('numéro saisi enregistré, Sylvain rattaché par la base',
        () => enBase() === `06.55.44.33.22|+33655443322|${COMPTES.sylvain.id}`, { obtenu: enBase });
      const creations = reponses(eliot, /\/rest\/v1\/pactes/, 'POST');
      await ex.verifier('réponse à la création : ligne reçue, sans aucun numéro',
        () => creations.length === 1 && creations[0].corps.includes('Sylvain Landiech')
          && numerosNonAutorises({ reponsesApi: creations }, {}).length === 0,
        { obtenu: () => creations.map((r) => r.corps.slice(0, 300)).join(' | ') || 'aucune réponse' });
      await ex.verifierTexte(eliot, /Mes Swends\s+2 à venir/, 'Eliot : 2 Swends à venir');
    });

    await ex.etape('Sylvain, personne de confiance de David : jamais le numéro d\'Eliot', async () => {
      chargerFixture('scelle_double');
      const sylvain = await ex.sylvain();
      await A.ouvrirConversationTiers(sylvain, 'David', 'Eliot');
      await ex.verifier('Sylvain : bouton « Appeler » (numéro de David par la fonction dédiée)',
        async () => (await sylvain.nombreDeBoutons('Appeler')) === 1);
      await verifierSwendRecu(ex, sylvain, 'Eliot Martin');
      await verifierNumeros(ex, sylvain, { sylvain: true, david: RPC_TITULAIRE },
        'Sylvain : jamais le numéro d\'Eliot ; celui de David seulement par la fonction dédiée');
    });
  },
};
