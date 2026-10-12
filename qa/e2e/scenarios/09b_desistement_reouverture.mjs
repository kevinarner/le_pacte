// DÉSISTEMENT — réactivation automatique (D-027) : la demande de Sylvain,
// en attente avant l'acceptation de Kevin puis close par elle, attend de
// nouveau sa réponse dès que Kevin se désiste ; Eliot n'a rien à refaire.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const pushs = (nom) => sql(`select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);

export default {
  nom: 'desistement_reouverture',
  titre: 'Après le désistement de Kevin, la demande de Sylvain (close) est réactivée',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Demandes à Kevin et Sylvain, Kevin accepte : Sylvain n\'a plus besoin de répondre', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(kevin, true);
      await ex.verifier('Sylvain clôturé', () => demande(FICHES.sylvain) === 'cloturee|f', { obtenu: () => demande(FICHES.sylvain) });
      await ex.verifier('Sylvain : push "Plus besoin de répondre / La place a été prise pour ce Swend."',
        () => pushs('sylvain').endsWith('Plus besoin de répondre|La place a été prise pour ce Swend.'), { obtenu: () => pushs('sylvain') });
    });

    await ex.etape('Kevin se désiste : la demande de Sylvain attend de nouveau sa réponse', async () => {
      await A.seDesister(kevin);
      await ex.verifier('Sylvain de nouveau "envoyee"', () => demande(FICHES.sylvain) === 'envoyee|f', { obtenu: () => demande(FICHES.sylvain) });
      await ex.verifier('Kevin "desistee"', () => demande(FICHES.kevin) === 'desistee|f', { obtenu: () => demande(FICHES.kevin) });
      await ex.verifier('Tom (jamais sollicité) reste seulement prévu', () => demande(FICHES.tom) === '|f', { obtenu: () => demande(FICHES.tom) });
      await ex.verifier('Sylvain : push "Ta réponse est finalement attendue"',
        () => pushs('sylvain').endsWith('Ta réponse est finalement attendue|La place est à nouveau disponible pour ce Swend.'), { obtenu: () => pushs('sylvain') });
      await ex.verifier('Eliot : push "Kevin ne peut finalement plus venir / Les personnes qui n’avaient pas encore répondu…"',
        () => pushs('eliot').endsWith('Kevin ne peut finalement plus venir|Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.'), { obtenu: () => pushs('eliot') });
    });

    await ex.etape('Eliot : Sylvain en attente, rien à refaire', async () => {
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, /Kevin Arner\s+Indisponible/, 'Kevin "Indisponible"');
      await ex.verifierTexte(eliot, /Sylvain Landiech\s+En attente/, 'Sylvain "En attente"');
      await ex.verifier('aucun "Lui demander" pour Sylvain', async () => (await eliot.nombreDeBoutons('Lui demander')) === 0);
    });

    await ex.etape('Sylvain voit la demande et accepte', async () => {
      await sylvain.accueil();
      await ex.verifierTexte(sylvain, "UNE DEMANDE T'ATTEND", 'Sylvain : "Une demande t\'attend"');
      await A.repondre(sylvain, true);
      await ex.verifier('Sylvain sélectionné', () => demande(FICHES.sylvain) === 'acceptee|t', { obtenu: () => demande(FICHES.sylvain) });
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Sylvain prendra votre place', 'Eliot : "Sylvain prendra votre place"');
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
