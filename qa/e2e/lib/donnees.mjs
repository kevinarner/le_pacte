// Accès direct à la base locale (vérifications d'état métier, fixtures) et
// à l'API locale "en tant que" un compte (vérifications RLS réelles).
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { config, COMPTES } from './config.mjs';

const PSQL = path.join(config.PG_BIN || '/usr/lib/postgresql/16/bin', 'psql');

export function sql(requete) {
  return execFileSync(PSQL, ['-h', config.pgSocket, '-p', config.QA_PG_PORT, '-U', 'postgres', '-d', config.QA_DB,
    '-X', '-q', '-tA', '-v', 'ON_ERROR_STOP=1', '-c', requete], { encoding: 'utf8' }).trim();
}
export function sqlJson(requete) {
  const r = sql(`select coalesce(json_agg(t), '[]') from (${requete}) t`);
  return JSON.parse(r || '[]');
}
export function chargerFixture(nom) {
  sql(`select qa.charger('${nom.replace(/'/g, '')}')`);
}

// État métier lisible, joint aux artefacts en cas d'échec (aucun secret).
export function etatMetier() {
  return {
    swends: sqlJson(`select id, statut, initiateur_nom, destinataire_nom, date_retenue from pactes order by created_at`),
    personnes: sqlJson(`select r.prenom, r.nom, r.cote, r.demande_statut, r.selectionne, pr.prenom as compte
                        from remplacants r left join profiles pr on pr.id = r.profil_id order by r.cote, r.id desc`),
    evenements: sqlJson(`select r.prenom, e.code, e.created_at from evenements_fil e join remplacants r on r.id = e.remplacant_id order by e.created_at`),
    messages: sqlJson(`select r.prenom as fil, p.prenom as expediteur, m.contenu, m.created_at
                       from messages m join remplacants r on r.id = m.remplacant_id left join profiles p on p.id = m.expediteur_id order by m.created_at`),
    notifications: sqlJson(`select p.prenom as destinataire, n.titre, n.corps from notifications_log n left join profiles p on p.id = n.profile_id order by n.id`),
  };
}

// --- API locale en tant qu'un compte (la RLS s'applique) -----------------
const jetons = new Map();
async function anon() {
  // Jeton anonyme local, signé avec le secret de la pile QA.
  const crypto = await import('node:crypto');
  const b = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const h = b({ alg: 'HS256', typ: 'JWT' }), p = b({ role: 'anon', iss: 'swend-qa', iat: 1700000000, exp: 2100000000 });
  return `${h}.${p}.${crypto.createHmac('sha256', config.QA_JWT_SECRET).update(`${h}.${p}`).digest('base64url')}`;
}
export async function jeton(nom) {
  if (jetons.has(nom)) return jetons.get(nom);
  const r = await fetch(`${config.apiUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: await anon(), 'content-type': 'application/json' },
    body: JSON.stringify({ email: COMPTES[nom].email, password: config.QA_MOT_DE_PASSE }),
  });
  const j = (await r.json()).access_token;
  jetons.set(nom, j);
  return j;
}
export async function lireComme(nom, table, requete = 'select=*') {
  const r = await fetch(`${config.apiUrl}/rest/v1/${table}?${requete}`, {
    headers: { apikey: await anon(), authorization: `Bearer ${await jeton(nom)}` },
  });
  if (!r.ok) throw new Error(`API ${table} (${nom}) : ${r.status} ${await r.text()}`);
  return r.json();
}

// Fiches des fixtures (identifiants fixes, voir qa/db/fixtures.sql).
const f = (s) => `00000000-0000-4000-8000-00000000${s}`;
export const FICHES = {
  kevin: f('a003'), sylvain: f('a002'), tom: f('a001'),       // côté Eliot
  leo: f('b002'), nina: f('b001'), kevinCoteDavid: f('b003'), // côté David
  sylvainCoteDavid: f('b003'),                                // (scelle_double)
};
// "statut|selectionne" d'une fiche, ex. "envoyee|f", "acceptee|t", "|f".
export function demande(ficheId) {
  return sql(`select coalesce(demande_statut, '') || '|' || case when selectionne then 't' else 'f' end from remplacants where id = '${ficheId}'`);
}
// Appel d'une fonction (RPC) en tant qu'un compte ; renvoie { ok, statut, corps }.
export async function appelerComme(nom, fonction, params) {
  const r = await fetch(`${config.apiUrl}/rest/v1/rpc/${fonction}`, {
    method: 'POST',
    headers: { apikey: await anon(), authorization: `Bearer ${await jeton(nom)}`, 'content-type': 'application/json' },
    body: JSON.stringify(params),
  });
  return { ok: r.ok, statut: r.status, corps: await r.text() };
}
// Insertion directe en tant qu'un compte (la RLS s'applique) ; renvoie
// { ok, statut, corps } — sert à vérifier qu'une écriture est refusée.
export async function insererComme(nom, table, ligne) {
  const r = await fetch(`${config.apiUrl}/rest/v1/${table}`, {
    method: 'POST',
    headers: { apikey: await anon(), authorization: `Bearer ${await jeton(nom)}`, 'content-type': 'application/json' },
    body: JSON.stringify(ligne),
  });
  return { ok: r.ok, statut: r.status, corps: await r.text() };
}
// Modification directe en tant qu'un compte (la RLS s'applique) ; renvoie
// { ok, statut, corps } (corps : l'erreur ; rien n'est relu, D-024).
export async function modifierComme(nom, table, filtre, valeurs) {
  const r = await fetch(`${config.apiUrl}/rest/v1/${table}?${filtre}`, {
    method: 'PATCH',
    headers: { apikey: await anon(), authorization: `Bearer ${await jeton(nom)}`, 'content-type': 'application/json',
      prefer: 'return=minimal' },
    body: JSON.stringify(valeurs),
  });
  return { ok: r.ok, statut: r.status, corps: await r.text() };
}
