# Preuves conservées (banc QA local)

Journaux bruts de vérifications ponctuelles qu'on veut pouvoir relire
(les `*.log` et `qa/artifacts/` ne sont pas versionnés). Données fictives
uniquement ; aucune donnée ni aucun identifiant de production.

- `2026-10-15_D-027-02_verrou_paire.txt` : course « annulation et scellement
  Eliot–Kevin simultanés » avec et sans le verrou par paire
  (`qa/metier/preuve_verrou_paire.sh`).
- `2026-10-15_D-027-02_repetition.txt` : répétition du paquet D-027-02 sur une
  base reproduisant la production attendue. Scripts et données utilisés,
  copiés tels quels (chemins locaux de la session d'origine) :
  `…_base_avant_lot2.sh.txt` (toutes les migrations sauf le lot 2),
  `…_prod_deux.sql.txt` (définitions de production de `annuler_swend()` et
  `annuler_si_double_absence()`, relues en lecture seule le 15/10),
  `…_donnees_rep.sql.txt`, `…_usage_rep.sql.txt`, `…_repetition.sh.txt`.
- `2026-10-15_D-027-02_suites_base_paquet.txt` : suites SQL métier sur une
  base où le lot 2 vient du paquet (et non de la migration).
