# R1b-01

Niveau : 1 — préparé le 02/10/2026. Empreinte : donnée par
`scripts/paquet_controler.sh R1b-01 --avant-go`.

## Objectif

Fermer R1b : aujourd'hui, n'importe qui peut appeler l'Edge Function
`send-notification` avec la clé anon publique de l'app. La passerelle
l'accepte (`Verify JWT with legacy secret`) et le code ne contrôle pas
l'appelant : notification arbitraire vers n'importe quel profil, voire
suppression de ses appareils (réponse FCM `INVALID_ARGUMENT`). Après R1b,
seuls les appels émis par `public.notifier()` sont servis ; tout autre appel
reçoit 403, avant toute lecture de la requête.

**Mécanisme : un jeton à usage unique, sans aucun secret.**
1. `notifier()` tire un jeton aléatoire (`gen_random_uuid()`, 122 bits) et
   l'envoie brut dans l'en-tête `x-swend-jeton`. Elle n'enregistre en base
   (`notification_jetons`) que son **empreinte SHA-256**, jamais le jeton
   brut : lire la table, y compris avec l'accès en lecture seule, ne donne
   aucun jeton utilisable.
2. `send-notification` le consomme par la fonction
   `consommer_jeton_notification()` avec sa clé service_role. Celle-ci
   recalcule l'empreinte et fait un `delete … returning` atomique sur la clé
   primaire : vrai une seule fois, si le jeton a été émis il y a moins de
   15 minutes.

Pourquoi ce mécanisme plutôt que contrôler le rôle du jeton
d'authentification :
- le pré-contrôle du 02/10 a échoué en `22P02`, car le secret
  `service_role_key_notifications` n'est pas un JWT (nouveau format de clé
  probable) ;
- on ne sait pas non plus ce que la passerelle transmet à la fonction.

Le jeton ne dépend ni du format des clés, ni de la passerelle, ni d'aucun
secret à créer, lire ou recopier.

## Fichiers concernés

Production :
- table `public.notification_jetons` (nouvelle) : `empreinte` (SHA-256,
  32 octets) et `cree_le` seulement ;
- fonction `public.consommer_jeton_notification(uuid)` (nouvelle) ;
- fonction `public.notifier()` : même corps, plus le jeton ;
- Edge Function `send-notification`.

Dépôt : `supabase/functions/send-notification/index.ts` contient la nouvelle
version. La porte refuse de la déployer si elle diffère de
`send-notification.ts`.

Artefacts du paquet :

| Fichier | Rôle |
|---|---|
| `appliquer.sql` | Préconditions, changement SQL, assertions, en une transaction |
| `verifier.sql` | Assertions en lecture seule ; la porte s'arrête avant le déploiement si l'une échoue |
| `send-notification.ts` | Nouvelle version de l'Edge Function, `verify_jwt` inchangé à `true` |
| `tests_fonctionnels.sql` | Une push « Test technique R1b » vers Kevin et deux appels directs avec la clé anon (publique) |
| `send-notification.precedente.ts` | Version déployée actuelle (`main`, D-023b), pour le rollback |
| `rollback.sql` | `notifier()` d'origine à l'identique, suppression des objets R1b |

`notifier()` n'est pas versionnée dans `supabase/migrations/` (comme avant) :
sa nouvelle définition est dans `appliquer.sql`. Le banc QA garde sa doublure
de `notifier()` ; son réalignement est un lot à part.

## Préconditions

Relues en lecture seule le 02/10 à 15:09 UTC, et vérifiées à nouveau par
`appliquer.sql`, qui annule tout si l'une est fausse :
- corps de `notifier()` d'empreinte `b377eb8917710850ebdf01541448879b`
  (inchangé depuis l'audit) ;
- droits de `notifier()` : `{postgres=X/postgres}` (R1 en place) ;
- aucun objet R1b existant.

Vérifiées par lecture seule, sans être rejouées dans le SQL :
- `service_role` a l'usage du schéma `public` ;
- Kevin a un compte confirmé et 1 appareil ;
- les objets existants appartiennent à `postgres` (les nouveaux aussi :
  `owner to postgres`, avec une assertion) ;
- aucun échec pg_cron sur 24 h.

Session d'exécution : « Swend – écriture prod », sur une branche contenant
ce paquet validé.

## Impact attendu

- **Appels légitimes :** les notifications continuent sans interruption.
  - Pendant l'étape SQL, l'ancienne Edge Function ignore le nouvel en-tête.
  - Une fois la nouvelle déployée, `notifier()` envoie déjà son jeton.
  - Coût : une insertion et une suppression d'une ligne par notification.
- **Appels directs** (clé anon, jeton utilisateur, jeton inventé ou rejoué) :
  403 `{"error":"non_autorise"}`, sans lecture de la requête ni appel FCM.
- **Aucun changement** pour l'app, les planifications, les droits de
  `notifier()` (R1) ni `verify_jwt`.
- **Reste hors R1b :** R4 (numéro dans la push de message) ; le contenu des
  réponses en cas d'erreur.

## Vérifications après exécution

Par la porte, dans l'ordre (elle s'arrête au premier échec) :
1. **`appliquer.sql`** : assertions en fin de transaction — nouveau corps
   `cb331a844d5b2a5d155adeb6a948e558`, droits R1 conservés,
   `consommer_jeton_notification` réservée à `service_role`, table
   inaccessible à l'app et sous RLS, propriétaire `postgres`.
2. **`verifier.sql`** (lecture seule) : mêmes contrôles.
3. **Déploiement**, puis `GET …/functions/send-notification` : slug, statut
   `ACTIVE`, `verify_jwt = true` ; version et `ezbr_sha256` au reçu.
4. **`tests_fonctionnels.sql`** : envoie les trois requêtes de test.

Par la session de travail, en lecture seule, environ une minute après
l'exécution :
- `net._http_response` : la requête de `notifier()` vers Kevin en **200**
  (`envoyes` ≥ 1), les deux requêtes anon en **403** `non_autorise` ;
- `notification_jetons` sans jeton en attente ;
- comparaison complète du catalogue : seuls les objets R1b et le corps de
  `notifier()` changent ;
- planifications pg_cron en `succeeded` ;
- Kevin confirme la réception de « Test technique R1b ».

Tests locaux faits avant le Go :
- **SQL** (36 cas) : sur une base qui reproduit exactement la `notifier()` de
  production (même empreinte), avec `net.http_post` et Vault simulés.
  Couvre : rejeu, jeton expiré, jeton inventé, empreinte présentée à la place
  du jeton, absence du jeton brut en base, et concurrence (entrelacement
  forcé, annulation, rafale de 30 consommations simultanées : une seule
  acceptée) ;
- **Edge Function** (7 cas) : exécutée sous Deno avec client Supabase et
  réseau simulés. L'ancienne version laisse passer la clé anon dans 5 des 7
  cas, la nouvelle aucun.

## Rollback

`scripts/prod_ecrire.sh R1b-01 <empreinte> --rollback`, dans cet ordre :
1. redéploie `send-notification.precedente.ts` (avec `verify_jwt = true`),
   qui ignore l'en-tête ;
2. `rollback.sql` : `notifier()` rétablie à l'identique (empreinte
   `b377eb89…`, droits R1 conservés), puis suppression de
   `consommer_jeton_notification` et `notification_jetons`.

**Quand l'utiliser :** une notification légitime en 403 après le
déploiement, ou un test fonctionnel non conforme.

**Si le déploiement échoue :** la porte s'arrête, la partie SQL reste en
place mais elle est sans effet, puisque l'ancienne fonction ignore
l'en-tête. Le rollback ramène alors aussi la partie SQL.

**Ce que le rollback ne rétablit pas :** R1b redevient ouvert ; R1 reste
corrigé.

**Limite :** la version précédente est celle de `main` (déployée pour
D-023b, le 30/09). Le code déployé aujourd'hui n'a pas pu être comparé octet
par octet, faute d'accès en lecture aux Edge Functions ; sa structure a été
confirmée par Kevin.

## Sauvegardes

Aucune donnée n'est modifiée. Les deux états d'origine sont conservés dans le
paquet :
- `rollback.sql`, avec la définition exacte de `notifier()` relue en
  production ;
- `send-notification.precedente.ts`.

Niveau 1 : pas de sauvegarde de données requise.
