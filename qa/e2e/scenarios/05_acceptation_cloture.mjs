// ACCEPTATION ET CLÔTURE — Kevin accepte, la demande de Sylvain est close,
// Eliot garde Discuter, compteurs, confidentialité de David.
import * as A from '../lib/actions.mjs';
import { demande, FICHES } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

export default {
  nom: 'acceptation_cloture',
  titre: 'Kevin accepte, la demande à Sylvain est close, Eliot garde Discuter',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Eliot demande à Kevin et à Sylvain ; Kevin accepte', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(kevin, true);
      await ex.verifier('Kevin sélectionné, Sylvain clôturé',
        () => demande(FICHES.kevin) === 'acceptee|t' && demande(FICHES.sylvain) === 'cloturee|f',
        { obtenu: () => `Kevin ${demande(FICHES.kevin)} / Sylvain ${demande(FICHES.sylvain)}` });
      await ex.verifier('Tom (jamais sollicité) reste sans demande', () => demande(FICHES.tom) === '|f', { obtenu: () => demande(FICHES.tom) });
    });

    await ex.etape('Sylvain : la demande n\'est plus d\'actualité', async () => {
      await sylvain.accueil();
      await ex.verifierAbsent(sylvain, "UNE DEMANDE T'ATTEND", 'Sylvain : plus de demande sur l\'accueil');
      await ex.verifierAbsent(sylvain, 'Eliot a un imprévu', 'Sylvain : plus de "Eliot a un imprévu"');
      await A.ouvrirSwend(sylvain, /Swend d'Eliot avec David/);
      await ex.verifierTexte(sylvain, "C'est bon, quelqu'un a pu prendre la place d'Eliot.", 'Sylvain : "C\'est bon, quelqu\'un a pu prendre la place"');
      await ex.verifierAbsent(sylvain, 'Kevin', 'Sylvain ne sait pas que c\'est Kevin');
      await ex.verifier('Sylvain : aucun bouton "Accepter"', async () => (await sylvain.nombreDeBoutons('Accepter')) === 0);
    });

    await ex.etape('Eliot : Kevin prendra votre place, Discuter conservé', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Kevin prendra votre place', 'Eliot : "Kevin prendra votre place"');
      await ex.verifierTexte(eliot, 'Votre Swend reste scellé.', 'Eliot : "Votre Swend reste scellé."');
      await ex.verifier('Eliot : "Écrire à Kevin"', async () => (await eliot.nombreDeBoutons('Écrire à Kevin')) === 1);
      await eliot.cliquer('Discuter');
      await ex.verifierTexte(eliot, 'Sylvain Landiech', '"Discuter" propose toujours Sylvain');
      await eliot.cliquerTexte('Sylvain Landiech');
      await A.envoyerMessage(eliot, 'Merci quand même Sylvain');
      await sylvain.accueil();
      await ex.verifierTexte(sylvain, 'Eliot Martin vous a écrit', 'Sylvain reçoit le message d\'Eliot');
    });

    await ex.etape('Un imprévu ? et Modifier ma liste après acceptation', async () => {
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Kevin prendra votre place.', 'Un imprévu ? : "Kevin prendra votre place."');
      await ex.verifier('Un imprévu ? : plus aucun "Lui demander"', async () => (await eliot.nombreDeBoutons('Lui demander')) === 0);
      await eliot.accueil({ rafraichir: false });
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Voir les personnes prévues');
      await ex.verifierTexte(eliot, /Kevin Arner\s+Prend ta place ✓/, 'Modifier ma liste : Kevin "Prend ta place ✓"');
      await ex.verifier('Kevin ne peut plus être retiré', async () => (await eliot.nombreDeBoutons('Retirer')) === 2);
    });

    await ex.etape('Compteurs : le Swend compte pour Kevin, plus pour Eliot', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, /Mes Swends\s+1 à venir/, 'Kevin : 1 Swend à venir');
      await ex.verifierTexte(kevin, "Tu prends la place d'Eliot", 'Kevin : "Tu prends la place d\'Eliot"');
      await eliot.accueil();
      await ex.verifierTexte(eliot, /Mes Swends\s+1 à venir/, 'Eliot : le Swend reste dans ses Swends (titulaire)');
      await sylvain.accueil();
      await ex.verifierTexte(sylvain, /Mes Swends\s+0 à venir/, 'Sylvain : 0 Swend à venir');
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
