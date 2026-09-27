// D-008 — INDISPONIBILITÉ SPONTANÉE — Kevin, simplement prévu, indique
// "Je ne serai pas disponible" puis "Je suis finalement disponible".
// Eliot est prévenu, les listes et "Un imprévu ?" suivent, le refus
// reste définitif, David ne voit rien.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const drapeau = () => sql(`select indisponible_spontanement from remplacants where id = '${FICHES.kevin}'`);
const notifsEliot = () => sql(`select coalesce(string_agg(corps, ' | ' order by id), '') from notifications_log where profile_id = '${COMPTES.eliot.id}'`);

export default {
  nom: 'indisponibilite_spontanee',
  titre: 'Kevin : "Je ne serai pas disponible" puis "Je suis finalement disponible"',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Kevin, simplement prévu, voit l\'action', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, 'Eliot compte sur toi pour un Swend', 'Kevin : "Eliot compte sur toi"');
      await ex.verifier('"Je ne serai pas disponible" visible', async () => (await kevin.nombreDeBoutons('Je ne serai pas disponible')) === 1);
    });

    await ex.etape('Kevin se déclare indisponible', async () => {
      await A.seDeclarerIndisponible(kevin);
      await ex.verifier('drapeau posé, aucune demande', () => drapeau() === 't' && demande(FICHES.kevin) === '|f',
        { obtenu: () => `${drapeau()} / ${demande(FICHES.kevin)}` });
      await ex.verifierTexte(kevin, 'Eliot compte sur toi pour un Swend', 'Kevin reste dans "On compte sur toi"');
      await ex.verifierTexte(kevin, 'Tu as indiqué que tu ne seras pas disponible', 'Kevin : "Tu as indiqué que tu ne seras pas disponible"');
      await ex.verifierTexte(kevin, /Mes Swends\s+0 à venir/, 'Kevin : toujours 0 à venir');
      await ex.verifier('Eliot notifié (push)', () => notifsEliot() === "Kevin ne sera pas disponible en cas d'imprévu pour ce Swend.", { obtenu: notifsEliot });
    });

    await ex.etape('Eliot est informé dans l\'app et Kevin n\'est plus proposé', async () => {
      await eliot.accueil();
      await ex.verifierTexte(eliot, "Kevin ne sera pas disponible en cas d'imprévu.", 'Eliot : box "Kevin ne sera pas disponible"');
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, /EN CAS D'IMPRÉVU\s+Sylvain, Tom/, 'EN CAS D\'IMPRÉVU : "Sylvain, Tom" (Kevin retiré des disponibles)');
      await eliot.cliquer('Modifier ma liste');
      await ex.verifierTexte(eliot, /Kevin Arner\s+Indisponible/, 'Modifier ma liste : Kevin "Indisponible"');
      await eliot.accueil({ rafraichir: false });
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, /Kevin Arner\s+Indisponible/, 'Un imprévu ? : Kevin "Indisponible"');
      await ex.verifier('Un imprévu ? : seul Sylvain en "Lui demander"', async () => (await eliot.nombreDeBoutons('Lui demander')) === 1);
      await A.ouvrirBox(eliot, "Kevin ne sera pas disponible en cas d'imprévu.");
      await ex.verifierTexte(eliot, "Kevin ne sera pas disponible en cas d'imprévu.", 'l\'événement figure dans la conversation');
      await eliot.accueil();
      await ex.verifierAbsent(eliot, "Kevin ne sera pas disponible en cas d'imprévu.", 'box disparue une fois la conversation ouverte');
    });

    await ex.etape('Fiche du Swend côté Kevin', async () => {
      await kevin.accueil();
      await kevin.cliquer('Voir le Swend');
      await ex.verifierTexte(kevin, 'Tu as indiqué que tu ne seras pas disponible pour ce Swend. Eliot le sait.', 'fiche : état indisponible');
      await ex.verifier('fiche : "Je suis finalement disponible"', async () => (await kevin.nombreDeBoutons('Je suis finalement disponible')) === 1);
    });

    await ex.etape('Kevin redevient disponible', async () => {
      await A.seDeclarerDisponible(kevin);
      await ex.verifier('drapeau levé', () => drapeau() === 'f', { obtenu: drapeau });
      await ex.verifierTexte(kevin, "Tu pourrais prendre sa place en cas d'imprévu.", 'Kevin : de nouveau "Tu pourrais prendre sa place"');
      await ex.verifier('Eliot notifié du retour (2 notifications au total, aucun doublon)',
        () => notifsEliot() === "Kevin ne sera pas disponible en cas d'imprévu pour ce Swend. | Kevin est de nouveau disponible en cas d'imprévu pour ce Swend.",
        { obtenu: notifsEliot });
      await eliot.accueil();
      await ex.verifierTexte(eliot, "Kevin est de nouveau disponible en cas d'imprévu.", 'Eliot : box "Kevin est de nouveau disponible"');
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, /(Kevin, Sylvain|Sylvain, Kevin), Tom/, 'EN CAS D\'IMPRÉVU : Kevin de nouveau disponible');
    });

    await ex.etape('Kevin de nouveau sollicitable ; pendant une demande, pas d\'action', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await ex.verifier('demande envoyée à Kevin', () => demande(FICHES.kevin) === 'envoyee|f', { obtenu: () => demande(FICHES.kevin) });
      await kevin.accueil();
      await ex.verifierTexte(kevin, "UNE DEMANDE T'ATTEND", 'Kevin : "Une demande t\'attend"');
      await ex.verifier('pendant la demande : pas de "Je ne serai pas disponible"', async () => (await kevin.nombreDeBoutons('Je ne serai pas disponible')) === 0);
    });

    await ex.etape('Le refus reste définitif', async () => {
      await A.repondre(kevin, false);
      await ex.verifier('refus enregistré, sans drapeau', () => demande(FICHES.kevin) === 'refusee|f' && drapeau() === 'f');
      await kevin.accueil();
      await ex.verifierAbsent(kevin, 'Je suis finalement disponible', 'après un refus : pas de "Je suis finalement disponible"');
      await ex.verifierAbsent(kevin, 'Je ne serai pas disponible', 'après un refus : pas de "Je ne serai pas disponible"');
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, /Kevin Arner\s+Indisponible/, 'Eliot : Kevin "Indisponible" (refus)');
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
