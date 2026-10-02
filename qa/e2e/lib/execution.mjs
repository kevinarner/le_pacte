// Exécution d'un scénario : acteurs à la demande, étapes nommées,
// vérifications avec rapport PASS/FAIL et artefacts en cas d'échec.
import fs from 'node:fs';
import path from 'node:path';
import { Acteur } from './acteur.mjs';
import { etatMetier, chargerFixture } from './donnees.mjs';

export class Echec extends Error {
  constructor(message, { attendu, obtenu } = {}) {
    super(message);
    this.attendu = attendu;
    this.obtenu = obtenu;
  }
}

export class Execution {
  constructor(scenario, navigateur, rapport) {
    this.scenario = scenario;
    this.navigateur = navigateur;
    this.rapport = rapport;
    this.acteurs = new Map();
    this.etapeCourante = '(préparation)';
    this.memo = {}; // données partagées entre étapes (photos de David…)
  }

  // Session de l'acteur, démarrée et connectée au premier usage ; options :
  // { fuseau } de l'appareil (Europe/Paris par défaut).
  async acteur(nom, options = {}) {
    if (!this.acteurs.has(nom)) {
      const a = new Acteur(nom, options);
      this.acteurs.set(nom, a);
      await a.demarrer(this.navigateur);
    }
    return this.acteurs.get(nom);
  }
  async eliot() { return this.acteur('eliot'); }
  async david() { return this.acteur('david'); }
  async kevin() { return this.acteur('kevin'); }
  async sylvain() { return this.acteur('sylvain'); }
  // Nouvelle session (navigateur neuf, reconnexion) : vérifie la persistance.
  async redemarrer(nom) {
    await this.acteurs.get(nom)?.fermer();
    this.acteurs.delete(nom);
    return this.acteur(nom);
  }

  async etape(nom, fn) {
    this.etapeCourante = nom;
    await fn();
  }

  // Vérifie une condition, en la réévaluant jusqu'à ce qu'elle soit vraie
  // (l'écran peut mettre un instant à refléter l'état) ; échec au délai.
  async verifier(libelle, condition, { attendu, obtenu, delai = 8000 } = {}) {
    const limite = Date.now() + delai;
    let ok = false, erreur;
    while (true) {
      try { ok = Boolean(await condition()); erreur = undefined; } catch (e) { ok = false; erreur = e; }
      if (ok || Date.now() > limite) break;
      await new Promise((r) => setTimeout(r, 200));
    }
    if (ok) { this.rapport.pass(this.scenario.nom, libelle); return; }
    let valeur = erreur ? `erreur : ${erreur.message}` : undefined;
    if (!valeur && obtenu) { try { valeur = await obtenu(); } catch (e) { valeur = `(illisible : ${e.message})`; } }
    throw new Echec(libelle, { attendu, obtenu: valeur });
  }

  // Vérifie qu'un texte est ABSENT une fois l'écran à jour (et le reste).
  async verifierAbsent(acteur, texte, libelle) {
    await acteur.attendreCalme();
    await this.verifier(libelle, async () => !(await acteur.voit(texte)), {
      attendu: `« ${texte} » absent de l'écran de ${acteur.nom}`,
      obtenu: async () => `présent : ${extrait(await acteur.texte(), texte)}`,
    });
    await new Promise((r) => setTimeout(r, 600));
    if (await acteur.voit(texte)) throw new Echec(libelle, { attendu: `« ${texte} » absent`, obtenu: 'apparu après coup' });
  }
  async verifierTexte(acteur, texte, libelle, delai) {
    await this.verifier(libelle, () => acteur.voit(texte), {
      delai,
      attendu: `« ${texte} » visible chez ${acteur.nom}`,
      obtenu: async () => `écran de ${acteur.nom} : ${resume(await acteur.texte())}`,
    });
  }

  async executer() {
    chargerFixture(this.scenario.fixture || 'comptes');
    await this.scenario.executer(this);
  }

  async conserverArtefacts(dossier, erreur) {
    fs.mkdirSync(dossier, { recursive: true });
    const lignes = [
      `Scénario : ${this.scenario.nom} — ${this.scenario.titre}`,
      `Étape    : ${this.etapeCourante}`,
      `Échec    : ${erreur.message}`,
    ];
    if (erreur.attendu !== undefined) lignes.push(`Attendu  : ${erreur.attendu}`);
    if (erreur.obtenu !== undefined) lignes.push(`Obtenu   : ${erreur.obtenu}`);
    if (!(erreur instanceof Echec)) lignes.push('', erreur.stack || '');
    fs.writeFileSync(path.join(dossier, 'echec.txt'), lignes.join('\n') + '\n');
    for (const [nom, a] of this.acteurs) {
      await a.capture(path.join(dossier, `${nom}.png`));
      const ecran = await a.texte().catch(() => '');
      fs.writeFileSync(path.join(dossier, `${nom}.log`),
        [`URL : ${a.page?.url()}`, `Liens ouverts : ${a.liensOuverts.join(' | ') || '—'}`, '', '--- Écran (texte accessible) ---',
          ecran, '', '--- Journal ---', ...a.journal].join('\n'));
    }
    try { fs.writeFileSync(path.join(dossier, 'etat_metier.json'), JSON.stringify(etatMetier(), null, 2)); } catch { /* base indisponible */ }
  }

  async fermer() { for (const a of this.acteurs.values()) await a.fermer(); }
}

export function resume(t, n = 400) { return t.replace(/\s+/g, ' ').trim().slice(0, n); }
function extrait(t, cible) {
  const plat = t.replace(/\s+/g, ' ');
  const i = typeof cible === 'string' ? plat.indexOf(cible) : plat.search(cible);
  return i < 0 ? '' : `…${plat.slice(Math.max(0, i - 60), i + 80)}…`;
}

// Vrai si les textes apparaissent dans cet ordre dans l'écran (ordre de lecture).
export function dansLOrdre(ecran, textes) {
  let depuis = 0;
  for (const t of textes) {
    const i = ecran.indexOf(t, depuis);
    if (i < 0) return false;
    depuis = i + t.length;
  }
  return true;
}
