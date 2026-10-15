// D-023a — RELIRE APRÈS ANNULATION. Kevin a accepté de prendre la place
// d'Eliot ; Eliot a aussi écrit à Sylvain ; Tom n'a jamais rien échangé.
// Eliot, remplacé, ne peut plus annuler (D-027 lot 2) : David annule. Depuis
// la fiche du Swend annulé, « Relire une conversation » propose à Eliot Kevin
// et Sylvain (pas Tom), sans rappeler de remplacement (app du lot 1 : lecture
// seule à l'écran). Kevin, qui garde le Swend annulé dans son historique,
// relit aussi sa conversation. Sylvain (seulement prévu, mais une
// conversation existe) garde le Swend et sa seule conversation (D-027 lot 2),
// sans le numéro d'Eliot (D-024 inchangé). David ne voit rien des coulisses.
import * as A from '../lib/actions.mjs';
import { sql, lireComme, appelerComme, FICHES, baseAvecLot2 } from '../lib/donnees.mjs';

const champSaisie = (a) => a.page.getByRole('textbox', { name: 'Écrire un message…' }).count();

export default {
  nom: 'gel_relecture_annulation',
  titre: 'Swend annulé : relecture des conversations actives (titulaire et remplaçant), sans écriture',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const david = await ex.david();

    await ex.etape('Kevin accepte ; Eliot écrit à Kevin et à Sylvain', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.repondre(kevin, true);
      await A.ouvrirConversationTitulaire(eliot, 'Kevin Arner');
      await A.envoyerMessage(eliot, 'Merci Kevin !');
      await A.ouvrirConversationTitulaire(eliot, 'Sylvain Landiech');
      await A.envoyerMessage(eliot, 'Et toi Sylvain ?');
    });

    // Le parcours d'annulation lui-même est testé dans 19 et 20.
    await ex.etape('Eliot (remplacé) ne peut plus annuler ; David annule', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifier('Eliot : pas de « Annuler le Swend »', async () => (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
      const pacte = sql('select id from pactes');
      if (baseAvecLot2()) {
        const r = await appelerComme('eliot', 'annuler_swend', { p_pacte_id: pacte });
        await ex.verifier('API : refus remplacement_accepte', () => !r.ok && r.corps.includes('remplacement_accepte'), { obtenu: () => r.corps });
      }
      await ex.verifier('Swend toujours scellé', () => sql('select statut from pactes') === 'confirme');
      const r2 = await appelerComme('david', 'annuler_swend', { p_pacte_id: pacte });
      await ex.verifier('Swend annulé par David', () => r2.ok && sql('select statut from pactes') === 'annule', { obtenu: () => r2.corps });
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

    await ex.etape('Sylvain (seulement prévu, conversation existante) garde sa conversation ; David ne voit rien', async () => {
      const [sw, fi, s] = [await lireComme('sylvain', 'pactes', 'select=id'), await lireComme('sylvain', 'remplacants'), await lireComme('sylvain', 'messages')];
      await ex.verifier('API : Sylvain lit le Swend, sa seule fiche et sa conversation (D-027 lot 2)',
        () => sw.length === 1 && fi.length === 1 && s.length === 1, { obtenu: () => `${sw.length}/${fi.length}/${s.length}` });
      const k = await lireComme('kevin', 'pactes', 'select=id');
      await ex.verifier('API : Kevin (sélectionné) lit toujours le Swend annulé', () => k.length === 1, { obtenu: () => `${k.length}` });
      const tk = await appelerComme('kevin', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.kevin });
      const ts = await appelerComme('sylvain', 'telephone_titulaire_accessible', { p_remplacant_id: FICHES.sylvain });
      await ex.verifier('API : numéro d\'Eliot pour Kevin (sélectionné), rien pour Sylvain (D-024 inchangé)',
        () => tk.corps.includes('06 01 02 03 04') && ts.ok && !ts.corps.includes('06'), { obtenu: () => `${tk.corps} | ${ts.corps}` });
      const m = await lireComme('david', 'messages');
      const e = await lireComme('david', 'evenements_fil');
      await ex.verifier('David : aucun message ni événement lisible', () => m.length === 0 && e.length === 0,
        { obtenu: () => `${m.length} messages, ${e.length} événements` });
    });
  },
};
