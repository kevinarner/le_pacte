#!/bin/bash
# Parité de schéma banc QA ↔ production (R2) : colonnes du schéma public.
#   qa/metier/parite_schema.sh <base>     (base neuve : réplique + migrations)
# - Type : identique pour toute colonne présente des deux côtés, sans
#   exception possible (un écart de type a masqué le bug unnest(jsonb) de
#   D-025 : dates_proposees en timestamptz[] dans la réplique, jsonb en
#   production).
# - Autres écarts (nullabilité, table ou colonne absente d'un côté) : admis
#   seulement s'ils figurent dans qa/db/parite/ecarts_admis.tsv. Tout nouvel
#   écart échoue.
# Instantanés de production : qa/db/parite/colonnes_production.tsv et
# declencheurs_production.tsv, obtenus en lecture seule avec colonnes.sql et
# declencheurs.sql (endpoint …/read-only), à rafraîchir après chaque
# changement de production.
. "$(dirname "$0")/../lib/commun.sh"
BASE="$1"; P="$QA_ROOT/db/parite"
[ -n "$BASE" ] || { qa_erreur "usage : parite_schema.sh <base>"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
qa_psql "$BASE" -tA -f "$P/colonnes.sql" | sed '/^$/d' | sort > "$T/qa"
sed '/^$/d' "$P/colonnes_production.tsv" | sort > "$T/prod"
KO=0
# 1. Types : colonnes présentes des deux côtés.
join -t $'\t' <(awk -F'\t' '{print $1"."$2"\t"$3}' "$T/prod" | sort) \
              <(awk -F'\t' '{print $1"."$2"\t"$3}' "$T/qa" | sort) \
  | awk -F'\t' '$2 != $3' > "$T/types"
if [ -s "$T/types" ]; then
  while IFS=$'\t' read -r col tp tq; do
    echo "FAIL — [parite_schema] type de $col : production $tp, banc QA $tq"; KO=1
  done < "$T/types"
else
  echo "PASS — [parite_schema] types identiques pour les $(join -t $'\t' <(cut -f1,2 "$T/prod" | tr '\t' . | sort) <(cut -f1,2 "$T/qa" | tr '\t' . | sort) | wc -l) colonnes communes"
fi
# 2. Autres écarts : exactement ceux de la liste admise.
{ comm -23 "$T/prod" "$T/qa" | sed 's/^/production\t/'; comm -13 "$T/prod" "$T/qa" | sed 's/^/qa\t/'; } | sort > "$T/ecarts"
grep -v '^#' "$P/ecarts_admis.tsv" | sed '/^$/d' | sort > "$T/admis"
if comm -23 "$T/ecarts" "$T/admis" | grep -q .; then
  comm -23 "$T/ecarts" "$T/admis" | while IFS= read -r l; do echo "FAIL — [parite_schema] écart non admis : $(tr '\t' ' ' <<<"$l")"; done; KO=1
else
  echo "PASS — [parite_schema] aucun écart hors de la liste admise ($(wc -l < "$T/admis") écarts connus)"
fi
if comm -13 "$T/ecarts" "$T/admis" | grep -q .; then
  comm -13 "$T/ecarts" "$T/admis" | while IFS= read -r l; do echo "FAIL — [parite_schema] écart admis qui n'existe plus (retirer de la liste) : $(tr '\t' ' ' <<<"$l")"; done; KO=1
fi
# 3. Déclencheurs (nom et état actif / désactivé) : exactement les écarts de
#    qa/db/parite/declencheurs_admis.tsv (un déclencheur désactivé en
#    production, D-025, n'avait été vu par aucun test).
qa_psql "$BASE" -tA -f "$P/declencheurs.sql" | sed '/^$/d' | sort > "$T/qa_d"
sed '/^$/d' "$P/declencheurs_production.tsv" | sort > "$T/prod_d"
{ comm -23 "$T/prod_d" "$T/qa_d" | sed 's/^/production\t/'; comm -13 "$T/prod_d" "$T/qa_d" | sed 's/^/qa\t/'; } | sort > "$T/ecarts_d"
grep -v '^#' "$P/declencheurs_admis.tsv" | sed '/^$/d' | sort > "$T/admis_d"
if comm -3 "$T/ecarts_d" "$T/admis_d" | grep -q .; then
  comm -23 "$T/ecarts_d" "$T/admis_d" | while IFS= read -r l; do echo "FAIL — [parite_schema] déclencheur : écart non admis : $(tr '\t' ' ' <<<"$l")"; done
  comm -13 "$T/ecarts_d" "$T/admis_d" | while IFS= read -r l; do echo "FAIL — [parite_schema] déclencheur : écart admis qui n'existe plus (retirer de la liste) : $(tr '\t' ' ' <<<"$l")"; done
  KO=1
else
  echo "PASS — [parite_schema] déclencheurs et leur état : aucun écart hors de la liste admise ($(wc -l < "$T/admis_d") écarts connus)"
fi
exit "$KO"
