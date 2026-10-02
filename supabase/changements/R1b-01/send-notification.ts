// Envoie une notification push (FCM, API v1) à tous les appareils
// enregistrés d'un profil. Appelée en interne seulement, par
// public.notifier() en base (via pg_net).
//
// R1b : la passerelle laisse passer la clé anon (Verify JWT), donc chaque
// appel doit présenter un jeton à usage unique dans l'en-tête
// « x-swend-jeton ». notifier() le crée en base (table
// notification_jetons) ; il est consommé ici par
// consommer_jeton_notification() avec la clé service_role : inconnu, déjà
// utilisé ou expiré → 403, avant toute lecture de la requête.
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

/// Lien ouvert au clic sur une notification web. Rappel J-7 / J-3 / J-1 /
/// Jour J (D-021) : l'app lit ?rappel=<pacte_id> au démarrage et demande à
/// la base la destination selon l'état actuel du Swend
/// (destination_rappel). Toute autre notification : l'accueil.
function lienWeb(data?: Record<string, string>): string {
  if (data?.type === 'rappel' && data.pacte_id) {
    return `${LIEN_APP}?rappel=${encodeURIComponent(data.pacte_id)}`;
  }
  // Chat après le Swend (D-023b) : le clic ouvre directement le chat.
  if (data?.type === 'chat_apres_swend' && data.chat_id) {
    return `${LIEN_APP}?chat_apres=${encodeURIComponent(data.chat_id)}`;
  }
  return LIEN_APP;
}

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

const FORMAT_JETON = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function nonAutorise(): Response {
  return new Response(JSON.stringify({ error: 'non_autorise' }), {
    status: 403,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  try {
    const client = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // R1b : jeton à usage unique émis par notifier(), sinon refus.
    const jeton = req.headers.get('x-swend-jeton') ?? '';
    if (!FORMAT_JETON.test(jeton)) return nonAutorise();
    const { data: autorise, error: erreurJeton } = await client.rpc(
      'consommer_jeton_notification',
      { p_jeton: jeton },
    );
    if (erreurJeton) {
      console.error('Erreur Supabase (jeton) :', JSON.stringify(erreurJeton));
      return nonAutorise();
    }
    if (autorise !== true) return nonAutorise();

    const { profile_id, title, body, data } = await req.json();
    if (!profile_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'profile_id, title et body sont requis' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      );
    }

    const compte: CompteDeService = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON') ?? '');
    console.log('Compte de service chargé pour le projet :', compte.project_id);
    const accessToken = await obtenirAccessToken(compte);
    console.log('Access token OAuth2 obtenu.');

    const { data: appareils, error } = await client
      .from('device_tokens')
      .select('id, token')
      .eq('profile_id', profile_id);
    if (error) {
      console.error('Erreur Supabase (device_tokens) :', JSON.stringify(error));
      throw error;
    }
    console.log(`${appareils?.length ?? 0} appareil(s) trouvé(s) pour ce profil.`);
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
                webpush: { fcm_options: { link: lienWeb(data) } },
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
    const messageErreur =
      e instanceof Error
        ? `${e.message}${e.stack ? `\n${e.stack}` : ''}`
        : JSON.stringify(e, Object.getOwnPropertyNames(e ?? {}));
    console.error('send-notification error:', messageErreur);
    return new Response(JSON.stringify({ error: messageErreur }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
