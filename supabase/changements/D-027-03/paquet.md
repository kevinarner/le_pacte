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
   venir », accepter ou refuser une demande. L'heure est lue
   (`clock_timestamp()`) une fois les verrous du Swend et de ses fiches
   obtenus, au moment où l'action peut être validée : une requête partie
   avant H-3 mais qui attend un verrou jusqu'après H-3 est refusée.
   Exemple : Swend du mardi 17 novembre à 19h00 (Paris) → H-3 = 16h00.
2. Dès H-3 inclus, le désistement du remplaçant sélectionné annule le Swend
   immédiatement (motif `echeance_h3`), sans réactiver aucune demande ; le
   titulaire de son côté reçoit « Le Swend est annulé / Kevin ne peut
   finalement plus venir. ».
3. À H-3, toute recherche non résolue (côté en imprévu sans remplaçant
   sélectionné) annule le Swend (motif `echeance_h3`) :
   `appliquer_echeances_h3()`, exécutée **chaque minute** par un nouveau job
   pg_cron `swend-echeance-h3` (créé par ce paquet) et appelée aussi en tête
   du moteur des rappels (`envoyer_rappels_dus()`, job `swend-rappels`
   existant, toutes les 5 minutes, **fréquence inchangée**), donc avant tout
   rappel du Jour J. Le titulaire qui cherchait reçoit « Le Swend est
   annulé / Personne n’a pu prendre ta place à temps. ». Jamais deux
   annulations ni deux push (verrou du Swend, état relu).
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
planification `supabase/planification/echeance_h3_pg_cron.sql` en copie
exacte, assertions ; une transaction), `verifier.sql` (lecture seule),
`rollback.sql` (retire aussi le job).

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
- planification créée : job pg_cron `swend-echeance-h3`, `* * * * *`,
  `select public.appliquer_echeances_h3()` (`cron.schedule`, même rôle et
  même base que `swend-rappels`, vérifié) ; jobs existants inchangés ;
- schéma interne `sauvegarde` : tables `d027_03_fonctions_20261020`,
  `d027_03_pactes_20261020`.

Aucune table, colonne, contrainte, politique RLS, déclencheur ni Edge
Function modifiés : le motif `echeance_h3` est déjà admis par la contrainte
`pactes_annule_motif_valeurs` (D-027-02).

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
banc) ; aucune fonction de l'échéance ; pg_cron 1.6.4, `cron.schedule(text,
text, text)` et `cron.unschedule(bigint)` présents ; jobs `swend-chat-apres`
(`* * * * *`), `swend-gel-a-h` et `swend-rappels` (`*/5 * * * *`), actifs,
rôle `postgres`, base `postgres` ; aucun job `swend-echeance-h3` ; 0 côté
en imprévu.

Empreintes attendues (corps normalisé) : `ajouter_et_demander_remplacement`
`d1e31b12…`, `annuler_demande_remplacement` `0b313996…`,
`envoyer_demandes_remplacement` `2b2bb344…`, `envoyer_rappels_dus`
`fa9ffe25…`, `je_peux_finalement_venir` `9631961e…`,
`repondre_demande_remplacement` `902fd120…`, `se_desister_du_remplacement`
`ce38814e…` (valeurs complètes dans `appliquer.sql`).

`sauvegarde.sql` et `appliquer.sql` revérifient tout avant d'écrire et
annulent tout sinon : D-027-02 appliqué, D-027-03 pas encore appliqué,
7 empreintes identiques, job `swend-rappels` inchangé, **aucun job
`swend-echeance-h3`** et `cron.schedule` disponible, **aucun Swend en
imprévu dont l'heure tombe dans les 3 h 10 qui viennent** (sinon le premier
passage du job l'annulerait aussitôt : arbitrage nécessaire), sauvegarde
faite (pour appliquer). Après la création du job, `appliquer.sql` vérifie
qu'il est actif, chaque minute, avec la commande attendue, sous le même rôle
et sur la même base que `swend-rappels`, et que `swend-rappels` est
inchangé.

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
       (select count(*) from cron.job where jobname = 'swend-echeance-h3') as job_echeance,        -- 0
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
concurrence (`qa/metier/concurrence.sh`, connexions séparées) :
acceptation tenue ouverte juste avant H-3 pendant l'échéance (Swend
maintenu, course 6) ; **acceptation demandée avant H-3 mais en attente du
verrou du Swend jusqu'après H-3 → refusée `echeance_h3`, puis Swend annulé**
(course 6 ter ; la même course échoue si l'heure est lue au début de la
transaction : preuve `qa/preuves/2026-10-20_D-027-03_mutation_6ter.txt`) ;
10 courses acceptation / échéance de part et d'autre de H-3 (5 acceptées,
5 annulées, toujours cohérentes, course 7) ; 3 échéances simultanées
(course 7 bis) ; job de la minute et moteur des rappels au même moment
(une seule annulation, une push par personne, aucun rappel, course 7 ter) ;
métier complet, Dart et E2E : voir `qa/preuves/README.md` (D-027-03).

**Répétition** sur une base locale reproduisant la production attendue
(toutes les migrations sauf celle-ci, données fictives ; pg_cron n'existe
pas sur le banc : table `cron.job` simulée avec les 3 jobs de production,
rôle et base, et fonctions `cron.schedule(text, text, text)` /
`cron.unschedule(bigint)` aux signatures de pg_cron 1.6 ; journal et
scripts dans `qa/preuves/2026-10-20_D-027-03_repetition*`) — 9 refus
attendus, tous obtenus :
- job `swend-echeance-h3` déjà présent : `sauvegarde.sql` refusé ; job
  `swend-rappels` inactif : refusé ; Swend en imprévu dont l'heure tombe
  dans les 3 h 10 : refusé ; `appliquer.sql` sans sauvegarde refusé ;
  `swend-rappels` sous un autre rôle : `appliquer.sql` refusé par
  l'assertion finale et **tout annulé** (0 fonction de l'échéance, 0 job) ;
- `sauvegarde.sql`, `appliquer.sql`, `verifier.sql` OK (jobs ensuite :
  `swend-chat-apres`, `swend-echeance-h3` chaque minute, `swend-gel-a-h`,
  `swend-rappels` toutes les 5 minutes ; 0 annulation `echeance_h3`,
  3 Swends = 3 sauvegardés, 0 changé) ; seconde exécution de
  `appliquer.sql` et de `sauvegarde.sql` refusée (« déjà appliqué ») ;
- `rollback.sql` immédiat OK (7/7 fonctions à l'empreinte et aux droits de
  la sauvegarde, 2 fonctions de l'échéance supprimées, job
  `swend-echeance-h3` retiré, les 3 autres inchangés), `verifier.sql`
  refuse ensuite, second rollback refusé, réapplication OK ;
- usage réel simulé : acceptation à H-3 passé refusée (`echeance_h3`) ;
  **commande du job telle qu'enregistrée dans `cron.job` exécutée** : Swend
  en recherche annulé (`echeance_h3`), demande close ; moteur des rappels
  ensuite : 0 rappel ; une seule push par personne (« On a besoin de toi »
  initiale, puis « Personne n’a pu prendre ta place à temps. », « Eliot ne
  pourra finalement pas être là. », « Tu n’as plus besoin de répondre. ») ;
  désistement après H-3 : Swend annulé ; Swend normal maintenu ;
  `rollback.sql` après usage OK (les 2 annulations restent, job retiré),
  ancien code de nouveau actif (demande à H-1 acceptée) ;
- toutes les suites SQL sur une base où l'échéance vient du paquet :
  1116/0 (`qa/preuves/2026-10-20_D-027-03_suites_base_paquet.txt`).

## Impact attendu

- Immédiat : aucune donnée modifiée (la précondition exclut tout Swend en
  imprévu proche de H-3). Dès l'exécution : actions de recherche et de
  réponse refusées à partir de 3 heures avant un Swend ; désistement
  tardif = annulation.
- **Blocage strict et délai de traitement sont distincts.** Le blocage des
  actions vaut dès H-3 pile, par la base, quel que soit l'état des jobs.
  L'annulation d'une recherche non résolue, elle, attend le passage d'un
  job : normalement dans la minute qui suit H-3 (`swend-echeance-h3`) ; si
  seul ce job est en défaut, au passage suivant de `swend-rappels` (au plus
  5 minutes). **Aucun délai n'est garanti si les jobs échouent** ou si
  pg_cron s'arrête : l'annulation attend la prochaine exécution réussie ;
  entre-temps le Swend reste « confirmé », sans recherche possible, sans
  annulation ni push ; après H, l'échéance ne s'applique plus (gel à H,
  D-023a ; arbitrage manuel).
- Charge : une requête de plus par minute (Swends `confirme` à venir, dont
  H-3 est atteint, avec un imprévu déclaré) ; aucun rappel supplémentaire.
- Durée : une transaction courte (9 fonctions, 1 job).

## Vérifications après exécution

`verifier.sql` (lecture seule) ne lève aucune erreur (fonctions et
empreintes, appel en tête du moteur des rappels, rien d'exposé à l'app,
`swend-rappels` inchangé, `swend-echeance-h3` actif chaque minute avec la
commande attendue, même rôle et même base) et affiche :
`annulations_echeance_h3 = 0`, `swends = swends_sauvegardes`
(hors Swends créés entre-temps), `swends_changes = 0`.

**Ce que seul pg_cron réel peut montrer** (non reproductible sur le banc),
à relire en lecture seule dans la session de travail, quelques minutes après
l'exécution, sans déclencher aucun job à la main :

```sql
select j.jobname, count(*) as executions, count(*) filter (where d.status = 'succeeded') as reussies,
       max(d.start_time) as derniere, max(d.end_time - d.start_time) as duree_max
  from cron.job j join cron.job_run_details d on d.jobid = j.jobid
 where d.start_time > '<fin d'exécution du paquet>'
 group by j.jobname order by j.jobname;
```

Attendu : `swend-echeance-h3` environ une exécution par minute, toutes
`succeeded`, durée courte ; `swend-rappels`, `swend-gel-a-h` et
`swend-chat-apres` toujours `succeeded`. Une exécution `failed` →
`return_message`, puis rollback si nécessaire. Le délai réel d'une
annulation à H-3 ne sera observé qu'au premier cas réel (test humain).
`cron.unschedule` n'est exercé en production que par un rollback.

## Rollback

Quand : régression constatée sur les demandes, les réponses, le
désistement, les rappels ou une annulation à tort. Exécuter
`scripts/prod_ecrire.sh D-027-03 <empreinte> --rollback`.

Effet : les 7 fonctions retrouvent leur définition de production d'origine
(contrôlée contre la sauvegarde : empreinte et droits) ; le job
`swend-echeance-h3` est retiré (`cron.unschedule`), avant les 2 fonctions
de l'échéance, qui sont supprimées ; `swend-rappels` reste actif (vérifié).
Refusé si D-027-03 n'est pas appliqué.

Ne rétablit pas : les Swends déjà annulés par l'échéance ou par un
désistement tardif restent annulés (annulations réelles, chacun a été
prévenu) ; leur nombre est affiché. L'app publiée avec la règle H-3 garde
ses écrans de H-3 (plus stricts que la base après rollback : elle ne
propose plus de recherche à partir de 3 heures avant le Swend) : sans effet
sur les données.

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
- **app d'abord** : à partir de H-3, l'app ne propose plus de recherche
  (plus stricte que la base) ; mais la confirmation du désistement annonce
  l'annulation alors que l'ancienne base réactive les demandes, et
  l'acceptation reste possible ;
- **base d'abord** (app du lot 3 publiée) : à partir de H-3, les
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
