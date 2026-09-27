// UN IMPRÉVU ? — plusieurs demandes à la fois, annulation, refus,
// disponibilités, confidentialité de David.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

export default {
  nom: 'imprevu_demandes',
  titre: 'Demandes multiples, annulation, refus, disponibilités',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Écran "Un imprévu ?" : qui peut prendre la place', async () => {
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Qui peut prendre votre place ?', 'titre "Qui peut prendre votre place ?"');
      await ex.verifier('"Lui demander" pour Kevin et Sylvain (comptes)', async () => (await eliot.nombreDeBoutons('Lui demander')) === 2);
      await ex.verifier('"Inviter et demander" pour Tom (sans compte)', async () => (await eliot.nombreDeBoutons('Inviter et demander')) === 1);
      await ex.verifier('comptes Swend listés avant Tom',
        async () => (await eliot.positionY('Tom Petit')) > Math.max(await eliot.positionY('Kevin Arner'), await eliot.positionY('Sylvain Landiech')));
    });

    await ex.etape('Eliot demande à Kevin ET à Sylvain', async () => {
      await A.demander(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Sylvain Landiech');
      await ex.verifier('deux demandes "envoyee" en base',
        () => demande(FICHES.kevin) === 'envoyee|f' && demande(FICHES.sylvain) === 'envoyee|f',
        { obtenu: () => `${demande(FICHES.kevin)} / ${demande(FICHES.sylvain)}` });
      await ex.verifierTexte(eliot, /Kevin Arner\s+En attente/, 'Kevin : badge "En attente"');
      await ex.verifierTexte(eliot, /Sylvain Landiech\s+En attente/, 'Sylvain : badge "En attente"');
      for (const a of [kevin, sylvain]) {
        await a.accueil();
        await ex.verifierTexte(a, "UNE DEMANDE T'ATTEND", `${a.compte.prenom} : "Une demande t'attend"`);
        await ex.verifierTexte(a, 'Eliot a un imprévu', `${a.compte.prenom} : "Eliot a un imprévu"`);
      }
      await ex.verifier('Kevin et Sylvain notifiés (1 notification chacun)',
        () => sql(`select count(distinct profile_id) from notifications_log where profile_id in ('${COMPTES.kevin.id}', '${COMPTES.sylvain.id}')`) === '2');
    });

    await ex.etape('Eliot annule la demande à Sylvain', async () => {
      await A.ouvrirImprevu(eliot);
      await A.annulerDemande(eliot, 'Sylvain Landiech');
      await ex.verifier('demande de Sylvain annulée en base', () => demande(FICHES.sylvain) === '|f', { obtenu: () => demande(FICHES.sylvain) });
      await ex.verifier('Sylvain redevient "Lui demander"', async () => (await eliot.nombreDeBoutons('Lui demander')) === 1);
      await sylvain.accueil();
      await ex.verifierAbsent(sylvain, "UNE DEMANDE T'ATTEND", 'Sylvain : la demande a disparu de son accueil');
      await ex.verifierTexte(sylvain, 'Eliot compte sur toi pour un Swend', 'Sylvain : de nouveau "Eliot compte sur toi"');
    });

    await ex.etape('Eliot redemande à Sylvain, qui refuse', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(sylvain, false);
      await ex.verifier('refus enregistré', () => demande(FICHES.sylvain) === 'refusee|f', { obtenu: () => demande(FICHES.sylvain) });
      await A.ouvrirSwend(sylvain, /Swend d'Eliot avec David/);
      await ex.verifierTexte(sylvain, "Tu as indiqué ne pas être disponible pour prendre la place d'Eliot.", 'Sylvain : "Tu as indiqué ne pas être disponible"');
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, /Sylvain Landiech\s+Indisponible/, 'Eliot : Sylvain "Indisponible"');
      await ex.verifierTexte(eliot, /Kevin Arner\s+En attente/, 'Eliot : Kevin toujours "En attente"');
    });

    await ex.etape('Fiche d\'Eliot : seules les personnes encore disponibles', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Kevin, Tom', 'EN CAS D\'IMPRÉVU : "Kevin, Tom" (Sylvain a refusé)');
      await kevin.accueil();
      await ex.verifierTexte(kevin, "UNE DEMANDE T'ATTEND", 'Kevin : sa demande est toujours active');
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
