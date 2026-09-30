// D-023a — RELIRE APRÈS ANNULATION. Kevin a accepté de prendre la place
// d'Eliot ; Eliot a aussi écrit à Sylvain ; Tom n'a jamais rien échangé.
// Eliot annule : depuis la fiche du Swend annulé, « Relire une conversation »
// propose Kevin et Sylvain (pas Tom), en lecture seule, sans rappeler de
// remplacement. Kevin, qui garde le Swend annulé dans son historique, relit
// aussi sa conversation. David ne voit rien.
import * as A from '../lib/actions.mjs';
import { sql, lireComme } from '../lib/donnees.mjs';

const champSaisie = (a) => a.page.getByRole('textbox', { name: 'Écrire un message…' }).count();

export default {
  nom: 'gel_relecture_annulation',
  titre: 'Swend annulé : relecture des conversations actives (titulaire et remplaçant), sans écriture',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();

    await ex.etape('Kevin accepte ; Eliot écrit à Kevin et à Sylvain', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.repondre(kevin, true);
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await A.envoyerMessage(eliot, 'Merci Kevin !');
      await A.ouvrirConversationTitulaire(eliot, 'Sylvain Landiech');
      await A.envoyerMessage(eliot, 'Et toi Sylvain ?');
    });

    await ex.etape('Eliot annule le Swend', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Annuler le Swend');
      await eliot.cliquer('Annuler le Swend');
      await ex.verifier('Swend annulé', () => sql('select statut from pactes') === 'annule');
    });

    await ex.etape('Eliot : choix entre les conversations actives, lecture seule', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierAbsent(eliot, 'a pris votre place', 'Eliot : aucun rappel de remplacement sur un Swend annulé');
      await eliot.cliquer('Relire une conversation');
      await ex.verifierTexte(eliot, 'Relire la conversation avec…', 'Eliot : choix proposé');
      await ex.verifierTexte(eliot, 'Kevin Arner', 'Eliot : Kevin proposé');
      await ex.verifierTexte(eliot, 'Sylvain Landiech', 'Eliot : Sylvain proposé');
      await ex.verifierAbsent(eliot, 'Tom Petit', 'Eliot : fil vierge (Tom) non proposé');
      await eliot.cliquerTexte('Kevin Arner');
      await eliot.attendreTexte('Merci Kevin !');
      await ex.verifierTexte(eliot, 'Cette conversation est terminée. Elle reste consultable.', 'Eliot : lecture seule');
      await ex.verifier('Eliot : aucune zone de saisie', async () => (await champSaisie(eliot)) === 0);
    });

    await ex.etape('Kevin (remplaçant accepté) relit sa conversation depuis le Swend annulé', async () => {
      await A.ouvrirSwend(kevin, /Swend d'Eliot avec David/);
      await ex.verifierTexte(kevin, 'Ce Swend a été annulé.', 'Kevin : « Ce Swend a été annulé. »');
      await kevin.cliquer('Relire la conversation');
      await kevin.attendreTexte('Merci Kevin !');
      await ex.verifierTexte(kevin, 'Cette conversation est terminée. Elle reste consultable.', 'Kevin : lecture seule');
      await ex.verifier('Kevin : aucune zone de saisie', async () => (await champSaisie(kevin)) === 0);
    });

    await ex.etape('Sylvain garde l\'accès à son historique ; David ne voit rien', async () => {
      const s = await lireComme('sylvain', 'messages');
      await ex.verifier('Sylvain lit toujours le message d\'Eliot (API)', () => s.some((m) => m.contenu === 'Et toi Sylvain ?'),
        { obtenu: () => JSON.stringify(s) });
      const m = await lireComme('david', 'messages');
      const e = await lireComme('david', 'evenements_fil');
      await ex.verifier('David : aucun message ni événement lisible', () => m.length === 0 && e.length === 0,
        { obtenu: () => `${m.length} messages, ${e.length} événements` });
    });
  },
};
