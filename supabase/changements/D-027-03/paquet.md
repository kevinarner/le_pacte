# D-027-03

Niveau : 2 — préparé le 20/10/2026. Empreinte : donnée par
`scripts/paquet_controler.sh D-027-03 --avant-go`. Go d'Eliot.
**Pas de validation à ce jour.** À exécuter dans la même fenêtre que la
publication de l'app correspondante (voir « Ordre d'exécution »).

## Objectif

Mettre en production la **règle H-3 ferme** de D-027 (décision d'Eliot du
20/10/2026, `DECISIONS.md`, D-027, point 10 révisé) : 3 heures avant l'heure
du Swend, un imprévu doit être résolu.

1. Dès H-3 inclus, la base refuse toute recherche et toute réponse
   (`echeance_h3`) : envoyer une ou plusieurs demandes, ajouter une personne
   et lui demander, annuler une demande (ancienne app), « Je peux finalement
   venir », accepter ou refuser une demande.
2. Dès H-3 inclus, le désistement du remplaçant sélectionné annule le Swend
   immédiatement (motif `echeance_h3`), sans réactiver aucune demande ; le
   titulaire de son côté reçoit « Le Swend est annulé / Kevin ne peut
   finalement plus venir. ».
3. À H-3, toute recherche non résolue (côté en imprévu sans remplaçant
   sélectionné) annule le Swend (motif `echeance_h3`) :
   `appliquer_echeances_h3()`, appelée en tête du moteur des rappels
   (`envoyer_rappels_dus()`, job `swend-rappels` existant, toutes les
   5 minutes), donc avant tout rappel du Jour J. Le titulaire qui cherchait
   reçoit « Le Swend est annulé / Personne n’a pu prendre ta place à
   temps. ».
4. Un nouvel imprévu d'un titulaire dès H-3 passe par `annuler_swend()`,
   inchangée (motif `titulaire`).

Annulation, notifications d'annulation (« X ne pourra finalement pas être
là. », « Tu n’as plus besoin de répondre. », « Tu n’auras finalement pas
besoin de prendre la place de … »), chat d'annulation et conversations
conservées : `appliquer_annulation()` du lot 2, **inchangée**. Aucune
notification au restaurant (le suivi interne `reservations_a_suivre`
affiche « Annuler la réservation au restaurant » dès l'annulation d'un Swend
réservé). Un Swend dont les participants attendus restent disponibles est
maintenu.

## Fichiers concernés

Artefacts : `sauvegarde.sql` (sauvegarde ciblée, une transaction),
`appliquer.sql` (préconditions, migration
`supabase/migrations/20261020000000_echeance_h3.sql` en copie exacte,
assertions ; une transaction), `verifier.sql` (lecture seule),
`rollback.sql`.

Objets de production :
- créés : `echeance_h3_atteinte(timestamptz, timestamptz)` et
  `appliquer_echeances_h3(timestamptz)` (internes, non exécutables par
  l'app) ;
- remplacés (même signature, mêmes droits) :
  `envoyer_demandes_remplacement(uuid[])`,
  `ajouter_et_demander_remplacement(uuid, text, text, text, text)`,
  `annuler_demande_remplacement(uuid)`, `je_peux_finalement_venir(uuid)`,
  `repondre_demande_remplacement(uuid, boolean)`,
  `se_desister_du_remplacement(uuid)`, `envoyer_rappels_dus(timestamptz)` ;
- schéma interne `sauvegarde` : tables `d027_03_fonctions_20261020`,
  `d027_03_pactes_20261020`.

Aucune table, colonne, contrainte, politique RLS, déclencheur, Edge
Function ni planification modifiés : le motif `echeance_h3` est déjà admis
par la contrainte `pactes_annule_motif_valeurs` (D-027-02) et l'échéance
passe par le job `swend-rappels` existant.

Niveau 2 : la règle annule automatiquement des Swends réels et change le
comportement d'actions réelles (demander, répondre, se désister) et des
notifications. Sauvegarde ciblée, rollback, tests et préconditions
obligatoires.

## Préconditions

**Ordre.** Après D-027-02 (appliqué le 20/10/2026) ; `appliquer.sql`
refuse sinon.

**État relu en lecture seule le 20/10/2026** (endpoint `…/read-only`) :
D-027-02 appliqué, motif `echeance_h3` admis ; les 7 fonctions remplacées
identiques aux migrations du dépôt (empreintes ci-dessous, identiques au
banc) ; aucune fonction de l'échéance ; job `swend-rappels` actif,
`*/5 * * * *`, `select public.envoyer_rappels_dus()` ; 0 côté en imprévu.

Empreintes attendues (corps normalisé) : `ajouter_et_demander_remplacement`
`d1e31b12…`, `annuler_demande_remplacement` `0b313996…`,
`envoyer_demandes_remplacement` `2b2bb344…`, `envoyer_rappels_dus`
`fa9ffe25…`, `je_peux_finalement_venir` `9631961e…`,
`repondre_demande_remplacement` `902fd120…`, `se_desister_du_remplacement`
`ce38814e…` (valeurs complètes dans `appliquer.sql`).

`sauvegarde.sql` et `appliquer.sql` revérifient tout avant d'écrire et
annulent tout sinon : D-027-02 appliqué, D-027-03 pas encore appliqué,
7 empreintes identiques, job `swend-rappels` inchangé, **aucun Swend en
imprévu à moins de 3 h 10 de son heure** (sinon le premier passage du
moteur l'annulerait aussitôt : arbitrage nécessaire), sauvegarde faite
(pour appliquer).

À relire juste avant le Go (lecture seule) :

```sql
select (select json_object_agg(p.proname, md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')))
          from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('ajouter_et_demander_remplacement', 'annuler_demande_remplacement',
             'envoyer_demandes_remplacement', 'envoyer_rappels_dus', 'je_peux_finalement_venir',
             'repondre_demande_remplacement', 'se_desister_du_remplacement')) as md5_fonctions,
       to_regclass('public.fils_imprevu_fermes') is not null as d027_02,
       to_regprocedure('public.appliquer_echeances_h3(timestamptz)') is null as pas_encore_applique,
       (select count(*) from cron.job where jobname = 'swend-rappels' and active) as job_rappels,  -- 1
       (select count(*) from public.pactes p where p.statut = 'confirme' and p.date_retenue > now()
          and p.date_retenue <= now() + interval '3 hours 10 minutes'
          and exists (select 1 from public.imprevus_declares d where d.pacte_id = p.id)) as imprevus_sous_3h; -- 0
```

**Tests** (banc QA, 20/10/2026) : suite
`qa/metier/sql/99h_echeance_h3.sql` (51 vérifications : juste avant H-3,
à H-3 exactement, après H-3, désistement à H-3 et après, deux côtés en
recherche, autre côté remplacé, rappels, après H, idempotence,
confidentialité, chats, conversations, D-024, suivi de réservation) ;
suites `98` et `99` réalignées (recherche jusqu'à H abandonnée) ;
concurrence : acceptation tenue ouverte juste avant H-3 pendant
l'échéance (Swend maintenu), 10 courses acceptation / échéance de part et
d'autre de H-3 (5 acceptées, 5 annulées, toujours cohérentes), 3 échéances
simultanées (une seule annulation, une push par personne) ; métier complet
1869/0 ; E2E `32_echeance_h3` sur les deux bases.

**Répétition** sur une base locale reproduisant la production attendue
(toutes les migrations sauf celle-ci, table `cron.job` simulée avec les
3 jobs de production — pg_cron n'existe pas sur le banc —, données
fictives ; journal et scripts dans
`qa/preuves/2026-10-20_D-027-03_repetition*`) :
- job `swend-rappels` inactif : `sauvegarde.sql` refusé ; Swend en imprévu
  à moins de 3 h : refusé ; `appliquer.sql` sans sauvegarde refusé ;
- `sauvegarde.sql`, `appliquer.sql`, `verifier.sql` OK (0 annulation
  `echeance_h3`, 3 Swends = 3 sauvegardés, 0 changé) ; seconde exécution
  refusée (« déjà appliqué ») ;
- `rollback.sql` immédiat OK (7/7 fonctions à l'empreinte et aux droits de
  la sauvegarde, 2 fonctions de l'échéance supprimées), `verifier.sql`
  refuse ensuite, second rollback refusé, réapplication OK ;
- usage réel simulé : acceptation à H-3 passé refusée (`echeance_h3`) ;
  moteur des rappels : Swend en recherche annulé (`echeance_h3`), demande
  close, aucun rappel ; désistement après H-3 : Swend annulé ; Swend normal
  maintenu ; push exactes ; `rollback.sql` après usage OK (les 2
  annulations restent), ancien code de nouveau actif (demande à H-1
  acceptée) ;
- toutes les suites SQL sur une base où l'échéance vient du paquet :
  1116/0 (`qa/preuves/2026-10-20_D-027-03_suites_base_paquet.txt`).

## Impact attendu

- Immédiat : aucune donnée modifiée. Dès l'exécution : actions de
  recherche et de réponse refusées à moins de 3 heures d'un Swend ;
  désistement tardif = annulation ; au prochain passage du job
  `swend-rappels` (≤ 5 minutes), annulation des Swends dont un côté
  cherche encore à H-3 (aucun le 20/10). Après H-3, l'annulation d'une
  recherche non résolue intervient au plus 5 minutes après H-3 (passage
  du job) ; les actions, elles, sont refusées dès H-3 pile.
- Durée : une transaction courte (9 fonctions).

## Vérifications après exécution

`verifier.sql` (lecture seule) ne lève aucune erreur et affiche :
`annulations_echeance_h3 = 0`, `swends = swends_sauvegardes`
(hors Swends créés entre-temps), `swends_changes = 0`.

Session de travail, en lecture seule ensuite : jobs pg_cron
(`swend-rappels`, `swend-gel-a-h`, `swend-chat-apres`) toujours
`succeeded`.

## Rollback

Quand : régression constatée sur les demandes, les réponses, le
désistement, les rappels ou une annulation à tort. Exécuter
`scripts/prod_ecrire.sh D-027-03 <empreinte> --rollback`.

Effet : les 7 fonctions retrouvent leur définition de production d'origine
(contrôlée contre la sauvegarde : empreinte et droits) ; les 2 fonctions de
l'échéance sont supprimées. Refusé si D-027-03 n'est pas appliqué.

Ne rétablit pas : les Swends déjà annulés par l'échéance ou par un
désistement tardif restent annulés (annulations réelles, chacun a été
prévenu) ; leur nombre est affiché. L'app publiée avec la règle H-3 garde
ses écrans de H-3 (plus stricts que la base après rollback : elle ne
propose plus de recherche à moins de 3 heures) : sans effet sur les
données.

## Sauvegardes

`sauvegarde.sql` (étape `sauvegarde`, avant toute modification), dans le
schéma interne `sauvegarde` (aucun accès pour l'app, vérifié) :
- `d027_03_fonctions_20261020` : définition exacte (`pg_get_functiondef`),
  droits et empreinte des 7 fonctions remplacées ;
- `d027_03_pactes_20261020` : statut, date retenue, auteur, date et motif
  d'annulation de tous les Swends (identifiants et dates seulement).

`appliquer.sql` prouve, contre cette copie, qu'aucun Swend n'a changé.

## Ordre d'exécution (base et app dans la même fenêtre)

L'app avec les écrans de H-3 fonctionne sur les deux bases (E2E `32` sur la
base actuelle et sur la base avec D-027-03), mais chaque ordre laisse une
courte fenêtre où l'écran et la base ne disent pas la même chose, et
seulement pour un Swend qui se trouve entre H-3 et H pendant cette fenêtre :
- **app d'abord** : à moins de 3 heures, l'app ne propose plus de recherche
  (plus stricte que la base) ; mais la confirmation du désistement annonce
  l'annulation alors que l'ancienne base réactive les demandes, et
  l'acceptation reste possible ;
- **base d'abord** (app du lot 3 publiée) : à moins de 3 heures, les
  actions de recherche échouent avec un message générique (« Impossible
  pour le moment. Réessaie. ») et la confirmation du désistement annonce une
  recherche alors que la base annule le Swend.

Procédure recommandée : fenêtre choisie quand **aucun Swend scellé n'a son
heure dans les 3 heures qui suivent** (relu en lecture seule juste avant) ;
(1) Go d'Eliot pour D-027-03, exécution par la porte ; (2) dans la foulée,
Go d'Eliot pour la publication de l'app (niveau 1) ; (3) vérifications en
lecture seule et rechargement des apps. Hors de ce cas, la transition est
sans effet visible. Aucune mesure d'adoption ni rechargement automatique
(décisions du 15/10) : une session ancienne restée ouverte n'affiche les
écrans de H-3 qu'après rechargement ; la base reste seule juge.
