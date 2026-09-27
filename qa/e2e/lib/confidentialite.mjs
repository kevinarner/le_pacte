// Invariant transversal : l'autre titulaire (David) ne doit rien savoir des
// démarches d'Eliot pour se faire remplacer — ni à l'écran, ni via l'API.
import { lireComme, sql } from './donnees.mjs';
import { COMPTES } from './config.mjs';

const plat = (t) => t.replace(/\s+/g, ' ').trim();

// Ce que David voit : son accueil et la fiche du Swend avec Eliot.
export async function photoDavid(ex) {
  const d = await ex.david();
  await d.accueil();
  const accueil = plat(await d.texte());
  await d.cliquer('Mes Swends', { exact: false });
  await d.page.getByRole('button', { name: /Swend avec Eliot/ }).first().click();
  await d.attendreCalme();
  const fiche = plat(await d.texte());
  return { accueil, fiche };
}

// Compare avec la photo prise avant les démarches, et interroge l'API avec
// le compte de David pour vérifier qu'il ne PEUT pas lire ces données.
// Options : nomsInterdits (noms qui ne doivent pas apparaître chez David),
// comparerFiche (false si David agit lui-même sur sa fiche entre-temps),
// notificationsAutorisees (true si David reçoit légitimement des notifications).
export async function verifierDavidNeVoitRien(ex, avant, { nomsInterdits = ['Kevin', 'Sylvain', 'Tom'], comparerFiche = true, notificationsAutorisees = false } = {}) {
  const apres = await photoDavid(ex);
  await ex.verifier('David : accueil identique à avant les démarches d\'Eliot', () => apres.accueil === avant.accueil,
    { attendu: avant.accueil.slice(0, 300), obtenu: () => apres.accueil.slice(0, 300) });
  if (comparerFiche) {
    await ex.verifier('David : fiche du Swend identique à avant les démarches d\'Eliot', () => apres.fiche === avant.fiche,
      { attendu: avant.fiche.slice(0, 300), obtenu: () => apres.fiche.slice(0, 300) });
  }
  const indices = [...nomsInterdits, 'prendra votre place', 'a un imprévu', 'te demande', 'remplac'];
  const trouves = indices.filter((m) => (apres.accueil + ' ' + apres.fiche).includes(m));
  await ex.verifier('David : aucun nom ni indice de remplacement à l\'écran', () => trouves.length === 0,
    { attendu: 'aucun de : ' + indices.join(', '), obtenu: () => trouves.join(', ') });

  // API (RLS) : David ne peut lire aucune donnée du côté d'Eliot.
  const cotesEliot = sql(`select coalesce(string_agg(id::text, ','), '') from remplacants where cote = 'initiateur'`).split(',').filter(Boolean);
  const fiches = await lireComme('david', 'remplacants', 'select=id,cote');
  await ex.verifier('API : David ne lit aucune personne de confiance d\'Eliot', () => !fiches.some((f) => cotesEliot.includes(f.id)),
    { obtenu: () => JSON.stringify(fiches) });
  const messages = await lireComme('david', 'messages', 'select=remplacant_id');
  await ex.verifier('API : David ne lit aucun message Eliot ↔ ses personnes de confiance', () => !messages.some((m) => cotesEliot.includes(m.remplacant_id)),
    { obtenu: () => `${messages.length} message(s) lisible(s)` });
  const evenements = await lireComme('david', 'evenements_fil', 'select=remplacant_id,code');
  await ex.verifier('API : David ne lit aucun événement de demande d\'Eliot', () => !evenements.some((e) => cotesEliot.includes(e.remplacant_id)),
    { obtenu: () => JSON.stringify(evenements) });
  if (!notificationsAutorisees) {
    await ex.verifier('David : aucune notification liée au remplacement',
      () => sql(`select count(*) from notifications_log where profile_id = '${COMPTES.david.id}'`) === '0',
      { obtenu: () => sql(`select string_agg(corps, ' | ') from notifications_log where profile_id = '${COMPTES.david.id}'`) });
  }
}
