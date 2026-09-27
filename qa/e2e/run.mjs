#!/usr/bin/env node
// Lanceur des scénarios E2E.
//   node qa/e2e/run.mjs --suite smoke|full
//   node qa/e2e/run.mjs --scenario desistement      (nom ou partie du nom)
//   node qa/e2e/run.mjs --liste
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright-core';
import { config, gardeFou, cheminChromium, QA_ROOT } from './lib/config.mjs';
import { Rapport } from './lib/rapport.mjs';
import { Execution, Echec, resume } from './lib/execution.mjs';

gardeFou();

const args = process.argv.slice(2);
const option = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const suite = option('--suite');
const filtre = option('--scenario');

const dossierScenarios = path.join(QA_ROOT, 'e2e', 'scenarios');
const scenarios = [];
for (const f of fs.readdirSync(dossierScenarios).filter((f) => f.endsWith('.mjs')).sort()) {
  const m = await import(path.join(dossierScenarios, f));
  scenarios.push({ fichier: f, ...m.default });
}
if (args.includes('--liste')) {
  for (const s of scenarios) console.log(`${s.nom.padEnd(34)} [${s.suites.join(', ')}] ${s.titre}`);
  process.exit(0);
}
const choisis = scenarios.filter((s) => (filtre ? s.nom.includes(filtre) : s.suites.includes(suite || 'full')));
if (!choisis.length) { console.error('Aucun scénario ne correspond.'); process.exit(2); }

const horodatage = new Date().toISOString().replace(/[:T]/g, '-').slice(0, 19);
const dossierRun = path.join(config.artefacts, `${horodatage}-${filtre || suite || 'full'}`);
const rapport = new Rapport();
const navigateur = await chromium.launch({ executablePath: cheminChromium(), args: ['--no-sandbox'] });

for (const s of choisis) {
  rapport.titre(`${s.nom} — ${s.titre}`);
  const ex = new Execution(s, navigateur, rapport);
  const debut = Date.now();
  let ok = true;
  try {
    await ex.executer();
  } catch (e) {
    ok = false;
    const dossier = path.join(dossierRun, s.nom);
    const detail = [`scénario : ${s.nom}`, `étape    : ${ex.etapeCourante}`];
    if (e instanceof Echec) {
      if (e.attendu !== undefined) detail.push(`attendu  : ${e.attendu}`);
      if (e.obtenu !== undefined) detail.push(`obtenu   : ${resume(String(e.obtenu), 500)}`);
    } else detail.push(`erreur   : ${e.message.split('\n')[0]}`);
    detail.push(`artefacts : ${path.relative(process.cwd(), dossier)}`);
    rapport.fail(s.nom, e instanceof Echec ? e.message : `${ex.etapeCourante} (erreur inattendue)`, detail);
    await ex.conserverArtefacts(dossier, e);
  } finally {
    await ex.fermer();
  }
  rapport.scenarios.push({ nom: s.nom, ok, duree: Math.round((Date.now() - debut) / 1000) });
  rapport.ecrire(`   (${Math.round((Date.now() - debut) / 1000)} s)`);
}
await navigateur.close();

const resumeLignes = rapport.resume();
for (const l of resumeLignes) console.log(l);
fs.mkdirSync(dossierRun, { recursive: true });
fs.writeFileSync(path.join(dossierRun, 'rapport.txt'), [...rapport.lignes, ...resumeLignes].join('\n') + '\n');
const dernier = path.join(config.artefacts, 'dernier');
try { fs.rmSync(dernier, { force: true }); fs.symlinkSync(dossierRun, dernier); } catch { /* sans lien symbolique */ }
console.log(`Rapport : ${path.relative(process.cwd(), path.join(dossierRun, 'rapport.txt'))}`);
process.exit(rapport.nFail ? 1 : 0);
