// Faux Supabase LOCAL pour le banc QA :
//  - /auth/v1 : connexion par mot de passe (comptes de test fixes), jetons
//    JWT HS256 signés avec le secret local (même secret que PostgREST) ;
//  - /rest/v1 : relais vers PostgREST (la RLS de la base s'applique) ;
//  - /realtime/v1 : WebSocket minimal. Les abonnements postgres_changes
//    reçoivent les changements en direct : chaque abonnement relit sa table
//    via PostgREST AVEC LE JETON DE L'ABONNÉ (donc sous RLS, comme le vrai
//    Realtime) toutes les 300 ms et pousse les différences ;
//  - un second port sert la build web QA de l'app.
// N'écoute que sur 127.0.0.1. Aucune connexion vers l'extérieur.
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { WebSocketServer } from 'ws';

const env = process.env;
const SECRET = env.QA_JWT_SECRET;
const PGRST = { host: '127.0.0.1', port: Number(env.QA_PGRST_PORT) };
const API_PORT = Number(env.QA_API_PORT);
const APP_PORT = Number(env.QA_APP_PORT);
const APP_DIR = path.join(env.QA_WORK, 'build');
const MOT_DE_PASSE = env.QA_MOT_DE_PASSE;
if (!SECRET || !API_PORT || !APP_PORT || !MOT_DE_PASSE) throw new Error('configuration QA incomplète');

// Mêmes identifiants que qa.id() dans qa/db/fixtures.sql.
const COMPTES = {
  'eliot@swend.test': '00000000-0000-4000-8000-0000000000e1',
  'david@swend.test': '00000000-0000-4000-8000-0000000000d1',
  'kevin@swend.test': '00000000-0000-4000-8000-0000000000a1',
  'sylvain@swend.test': '00000000-0000-4000-8000-0000000000b1',
};

const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
function jwt(payload) {
  const tete = b64({ alg: 'HS256', typ: 'JWT' });
  const corps = b64(payload);
  const sig = crypto.createHmac('sha256', SECRET).update(`${tete}.${corps}`).digest('base64url');
  return `${tete}.${corps}.${sig}`;
}
function verifier(token) {
  const [t, c, s] = (token || '').split('.');
  if (!s) return null;
  const attendu = crypto.createHmac('sha256', SECRET).update(`${t}.${c}`).digest('base64url');
  if (attendu !== s) return null;
  try { return JSON.parse(Buffer.from(c, 'base64url').toString()); } catch { return null; }
}
const refresh = new Map();
function utilisateur(id, email) {
  const t = new Date().toISOString();
  return { id, aud: 'authenticated', role: 'authenticated', email, email_confirmed_at: t,
    app_metadata: { provider: 'email', providers: ['email'] }, user_metadata: {}, identities: [],
    created_at: t, updated_at: t };
}
function session(id, email) {
  const now = Math.floor(Date.now() / 1000);
  const rt = crypto.randomBytes(12).toString('hex');
  refresh.set(rt, { id, email });
  return { access_token: jwt({ sub: id, email, role: 'authenticated', aud: 'authenticated', iat: now, exp: now + 3600 }),
    token_type: 'bearer', expires_in: 3600, expires_at: now + 3600, refresh_token: rt, user: utilisateur(id, email) };
}
const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*',
  'access-control-allow-methods': 'GET,POST,PATCH,PUT,DELETE,OPTIONS', 'access-control-expose-headers': '*' };
const json = (res, code, obj) => { res.writeHead(code, { ...CORS, 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); };

const api = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, { ...CORS, 'access-control-allow-headers': req.headers['access-control-request-headers'] || '*', 'access-control-max-age': '600' });
    return res.end();
  }
  const url = new URL(req.url, 'http://x');
  if (url.pathname.startsWith('/rest/v1')) {
    const headers = { ...req.headers, host: `${PGRST.host}:${PGRST.port}` };
    const p = http.request({ ...PGRST, method: req.method, path: req.url.replace('/rest/v1', '') || '/', headers }, (r) => {
      const h = { ...r.headers };
      for (const k of Object.keys(h)) if (k.toLowerCase().startsWith('access-control-')) delete h[k];
      res.writeHead(r.statusCode, { ...h, ...CORS });
      r.pipe(res);
    });
    p.on('error', (e) => json(res, 502, { message: String(e) }));
    return req.pipe(p);
  }
  let corps = '';
  req.on('data', (c) => (corps += c));
  req.on('end', () => {
    let b = {};
    try { b = corps ? JSON.parse(corps) : {}; } catch { /* corps vide */ }
    if (url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'password') {
      const email = (b.email || '').toLowerCase();
      const id = COMPTES[email];
      if (!id || b.password !== MOT_DE_PASSE) return json(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials', code: 400 });
      return json(res, 200, session(id, email));
    }
    if (url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'refresh_token') {
      const s = refresh.get(b.refresh_token);
      if (!s) return json(res, 400, { error: 'invalid_grant', msg: 'Invalid Refresh Token', code: 400 });
      return json(res, 200, session(s.id, s.email));
    }
    if (url.pathname === '/auth/v1/user') {
      const p = verifier((req.headers.authorization || '').replace('Bearer ', ''));
      if (!p || !p.sub) return json(res, 401, { msg: 'no user' });
      return json(res, 200, utilisateur(p.sub, p.email));
    }
    if (url.pathname === '/auth/v1/logout') { res.writeHead(204, CORS); return res.end(); }
    if (url.pathname === '/sante') return json(res, 200, { ok: true });
    json(res, 404, { msg: 'inconnu : ' + url.pathname });
  });
});

const wss = new WebSocketServer({ noServer: true });
const abonnements = new Set();

// Lit les lignes visibles par l'abonné (RLS) pour un abonnement.
function lireLignes(ab) {
  const filtre = ab.filtre ? `&${ab.filtre}` : '';
  return new Promise((ok) => {
    const r = http.request({ ...PGRST, method: 'GET', path: `/${ab.table}?select=*${filtre}`,
      headers: { authorization: `Bearer ${ab.jeton}`, accept: 'application/json' } }, (rep) => {
      let corps = '';
      rep.on('data', (c) => (corps += c));
      rep.on('end', () => { try { ok(rep.statusCode === 200 ? JSON.parse(corps) : null); } catch { ok(null); } });
    });
    r.on('error', () => ok(null));
    r.end();
  });
}
function pousser(ab, type, record, ancien) {
  const data = { schema: 'public', table: ab.table, commit_timestamp: new Date().toISOString(), type, columns: [], errors: null,
    ...(record ? { record } : {}), ...(ancien ? { old_record: { id: ancien.id } } : {}) };
  const payload = { data, ids: [ab.idBinding] };
  const msg = ab.tableau ? [ab.joinRef, null, ab.topic, 'postgres_changes', payload]
    : { join_ref: ab.joinRef, ref: null, topic: ab.topic, event: 'postgres_changes', payload };
  if (ab.ws.readyState === 1) ab.ws.send(JSON.stringify(msg));
}
async function surveiller() {
  for (const ab of abonnements) {
    if (ab.enCours) continue;
    ab.enCours = true;
    try {
      const lignes = await lireLignes(ab);
      if (!lignes) continue;
      const vues = new Map(lignes.map((l) => [l.id, JSON.stringify(l)]));
      if (ab.connues) {
        for (const l of lignes) {
          const avant = ab.connues.get(l.id);
          if (avant === undefined) pousser(ab, 'INSERT', l);
          else if (avant !== vues.get(l.id)) pousser(ab, 'UPDATE', l, l);
        }
        for (const id of ab.connues.keys()) if (!vues.has(id)) pousser(ab, 'DELETE', null, { id });
      }
      ab.connues = vues;
    } finally { ab.enCours = false; }
  }
}
setInterval(surveiller, 300);

api.on('upgrade', (req, socket, head) => {
  if (!req.url.startsWith('/realtime/v1/websocket')) return socket.destroy();
  wss.handleUpgrade(req, socket, head, (ws) => {
    ws.on('close', () => { for (const ab of abonnements) if (ab.ws === ws) abonnements.delete(ab); });
    ws.on('message', (brut) => {
      let m; try { m = JSON.parse(brut); } catch { return; }
      const tableau = Array.isArray(m);
      const [joinRef, ref, topic, event, payload] = tableau ? m : [m.join_ref, m.ref, m.topic, m.event, m.payload];
      let response = {};
      if (event === 'phx_join') {
        const pc = payload?.config?.postgres_changes || [];
        response = { postgres_changes: pc.map((c, i) => ({ ...c, id: 1000 + i })) };
        const jeton = payload?.access_token;
        pc.forEach((c, i) => {
          if (!c.table || !verifier(jeton)) return;
          abonnements.add({ ws, topic, joinRef, tableau, table: c.table, filtre: c.filter, jeton, idBinding: 1000 + i });
        });
      }
      if (event === 'phx_leave') for (const ab of abonnements) if (ab.ws === ws && ab.topic === topic) abonnements.delete(ab);
      if (event === 'access_token' && payload?.access_token) {
        for (const ab of abonnements) if (ab.ws === ws && ab.topic === topic) ab.jeton = payload.access_token;
      }
      const reply = { status: 'ok', response };
      ws.send(JSON.stringify(tableau ? [joinRef, ref, topic, 'phx_reply', reply] : { join_ref: joinRef, ref, topic, event: 'phx_reply', payload: reply }));
      if (event === 'phx_join') {
        const sys = { status: 'ok', message: 'Subscribed to PostgreSQL', extension: 'postgres_changes', channel: topic.replace('realtime:', '') };
        ws.send(JSON.stringify(tableau ? [joinRef, null, topic, 'system', sys] : { join_ref: joinRef, ref: null, topic, event: 'system', payload: sys }));
      }
    });
  });
});
api.listen(API_PORT, '127.0.0.1', () => console.log(`faux Supabase sur 127.0.0.1:${API_PORT}`));

// Serveur statique de la build QA.
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2', '.bin': 'application/octet-stream' };
http.createServer((req, res) => {
  const chemin = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let fichier = path.normalize(path.join(APP_DIR, chemin));
  if (!fichier.startsWith(APP_DIR)) { res.writeHead(403); return res.end(); }
  if (!fs.existsSync(fichier) || fs.statSync(fichier).isDirectory()) fichier = path.join(APP_DIR, 'index.html');
  if (!fs.existsSync(fichier)) { res.writeHead(503); return res.end('build QA absente : lancer qa/app/construire_app.sh'); }
  res.writeHead(200, { 'content-type': TYPES[path.extname(fichier)] || 'application/octet-stream', 'cache-control': 'no-store' });
  fs.createReadStream(fichier).pipe(res);
}).listen(APP_PORT, '127.0.0.1', () => console.log(`app QA sur 127.0.0.1:${APP_PORT}`));
