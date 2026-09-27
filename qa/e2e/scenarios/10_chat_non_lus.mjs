// CHAT — messages dans les deux sens, une box par conversation non lue,
// lu/non lu persistant, ordre chronologique, rien chez David.
import * as A from '../lib/actions.mjs';
import { dansLOrdre } from '../lib/execution.mjs';
import { lireComme } from '../lib/donnees.mjs';

export default {
  nom: 'chat_non_lus',
  titre: 'Chat Eliot ↔ Kevin / Sylvain : boxes non lues, ordre, persistance',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();

    await ex.etape('Kevin puis Sylvain écrivent à Eliot', async () => {
      await A.ouvrirConversationTiers(kevin);
      await A.envoyerMessage(kevin, 'Salut Eliot, ici Kevin');
      await ex.verifierTexte(kevin, 'Salut Eliot, ici Kevin', 'Kevin voit son message');
      await A.ouvrirConversationTiers(sylvain);
      await A.envoyerMessage(sylvain, 'Coucou Eliot, ici Sylvain');
      await kevin.accueil();
      await ex.verifierAbsent(kevin, 'vous a écrit', 'Kevin : pas de box pour son propre message');
    });

    await ex.etape('Eliot : une box par conversation non lue', async () => {
      const eliot = await ex.eliot();
      await eliot.accueil();
      await ex.verifierTexte(eliot, 'Kevin Arner vous a écrit', 'box "Kevin Arner vous a écrit"');
      await ex.verifierTexte(eliot, 'Sylvain Landiech vous a écrit', 'box "Sylvain Landiech vous a écrit"');
    });

    await ex.etape('Eliot lit Kevin et répond', async () => {
      const eliot = await ex.eliot();
      await A.ouvrirConversationDepuisBox(eliot, 'Kevin Arner');
      await ex.verifierTexte(eliot, 'Salut Eliot, ici Kevin', 'Eliot lit le message de Kevin');
      await ex.verifierAbsent(eliot, 'ici Sylvain', 'la conversation de Kevin ne contient pas celle de Sylvain');
      await A.envoyerMessage(eliot, 'Salut Kevin, bien reçu');
      await eliot.accueil();
      await ex.verifierAbsent(eliot, 'Kevin Arner vous a écrit', 'box Kevin disparue une fois lue');
      await ex.verifierTexte(eliot, 'Sylvain Landiech vous a écrit', 'box Sylvain toujours là (non lue)');
    });

    await ex.etape('Kevin reçoit la réponse (notification symétrique)', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, 'Eliot Martin vous a écrit', 'Kevin : box "Eliot Martin vous a écrit"');
      await A.ouvrirConversationDepuisBox(kevin, 'Eliot Martin');
      await ex.verifier('ordre chronologique : message de Kevin puis réponse d\'Eliot',
        async () => dansLOrdre(await kevin.texte(), ['Salut Eliot, ici Kevin', 'Salut Kevin, bien reçu']),
        { obtenu: async () => (await kevin.texte()).replace(/\s+/g, ' ').slice(0, 400) });
      await kevin.accueil();
      await ex.verifierAbsent(kevin, 'Eliot Martin vous a écrit', 'Kevin : box disparue une fois lue');
    });

    await ex.etape('Lu / non lu persistant dans une nouvelle session', async () => {
      const eliot = await ex.redemarrer('eliot');
      await eliot.accueil();
      await ex.verifierTexte(eliot, 'Sylvain Landiech vous a écrit', 'nouvelle session : Sylvain toujours non lu');
      await ex.verifierAbsent(eliot, 'Kevin Arner vous a écrit', 'nouvelle session : Kevin toujours lu');
      const k = await ex.redemarrer('kevin');
      await k.accueil();
      await ex.verifierAbsent(k, 'vous a écrit', 'nouvelle session de Kevin : rien de non lu');
    });

    await ex.etape('Message reçu en direct, conversation ouverte', async () => {
      const eliot = await ex.eliot();
      const k = await ex.kevin();
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await A.ouvrirConversationTiers(k);
      await A.envoyerMessage(k, 'Tu es là ?');
      await ex.verifierTexte(eliot, 'Tu es là ?', 'Eliot voit le message sans rouvrir la conversation', 5000);
      await eliot.accueil();
      await ex.verifierAbsent(eliot, 'Kevin Arner vous a écrit', 'lu pendant qu\'il était affiché : pas de box');
    });

    await ex.etape('David : aucune box, aucun message lisible', async () => {
      const david = await ex.david();
      await david.accueil();
      await ex.verifierAbsent(david, 'vous a écrit', 'David : aucune box');
      const messages = await lireComme('david', 'messages', 'select=id');
      await ex.verifier('API : David ne lit aucun message', () => messages.length === 0, { obtenu: () => JSON.stringify(messages) });
    });
  },
};
