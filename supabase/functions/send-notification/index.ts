// Envoie une notification push (FCM, API v1) à tous les appareils
// enregistrés d'un profil. Appelée en interne — par les déclencheurs
// Postgres (via pg_net) sur les événements du pacte, jamais exposée
// publiquement sans vérification.
//
// Requête attendue : POST { profile_id: string, title: string, body: string,
// data?: Record<string, string> }
//
// Secrets requis (Dashboard Supabase > Edge Functions > Secrets) :
// - FCM_SERVICE_ACCOUNT_JSON : contenu entier du fichier JSON de compte de
//   service généré dans Firebase (Paramètres du projet > Comptes de
//   service > Générer une nouvelle clé privée). Ne jamais coller ce
//   fichier ailleurs que dans ce secret.
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement
// par l'environnement des Edge Functions.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const LIEN_APP = 'https://kevinarner.github.io/le_pacte/';

interface CompteDeService {
  project_id: string;
  client_email: string;
  private_key: string;
}

function base64url(entree: ArrayBuffer | string): string {
  const octets =
    typeof entree === 'string' ? new TextEncoder().encode(entree) : new Uint8Array(entree);
  let binaire = '';
  for (const o of octets) binaire += String.fromCharCode(o);
  return btoa(binaire).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemVersArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binaire = atob(base64);
  const octets = new Uint8Array(binaire.length);
  for (let i = 0; i < binaire.length; i++) octets[i] = binaire.charCodeAt(i);
  return octets.buffer;
}

/// Échange la clé privée du compte de service contre un jeton d'accès
/// OAuth2 de courte durée (flux JWT bearer), seul moyen d'authentification
/// accepté par l'API FCM v1 (contrairement à l'ancienne "server key").
async function obtenirAccessToken(compte: CompteDeService): Promise<string> {
  const maintenant = Math.floor(Date.now() / 1000);
  const entete = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const revendications = base64url(
    JSON.stringify({
      iss: compte.client_email,
      scope: FCM_SCOPE,
      aud: TOKEN_URL,
      iat: maintenant,
      exp: maintenant + 3600,
    }),
  );
  const aSigner = `${entete}.${revendications}`;

  const cle = await crypto.subtle.importKey(
    'pkcs8',
    pemVersArrayBuffer(compte.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cle,
    new TextEncoder().encode(aSigner),
  );
  const jwt = `${aSigner}.${base64url(signature)}`;

  const reponse = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!reponse.ok) {
    throw new Error(`Échec de l'obtention du token OAuth2 : ${await reponse.text()}`);
  }
  const { access_token } = await reponse.json();
  return access_token as string;
}

Deno.serve(async (req) => {
  try {
    const { profile_id, title, body, data } = await req.json();
    if (!profile_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'profile_id, title et body sont requis' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      );
    }

    const compte: CompteDeService = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON') ?? '');
    const accessToken = await obtenirAccessToken(compte);

    const client = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: appareils, error } = await client
      .from('device_tokens')
      .select('id, token')
      .eq('profile_id', profile_id);
    if (error) throw error;
    if (!appareils || appareils.length === 0) {
      return new Response(JSON.stringify({ envoyes: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const resultats = await Promise.all(
      appareils.map(async ({ id, token }) => {
        const reponse = await fetch(
          `https://fcm.googleapis.com/v1/projects/${compte.project_id}/messages:send`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token,
                notification: { title, body },
                data: data ?? {},
                webpush: { fcm_options: { link: LIEN_APP } },
              },
            }),
          },
        );
        if (!reponse.ok) {
          const texte = await reponse.text();
          // Token périmé/désinstallé : on le retire pour ne plus réessayer.
          if (
            texte.includes('UNREGISTERED') ||
            texte.includes('NOT_FOUND') ||
            texte.includes('INVALID_ARGUMENT')
          ) {
            await client.from('device_tokens').delete().eq('id', id);
          }
          return { id, ok: false, erreur: texte };
        }
        return { id, ok: true };
      }),
    );

    return new Response(
      JSON.stringify({ envoyes: resultats.filter((r) => r.ok).length, resultats }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
