// D-019 — une personne de confiance n'est active qu'après le scellage.
// D-011 — au plus 2 contre-propositions de date au total.
import { CONTACTS_SANS_COMPTE as C, COMPTES } from '../lib/config.mjs';
import * as A from '../lib/actions.mjs';
import { sql, lireComme } from '../lib/donnees.mjs';

const notifs = (nom) => sql(`select count(*) from notifications_log where profile_id = '${COMPTES[nom].id}'`);
const cartes = async (a) => (await a.texte()).split('\n').filter((l) => l.includes('compte sur toi pour un Swend')).length;
const avecKevin = [{ prenom: 'Kevin', nom: 'Arner', tel: COMPTES.kevin.tel }, C.tom];
const sylvain = { prenom: 'Sylvain', nom: 'Landiech', tel: COMPTES.sylvain.tel };
const aSonTour = (nom) => new RegExp(`Swend avec ${nom}[\\s\\S]*À vous de répondre`);
const dernierSwendSylvain = () => sql(`select statut || '|' || nombre_echanges_date from pactes where destinataire_id = '${COMPTES.sylvain.id}' order by created_at desc limit 1`);

export default {
  nom: 'scellage_et_negociation',
  titre: 'Personne de confiance active après scellage ; 2 contre-propositions au total',
  suites: ['full'],
  fixture: 'comptes',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();
    const sylv = await ex.sylvain();

    await ex.etape('Swend créé, pas encore scellé : Kevin ne voit rien', async () => {
      await A.creerSwend(eliot, { prenom: 'David', nom: 'Schlang', tel: COMPTES.david.tel, personnes: avecKevin });
      await ex.verifier('Kevin est bien rattaché à sa fiche', () => sql(`select count(*) from remplacants where profil_id = '${COMPTES.kevin.id}'`) === '1');
      await kevin.accueil();
      await ex.verifierAbsent(kevin, 'ON COMPTE SUR TOI', 'Kevin : pas de "On compte sur toi"');
      await ex.verifierAbsent(kevin, 'Eliot compte sur toi', 'Kevin : pas de carte pour ce Swend');
      await A.ouvrirMesSwends(kevin);
      await ex.verifierAbsent(kevin, "Swend d'Eliot", 'Kevin : rien dans "Mes Swends"');
      const pactes = await lireComme('kevin', 'pactes', 'select=id');
      const fiches = await lireComme('kevin', 'remplacants', 'select=id');
      await ex.verifier('API : Kevin ne lit ni le Swend ni sa fiche', () => pactes.length === 0 && fiches.length === 0,
        { obtenu: () => `${pactes.length} Swend(s), ${fiches.length} fiche(s)` });
      await ex.verifier('Kevin : aucune notification', () => notifs('kevin') === '0');
    });

    await ex.etape('David accepte : Swend scellé, Kevin devient actif', async () => {
      await A.accepterSwend(david, { avec: /Swend avec Eliot/, personnes: [C.leo, C.nina] });
      await ex.verifier('Swend scellé (date de scellage posée)', () => sql(`select count(*) from pactes where scelle_le is not null`) === '1');
      await kevin.accueil();
      await ex.verifierTexte(kevin, 'Eliot compte sur toi pour un Swend', 'Kevin : "Eliot compte sur toi"');
      await ex.verifierTexte(kevin, /Swend avec David/, 'Kevin : carte du Swend avec David');
      await ex.verifier('Kevin : "Je ne serai pas disponible" disponible', async () => (await kevin.nombreDeBoutons('Je ne serai pas disponible')) === 1);
      await A.ouvrirConversationTiers(kevin);
      await A.envoyerMessage(kevin, 'Je suis là si besoin');
      await ex.verifierTexte(kevin, 'Je suis là si besoin', 'Kevin : la conversation est ouverte');
    });

    await ex.etape('Refus : Kevin ne voit jamais ce Swend', async () => {
      await A.creerSwend(eliot, { ...sylvain, personnes: avecKevin });
      await A.ouvrirSwend(sylv, /Swend avec Eliot/);
      await A.choisirPremiereDate(sylv);
      await sylv.cliquer('Refuser le Swend');
      await ex.verifier('Swend refusé', () => dernierSwendSylvain().startsWith('annule|'), { obtenu: dernierSwendSylvain });
      await kevin.accueil();
      await ex.verifierAbsent(kevin, /Swend avec Sylvain/, 'Kevin : aucune trace du Swend refusé');
      await ex.verifier('Kevin : toujours une seule carte', async () => (await cartes(kevin)) === 1);
    });

    await ex.etape('Négociation : B (n°1), C (n°2), puis plus de contre-proposition', async () => {
      await A.creerSwend(eliot, { ...sylvain, personnes: avecKevin });
      await A.contreProposer(sylv, aSonTour('Eliot'));
      await ex.verifier('contre-proposition n°1 (Sylvain)', () => dernierSwendSylvain() === 'enAttenteChoixDateInitiateur|1', { obtenu: dernierSwendSylvain });
      await A.contreProposer(eliot, aSonTour('Sylvain'));
      await ex.verifier('contre-proposition n°2 (Eliot)', () => dernierSwendSylvain() === 'enAttenteChoixDateDestinataire|2', { obtenu: dernierSwendSylvain });
      await A.ouvrirSwend(sylv, aSonTour('Eliot'));
      await ex.verifierTexte(sylv, 'Dernière proposition : si aucune de ces dates ne convient, le Swend sera annulé.', 'Sylvain : "Dernière proposition"');
      await ex.verifier('Sylvain : plus de "Proposer d\'autres dates"', async () => (await sylv.nombreDeBoutons("Proposer d'autres dates")) === 0);
      await ex.verifierAbsent(sylv, 'Cette date me convient, mais pas cet horaire', 'Sylvain : plus de changement d\'horaire');
    });

    await ex.etape('Pas d\'accord : Sylvain annule, Kevin ne voit rien', async () => {
      await sylv.cliquer('Annuler le Swend');
      await ex.verifier('Swend annulé après 2 contre-propositions', () => dernierSwendSylvain() === 'annule|2', { obtenu: dernierSwendSylvain });
      await kevin.accueil();
      await ex.verifierAbsent(kevin, /Swend avec Sylvain/, 'Kevin : aucune trace de la négociation échouée');
    });

    await ex.etape('Nouveau Swend : négociation normale, accord sur C', async () => {
      await A.creerSwend(eliot, { ...sylvain, personnes: avecKevin });
      await ex.verifier('nouveau Swend : compteur à zéro', () => dernierSwendSylvain() === 'enAttenteChoixDateDestinataire|0', { obtenu: dernierSwendSylvain });
      await A.contreProposer(sylv, aSonTour('Eliot'));
      await A.contreProposer(eliot, aSonTour('Sylvain'));
      await A.accepterSwend(sylv, { avec: aSonTour('Eliot'), personnes: [C.leo, C.nina] });
      await ex.verifier('accord sur C : Swend scellé', () => dernierSwendSylvain() === 'confirme|2', { obtenu: dernierSwendSylvain });
      await kevin.accueil();
      await ex.verifierTexte(kevin, /Swend avec Sylvain/, 'Kevin : actif sur ce Swend une fois scellé');
      await ex.verifier('Kevin : deux cartes (les deux Swends scellés)', async () => (await cartes(kevin)) === 2);
    });

    await ex.etape('Aucune notification automatique à Kevin, aucune fuite', async () => {
      await ex.verifier('Kevin : aucune notification sur tout le parcours', () => notifs('kevin') === '0', { obtenu: () => notifs('kevin') });
      const fichesSylvain = await lireComme('sylvain', 'remplacants', 'select=id,cote');
      await ex.verifier('API : Sylvain ne lit aucune fiche côté Eliot', () => !fichesSylvain.some((f) => f.cote === 'initiateur'),
        { obtenu: () => JSON.stringify(fichesSylvain) });
      const fichesDavid = await lireComme('david', 'remplacants', 'select=id,cote');
      await ex.verifier('API : David ne lit aucune fiche côté Eliot', () => !fichesDavid.some((f) => f.cote === 'initiateur'),
        { obtenu: () => JSON.stringify(fichesDavid) });
    });
  },
};
