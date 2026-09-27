// Configuration E2E lue dans qa/config.env, avec garde-fou production.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const QA_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const REPO_ROOT = path.resolve(QA_ROOT, '..');

const env = {};
for (const ligne of fs.readFileSync(path.join(QA_ROOT, 'config.env'), 'utf8').split('\n')) {
  const m = ligne.match(/^\s*([A-Z_][A-Z0-9_]*)=(.*)$/);
  if (m) env[m[1]] = m[2].trim();
}
for (const [k, v] of Object.entries(process.env)) if (k.startsWith('QA_') || k === 'PG_BIN') env[k] = v;

export const config = {
  ...env,
  apiUrl: `http://127.0.0.1:${env.QA_API_PORT}`,
  appUrl: `http://127.0.0.1:${env.QA_APP_PORT}`,
  pgSocket: path.join(env.QA_DATA_DIR, 'run'),
  artefacts: path.join(QA_ROOT, 'artifacts'),
};

// Garde-fou : l'app et l'API visées doivent être locales, et rien ne doit
// ressembler au projet de production (référence lue dans lib/constants.dart).
const constantes = fs.readFileSync(path.join(REPO_ROOT, 'lib/constants.dart'), 'utf8');
export const REF_PRODUCTION = (constantes.match(/https:\/\/([a-z0-9]+)\.supabase\.co/) || [])[1];
export function gardeFou() {
  if (!REF_PRODUCTION) throw new Error('garde-fou : référence de production introuvable — arrêt par prudence');
  for (const url of [config.apiUrl, config.appUrl]) {
    if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url) || url.includes(REF_PRODUCTION)) {
      throw new Error(`garde-fou : ${url} n'est pas une adresse locale — refus de démarrer`);
    }
  }
  for (const [k, v] of Object.entries(process.env)) {
    if (/SERVICE_ROLE/i.test(k)) throw new Error(`garde-fou : ${k} défini — refus de démarrer`);
    if (typeof v === 'string' && (v.includes(REF_PRODUCTION) || /\.supabase\.(co|com)/.test(v)) &&
        (k.startsWith('QA_') || k.startsWith('SUPABASE') || k === 'DATABASE_URL' || k.startsWith('PG'))) {
      throw new Error(`garde-fou : ${k} pointe vers Supabase — refus de démarrer`);
    }
  }
}

// Seules les requêtes vers la pile locale sont autorisées depuis le navigateur.
export function urlAutorisee(url) {
  if (url.startsWith('data:') || url.startsWith('blob:')) return true;
  try {
    const u = new URL(url);
    return u.hostname === '127.0.0.1' && [config.QA_API_PORT, config.QA_APP_PORT].includes(u.port);
  } catch { return false; }
}

export function cheminChromium() {
  if (env.QA_CHROMIUM && fs.existsSync(env.QA_CHROMIUM)) return env.QA_CHROMIUM;
  const base = '/opt/pw-browsers';
  if (fs.existsSync(base)) {
    for (const d of fs.readdirSync(base).filter((d) => /^chromium-\d+$/.test(d)).sort().reverse()) {
      const c = path.join(base, d, 'chrome-linux', 'chrome');
      if (fs.existsSync(c)) return c;
    }
  }
  return undefined; // playwright-core utilisera son propre chemin
}

// Les comptes de test (identiques à qa/db/fixtures.sql et au faux serveur).
export const COMPTES = {
  eliot: { email: 'eliot@swend.test', prenom: 'Eliot', nomComplet: 'Eliot Martin', id: '00000000-0000-4000-8000-0000000000e1', tel: '06 01 02 03 04' },
  david: { email: 'david@swend.test', prenom: 'David', nomComplet: 'David Schlang', id: '00000000-0000-4000-8000-0000000000d1', tel: '+33 6 02 03 04 05' },
  kevin: { email: 'kevin@swend.test', prenom: 'Kevin', nomComplet: 'Kevin Arner', id: '00000000-0000-4000-8000-0000000000a1', tel: '06 70 41 92 77' },
  sylvain: { email: 'sylvain@swend.test', prenom: 'Sylvain', nomComplet: 'Sylvain Landiech', id: '00000000-0000-4000-8000-0000000000b1', tel: '06 55 44 33 22' },
};
export const CONTACTS_SANS_COMPTE = {
  tom: { prenom: 'Tom', nom: 'Petit', nomComplet: 'Tom Petit', tel: '07 11 22 33 44', e164: '+33711223344' },
  leo: { prenom: 'Léo', nom: 'Blanc', nomComplet: 'Léo Blanc', tel: '07 22 33 44 55' },
  nina: { prenom: 'Nina', nom: 'Roy', nomComplet: 'Nina Roy', tel: '07 33 44 55 66' },
};
