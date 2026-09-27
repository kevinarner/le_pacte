// ÉVÉNEMENTS SYSTÈME — chaque étape d'une demande apparaît dans la
// conversation concernée, rédigée selon qui regarde, horodatée, dans
// l'ordre, et persiste d'une session à l'autre.
import * as A from '../lib/actions.mjs';
import { dansLOrdre } from '../lib/execution.mjs';
import { sql } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const HORODATAGE = /\d{1,2} [a-zéû]+\.? · \d{2}:\d{2}/g;
const EVTS = {
  eliotKevin: ['Tu as demandé à Kevin de prendre ta place.', 'Tu as annulé ta demande à Kevin.',
    'Tu as demandé à Kevin de prendre ta place.', 'Kevin a accepté de prendre ta place.', 'Kevin ne peut finalement plus prendre ta place.'],
  kevinAvantDesistement: ["Eliot t'a demandé de prendre sa place.", 'Eliot a annulé sa demande.',
    "Eliot t'a demandé de prendre sa place.", "Tu as accepté de prendre la place d'Eliot."],
  eliotSylvain: ['Tu as demandé à Sylvain de prendre ta place.', "La demande à Sylvain n'est plus d'actualité.",
    'Tu as demandé à Sylvain de prendre ta place.', 'Sylvain a refusé de prendre ta place.'],
  sylvain: ["Eliot t'a demandé de prendre sa place.", "La demande n'est plus d'actualité.",
    "Eliot t'a demandé de prendre sa place.", "Tu as refusé de prendre la place d'Eliot."],
};

// nEvenements : combien d'éléments de [attendus] sont des événements (les messages ne sont pas comptés).
async function verifierFil(ex, a, attendus, libelle, nEvenements = attendus.length) {
  await ex.verifier(`${libelle} : événements dans l'ordre`, async () => dansLOrdre(await a.texte(), attendus),
    { attendu: attendus.join(' → '), obtenu: async () => (await a.texte()).replace(/\s+/g, ' ').slice(0, 700) });
  await ex.verifier(`${libelle} : chaque événement est horodaté`,
    async () => ((await a.texte()).match(HORODATAGE) || []).length >= nEvenements,
    { obtenu: async () => `${((await a.texte()).match(HORODATAGE) || []).length} horodatage(s)` });
}

export default {
  nom: 'evenements',
  titre: 'Événements du fil : tous les codes, ordre, horodatage, persistance',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Demande, annulation, nouvelle demande à Kevin ; demande à Sylvain', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.annulerDemande(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Sylvain Landiech');
    });

    await ex.etape('Kevin accepte (la demande à Sylvain est close)', async () => {
      await A.repondre(kevin, true);
      await A.ouvrirConversationTiers(kevin);
      await verifierFil(ex, kevin, EVTS.kevinAvantDesistement, 'Kevin');
    });

    await ex.etape('Kevin se désiste ; Eliot redemande à Sylvain, qui refuse', async () => {
      await A.seDesister(kevin);
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(sylvain, false);
      await ex.verifier('9 événements en base (5 pour Kevin, 4 pour Sylvain)',
        () => sql('select count(*) from evenements_fil') === '9', { obtenu: () => sql('select count(*) from evenements_fil') });
    });

    await ex.etape('Vue d\'Eliot (titulaire) dans les deux conversations', async () => {
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await verifierFil(ex, eliot, EVTS.eliotKevin, 'Eliot ↔ Kevin');
      await ex.verifierAbsent(eliot, 'Sylvain', 'conversation Kevin : rien sur Sylvain');
      await eliot.accueil({ rafraichir: false });
      await A.ouvrirConversationTitulaire(eliot, 'Sylvain Landiech');
      await verifierFil(ex, eliot, EVTS.eliotSylvain, 'Eliot ↔ Sylvain');
    });

    await ex.etape('Vue de Sylvain (tiers)', async () => {
      await A.ouvrirConversationTiers(sylvain);
      await verifierFil(ex, sylvain, EVTS.sylvain, 'Sylvain');
      await ex.verifierAbsent(sylvain, 'Kevin', 'Sylvain ne sait pas que Kevin avait accepté');
    });

    await ex.etape('Kevin, désisté, retrouve le fil via un message d\'Eliot', async () => {
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await A.envoyerMessage(eliot, 'Pas de souci Kevin');
      await A.ouvrirConversationDepuisBox(kevin, 'Eliot Martin');
      await verifierFil(ex, kevin, [...EVTS.kevinAvantDesistement, "Tu ne prends plus la place d'Eliot.", 'Pas de souci Kevin'], 'Kevin après désistement', 5);
    });

    await ex.etape('Persistance : nouvelle session d\'Eliot', async () => {
      const e2 = await ex.redemarrer('eliot');
      await A.ouvrirConversationTitulaire(e2, 'Kevin Arner');
      await verifierFil(ex, e2, [...EVTS.eliotKevin, 'Pas de souci Kevin'], 'nouvelle session, Eliot ↔ Kevin', 5);
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
