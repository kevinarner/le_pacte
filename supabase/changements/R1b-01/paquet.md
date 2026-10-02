# R1b-01

Niveau : 1 — préparé le 02/10/2026. Empreinte : donnée par
`scripts/paquet_controler.sh R1b-01 --avant-go`.

## Objectif

**Fermer R1b.** Aujourd'hui, n'importe qui peut appeler l'Edge Function
`send-notification` avec la clé anon publique de l'app. La passerelle
l'accepte (`Verify JWT with legacy secret`) et le code ne contrôle pas
l'appelant. Conséquences possibles :
- une notification arbitraire vers n'importe quel profil ;
- la suppression de ses appareils (réponse FCM `INVALID_ARGUMENT`).

Après R1b, seuls les appels émis par `public.notifier()` sont servis, et
seulement pour la notification exacte qu'elle a préparée. Tout autre appel
reçoit 403, avant tout traitement.

**Fermer aussi l'exposition de la clé service_role** constatée le 02/10.
`notifier()` l'envoyait en clair dans l'en-tête `Authorization`, donc dans
`net.http_request_queue`, une table lisible avec l'accès en lecture seule
(`pg_read_all_data`), le temps du traitement par pg_net. Après R1b,
`notifier()` ne lit plus ni n'envoie aucun secret.

**Mécanisme : un jeton à usage unique, lié au contenu, sans aucun secret.**
1. **Émission par `notifier()`.**
   - Elle prépare le corps de la notification (`profile_id`, `title`, `body`,
     `data`).
   - Elle tire un jeton aléatoire (`gen_random_uuid()`, 122 bits).
   - Elle n'enregistre en base (`notification_jetons`) que deux empreintes
     SHA-256 : celle du jeton et celle du corps (forme canonique
     `jsonb::text`). Jamais le jeton brut.
   - Elle appelle la fonction avec la **clé anon publique**, qui suffit à la
     passerelle, et le jeton brut dans `x-swend-jeton`.
2. **Consommation par `send-notification`.**
   - Avant tout traitement, elle transmet le jeton et le **corps brut reçu** à
     `consommer_jeton_notification()`, avec sa propre clé service_role (celle
     de son environnement, qui ne transite jamais par la base).
   - Cette fonction recalcule les deux empreintes et fait un `delete`
     atomique sur la clé primaire.
   - Le résultat est vrai une seule fois : pour ce jeton, pour **ce corps
     exact**, s'il a été émis il y a moins de 15 minutes.
   - Un corps différent (autre profil, autre texte, autres données) ne
     consomme rien et reçoit 403.

**Pourquoi ce mécanisme plutôt que contrôler le rôle du jeton
d'authentification :**
- le pré-contrôle du 02/10 a échoué en `22P02`, car le secret
  `service_role_key_notifications` n'est pas un JWT (nouveau format de clé
  probable) ;
- on ne sait pas non plus ce que la passerelle transmet à la fonction.

Le jeton ne dépend ni du format des clés, ni de la passerelle, ni d'aucun
secret.

**Ce qui reste visible quelques instants dans la file pg_net :**
- la clé anon, qui est publique ;
- le jeton brut ;
- le corps de la notification.

Quelqu'un qui les lirait ne pourrait que provoquer l'envoi de la même
notification au même destinataire : une seule fois, et à la place de l'appel
légitime, pas en plus.

## Fichiers concernés

Production :
- table `public.notification_jetons` (nouvelle) : `empreinte`,
  `charge_empreinte` (SHA-256, 32 octets chacune) et `cree_le` seulement ;
- fonction `public.consommer_jeton_notification(uuid, text)` (nouvelle) ;
- fonction `public.notifier()` : clé anon au lieu du secret Vault, jeton lié
  au corps ; reste inchangé (corps, URL, gestion d'erreur) ;
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
| `tests_fonctionnels.sql` | Une push « Test technique R1b » vers Kevin et deux appels directs avec la clé anon |
| `send-notification.precedente.ts` | Version déployée actuelle (`main`, D-023b), pour le rollback |
| `rollback.sql` | `notifier()` d'origine à l'identique, suppression des objets R1b |

La clé anon figure en clair dans `appliquer.sql` et `tests_fonctionnels.sql` :
c'est la clé publique de l'app, déjà présente dans `lib/constants.dart`.

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
- aucun échec pg_cron sur 24 h ;
- la file pg_net est lisible par l'accès en lecture seule : c'est l'objet du
  second volet.

**Le secret Vault `service_role_key_notifications` doit rester en place
jusqu'à la validation de R1b** : le rollback en a besoin.

Session d'exécution : « Swend – écriture prod », sur une branche contenant
ce paquet validé.

## Impact attendu

- **Appels légitimes :** les notifications continuent sans interruption.
  - Après l'étape SQL, l'ancienne Edge Function, toujours déployée, accepte
    la clé anon et ignore le jeton.
  - Après le déploiement, la nouvelle exige le jeton, que `notifier()` envoie
    déjà.
  - Coût : une insertion et une suppression d'une ligne par notification.
- **Appels directs** (clé anon, jeton utilisateur, jeton inventé ou rejoué,
  corps modifié) : 403 `{"error":"non_autorise"}`, sans appel FCM.
- **La clé service_role ne transite plus par la file pg_net.** Le secret Vault
  `service_role_key_notifications` n'est plus utilisé par `notifier()`.
- **Aucun changement** pour l'app, les planifications, les droits de
  `notifier()` (R1) ni `verify_jwt`.
- **Journaux de la fonction :** en cas d'erreur de consommation, seul le code
  d'erreur est écrit, ni jeton ni contenu.
- **Reste hors R1b :** R4 (numéro dans la push de message) ; le contenu des
  réponses d'erreur après le contrôle.

## Vérifications après exécution

Par la porte, dans l'ordre (elle s'arrête au premier échec) :
1. **`appliquer.sql`** : assertions en fin de transaction.
   - nouveau corps `cfb0159e1a33d7f77bd390baaf66a2f3`, et plus aucune lecture
     de Vault ;
   - droits R1 conservés ;
   - `consommer_jeton_notification` réservée à `service_role` ;
   - table limitée aux empreintes et à `cree_le`, inaccessible à l'app et
     sous RLS ;
   - propriétaire `postgres`.
2. **`verifier.sql`** (lecture seule) : mêmes contrôles.
3. **Déploiement**, puis `GET …/functions/send-notification` : slug, statut
   `ACTIVE`, `verify_jwt = true` ; version et `ezbr_sha256` au reçu.
4. **`tests_fonctionnels.sql`** : envoie les trois requêtes de test.

Par la session de travail, en lecture seule, environ une minute après
l'exécution (sans lire les en-têtes ni les empreintes) :
- `net._http_response` : la requête de `notifier()` vers Kevin en **200**
  (`envoyes` ≥ 1), les deux requêtes anon en **403** `non_autorise` ;
- `notification_jetons` sans jeton en attente ;
- comparaison complète du catalogue : seuls les objets R1b et le corps de
  `notifier()` changent ;
- planifications pg_cron en `succeeded` ;
- Kevin confirme la réception de « Test technique R1b ».

Tests locaux faits avant le Go :
- **SQL, 45 cas.** Base qui reproduit exactement la `notifier()` de
  production (même empreinte), avec `net.http_post` et Vault simulés. Ils
  couvrent :
  - la clé anon dans les en-têtes, aucun secret, l'envoi sans Vault ;
  - l'absence du jeton brut en base ;
  - la liaison au contenu : titre, texte, `profile_id` ou données modifiés et
    corps illisible refusés, sans consommer le jeton ; même contenu reformaté
    accepté ;
  - le rejeu, le jeton expiré, le jeton inventé, l'empreinte présentée à la
    place du jeton ;
  - le nettoyage ;
  - la concurrence : entrelacement forcé, annulation, rafale de 30
    consommations et rafale mixte de 15 corps modifiés + 15 légitimes, avec
    chaque fois une seule acceptée ;
  - les préconditions, le rollback et la ré-application.
- **Edge Function, 10 cas.** Exécutée sous Deno avec client Supabase et réseau
  simulés : corps brut transmis à la base, corps ou profil modifié refusé,
  rejeu, échec fermé, aucun jeton ni contenu dans les journaux. L'ancienne
  version échoue sur 7 cas, la nouvelle sur aucun.

## Rollback

`scripts/prod_ecrire.sh R1b-01 <empreinte> --rollback`, dans cet ordre :
1. redéploie `send-notification.precedente.ts` (avec `verify_jwt = true`),
   qui ignore le jeton ;
2. `rollback.sql` : `notifier()` rétablie à l'identique (empreinte
   `b377eb89…`, secret Vault, droits R1 conservés), puis suppression de
   `consommer_jeton_notification` et `notification_jetons`.

**Quand l'utiliser :** une notification légitime en 403 après le
déploiement, ou un test fonctionnel non conforme.

**Si le déploiement échoue :** la porte s'arrête. La partie SQL reste en
place et les notifications continuent : l'ancienne fonction accepte la clé
anon et ignore le jeton. Le rollback ramène alors aussi la partie SQL.

**Ce que le rollback ne rétablit pas :** R1b redevient ouvert, et la clé
service_role transite de nouveau par la file pg_net. R1 reste corrigé.

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

**Après validation de R1b, deux décisions humaines (niveau 3) :**
- supprimer le secret Vault `service_role_key_notifications`, devenu inutile ;
- changer ou non la clé secrète, par précaution, après l'exposition
  constatée.
