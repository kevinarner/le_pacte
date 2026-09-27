// D-015 — NOTIFICATIONS DES ACTIONS DIRECTES — annulation (→ Sylvain),
// refus, acceptation, désistement (→ Eliot) : push (notifications_log) +
// box sur l'accueil, sans doublon, et rien pour David.
import * as A from '../lib/actions.mjs';
import { sql } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const notifs = (nom) => sql(`select coalesce(string_agg(corps, ' | ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);

export default {
  nom: 'notifications_actions',
  titre: 'Annulation, refus, acceptation, désistement : la personne concernée est prévenue',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Demandes à Kevin et Sylvain : notifiées une seule fois, sans box', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Sylvain Landiech');
      await ex.verifier('Kevin : une notification "demande"', () => notifs('kevin') === 'Eliot Martin te demande de prendre sa place pour un Swend.', { obtenu: () => notifs('kevin') });
      await ex.verifier('Eliot : aucune notification pour ses propres demandes', () => notifs('eliot') === '', { obtenu: () => notifs('eliot') });
      await kevin.accueil();
      await ex.verifierTexte(kevin, "UNE DEMANDE T'ATTEND", 'Kevin : carte "Une demande t\'attend"');
      await ex.verifierAbsent(kevin, "Eliot t'a demandé de prendre sa place.", 'Kevin : pas de box en double pour la demande');
    });

    await ex.etape('Eliot annule la demande à Sylvain → Sylvain prévenu', async () => {
      await A.ouvrirImprevu(eliot);
      await A.annulerDemande(eliot, 'Sylvain Landiech');
      await ex.verifier('Sylvain : push "Eliot a annulé sa demande."',
        () => notifs('sylvain').endsWith('Eliot a annulé sa demande.'), { obtenu: () => notifs('sylvain') });
      await sylvain.accueil();
      await ex.verifierTexte(sylvain, 'Eliot a annulé sa demande.', 'Sylvain : box "Eliot a annulé sa demande."');
      await A.ouvrirBox(sylvain, 'Eliot a annulé sa demande.');
      await sylvain.accueil();
      await ex.verifierAbsent(sylvain, 'Eliot a annulé sa demande.', 'Sylvain : box disparue une fois lue');
    });

    await ex.etape('Sylvain, redemandé, refuse → Eliot prévenu', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(sylvain, false);
      await ex.verifier('Eliot : push "Sylvain ne peut pas prendre votre place."',
        () => notifs('eliot') === 'Sylvain ne peut pas prendre votre place.', { obtenu: () => notifs('eliot') });
      await eliot.accueil();
      await ex.verifierTexte(eliot, 'Sylvain a refusé de prendre ta place.', 'Eliot : box "Sylvain a refusé"');
    });

    await ex.etape('Kevin accepte → Eliot prévenu', async () => {
      await A.repondre(kevin, true);
      await ex.verifier('Eliot : push "Kevin a accepté de prendre votre place."',
        () => notifs('eliot') === 'Sylvain ne peut pas prendre votre place. | Kevin a accepté de prendre votre place.', { obtenu: () => notifs('eliot') });
      await ex.verifier('Kevin : aucune notification pour sa propre réponse', () => notifs('kevin') === 'Eliot Martin te demande de prendre sa place pour un Swend.', { obtenu: () => notifs('kevin') });
      await eliot.accueil();
      await ex.verifierTexte(eliot, 'Kevin a accepté de prendre ta place.', 'Eliot : box "Kevin a accepté"');
      await ex.verifierTexte(eliot, 'Sylvain a refusé de prendre ta place.', 'Eliot : box Sylvain toujours là (une box par conversation)');
      await A.ouvrirBox(eliot, 'Kevin a accepté de prendre ta place.');
      await eliot.accueil();
      await ex.verifierAbsent(eliot, 'Kevin a accepté de prendre ta place.', 'Eliot : box Kevin lue');
      await ex.verifierTexte(eliot, 'Sylvain a refusé de prendre ta place.', 'Eliot : box Sylvain encore non lue');
    });

    await ex.etape('Kevin se désiste → Eliot prévenu', async () => {
      await A.seDesister(kevin);
      await ex.verifier('Eliot : push "Kevin ne peut finalement plus prendre votre place."',
        () => notifs('eliot').endsWith('Kevin ne peut finalement plus prendre votre place.'), { obtenu: () => notifs('eliot') });
      await ex.verifier('Eliot : 3 notifications au total (refus, acceptation, désistement), aucun doublon',
        () => sql(`select count(*) from notifications_log where profile_id = '${COMPTES.eliot.id}'`) === '3');
      await eliot.accueil();
      await ex.verifierTexte(eliot, 'Kevin ne peut finalement plus prendre ta place.', 'Eliot : box "Kevin ne peut finalement plus"');
    });

    await ex.etape('Nouvelle session : les alertes non lues persistent', async () => {
      const e2 = await ex.redemarrer('eliot');
      await e2.accueil();
      await ex.verifierTexte(e2, 'Kevin ne peut finalement plus prendre ta place.', 'nouvelle session : box Kevin toujours là');
      await ex.verifierTexte(e2, 'Sylvain a refusé de prendre ta place.', 'nouvelle session : box Sylvain toujours là');
    });

    await ex.etape('David ne voit rien et ne reçoit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
