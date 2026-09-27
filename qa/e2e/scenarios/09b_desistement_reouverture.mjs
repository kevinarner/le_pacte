// DÉSISTEMENT — la personne dont la demande avait été close (quelqu'un
// d'autre avait accepté) redevient disponible, sans demande automatique.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';

export default {
  nom: 'desistement_reouverture',
  titre: 'Après le désistement de Kevin, Sylvain (clos) redevient disponible',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();

    await ex.etape('Demandes à Kevin et Sylvain, Kevin accepte, puis se désiste', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(kevin, true);
      await ex.verifier('Sylvain clôturé', () => demande(FICHES.sylvain) === 'cloturee|f', { obtenu: () => demande(FICHES.sylvain) });
      await A.seDesister(kevin);
      await ex.verifier('Sylvain rouvert, sans demande', () => demande(FICHES.sylvain) === '|f', { obtenu: () => demande(FICHES.sylvain) });
      await ex.verifier('aucune demande envoyée automatiquement',
        () => sql(`select count(*) from remplacants where demande_statut = 'envoyee'`) === '0');
    });

    await ex.etape('Eliot peut de nouveau solliciter Sylvain', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, /EN CAS D'IMPRÉVU\s+Sylvain, Tom/, 'EN CAS D\'IMPRÉVU : "Sylvain, Tom"');
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, /Kevin Arner\s+Indisponible/, 'Kevin "Indisponible"');
      await ex.verifier('"Lui demander" pour Sylvain', async () => (await eliot.nombreDeBoutons('Lui demander')) === 1);
      await sylvain.accueil();
      await ex.verifierAbsent(sylvain, "UNE DEMANDE T'ATTEND", 'Sylvain : pas de demande tant qu\'Eliot ne redemande pas');
      await ex.verifierTexte(sylvain, 'Eliot compte sur toi pour un Swend', 'Sylvain : de nouveau "Eliot compte sur toi"');
    });

    await ex.etape('Eliot redemande à Sylvain, qui accepte', async () => {
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(sylvain, true);
      await ex.verifier('Sylvain sélectionné', () => demande(FICHES.sylvain) === 'acceptee|t', { obtenu: () => demande(FICHES.sylvain) });
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Sylvain prendra votre place', 'Eliot : "Sylvain prendra votre place"');
    });
  },
};
