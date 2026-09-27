# Migrations de la base Supabase (production)

Les scripts SQL exécutés **à la main** dans le SQL Editor de Supabase, dans
l'ordre des noms de fichiers. Ils sont versionnés ici pour l'historique et
pour le banc QA (`qa/`), qui les rejoue sur une base locale.

- Ne pas les pousser avec la CLI Supabase : ils ont déjà été appliqués en
  production (jusqu'à `20260927010000_disponibilite_spontanee_et_notifications.sql`,
  exécutée le 27/09 — lot D-008 / D-015).
- Tout nouveau changement de schéma = un nouveau fichier ici, daté, testé
  par `qa/run_metier.sh` avant d'être exécuté en production.
- Le schéma antérieur à ces scripts (tables, premières policies, triggers de
  notification...) n'existe pas sous forme de migration : le banc QA en
  utilise une reconstruction, `qa/db/replica/00_schema_initial.sql`.

`20260925020000_telephones_phase1.sql` est la version finale (séparateurs
explicites) : la version exécutée en production était antérieure, la
phase 2 redéfinit de toute façon `normaliser_telephone()`.
