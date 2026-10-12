# D-027-01

Niveau : 2 — préparé le 12/10/2026. Empreinte : donnée par
`scripts/paquet_controler.sh D-027-01 --avant-go`. Go d'Eliot.

## Objectif

Mettre en production le côté serveur du **lot 1 de D-027** (« En cas
d'imprévu » : états et actions), décrit dans `DECISIONS.md` (D-027) et
`PRODUCT_RULES.md` §6, §7.5, §7.6, §9.6 :

1. **Déclaration d'imprévu par côté** (table interne `imprevus_declares`),
   posée dès qu'une demande existe de ce côté, effacée par « Je peux
   finalement venir ». Elle fait foi pour l'état « cherche » des rappels
   (`etat_cote_titulaire()`) et prépare les échéances H-3 / H (lot 4).
2. **Envoi groupé** `envoyer_demandes_remplacement(ids[])` : tout ou rien,
   personnes avec et sans compte mélangées, canal de remise renvoyé pour
   chacune ; `envoyer_demande_remplacement(id)` en devient le cas d'une
   personne (l'app actuelle continue de l'appeler).
3. **« Je peux finalement venir »** `je_peux_finalement_venir(pacte)` : avant
   toute acceptation, demandes en attente closes (« Plus besoin de répondre /
   Eliot pourra finalement être là pour ce Swend. »), le côté redevient
   normal, les refus restent des refus.
4. **Réactivation au désistement** : les demandes en attente avant
   l'acceptation (mémorisées dans la table interne `clotures_demandes`)
   redeviennent actives (« Ta réponse est finalement attendue / La place est
   à nouveau disponible pour ce Swend. ») ; personne sans compte : demande
   active **et** action « Renvoyer le message à … » pour le titulaire
   (`remplacants.message_a_renvoyer`, `marquer_message_renvoye()`), jamais en
   silence. Remplace D-004.
5. **Notifications de l'imprévu** au tutoiement, envoyées par les fonctions :
   acceptation (titulaire, personnes en attente), refus (titulaire,
   seulement au dernier refus), désistement, retour, réactivation. Le
   déclencheur `notifier_demande_remplacement()` ne garde que
   l'indisponibilité spontanée.

Aucune donnée existante n'est modifiée : seule la table interne des
déclarations est remplie (côtés `confirme` qui cherchent déjà ou dont la
place est prise).

## Fichiers concernés

Artefacts : `sauvegarde.sql` (sauvegarde ciblée, une transaction),
`appliquer.sql` (préconditions, migration
`supabase/migrations/20261012000000_imprevu_etats_et_actions.sql` en copie
exacte, assertions ; une transaction), `verifier.sql` (lecture seule),
`rollback.sql`.

Objets de production :
- créés : tables internes `public.imprevus_declares` et
  `public.clotures_demandes` (RLS activée, aucun droit pour `public`,
  `anon`, `authenticated`) ; colonne `public.remplacants.message_a_renvoyer`
  (`boolean not null default false`, aucun droit d'écriture pour l'app) ;
  fonctions `envoyer_demandes_remplacement(uuid[])`,
  `je_peux_finalement_venir(uuid)`, `marquer_message_renvoye(uuid)`
  (SECURITY DEFINER, `authenticated` seulement), `pousser_personne(uuid,
  text, text)`, `pousser_titulaire(uuid, text, text, boolean)`,
  `prenom_titulaire_de(uuid)`, `suivre_demande_avant()`,
  `suivre_demande_apres()` (internes, non exécutables par l'app) ;
  déclencheurs `trg_suivre_demande_avant` (BEFORE UPDATE OF demande_statut,
  message_a_renvoyer) et `trg_suivre_demande_apres` (AFTER INSERT OR UPDATE
  OF demande_statut) sur `remplacants` ;
- remplacées (même signature) : `normaliser_nouveau_remplacant()`,
  `etat_cote_titulaire(uuid, text)`, `notifier_demande_remplacement()`,
  `journaliser_demande_remplacement()`, `envoyer_demande_remplacement(uuid)`
  (le droit d'exécution de `public` / `anon` est retiré : `authenticated`
  seulement), `ajouter_et_demander_remplacement(…)`,
  `annuler_demande_remplacement(uuid)`, `repondre_demande_remplacement(uuid,
  boolean)`, `se_desister_du_remplacement(uuid)` ;
- contrainte `evenements_fil_code_check` élargie à `demande_reactivee` et
  `retour_titulaire` ;
- schéma interne `sauvegarde` : tables `d027_01_fonctions_20261012` et
  `d027_01_remplacants_20261012`.

Aucune politique RLS, aucune Edge Function, aucune planification, aucun
objet `auth` modifiés. `annuler_swend()`, `figer_swends_passes()`,
`annuler_si_double_absence()` et les rappels sont inchangés (lots 2 et 4).

Niveau 2 : la migration change le comportement de demandes réelles en cours
(réactivation automatique avec push après un désistement, notifications
réécrites), remplit une table à partir des données réelles, et le rollback
supprime une colonne de `remplacants` (DDL destructif, limité aux objets
créés par ce paquet). Sauvegarde ciblée, rollback et préconditions
obligatoires.

## Préconditions

**Ordre.** À exécuter **après** R2-01 et D-023c-01 (migrations
`fuseaux_horaires.sql` et `nouveau_swend.sql`) : c'est l'ordre testé.
`appliquer.sql` refuse sinon (`trg_verrou_zz_dates_swend` et
`trg_verrou_un_swend_par_paire` actifs exigés). D'après leurs reçus
(branches `recu/R2-01` et `recu/D-023c-01`), les deux ont été appliqués
(R2-01 le 03/10 : succès ; D-023c-01 le 04/10 : `appliquer` HTTP 201, seule
l'étape `verifier` a échoué sur un droit de lecture de `swend_en_cours`) ;
l'app D-023c est publiée depuis le 04/10.

**App du lot 1 publiée d'abord** (voir « Ordre d'exécution ») : c'est une
précondition de ce paquet. Elle garantit qu'aucune demande d'une personne
sans compte ne peut être réactivée tant que l'app publiée ne propose pas
« Renvoyer le message à … ».

**État relu.** La lecture de la production n'a pas pu être faite le 12/10
(l'endpoint `…/read-only` a répondu « Invalid access token » : identifiant
de l'environnement à renouveler, action humaine). À relire en lecture seule
avant le Go :

```sql
select (select json_object_agg(p.proname, md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')))
          from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('normaliser_nouveau_remplacant', 'etat_cote_titulaire',
             'notifier_demande_remplacement', 'journaliser_demande_remplacement',
             'envoyer_demande_remplacement', 'ajouter_et_demander_remplacement',
             'annuler_demande_remplacement', 'repondre_demande_remplacement',
             'se_desister_du_remplacement')) as md5_fonctions,
       to_regclass('public.imprevus_declares') is null as pas_encore_applique,
       (select count(*) from pg_trigger where tgname in ('trg_verrou_zz_dates_swend',
          'trg_verrou_un_swend_par_paire') and tgenabled = 'O') as r2_et_d023c,  -- 2
       (select json_object_agg(coalesce(demande_statut, 'null'), n)
          from (select demande_statut, count(*) n from public.remplacants group by 1) x) as demandes;
```

Empreintes attendues (corps normalisé ; fonctions des migrations
`gel_a_h.sql`, exécutée en production dans la version sha256 `95bce7ea…`, et
`fil_evenements_et_lectures.sql`) : `ajouter_et_demander_remplacement`
`f05127e4…`, `annuler_demande_remplacement` `a6437d25…`,
`envoyer_demande_remplacement` `1751db53…`, `etat_cote_titulaire`
`9192fd44…`, `journaliser_demande_remplacement` `15532fb3…`,
`normaliser_nouveau_remplacant` `7d96b877…`, `notifier_demande_remplacement`
`c8ecfca8…`, `repondre_demande_remplacement` `17ba2628…`,
`se_desister_du_remplacement` `d96df4ca…` (valeurs complètes dans
`appliquer.sql`).

`sauvegarde.sql` et `appliquer.sql` revérifient tout avant d'écrire et
annulent tout sinon : paquet pas encore appliqué, 9 empreintes identiques,
contrainte des événements d'origine, sauvegarde faite (pour appliquer).

**Tests** (banc QA, 12/10/2026) :
- suite `qa/metier/sql/99f_imprevu_etats_actions.sql` (93 vérifications) ;
  suites existantes réalignées (`10_imprevu`, `60`, `80`, `98`, `99`) ;
- concurrence : 2 nouvelles courses réelles (retour et acceptation
  simultanés ; envoi groupé et acceptation simultanés), 30 essais chacune ;
- Dart : libellés des nouveaux événements, modèle ;
- E2E : `09b_desistement_reouverture` (réactivation), `16_notifications_actions`
  (textes), nouveau `29_renvoyer_message` ;
- régression complète : voir `DECISIONS.md` (D-027) et `PRODUCT_STATUS.md`.

**Répétition** sur une base locale reproduisant la production attendue
avant D-027 (toutes les migrations sauf celle-ci, données fictives : un
Swend en recherche d'un côté et remplacé de l'autre, un Swend sans demande,
un Swend annulé) : `sauvegarde.sql` OK ; `appliquer.sql` OK (2 déclarations,
les 2 côtés du Swend en recherche, rien pour le Swend annulé) ;
`verifier.sql` OK ; seconde exécution d'`appliquer.sql` et de
`sauvegarde.sql` refusée (« déjà appliqué ») ; `rollback.sql` OK (les 9
fonctions retrouvent leur empreinte, droits d'origine) ; `verifier.sql`
refuse ensuite ; second rollback refusé ; réapplication OK ; toutes les
suites SQL sur la base répétée : 973/0 ; rollback après usage réel (16
événements D-027 présents) OK, contrainte élargie conservée.

## Impact attendu

- Immédiat : aucune donnée existante modifiée ; seule la table interne des
  déclarations est remplie. Côté app (lot 1, déjà publiée) : « Renvoyer le
  message à … » apparaît dès qu'une demande d'une personne sans compte est
  réactivée. Autres effets visibles :
  - textes des push de l'imprévu (tutoiement D-027) ;
  - le titulaire n'est plus prévenu de chaque refus, seulement du dernier ;
  - après un désistement, les demandes qui attendaient une réponse
    redeviennent actives (avec push) au lieu de redevenir « Lui demander » ;
  - retirer une personne qui a refusé ne fait plus sortir de l'état
    « cherche » des rappels.
- Appareil qui affiche encore l'app précédente en cache (service worker
  Flutter, le temps d'un rechargement) : la demande réactivée y apparaît
  « En attente » avec « Envoyer le message » ; jamais invisible.
- Durée : une transaction courte (fonctions, 2 tables, 1 colonne avec valeur
  par défaut constante, 2 déclencheurs ; verrou bref sur `remplacants`).

## Vérifications après exécution

`verifier.sql` (lecture seule) ne lève aucune erreur et affiche :
`cotes_en_imprevu` = nombre de côtés `confirme` qui cherchent ou sont
remplacés au moment de l'exécution, `clotures_memorisees = 0`,
`messages_a_renvoyer = 0`, `fonctions_d027 = 8`, `fiches =
fiches_sauvegardees`.

Session de travail, en lecture seule ensuite : jobs pg_cron (`swend-rappels`,
`swend-gel-a-h`, `swend-chat-apres`) toujours `succeeded`.

## Rollback

Quand : régression constatée sur les demandes de remplacement. L'app du
lot 1 fonctionne aussi sans D-027 (testé : sans la colonne
`message_a_renvoyer`, elle ne propose jamais « Renvoyer le message » et
n'appelle pas `marquer_message_renvoye()`) ; remettre l'app précédente n'est
nécessaire qu'en cas de problème de l'app elle-même. Exécuter
`scripts/prod_ecrire.sh D-027-01 <empreinte> --rollback`.

Effet : les 9 fonctions retrouvent leur définition d'origine (contrôlée
contre la sauvegarde : empreinte et droits), `envoyer_demande_remplacement`
retrouve son droit `public` ; déclencheurs, fonctions, tables internes et
colonne `message_a_renvoyer` D-027 supprimés ; contrainte des événements
remise à l'identique s'il n'existe encore aucun événement D-027, sinon
conservée élargie (aucun historique de conversation supprimé ; l'app
précédente affiche un texte vide pour ces événements).

Ne rétablit pas : les demandes déjà réactivées restent en attente, les
demandes closes par un retour restent de simples personnes prévues (états
valides pour l'ancien code) ; les déclarations d'imprévu et la mémoire des
clôtures sont perdues (un désistement retrouve l'ancien comportement).
Refusé si D-027-01 n'est pas appliqué.

## Sauvegardes

`sauvegarde.sql` (étape `sauvegarde`, avant toute modification), dans le
schéma interne `sauvegarde` (aucun accès pour l'app, vérifié) :
- `d027_01_fonctions_20261012` : définition exacte (`pg_get_functiondef`),
  droits et empreinte de chacune des 9 fonctions remplacées, et définition
  de la contrainte `evenements_fil_code_check` ;
- `d027_01_remplacants_20261012` : état des demandes de toutes les fiches
  (identifiants, côté, statut, sélection, retrait, indisponibilité ; ni nom
  ni numéro) et statut du Swend.

`appliquer.sql` prouve, contre cette copie, qu'aucune demande existante n'a
changé.

## Ordre d'exécution (app d'abord, puis base)

Aucune fenêtre où la base peut réactiver la demande d'une personne sans
compte sans que l'app publiée permette de renvoyer le message : l'app du
lot 1 est publiée **avant** la migration. Elle est compatible avec la base
actuelle (sans D-027) : `message_a_renvoyer` absent est lu comme `false`,
rien d'autre ne change à l'écran (scénarios E2E de l'imprévu rejoués avec
cette app sur une base sans D-027 : voir `DECISIONS.md`, D-027).

1. Préalables, déjà faits selon les reçus : R2-01, D-023c-01, app D-023c.
2. **App du lot 1** (niveau 1, Go d'Eliot à part) : build web depuis le
   commit source indiqué dans `DECISIONS.md` (D-027, « Mise en
   production »), `flutter build web --release --base-href /le_pacte/`,
   publication sur `gh-pages` (`ARCHITECTURE.md` §3), puis fast-forward de
   `main`.
3. Vérification de l'app publiée (lecture seule) : `.last_build_id` de
   `gh-pages` = celui de la build de l'étape 2 ; l'app s'ouvre, un Swend et
   « Un imprévu ? » s'affichent normalement. Laisser aux appareils le temps
   de recharger l'app (service worker Flutter), par exemple jusqu'au
   lendemain.
4. Lecture seule des préconditions ci-dessus, puis Go sur ce paquet selon la
   gouvernance en vigueur (`CLAUDE.md`), puis exécution par la porte
   (sauvegarde, appliquer, verifier).
5. `verifier.sql`, puis vérification en lecture seule (jobs pg_cron).
