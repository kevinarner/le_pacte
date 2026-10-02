# R2-01

Niveau : 2 — préparé le 03/10/2026. Empreinte : donnée par
`scripts/paquet_controler.sh R2-01 --avant-go`. Go des **deux** fondateurs.

## Objectif

**Fermer R2 : une heure choisie à Paris reste la même heure partout.**

Avant R2, l'app envoyait l'heure choisie sans fuseau
(`"2026-11-17T19:00:00.000"`). PostgREST la convertissait en `timestamptz`
dans le fuseau de session de la base (UTC) : 19:00 à Paris devenait 19:00 UTC,
soit **20:00 à Paris en hiver** et 21:00 en été.
- L'app et les push de négociation affichaient 19h00 : ils lisaient l'heure
  UTC comme si c'était l'heure de Paris.
- Toute la logique serveur, elle, convertit en heure de Paris :
  - textes des rappels à 20h00 ;
  - gel à H à 20:00 ;
  - rappel du Jour J à 17:00 ;
  - chat à 23:00 ;
  - vue des réservations à 20:00.

Convention R2 (appliquée par l'app et par ce paquet) :
- heure métier = heure murale d'Europe/Paris ;
- un rendez-vous est stocké comme un **instant absolu** :
  - `date_retenue` reste un `timestamptz` ;
  - chaque élément de `dates_proposees` (`jsonb`) est une chaîne ISO 8601
    **avec fuseau**, enregistrée sous la forme canonique UTC
    `"2026-11-17T18:00:00.000Z"` ;
- les conversions vers l'heure de Paris sont explicites, côté app (module
  `heure_paris.dart`, données IANA) comme côté base (`at time zone
  'Europe/Paris'`) ;
- une chaîne sans fuseau est **refusée** (`date_sans_fuseau`) au lieu d'être
  interprétée en silence.

Ce paquet applique en une transaction :
1. la migration `supabase/migrations/20261003000000_fuseaux_horaires.sql`
   (copie exacte, sections 1 à 4) :
   - lecture stricte des dates proposées ;
   - `formater_date_heure_fr()` à l'heure de Paris ;
   - correction `jsonb` de `verifier_delai_minimum_swend()`, D-025 :
     `unnest()` n'existe pas pour un `jsonb`, toute création par un
     utilisateur non fondateur aurait échoué ;
   - nouveau déclencheur des dates : forme canonique, et **D-025b** ;
2. la conversion des 2 Swends existants : le Swend du 17/11 revient à
   **19:00 à Paris**.

**D-025b** : pour une écriture de l'app (`authenticated` / `anon`), la date
retenue doit être exactement l'une des dates proposées, au même instant.
Sinon : refus `date_non_proposee`. Une app périmée ne peut donc pas
réenregistrer une heure décalée : son « 19:00 » sans fuseau, lu 19:00 UTC,
ne correspond à aucune date proposée. Comme D-025, le SQL Editor et les
fonctions serveur ne sont pas concernés.

## Fichiers concernés

Production :
- fonctions **nouvelles** :
  - `instant_date_proposee(jsonb)`, `instants_proposes(jsonb)` ;
  - `dates_proposees_canoniques(jsonb)` ;
  - `verifier_dates_swend()` ;
- fonctions **remplacées** :
  - `formater_date_heure_fr(timestamptz)`, qui devient `STABLE` ;
  - `verifier_delai_minimum_swend()` ;
- déclencheur **nouveau** `trg_verrou_zz_dates_swend` sur `pactes`
  (`BEFORE INSERT OR UPDATE OF dates_proposees, date_retenue`). Son nom le
  fait passer après tous les gardes existants : `swend_passe`,
  `negociation_terminee`, `date_trop_proche` et `modification_interdite`
  restent prioritaires ;
- données : 2 lignes de `pactes`, colonnes `dates_proposees` et
  `date_retenue` ;
- sauvegarde : 2 tables du schéma interne `sauvegarde`.

Inchangés : `echeance_rappel`, `date_rappel_fr`, `heure_rappel_fr`,
`texte_rappel`, `ouverture_chat_apres_swend` (règle D-023b ; D-026 n'est pas
appliquée), `date_minimale_swend`, `figer_swends_passes`, la vue
`reservations_a_suivre`, les droits, RLS et planifications. **L'état du
déclencheur D-025 `trg_verrou_delai_minimum_swend` n'est pas modifié** : il
est désactivé en production (`D`, constaté le 03/10, origine inconnue) et le
reste ; le réactiver relève d'une décision séparée.

Artefacts :

| Fichier | Rôle |
|---|---|
| `sauvegarde.sql` | Préconditions, puis copie des 2 Swends (colonnes de date) et des 2 définitions de fonction remplacées |
| `appliquer.sql` | Préconditions, migration (copie exacte), conversion des 2 Swends, assertions ; une transaction |
| `verifier.sql` | Assertions en lecture seule, puis résumé du Swend du 17/11 |
| `rollback.sql` | Fonctions d'origine à l'identique, objets R2 supprimés, 2 Swends restaurés depuis la sauvegarde |

Dépôt (hors paquet, déployé séparément) : app Flutter (écriture en `…Z`,
affichage à l'heure de Paris quel que soit le fuseau de l'appareil), banc QA
réaligné sur le schéma de production, tests.

## Préconditions

Relues en lecture seule le 03/10/2026, et vérifiées à nouveau par
`sauvegarde.sql` et `appliquer.sql`, qui annulent tout si l'une est fausse :

- **Swend `8c6c9d64-d13d-44c6-8d0a-dec7eae430d6`** :
  - `confirme`, scellé, `nombre_echanges_date = 0` ;
  - `dates_proposees = ["2026-11-17T19:00:00.000"]` ;
  - `date_retenue = 2026-11-17 19:00:00+00` ;
- **Swend `6cb94c32-f2d7-49e8-9fec-24cff795cccf`** :
  - `enAttenteChoixDateDestinataire`, non scellé ;
  - `dates_proposees = ["2026-12-01T20:00:00.000"]`, pas de date retenue ;
- **tout autre Swend** (créé par la nouvelle app entre-temps) : des dates
  avec fuseau seulement. Un Swend créé par une ancienne app bloque le paquet ;
- **fonctions remplacées** :
  - `formater_date_heure_fr` : empreinte `4ae6b1ca…` ;
  - `verifier_delai_minimum_swend` : empreinte `839c15e1…` ;
- **aucun objet R2 présent** ;
- **déclencheurs** :
  - de négociation : actif (`O`) ;
  - D-025 : désactivé (`D`) ;
- **schéma `sauvegarde`** : inaccessible à l'app.

**Prérequis : l'app R2 est déployée et vérifiée avant ce paquet** (voir
l'ordre ci-dessous).

## Impact attendu

**Swend du 17/11 :**

| | Avant | Après |
|---|---|---|
| Stocké | 19:00 UTC | 18:00 UTC |
| Heure à Paris pour le serveur | 20:00 | 19:00 |
| Texte des rappels | « à 20h00 » | « à 19h00 » |
| Rappel J-7 | 10/11 18:00 | inchangé |
| Rappel J-1 | 16/11 18:00 | inchangé |
| Rappel Jour J | 17:00 | 16:00 |
| Gel à H | 20:00 | 19:00 |
| Chat | 23:00 | 22:00 |
| Vue des réservations | 20:00 | 19:00 |
| Push et app | 19h00 | 19h00 (inchangé) |

**Swend du 01/12 (en négociation) :** la date proposée devient
`2026-12-01T19:00:00.000Z`, soit 20:00 à Paris. C'est l'heure qui a été
choisie, et l'app l'affiche déjà ainsi.

**Écritures :**
- *nouvelle app* : aucun changement visible ;
- *ancienne app (cache)* : sa création ou contre-proposition est refusée
  (`date_sans_fuseau`), et son choix de date aussi (`date_non_proposee`) ;
  l'utilisateur doit recharger l'app.

**Hors R2 :**
- la réactivation éventuelle du déclencheur D-025 ;
- la règle D-026 (07:00).

## Vérifications après exécution

Par la porte, dans l'ordre (elle s'arrête au premier échec) :
1. **`sauvegarde.sql`** : 2 lignes et 2 définitions sauvegardées.
2. **`appliquer.sql`** : assertions en fin de transaction :
   - valeurs exactes des 2 Swends, et 19:00 à Paris pour le 17/11 ;
   - tous les Swends conformes : forme canonique et D-025b ;
   - empreintes des 6 fonctions identiques au banc QA, propriétaire
     `postgres`, aucune en `SECURITY DEFINER` ;
   - `formater_date_heure_fr('2026-11-17T18:00Z')` vaut
     « mardi 17 novembre à 19h00 » ;
   - déclencheurs : nouveau actif, négociation réactivé, D-025 inchangé.
3. **`verifier.sql`** (lecture seule) : mêmes contrôles, puis le résumé
   attendu :

   | Rendez-vous | Push | Rappels | J-7 | J-1 | Jour J | Chat | Réservation | D-025 |
   |---|---|---|---|---|---|---|---|---|
   | 17/11 19:00 | « mardi 17 novembre à 19h00 » | 19h00 | 10/11 18:00 | 16/11 18:00 | 17/11 16:00 | 17/11 22:00 | 19:00 | D |

Par la session de travail, en lecture seule ensuite :
- catalogue (seuls les objets R2 changent) ;
- pg_cron en `succeeded` ;
- instantanés de parité QA à rafraîchir : `qa/db/parite/*_production.tsv`
  et `declencheurs_admis.tsv` (retirer la ligne R2).

Répétition locale (03/10), sur une copie de l'état de production d'avant R2 :
- migrations sans R2, fonctions et Swends identiques à la production,
  déclencheur D-025 désactivé ;
- appliquer sans sauvegarde : refus ;
- sauvegarde, puis une 2ᵉ sauvegarde : refus ;
- appliquer, puis vérification en transaction en lecture seule ;
- 2ᵉ application : refus ;
- rollback : retour exact aux empreintes et valeurs d'origine ; 2ᵉ rollback :
  refus ;
- nouvelle application : succès ;
- un Swend créé avec fuseau avant le paquet : accepté ; un Swend sans fuseau
  (ancienne app) : refus.

## Rollback

`scripts/prod_ecrire.sh R2-01 <empreinte> --rollback` :
- fonctions d'origine **à l'identique** (définitions relues en production) ;
- suppression du déclencheur et des 4 fonctions R2 ;
- les 2 Swends remis dans l'état sauvegardé ;
- assertions : empreintes et valeurs d'origine ;
- la sauvegarde est conservée.

**Refus du rollback, sans rien modifier :** si l'un des 2 Swends a changé
depuis R2-01 (par exemple, la date du 01/12 a été choisie). La suite est
alors une décision humaine.

**À combiner avec le retour à l'app précédente** (gh-pages précédent). Sinon,
la nouvelle app écrit des instants corrects, mais les push de négociation
reviennent à l'heure UTC et la date du 17/11 y apparaîtrait à 20h00.

**Ce que le rollback ne rétablit pas :** les Swends créés après R2-01 gardent
leurs dates avec fuseau. Elles sont compatibles avec l'ancien schéma, qui
les lit comme des instants.

## Sauvegardes

Avant toute modification, dans le schéma interne `sauvegarde` (aucun accès
pour l'app) :
- `sauvegarde.r2_01_pactes_20261003` : `id`, `statut`, `dates_proposees`,
  `date_retenue`, `nombre_echanges_date`, `scelle_le` des 2 Swends convertis ;
- `sauvegarde.r2_01_fonctions_20261003` : définitions complètes et
  empreintes de `formater_date_heure_fr` et `verifier_delai_minimum_swend`.

Les mêmes définitions figurent aussi en clair dans `rollback.sql`.

## Ordre d'exécution (app puis production)

1. QA complète au vert sur le commit à déployer.
2. Déploiement de l'app R2 (gh-pages), puis vérification en production : un
   Swend s'affiche, la date proposée créée est en `…Z`.
   - Elle lit encore les anciennes chaînes sans fuseau.
   - Pendant quelques minutes, le Swend du 17/11 (19:00 UTC non corrigé)
     s'affiche à 20h00 : c'est l'heure que le serveur utilise à ce moment.
   - Ses nouvelles écritures sont déjà justes.
3. **Juste après**, exécution de R2-01 par la porte, après le Go de Kevin
   **et** d'Eliot. Si un des 2 Swends a bougé entre-temps, les préconditions
   arrêtent tout et le paquet est à refaire.
4. Vérifications en lecture seule (ci-dessus), puis la documentation.
