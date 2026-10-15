// D-027 lot 3a — « Un imprévu ? » de bout en bout : envoi groupé avec une
// personne sans compte (Tom), acceptation de Kevin (plus aucune action),
// désistement (« Kevin ne peut finalement plus venir. » / demandes
// réactivées, « Renvoyer le message à Tom »), puis nouvelle sollicitation
// (retour à « C'est envoyé. »). David ne voit rien.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

export default {
  nom: 'imprevu_desistement_reactivation',
  titre: 'Envoi groupé avec une personne sans compte, acceptation, désistement, réactivation à l’écran',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    ex.memo.david = await photoDavid(ex);
    const dernierLien = () => eliot.liensOuverts.at(-1) || '';

    await ex.etape('Kevin et Tom (sans compte) dans un même envoi', async () => {
      await A.ouvrirImprevu(eliot);
      await A.cocher(eliot, 'Kevin Arner');
      await A.cocher(eliot, 'Tom Petit');
      await eliot.cliquer('Envoyer 2 demandes');
      await eliot.cliquer('Envoyer les demandes');
      await ex.verifier('deux demandes envoyées ensemble', () => demande(FICHES.kevin) === 'envoyee|f' && demande(FICHES.tom) === 'envoyee|f',
        { obtenu: () => `${demande(FICHES.kevin)} / ${demande(FICHES.tom)}` });
      await ex.verifierTexte(eliot, 'Demande envoyée à Tom', 'Tom : « Demande envoyée à Tom »');
      await ex.verifierTexte(eliot, 'Tom n’a pas encore Swend : envoie-lui un message pour lui expliquer et lui permettre de répondre depuis l’app.', 'Tom : message à envoyer soi-même');
      await eliot.cliquer('Plus tard');
      await ex.verifierTexte(eliot, 'C’est envoyé.', 'attente : « C’est envoyé. »');
      await ex.verifierTexte(eliot, /Tom Petit\s+En attente/, 'Tom : « En attente »');
      await ex.verifier('Tom : « Envoyer le message » ; Kevin : « Discuter »', async () =>
        (await eliot.nombreDeBoutons('Envoyer le message')) === 1 && (await eliot.nombreDeBoutons('Discuter')) === 1);
      await eliot.cliquer('Envoyer le message');
      await eliot.cliquer('Messages');
      await ex.verifier('message d’urgence vers Tom', () => dernierLien().startsWith('sms:'), { obtenu: dernierLien });
    });

    await ex.etape('Kevin accepte : plus aucune action d’imprévu', async () => {
      await A.repondre(kevin, true);
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Kevin a accepté.', '« Kevin a accepté. »');
      await ex.verifierTexte(eliot, 'Kevin sera là à ta place le jour J.', '« Kevin sera là à ta place le jour J. »');
      await ex.verifier('aucune case, ni retour, ni dernier recours', async () =>
        (await eliot.page.getByRole('checkbox').count()) === 0
        && (await eliot.nombreDeBoutons('Je peux finalement venir')) === 0
        && (await eliot.nombreDeBoutons('Je n’ai personne d’autre')) === 0);
    });

    await ex.etape('Kevin se désiste : demande de Tom réactivée, message à renvoyer', async () => {
      await A.seDesister(kevin);
      await ex.verifier('Tom de nouveau en attente, message à renvoyer',
        () => demande(FICHES.tom) === 'envoyee|f' && sql(`select message_a_renvoyer from remplacants where id = '${FICHES.tom}'`) === 't');
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Kevin ne peut finalement plus venir.', 'fiche : « Kevin ne peut finalement plus venir. »');
      await ex.verifierTexte(eliot, 'Renvoyer le message à Tom', 'fiche : « Renvoyer le message à Tom »');
      await eliot.cliquer('Un imprévu ?');
      await eliot.attendreTexte('Kevin ne peut finalement plus venir.');
      await ex.verifierTexte(eliot, 'Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.', 'écran : demandes réactivées');
      await ex.verifierTexte(eliot, /Kevin Arner\s+Indisponible/, 'Kevin : « Indisponible »');
      await ex.verifierTexte(eliot, 'La demande attend de nouveau sa réponse.', 'Tom : « La demande attend de nouveau sa réponse. »');
      await eliot.cliquer('Renvoyer le message à Tom');
      await eliot.cliquer('Messages');
      await ex.verifier('message renvoyé à Tom', () => dernierLien().startsWith('sms:'), { obtenu: dernierLien });
      await ex.verifier('action disparue (message_a_renvoyer effacé)',
        () => sql(`select message_a_renvoyer from remplacants where id = '${FICHES.tom}'`) === 'f');
      await ex.verifier('« Je peux finalement venir » de nouveau possible', async () => (await eliot.nombreDeBoutons('Je peux finalement venir')) === 1);
    });

    await ex.etape('Nouvelle sollicitation (Sylvain) : retour à « C’est envoyé. »', async () => {
      await A.demander(eliot, 'Sylvain Landiech');
      await ex.verifierTexte(eliot, 'C’est envoyé.', '« C’est envoyé. »');
      await ex.verifierAbsent(eliot, 'Kevin ne peut finalement plus venir.', 'plus d’en-tête de désistement');
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david, { nomsInterdits: ['Kevin', 'Sylvain', 'Tom'] });
    });
  },
};
