// D-027 (décision d'Eliot du 20/10/2026) — H-3, LIMITE FERME DE L'IMPRÉVU.
//  - Avant H-3 : « Un imprévu ? » annonce l'échéance (« Si personne n’a
//    accepté avant …, le Swend sera annulé. »).
//  - Recherche non résolue à H-3 : plus aucune action (« Personne n’a pu
//    prendre ta place à temps. »), Kevin ne peut plus accepter ; l'échéance
//    annule le Swend, chacun est prévenu, David sans coulisse.
//  - Nouvel imprévu après H-3 : plus de recherche, « Annuler le Swend »
//    (confirmation validée), annulation immédiate.
//  - Désistement du remplaçant sélectionné après H-3 : la confirmation
//    l'annonce, le Swend est annulé sans réactivation.
// Base sans l'échéance (QA_BASE=avant-D-027-03, production depuis le 20/10) :
// l'app applique déjà les écrans de H-3 (son horloge) ; la base, elle, garde
// l'ancienne règle (acceptation et désistement acceptés) : transition
// décrite dans le paquet D-027-03.
import * as A from '../lib/actions.mjs';
import { sql, FICHES, demande, chargerFixture, baseAvecEcheanceH3 } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';

const notifs = (nom) => sql(`select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);
const statut = () => sql(`select statut || '|' || coalesce(annule_motif, 'aucun') from pactes`);
// H-3 passé depuis 2 minutes (H dans 2 h 58).
const apresH3 = () => sql(`select qa.deplacer_swend(id, now() + interval '2 hours 58 minutes') from pactes`);
const echeanceFr = () => sql(`select date_rappel_fr(date_retenue - interval '3 hours') || ' à '
  || to_char((date_retenue - interval '3 hours') at time zone 'Europe/Paris', 'FMHH24"h"MI') from pactes`);

export default {
  nom: 'echeance_h3',
  titre: 'H-3, limite ferme : échéance annoncée, recherche close, annulation, nouvel imprévu, désistement tardif',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const h3 = baseAvecEcheanceH3();
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const david = await ex.david();

    await ex.etape('Avant H-3 : l’échéance est annoncée pendant la recherche', async () => {
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, `Si personne n’a accepté avant ${echeanceFr()}, le Swend sera annulé.`, 'choix : échéance annoncée');
      await A.demander(eliot, 'Kevin Arner');
      await ex.verifierTexte(eliot, 'C’est envoyé.', 'attente : « C’est envoyé. »');
      await ex.verifierTexte(eliot, `Si personne n’a accepté avant ${echeanceFr()}, le Swend sera annulé.`, 'attente : échéance annoncée');
    });

    await ex.etape('H-3 passé, recherche non résolue : plus aucune action', async () => {
      apresH3();
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Personne n’a pu prendre ta place à temps.', 'fiche : « Personne n’a pu prendre ta place à temps. »');
      await eliot.cliquer('Un imprévu ?');
      await eliot.attendreTexte('Personne n’a pu prendre ta place à temps.');
      await ex.verifierTexte(eliot, 'À partir de 3 heures avant le Swend, on ne peut plus chercher personne : le Swend va être annulé.', 'Un imprévu ? : texte de fin de recherche');
      await ex.verifier('aucune case, ni « Solliciter », ni « Je peux finalement venir », ni « Ajouter une personne »', async () =>
        (await eliot.page.getByRole('checkbox').count()) === 0
        && (await eliot.nombreDeBoutons('Solliciter quelqu’un d’autre')) === 0
        && (await eliot.nombreDeBoutons('Je peux finalement venir')) === 0
        && (await eliot.nombreDeBoutons('Ajouter une personne')) === 0);
      if (h3) {
        await A.repondre(kevin, true);
        await ex.verifierTexte(kevin, 'Il est trop tard : à partir de 3 heures avant le Swend, on ne peut plus chercher ni accepter de remplaçant.', 'Kevin : acceptation refusée, message clair');
        await ex.verifier('demande de Kevin toujours en attente (rien n’a bougé)', () => demande(FICHES.kevin) === 'envoyee|f', { obtenu: () => demande(FICHES.kevin) });
      }
    });

    if (h3) {
      await ex.etape('Échéance : Swend annulé, chacun prévenu, sans coulisse', async () => {
        sql('select appliquer_echeances_h3()');
        await ex.verifier('Swend annulé (echeance_h3)', () => statut() === 'annule|echeance_h3', { obtenu: statut });
        await ex.verifier('Eliot : « Le Swend est annulé / Personne n’a pu prendre ta place à temps. »',
          () => notifs('eliot').endsWith('Le Swend est annulé|Personne n’a pu prendre ta place à temps.'), { obtenu: () => notifs('eliot') });
        await ex.verifier('David : « Le Swend est annulé / Eliot ne pourra finalement pas être là. »',
          () => notifs('david').endsWith('Le Swend est annulé|Eliot ne pourra finalement pas être là.'), { obtenu: () => notifs('david') });
        await ex.verifier('Kevin : « Le Swend est annulé / Tu n’as plus besoin de répondre. »',
          () => notifs('kevin').endsWith('Le Swend est annulé|Tu n’as plus besoin de répondre.'), { obtenu: () => notifs('kevin') });
        await A.ouvrirSwend(eliot, /Swend avec David/);
        await ex.verifierTexte(eliot, 'Ton Swend avec David est annulé.', 'Eliot : « Ton Swend avec David est annulé. »');
        await A.ouvrirSwend(david, /Swend avec Eliot/);
        await ex.verifierTexte(david, 'Ton Swend avec Eliot est annulé.', 'David : « Ton Swend avec Eliot est annulé. »');
        await ex.verifierAbsent(david, /Kevin|Sylvain|Tom/, 'David : aucune personne de confiance d’Eliot');
      });
    }

    await ex.etape('Nouvel imprévu après H-3 : annulation, sans recherche', async () => {
      chargerFixture('scelle');
      apresH3();
      const d2 = await ex.redemarrer('david');
      await A.ouvrirImprevu(d2, /Swend avec Eliot/);
      await ex.verifierTexte(d2, 'Tu ne peux plus être là ?', '« Tu ne peux plus être là ? »');
      await ex.verifierTexte(d2, 'À partir de 3 heures avant le Swend, il n’est plus possible de chercher quelqu’un pour prendre ta place. Si tu ne peux pas venir, le Swend sera annulé.', 'texte de H-3');
      await ex.verifier('aucune personne à cocher, pas d’ajout', async () =>
        (await d2.page.getByRole('checkbox').count()) === 0 && (await d2.nombreDeBoutons('Ajouter une personne')) === 0);
      await d2.cliquer('Annuler le Swend');
      await ex.verifierTexte(d2, 'Annuler ce Swend ?', 'confirmation validée');
      await ex.verifierTexte(d2, 'Cette action est définitive. L’autre personne sera prévenue.', 'confirmation : texte validé');
      await d2.cliquer('Annuler le Swend', { dernier: true });
      await d2.attendreCalme();
      await ex.verifier('Swend annulé par David (motif titulaire)', () => statut() === 'annule|titulaire', { obtenu: statut });
      await ex.verifierTexte(d2, 'Swend annulé', 'David : retour à la fiche, « Swend annulé »');
      await ex.verifier('Eliot prévenu : « David ne pourra finalement pas être là. »',
        () => notifs('eliot').endsWith('Le Swend est annulé|David ne pourra finalement pas être là.'), { obtenu: () => notifs('eliot') });
    });

    await ex.etape('Désistement de Kevin après H-3 : annoncé, puis Swend annulé sans réactivation', async () => {
      chargerFixture('scelle');
      const e3 = await ex.redemarrer('eliot');
      const k3 = await ex.redemarrer('kevin');
      await A.ouvrirImprevu(e3);
      await A.demander(e3, 'Kevin Arner', 'Sylvain Landiech');
      await A.repondre(k3, true);
      apresH3();
      await A.ouvrirSwend(k3, /Swend d'Eliot avec David/);
      await k3.cliquer('Je ne peux finalement plus venir');
      await ex.verifierTexte(k3, 'À partir de 3 heures avant le Swend, personne d’autre ne pourra prendre la place d’Eliot : le Swend sera annulé.', 'confirmation : annulation annoncée');
      await k3.cliquer('Je ne peux plus venir');
      await k3.attendreCalme();
      if (h3) {
        await ex.verifier('Swend annulé (echeance_h3)', () => statut() === 'annule|echeance_h3', { obtenu: statut });
        await ex.verifier('aucune réactivation : Sylvain reste close', () => demande(FICHES.sylvain) === 'cloturee|f', { obtenu: () => demande(FICHES.sylvain) });
        await ex.verifier('Eliot : « Le Swend est annulé / Kevin ne peut finalement plus venir. »',
          () => notifs('eliot').endsWith('Le Swend est annulé|Kevin ne peut finalement plus venir.'), { obtenu: () => notifs('eliot') });
        await ex.verifier('David : « Eliot ne pourra finalement pas être là. » (jamais Kevin)',
          () => notifs('david').endsWith('Le Swend est annulé|Eliot ne pourra finalement pas être là.') && !notifs('david').includes('Kevin'),
          { obtenu: () => notifs('david') });
        await ex.verifier('Sylvain : rien (aucune « Ta réponse est finalement attendue »)', () => !notifs('sylvain').includes('finalement attendue'), { obtenu: () => notifs('sylvain') });
        await ex.verifierTexte(k3, 'Ce Swend a été annulé.', 'Kevin : « Ce Swend a été annulé. »');
      } else {
        // Base sans l'échéance : l'ancienne règle s'applique encore (transition).
        await ex.verifier('base sans l’échéance : Swend maintenu, Sylvain réactivé (ancienne règle)',
          () => statut() === 'confirme|aucun' && demande(FICHES.sylvain) === 'envoyee|f',
          { obtenu: () => `${statut()} ${demande(FICHES.sylvain)}` });
      }
    });
  },
};
