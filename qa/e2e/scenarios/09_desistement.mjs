// DÉSISTEMENT — Kevin accepte puis se désiste. Le refus de Sylvain reste
// un refus, la recherche rouvre sans demande automatique, Kevin ne voit
// plus le Swend, David ne sait rien.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

export default {
  nom: 'desistement',
  titre: 'Kevin se désiste : refus conservé, recherche rouverte, Kevin masqué',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Sylvain refuse, puis Kevin accepte', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(sylvain, false);
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.repondre(kevin, true);
      await ex.verifier('Kevin sélectionné, Sylvain toujours "refusee"',
        () => demande(FICHES.kevin) === 'acceptee|t' && demande(FICHES.sylvain) === 'refusee|f',
        { obtenu: () => `Kevin ${demande(FICHES.kevin)} / Sylvain ${demande(FICHES.sylvain)}` });
    });

    await ex.etape('Kevin se désiste depuis la fiche du Swend', async () => {
      await A.seDesister(kevin);
      await ex.verifier('Kevin "desistee", plus sélectionné', () => demande(FICHES.kevin) === 'desistee|f', { obtenu: () => demande(FICHES.kevin) });
      await ex.verifier('le refus de Sylvain est conservé', () => demande(FICHES.sylvain) === 'refusee|f', { obtenu: () => demande(FICHES.sylvain) });
      await ex.verifier('aucune demande envoyée automatiquement',
        () => sql(`select count(*) from remplacants where demande_statut = 'envoyee'`) === '0');
      await ex.verifier('le Swend reste scellé', () => sql('select statut from pactes') === 'confirme');
    });

    await ex.etape('Kevin ne voit plus ce Swend', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, /Mes Swends\s+0 à venir/, 'Kevin : 0 Swend à venir');
      await ex.verifierAbsent(kevin, "Tu prends la place d'Eliot", 'Kevin : plus "Tu prends la place d\'Eliot"');
      await ex.verifierAbsent(kevin, 'TON PROCHAIN SWEND', 'Kevin : plus de "Ton prochain Swend"');
      await ex.verifierAbsent(kevin, 'ON COMPTE SUR TOI', 'Kevin : plus dans "On compte sur toi"');
      await ex.verifierAbsent(kevin, 'Eliot compte sur toi pour un Swend', 'Kevin : plus de carte "Eliot compte sur toi"');
      await A.ouvrirMesSwends(kevin);
      await ex.verifierAbsent(kevin, "Swend d'Eliot avec David", 'Kevin : le Swend a disparu de "Mes Swends"');
    });

    await ex.etape('Eliot : la recherche est rouverte', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierAbsent(eliot, 'prendra votre place', 'Eliot : plus "Kevin prendra votre place"');
      await ex.verifierTexte(eliot, "EN CAS D'IMPRÉVU", 'Eliot : bloc "En cas d\'imprévu" de retour');
      await ex.verifierTexte(eliot, /EN CAS D'IMPRÉVU\s+Tom\s/, 'EN CAS D\'IMPRÉVU : seulement Tom (Kevin désisté, Sylvain a refusé)');
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, /Kevin Arner\s+Indisponible/, 'Un imprévu ? : Kevin "Indisponible"');
      await ex.verifierTexte(eliot, /Sylvain Landiech\s+Indisponible/, 'Un imprévu ? : Sylvain "Indisponible"');
      await ex.verifier('Un imprévu ? : Tom peut être sollicité', async () => (await eliot.nombreDeBoutons('Inviter et demander')) === 1);
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
