// CONCURRENCE — Kevin et Sylvain confirment au même moment : une seule
// personne prend la place, l'autre reçoit un message clair.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';

export default {
  nom: 'premiere_acceptation_gagnante',
  titre: 'Kevin et Sylvain acceptent en même temps : une seule place',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();

    await ex.etape('Demandes à Kevin et Sylvain, les deux ouvrent la confirmation', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.demander(eliot, 'Sylvain Landiech');
      for (const a of [kevin, sylvain]) {
        await a.accueil();
        await a.cliquer('Répondre à la demande');
        await a.cliquer('Voir la demande et répondre');
        await a.cliquer('Accepter');
        await a.attendreTexte("Prendre la place d'Eliot ?");
      }
    });

    await ex.etape('Les deux confirment simultanément', async () => {
      await Promise.all([kevin, sylvain].map((a) => a.page.getByRole('button', { name: 'Accepter', exact: true }).last().click()));
      await Promise.all([kevin.attendreCalme(), sylvain.attendreCalme()]);
      await ex.verifier('une seule personne sélectionnée côté Eliot',
        () => sql(`select count(*) from remplacants where cote = 'initiateur' and selectionne`) === '1',
        { obtenu: () => `Kevin ${demande(FICHES.kevin)} / Sylvain ${demande(FICHES.sylvain)}` });
      const gagnant = demande(FICHES.kevin) === 'acceptee|t' ? kevin : sylvain;
      const perdant = gagnant === kevin ? sylvain : kevin;
      ex.memo.gagnant = gagnant; ex.memo.perdant = perdant;
      await ex.verifier(`le perdant (${perdant.compte.prenom}) est clôturé`,
        () => demande(FICHES[perdant.nom]) === 'cloturee|f', { obtenu: () => demande(FICHES[perdant.nom]) });
      await ex.verifierTexte(gagnant, "C'est noté : tu prends la place.", `${gagnant.compte.prenom} : "C'est noté : tu prends la place."`);
      await ex.verifierTexte(perdant, "La place vient d'être prise.", `${perdant.compte.prenom} : "La place vient d'être prise."`);
    });

    await ex.etape('Chaque écran reflète le bon état', async () => {
      const { gagnant, perdant } = ex.memo;
      await gagnant.accueil();
      await ex.verifierTexte(gagnant, "Tu prends la place d'Eliot", `${gagnant.compte.prenom} : "Tu prends la place d'Eliot"`);
      await perdant.accueil();
      await ex.verifierAbsent(perdant, "Tu prends la place d'Eliot", `${perdant.compte.prenom} : ne prend pas la place`);
      await ex.verifierAbsent(perdant, "UNE DEMANDE T'ATTEND", `${perdant.compte.prenom} : plus de demande`);
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, `${gagnant.compte.prenom} prendra votre place`, `Eliot : "${gagnant.compte.prenom} prendra votre place"`);
    });
  },
};
