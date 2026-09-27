// MÊME PERSONNE DES DEUX CÔTÉS — Kevin est personne de confiance d'Eliot
// ET de David. Il ne peut prendre qu'une place ; ni Eliot ni David ne
// découvrent le rôle de Kevin de l'autre côté. L'app lui montre une seule
// carte pour ce Swend (sa fiche la plus active).
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES, lireComme, appelerComme } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const nbCartes = async (a) => (await a.texte()).split('\n').filter((l) => l.includes('compte sur toi pour un Swend')).length;

export default {
  nom: 'meme_personne_deux_cotes',
  titre: 'Kevin des deux côtés : une seule place, rien ne fuit',
  suites: ['full'],
  fixture: 'scelle_kevin_deux_cotes',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Kevin : une seule carte pour ce Swend', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, /(Eliot|David) compte sur toi pour un Swend/, 'Kevin : "… compte sur toi"');
      await ex.verifier('une seule carte "compte sur toi" pour ce Swend', async () => (await nbCartes(kevin)) === 1,
        { obtenu: async () => `${await nbCartes(kevin)} carte(s)` });
      await ex.verifierTexte(kevin, /Mes Swends\s+0 à venir/, 'Kevin : 0 à venir');
    });

    await ex.etape('Eliot demande à Kevin, qui accepte', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await kevin.accueil();
      await ex.verifierTexte(kevin, 'Eliot a un imprévu', 'Kevin : "Eliot a un imprévu"');
      await A.repondre(kevin, true);
      await ex.verifier('Kevin sélectionné côté Eliot, clos côté David',
        () => demande(FICHES.kevin) === 'acceptee|t' && demande(FICHES.kevinCoteDavid) === 'cloturee|f',
        { obtenu: () => `Eliot ${demande(FICHES.kevin)} / David ${demande(FICHES.kevinCoteDavid)}` });
      await ex.verifier('le Swend reste scellé', () => sql('select statut from pactes') === 'confirme');
      await kevin.accueil();
      await ex.verifierTexte(kevin, "Tu prends la place d'Eliot", 'Kevin : "Tu prends la place d\'Eliot"');
      await ex.verifierTexte(kevin, /Mes Swends\s+1 à venir/, 'Kevin : 1 à venir');
    });

    await ex.etape('Kevin ne peut pas prendre aussi la place de David', async () => {
      await A.ouvrirImprevu(david, /Swend avec Eliot/);
      await ex.verifierTexte(david, /Kevin Arner\s+Indisponible/, 'David : Kevin "Indisponible"');
      await ex.verifier('David ne peut pas solliciter Kevin', async () => (await david.nombreDeBoutons('Lui demander')) === 0);
      const r = await appelerComme('david', 'envoyer_demande_remplacement', { p_remplacant_id: FICHES.kevinCoteDavid });
      await ex.verifier('API : David ne peut pas envoyer de demande à Kevin', () => !r.ok, { obtenu: () => `${r.statut} ${r.corps}` });
      const r2 = await appelerComme('kevin', 'repondre_demande_remplacement', { p_remplacant_id: FICHES.kevinCoteDavid, p_accepte: true });
      await ex.verifier('API : Kevin ne peut pas accepter côté David', () => !r2.ok, { obtenu: () => `${r2.statut} ${r2.corps}` });
      await ex.verifier('aucune fiche de David sélectionnée',
        () => sql(`select count(*) from remplacants where cote = 'destinataire' and selectionne`) === '0');
    });

    await ex.etape('Confidentialité des deux côtés', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david, { nomsInterdits: ['Sylvain', 'Tom'], comparerFiche: false });
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierAbsent(david, 'prendra votre place', 'David : aucun remplaçant affiché de son côté');
      await ex.verifierAbsent(david, "place d'Eliot", 'David : rien sur la place d\'Eliot');
      const fichesDavid = await lireComme('eliot', 'remplacants', 'select=id&cote=eq.destinataire');
      await ex.verifier('API : Eliot ne lit aucune personne de confiance de David', () => fichesDavid.length === 0, { obtenu: () => JSON.stringify(fichesDavid) });
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierAbsent(eliot, 'Léo', 'Eliot ne voit pas la liste de David');
    });

    await ex.etape('Kevin se désiste côté Eliot, puis prend la place de David', async () => {
      await A.seDesister(kevin);
      await ex.verifier('fiche de Kevin côté David rouverte', () => demande(FICHES.kevinCoteDavid) === '|f', { obtenu: () => demande(FICHES.kevinCoteDavid) });
      await A.ouvrirImprevu(david, /Swend avec Eliot/);
      await A.demander(david, 'Kevin Arner');
      await kevin.accueil();
      await ex.verifierTexte(kevin, 'David a un imprévu', 'Kevin : "David a un imprévu"');
      await A.repondre(kevin, true);
      await ex.verifier('Kevin sélectionné côté David, Swend toujours scellé',
        () => demande(FICHES.kevinCoteDavid) === 'acceptee|t' && sql('select statut from pactes') === 'confirme',
        { obtenu: () => `${demande(FICHES.kevinCoteDavid)} / ${sql('select statut from pactes')}` });
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierAbsent(eliot, 'Kevin prendra', 'Eliot ne sait pas que Kevin remplace David');
    });
  },
};
