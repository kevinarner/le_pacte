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
    **avec fuseau**, enregistrée sous une forme canonique UTC sans perte :
    `"2026-11-17T18:00:00.000Z"`, avec des microsecondes si l'instant en a ;
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
   - **D-025** :
     - correction `jsonb` de `verifier_delai_minimum_swend()` : `unnest()`
       n'existe pas pour un `jsonb`, et toute création par un utilisateur non
       fondateur échouait ;
     - **réactivation de son déclencheur**, désactivé en production à cause
       de ce bug (état cible : actif) ;
   - nouveau déclencheur des dates : forme canonique, et **D-025b** ;
2. la correction des 2 Swends existants :
   - le Swend du 17/11 revient à **19:00 à Paris** ;
   - le Swend `6cb94c32` reçoit la `date_minimale` (17/10/2026) que le
     déclencheur désactivé n'avait pas posée.

**D-025b, invariant de production.** Pour **toute** écriture (app, fonction
serveur, SQL Editor), la date retenue doit être exactement l'une des dates
proposées, au même instant. Sinon : refus `date_non_proposee`. Le contrôle
porte aussi sur une modification des dates proposées.

**Aucune exception :**
- aucune fonction serveur n'écrit `date_retenue` ni `dates_proposees`
  (vérifié en production le 03/10, et vérifié par le test de parité du banc
  QA) ;
- déplacer un Swend revient à changer les deux colonnes ensemble ;
- une app périmée ne peut pas réenregistrer une heure décalée : son « 19:00 »
  sans fuseau, lu 19:00 UTC, ne correspond à aucune date proposée ;
- seul le banc QA déplace des Swends scellés dans le temps, avec
  `qa.deplacer_swend()`. Cet outil change les deux colonnes ensemble ; seul le
  déclencheur de négociation (dates figées hors négociation) y est contourné,
  et D-025b est revérifié. Cela n'existe pas en production.

## Fichiers concernés

Production :
- fonctions **nouvelles** :
  - `instant_date_proposee(jsonb)`, `instants_proposes(jsonb)` ;
  - `dates_proposees_canoniques(jsonb)` ;
  - `verifier_dates_swend()` ;
- fonctions **remplacées** :
  - `formater_date_heure_fr(timestamptz)`, qui devient `STABLE` ;
  - `verifier_delai_minimum_swend()` ;
- déclencheurs :
  - **nouveau** `trg_verrou_zz_dates_swend` sur `pactes`
    (`BEFORE INSERT OR UPDATE OF dates_proposees, date_retenue`). Son nom le
    fait passer après tous les gardes existants : `swend_passe`,
    `negociation_terminee`, `date_trop_proche` et `modification_interdite`
    restent prioritaires ;
  - **réactivé** `trg_verrou_delai_minimum_swend` (D-025), de `D` à `O` ;
- données : 2 lignes de `pactes`, colonnes `dates_proposees`, `date_retenue`
  et `date_minimale` ;
- sauvegarde : 2 tables du schéma interne `sauvegarde`.

Inchangés : `echeance_rappel`, `date_rappel_fr`, `heure_rappel_fr`,
`texte_rappel`, `ouverture_chat_apres_swend` (règle D-023b ; D-026 n'est pas
appliquée), `date_minimale_swend`, `figer_swends_passes`, la vue
`reservations_a_suivre`, la règle D-025 elle-même, les droits, RLS et
planifications.

Artefacts :

| Fichier | Rôle |
|---|---|
| `sauvegarde.sql` | Préconditions, puis copie des 2 Swends (dates, `date_minimale`), des 2 définitions de fonction remplacées et de l'état du déclencheur D-025 |
| `appliquer.sql` | Préconditions, migration (copie exacte, réactivation de D-025 comprise), correction des 2 Swends, assertions ; une transaction |
| `verifier.sql` | Assertions en lecture seule, puis résumé |
| `rollback.sql` | Fonctions d'origine à l'identique, objets R2 supprimés, déclencheur D-025 remis désactivé, 2 Swends restaurés depuis la sauvegarde |

Dépôt (hors paquet, déployé séparément) : app Flutter (écriture en `…Z`,
affichage à l'heure de Paris quel que soit le fuseau de l'appareil), banc QA
réaligné sur le schéma de production, tests.

## Préconditions

Relues en lecture seule le 03/10/2026, et vérifiées à nouveau par
`sauvegarde.sql` et `appliquer.sql`, qui annulent tout si l'une est fausse.

**Swend `8c6c9d64-d13d-44c6-8d0a-dec7eae430d6`** (le Swend du 17/11) :
- `confirme`, scellé, `nombre_echanges_date = 0` ;
- `dates_proposees = ["2026-11-17T19:00:00.000"]` ;
- `date_retenue = 2026-11-17 19:00:00+00` ;
- `date_minimale` NULL ;
- créé le 27/09, **avant** D-025 (exécutée le 01/10/2026 à 16:33 UTC), par
  des fondateurs.

**Swend `6cb94c32-f2d7-49e8-9fec-24cff795cccf`** (en négociation) :
- `enAttenteChoixDateDestinataire`, non scellé ;
- `dates_proposees = ["2026-12-01T20:00:00.000"]`, pas de date retenue ;
- `date_minimale` NULL ;
- créé le 02/10 à 02:30 (Paris), **après** D-025, par un utilisateur
  **non fondateur** : la date minimale attendue est le 17/10/2026.

**Tout autre Swend** (créé par la nouvelle app entre-temps) :
- des dates avec fuseau seulement, et une date retenue parmi ses dates
  proposées ;
- aucun autre Swend non fondateur, créé après D-025, sans `date_minimale`.

Sinon, le paquet s'arrête et il est à refaire.

**Fonctions remplacées :**
- `formater_date_heure_fr` : empreinte `4ae6b1ca…` ;
- `verifier_delai_minimum_swend` : empreinte `839c15e1…`.

**État de la base :**
- aucun objet R2 présent ;
- déclencheur de négociation : actif (`O`) ;
- déclencheur D-025 : désactivé (`D`) ;
- schéma `sauvegarde` : inaccessible à l'app.

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
| `date_minimale` | NULL | NULL (antérieur à D-025, pas de rétroactivité) |

**Swend du 01/12 (`6cb94c32`, en négociation) :**
- la date proposée devient `2026-12-01T19:00:00.000Z`, soit 20:00 à Paris.
  C'est l'heure qui a été choisie, et l'app l'affiche déjà ainsi ;
- `date_minimale` passe de NULL à **2026-10-17** (jour de création à Paris
  + 15) :
  - avant : sans cette valeur, la négociation pouvait contourner J+15 ;
  - après : une contre-proposition avant le 17/10 est refusée
    (`date_trop_proche`) ;
  - sa date actuelle (01/12) la respecte déjà ;
- les deux participants ne sont pas fondateurs.

**D-025 actif :**
- pour un Swend créé par un utilisateur standard, la base pose
  `date_minimale` et refuse toute date avant J+15 (règle validée, jusqu'ici
  inopérante en production) ;
- les fondateurs restent exemptés ;
- les Swends antérieurs au 01/10 ne sont pas concernés.

**Écritures :**
- *nouvelle app* : aucun changement visible, hors les refus D-025 voulus ;
- *ancienne app (cache)* : sa création ou contre-proposition est refusée
  (`date_sans_fuseau`), et son choix de date aussi (`date_non_proposee`) ;
  l'utilisateur doit recharger l'app ;
- *SQL Editor* : déplacer un Swend impose de modifier ensemble
  `date_retenue` et `dates_proposees` (D-025b) ; pour un Swend scellé, le
  déclencheur de négociation l'interdit déjà (paquet dédié si besoin).

**Hors R2 :** la règle D-026 (07:00).

## Vérifications après exécution

Par la porte, dans l'ordre (elle s'arrête au premier échec) :
1. **`sauvegarde.sql`** : 2 lignes, 2 définitions et l'état du déclencheur
   D-025 sauvegardés.
2. **`appliquer.sql`** : assertions en fin de transaction :
   - valeurs exactes des 2 Swends : 19:00 à Paris pour le 17/11 ;
     `date_minimale` à 17/10 pour `6cb94c32`, NULL pour `8c6c9d64` ;
   - tous les Swends conformes : forme canonique, D-025b, D-025 (dates ≥
     date minimale) ; aucun Swend non fondateur postérieur à D-025 sans
     `date_minimale` ;
   - empreintes des 6 fonctions identiques au banc QA, propriétaire
     `postgres`, aucune en `SECURITY DEFINER` ;
   - `formater_date_heure_fr('2026-11-17T18:00Z')` vaut
     « mardi 17 novembre à 19h00 » ;
   - déclencheurs : dates actif, négociation réactivé, **D-025 actif**.
3. **`verifier.sql`** (lecture seule) : mêmes contrôles, puis le résumé
   attendu :

   | Rendez-vous | Push | Rappels | J-7 | J-1 | Jour J | Chat | Réservation | D-025 | `date_minimale` 6cb94c32 |
   |---|---|---|---|---|---|---|---|---|---|
   | 17/11 19:00 | « mardi 17 novembre à 19h00 » | 19h00 | 10/11 18:00 | 16/11 18:00 | 17/11 16:00 | 17/11 22:00 | 19:00 | O | 2026-10-17 |

Par la session de travail, en lecture seule ensuite :
- catalogue (seuls les objets R2 et l'état du déclencheur D-025 changent) ;
- pg_cron en `succeeded` ;
- instantanés de parité QA à rafraîchir : `qa/db/parite/*_production.tsv`,
  et `declencheurs_admis.tsv` (retirer les lignes R2 et D-025).

Répétition locale (03/10), sur une copie de l'état de production d'avant R2 :
- **copie** : migrations sans R2, fonctions identiques à la production,
  déclencheur D-025 désactivé, 2 Swends identiques (dates, créateurs
  fondateur et non fondateur, dates de création) ;
- **déroulé** :
  - appliquer sans sauvegarde : refus ;
  - sauvegarde, puis une 2ᵉ sauvegarde : refus ;
  - appliquer, puis vérification en transaction en lecture seule :
    résumé conforme ;
  - 2ᵉ application : refus ;
  - rollback : retour exact aux empreintes, aux valeurs (`date_minimale`
    comprise) et au déclencheur D-025 désactivé ; 2ᵉ rollback : refus ;
  - nouvelle application : succès ;
- **après application** :
  - contre-proposition de l'app avant le 17/10 sur `6cb94c32` : refus
    `date_trop_proche` ;
  - choix de sa date proposée : accepté ;
  - ancienne app (« 20:00 » sans fuseau) : refus `date_non_proposee` ;
  - postgres qui pose une date retenue hors des propositions : refus
    `date_non_proposee` ;
- **préconditions** :
  - un autre Swend non fondateur postérieur à D-025 sans `date_minimale` :
    refus ;
  - le même avec sa date minimale : accepté.

## Rollback

`scripts/prod_ecrire.sh R2-01 <empreinte> --rollback` :
- fonctions d'origine **à l'identique** (définitions relues en production) ;
- suppression du déclencheur des dates et des 4 fonctions R2 ;
- **déclencheur D-025 remis désactivé** : avec la fonction d'origine,
  `unnest(jsonb)` ferait échouer les créations ;
- les 2 Swends remis dans l'état sauvegardé (dates et `date_minimale`) ;
- assertions : empreintes, valeurs et états d'origine ;
- la sauvegarde est conservée.

**Refus du rollback, sans rien modifier :** si l'un des 2 Swends a changé
depuis R2-01 (par exemple, la date du 01/12 a été choisie). La suite est
alors une décision humaine.

**À combiner avec le retour à l'app précédente** (gh-pages précédent). Sinon,
la nouvelle app écrit des instants corrects, mais les push de négociation
reviennent à l'heure UTC et la date du 17/11 y apparaîtrait à 20h00.

**Ce que le rollback ne rétablit pas :**
- les Swends créés après R2-01 gardent leurs dates avec fuseau (compatibles
  avec l'ancien schéma) et leur `date_minimale` ;
- D-025 redevient inopérant.

## Sauvegardes

Avant toute modification, dans le schéma interne `sauvegarde` (aucun accès
pour l'app) :
- `sauvegarde.r2_01_pactes_20261003` : `id`, `statut`, `dates_proposees`,
  `date_retenue`, `date_minimale`, `nombre_echanges_date`, `scelle_le` et
  `created_at` des 2 Swends ;
- `sauvegarde.r2_01_fonctions_20261003` : définitions complètes et
  empreintes de `formater_date_heure_fr` et `verifier_delai_minimum_swend`,
  et l'état du déclencheur D-025 (`tgenabled = D`).

Les mêmes définitions figurent aussi en clair dans `rollback.sql`.

## Ordre d'exécution (app puis production)

1. QA complète au vert sur le commit à déployer.
2. Déploiement de l'app R2 (gh-pages), puis vérification en production : un
   Swend s'affiche, la date proposée créée est en `…Z`.
   - Elle lit encore les anciennes chaînes sans fuseau.
   - Pendant quelques minutes, le Swend du 17/11 (19:00 UTC non corrigé)
     s'affiche à 20h00 : c'est l'heure que le serveur utilise à ce moment.
   - Ses nouvelles écritures sont déjà justes.
   - Un Swend créé par un utilisateur non fondateur pendant cette fenêtre
     (D-025 encore désactivé) bloquerait le paquet : il serait à refaire.
3. **Juste après**, exécution de R2-01 par la porte, après le Go de Kevin
   **et** d'Eliot. Si un Swend a bougé entre-temps, les préconditions
   arrêtent tout et le paquet est à refaire.
4. Vérifications en lecture seule (ci-dessus), puis la documentation.
