// PERSONNE DE CONFIANCE AVANT TOUTE DEMANDE — "On compte sur toi", fiche
// tiers, droits limités (écran et API), pas de Swend "à venir".
import * as A from '../lib/actions.mjs';
import { lireComme, FICHES } from '../lib/donnees.mjs';

export default {
  nom: 'tiers_avant_demande',
  titre: 'Kevin et Sylvain avant toute demande : On compte sur toi, droits limités',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();

    await ex.etape('Accueil de Kevin et Sylvain', async () => {
      for (const a of [kevin, sylvain]) {
        const p = a.compte.prenom;
        await a.accueil();
        await ex.verifierTexte(a, 'ON COMPTE SUR TOI', `${p} : "On compte sur toi"`);
        await ex.verifierTexte(a, 'Eliot compte sur toi pour un Swend', `${p} : "Eliot compte sur toi pour un Swend"`);
        await ex.verifierTexte(a, /Mes Swends\s+0 à venir/, `${p} : 0 Swend à venir`);
        await ex.verifierAbsent(a, "UNE DEMANDE T'ATTEND", `${p} : aucune demande en attente`);
        await ex.verifierAbsent(a, 'TON PROCHAIN SWEND', `${p} : pas de "Ton prochain Swend"`);
      }
    });

    await ex.etape('Kevin ouvre le Swend depuis "Voir le Swend"', async () => {
      await kevin.accueil();
      await kevin.cliquer('Voir le Swend');
      await ex.verifierTexte(kevin, "Eliot peut faire appel à toi en cas d'imprévu.", 'Kevin : "Eliot peut faire appel à toi"');
      await ex.verifierTexte(kevin, "Tu n'as rien à faire pour le moment.", 'Kevin : "Tu n\'as rien à faire pour le moment."');
      await ex.verifierTexte(kevin, 'Avec David', 'Kevin voit avec qui est le Swend');
      await ex.verifier('Kevin : bouton "Écrire à Eliot"', async () => (await kevin.nombreDeBoutons('Écrire à Eliot')) === 1);
      for (const b of ['Un imprévu ?', 'Modifier ma liste', 'Discuter']) {
        await ex.verifier(`Kevin : pas de bouton "${b}"`, async () => (await kevin.nombreDeBoutons(b)) === 0);
      }
      for (const n of ['Sylvain', 'Tom', 'Léo', 'Nina']) await ex.verifierAbsent(kevin, n, `Kevin ne voit pas ${n}`);
    });

    await ex.etape('API : Kevin ne lit que sa propre fiche', async () => {
      const fiches = await lireComme('kevin', 'remplacants', 'select=id');
      await ex.verifier('Kevin lit exactement 1 fiche : la sienne',
        () => fiches.length === 1 && fiches[0].id === FICHES.kevin, { obtenu: () => JSON.stringify(fiches) });
      const messages = await lireComme('kevin', 'messages', 'select=id');
      await ex.verifier('Kevin ne lit aucun message', () => messages.length === 0, { obtenu: () => JSON.stringify(messages) });
    });

    await ex.etape('Kevin écrit à Eliot avant toute demande', async () => {
      await A.ouvrirConversationTiers(kevin);
      await ex.verifierTexte(kevin, "Eliot peut faire appel à toi en cas d'imprévu.", 'bandeau de la conversation (aucune demande)');
      await ex.verifier('pas de bouton "Accepter" sans demande', async () => (await kevin.nombreDeBoutons('Accepter')) === 0);
      await A.envoyerMessage(kevin, 'Bonjour Eliot, je suis dispo si besoin');
      const eliot = await ex.eliot();
      await eliot.accueil();
      await ex.verifierTexte(eliot, 'Kevin Arner vous a écrit', 'Eliot : box "Kevin Arner vous a écrit"');
    });
  },
};
