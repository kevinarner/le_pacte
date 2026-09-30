# Migrations de la base Supabase (production)

Les scripts SQL exécutés **à la main** dans le SQL Editor de Supabase, dans
l'ordre des noms de fichiers. Ils sont versionnés ici pour l'historique et
pour le banc QA (`qa/`), qui les rejoue sur une base locale.

- Ne pas les pousser avec la CLI Supabase : ils ont déjà été appliqués en
  production (jusqu'à `20260927010000_disponibilite_spontanee_et_notifications.sql`,
  exécutée le 27/09 — lot D-008 / D-015).
  `20260927020000_scellage_et_negociation.sql` : exécutée le 27/09 (lot
  D-019 / D-011).
  `20260927030000_reservations_suivi.sql` : exécutée le 27/09 (suivi
  interne des réservations, D-020).
  `20260927040000_rappels_jour_j.sql` : exécutée (confirmée le 28/09 ;
  rappels J-7 / J-3 / J-1 / Jour J et push de double remplacement, D-021).
  `20260928000000_annulation_manuelle.sql` : exécutée le 28/09 (annulation
  manuelle d'un Swend scellé, auteur et date de l'annulation, suppression
  d'un Swend scellé bloquée, D-022).
  `20260929000000_gel_a_h.sql` : **exécutée le 30/09** (gel à l'heure du
  Swend, D-023a). Une première exécution partielle (début du fichier
  seulement) a été complétée par une ré-exécution EN ENTIER de la version du
  commit `d9d064b` (sha256
  `95bce7ea47af6a883900f4574726532570c60be88c4d7b8f1ff3d738eea02eac`,
  idempotente sur tout état partiel : 120 points d'arrêt testés) :
  10 vérifications à true, et contrôle
  `supabase/controles/gel_a_h_controle.sql` (lecture seule) : 7 lignes à
  true. App correspondante déployée le 30/09.
- La planification du gel à H (pg_cron, D-023a) n'est pas une migration :
  `supabase/planification/gel_a_h_pg_cron.sql`. **Active en production
  depuis le 30/09** (job `swend-gel-a-h`, toutes les 5 minutes, exécutions
  vérifiées : `succeeded`).
- La planification des rappels (pg_cron) n'est pas une migration :
  `supabase/planification/rappels_pg_cron.sql`. **Active en production
  depuis le 28/09** (job `swend-rappels`, toutes les 5 minutes, exécutions
  vérifiées : `succeeded`, `1 row`).
- L'Edge Function `supabase/functions/send-notification` (hors migration)
  a été redéployée le 28/09 avec le lien web des rappels
  (`?rappel=<pacte_id>`).
- Tout nouveau changement de schéma = un nouveau fichier ici, daté, testé
  par `qa/run_metier.sh` avant d'être exécuté en production.
- Le schéma antérieur à ces scripts (tables, premières policies, triggers de
  notification...) n'existe pas sous forme de migration : le banc QA en
  utilise une reconstruction, `qa/db/replica/00_schema_initial.sql`.

`20260925020000_telephones_phase1.sql` est la version finale (séparateurs
explicites) : la version exécutée en production était antérieure, la
phase 2 redéfinit de toute façon `normaliser_telephone()`.
