#!/bin/bash
# Preuve que la course 18 de concurrence.sh (annulation et scellement
# Eliot–Kevin simultanés) détecte l'absence du verrou par paire (D-027 lot 2).
# Exécute la même course AVEC le verrou, puis SANS (cle_paire_fil_imprevu()
# remplacée le temps du test par une clé aléatoire : plus aucun conflit),
# puis restaure la fonction d'origine et vérifie son empreinte.
#   qa/metier/preuve_verrou_paire.sh <base> [essais par ordre, défaut 5]
# À lancer sur une base où les suites SQL ont tourné (outils g_*, nv_*, ac_*).
# Sortie : une ligne par essai, puis le bilan par variante et par ordre.
. "$(dirname "$0")/../lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1
BASE="$1"; N="${2:-5}"
[ -n "$BASE" ] || { qa_erreur "usage : preuve_verrou_paire.sh <base> [essais]"; exit 1; }
P() { qa_psql "$BASE" -tA "$@"; }
E=00000000-0000-0000-0000-00000000000e
K=00000000-0000-0000-0000-00000000000a
MD5="select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc where oid = 'public.cle_paire_fil_imprevu(uuid, uuid)'::regprocedure"
ORIGINE_MD5=$(P -c "$MD5")
ORIGINE_DEF=$(mktemp); P -c "select pg_get_functiondef('public.cle_paire_fil_imprevu(uuid, uuid)'::regprocedure)" > "$ORIGINE_DEF"
restaurer() {
  qa_psql "$BASE" -q -v ON_ERROR_STOP=1 -f "$ORIGINE_DEF" >/dev/null
  [ "$(P -c "$MD5")" = "$ORIGINE_MD5" ] && echo "fonction d'origine restaurée (empreinte $ORIGINE_MD5)" \
    || { echo "ERREUR : fonction non restaurée" >&2; exit 2; }
  rm -f "$ORIGINE_DEF"
}
trap restaurer EXIT

ordre_nom() { case $1 in 0) echo "scellement tenu ouvert" ;; 1) echo "annulation tenue ouverte" ;; 2) echo "lancés ensemble" ;; esac; }
course() { # variante → lignes « variante|essai|ordre|état|verdict »
  local v="$1" i m p k s2 etat
  for ((i = 1; i <= 3 * N; i++)); do
    m=$((i % 3))
    read p k s2 <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '2 days') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select g_rpc('$E', 'envoyer_demande_remplacement', :'k') \gset
select nv_swend('$E', '$K', now() + interval '$((200 + i)) days', 'enAttenteChoixDateDestinataire') as s2 \gset
select :'p' || ' ' || :'k' || ' ' || :'s2';
SQL
)"
    case $m in
      0) ( P -c "begin; select nv_sceller('$s2'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
         sleep 0.4; P -c "begin; set local role authenticated; select set_config('request.jwt.claim.sub', '$E', true); select annuler_swend('$p'); commit;" >/dev/null 2>&1; wait ;;
      1) ( P -c "begin; set local role authenticated; select set_config('request.jwt.claim.sub', '$E', true); select annuler_swend('$p'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
         sleep 0.4; P -c "select nv_sceller('$s2')" >/dev/null 2>&1; wait ;;
      2) P -c "begin; set local role authenticated; select set_config('request.jwt.claim.sub', '$E', true); select annuler_swend('$p'); commit;" >/dev/null 2>&1 &
         P -c "select nv_sceller('$s2')" >/dev/null 2>&1 & wait ;;
    esac
    etat=$(P -c "select (select statut from pactes where id = '$p') || '|scelle=' || ((select scelle_le from pactes where id = '$s2') is not null) || '|ferme=' || ac_ferme('$k') || '|fil_ferme=' || (select count(*) from evenements_fil where remplacant_id = '$k' and code = 'fil_ferme')")
    if [ "$etat" = "annule|scelle=true|ferme=true|fil_ferme=1" ]; then echo "$v|$i|$(ordre_nom $m)|$etat|réussi"; else echo "$v|$i|$(ordre_nom $m)|$etat|ÉCHEC"; fi
  done
}

echo "base $BASE, $N essais par ordre ($((3 * N)) par variante), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
RES=$(mktemp)
course "avec verrou" | tee -a "$RES"
P -q -c "create or replace function public.cle_paire_fil_imprevu(p_a uuid, p_b uuid) returns bigint language sql volatile set search_path = public as \$\$ select (random() * 1e15)::bigint \$\$"
course "sans verrou" | tee -a "$RES"
echo "== bilan"
awk -F'|' '{ t[$1]++; if ($NF == "réussi") r[$1]++; o[$1 " / " $3]++; if ($NF == "réussi") ro[$1 " / " $3]++ }
  END { for (k in t) printf "%s : %d réussis, %d échecs sur %d\n", k, r[k], t[k] - r[k], t[k];
        for (k in o) printf "  %s : %d réussis, %d échecs\n", k, ro[k], o[k] - ro[k] }' "$RES" | sort
rm -f "$RES"
