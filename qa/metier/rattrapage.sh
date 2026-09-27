#!/bin/bash
# Migration téléphone phase 2 sur des données "sales" (doublons, formats
# mélangés) : arrêt net sans rien modifier tant que les doublons existent,
# puis rattrapage des seuls liens vides une fois résolus.
. "$(dirname "$0")/../lib/commun.sh"
BASE="${QA_DB_METIER}_rattrapage"; M="$REPO_ROOT/supabase/migrations"
P() { qa_psql "$BASE" "$@"; }
resultat() { if [ "$2" = "1" ]; then echo "PASS — [rattrapage] $1"; else echo "FAIL — [rattrapage] $1 — $3"; fi; }

qa_psql postgres -c "drop database if exists $BASE" 2>/dev/null; qa_psql postgres -c "create database $BASE" || exit 1
for f in "$QA_ROOT/db/replica/00_schema_initial.sql" "$M"/*_supprimer_pacte.sql "$M"/*_un_imprevu.sql "$M"/*_garde_fou_double_remplacement.sql "$M"/*_un_imprevu_v2.sql; do
  P -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "FAIL — [rattrapage] préparation : $(basename "$f")"; exit 0; }
done
P -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
insert into restaurants (id, nom) values ('00000000-0000-0000-0000-0000000000aa', 'R');
insert into profiles (id, prenom, nom, telephone) values
 ('00000000-0000-0000-0000-00000000000e','Eliot','E','0601020304'),
 ('00000000-0000-0000-0000-00000000000d','David','D','+33 6 02 03 04 05'),
 ('00000000-0000-0000-0000-00000000000a','Kevin','Arner','0670419277'),
 ('00000000-0000-0000-0000-0000000000a2','Kevin','Doublon','+33 6 70 41 92 77'),
 ('00000000-0000-0000-0000-00000000000f','Zoe','Reunion','0692 12 34 56');
insert into pactes (id, statut, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone) values
 ('10000000-0000-0000-0000-000000000001','confirme','00000000-0000-0000-0000-00000000000e','Eliot E','00000000-0000-0000-0000-00000000000d','David D','0602030405'),
 ('10000000-0000-0000-0000-000000000002','enAttenteChoixDateDestinataire','00000000-0000-0000-0000-00000000000e','Eliot E',null,'Zoé','+262 692 12 34 56'),
 ('10000000-0000-0000-0000-000000000003','enAttenteReponse','00000000-0000-0000-0000-00000000000e','Eliot E',null,'Moi-même','06 01 02 03 04');
alter table remplacants disable trigger trg_normaliser_nouveau_remplacant;
insert into remplacants (id, pacte_id, cote, prenom, nom, telephone, email, profil_id, demande_statut) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','initiateur','Kevin','Arner','06 70 41 92 77','',null,null),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','initiateur','Kevin','bis','0670419277','','00000000-0000-0000-0000-00000000000a','envoyee'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','destinataire','Kevin','Arner','+33670419277','',null,null),
 ('20000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','initiateur','t','t','0000','',null,null),
 ('20000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','initiateur','Zoé','Z','07 11 22 33 44','','00000000-0000-0000-0000-00000000000f',null),
 ('20000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001','initiateur','David','D','06 02 03 04 05','',null,null);
alter table remplacants enable trigger trg_normaliser_nouveau_remplacant;
SQL
P -v ON_ERROR_STOP=1 -f "$M"/*_telephones_phase1.sql >/dev/null 2>&1 || echo "FAIL — [rattrapage] phase 1"
etat() { P -tA -c "select string_agg(x, ';' order by x) from (select id::text || '=' || coalesce(profil_id::text, '-') as x from remplacants union all select id::text || '=' || coalesce(destinataire_id::text, '-') from pactes) s"; }
lien() { P -tA -c "select coalesce(right(profil_id::text, 2), '-') from remplacants where id = '$1'"; }
avant="$(etat)"
sortie="$(P -v ON_ERROR_STOP=1 -f "$M"/*_telephones_phase2.sql 2>&1)"
resultat "doublons présents : la phase 2 s'arrête" "$(echo "$sortie" | grep -q 'partagé(s) par plusieurs comptes' && echo 1)" "$(echo "$sortie" | grep ERROR | head -1)"
resultat "doublons présents : aucune donnée modifiée" "$([ "$(etat)" = "$avant" ] && echo 1)"
resultat "doublons présents : index canonique non créé" "$([ "$(P -tA -c "select to_regclass('profiles_telephone_e164_unique') is null")" = t ] && echo 1)"
P -c "delete from remplacants where id = '20000000-0000-0000-0000-000000000002'; delete from profiles where id = '00000000-0000-0000-0000-0000000000a2';" >/dev/null
sortie="$(P -v ON_ERROR_STOP=1 -f "$M"/*_telephones_phase2.sql 2>&1)"
resultat "après résolution : la phase 2 passe" "$(echo "$sortie" | grep -q ERROR || echo 1)" "$(echo "$sortie" | grep ERROR | head -1)"
resultat "rattrapage : fiches de Kevin (formats différents) liées à son compte" "$([ "$(lien 20000000-0000-0000-0000-000000000001)" = 0a ] && [ "$(lien 20000000-0000-0000-0000-000000000003)" = 0a ] && echo 1)"
resultat "rattrapage : le destinataire (David) n'est jamais lié comme personne de confiance" "$([ "$(lien 20000000-0000-0000-0000-000000000006)" = - ] && echo 1)"
resultat "rattrapage : un lien existant n'est jamais écrasé" "$([ "$(lien 20000000-0000-0000-0000-000000000005)" = 0f ] && echo 1)"
resultat "rattrapage : Swend vers Zoé (outre-mer, autre format) rattaché" "$([ "$(P -tA -c "select right(destinataire_id::text, 2) from pactes where id = '10000000-0000-0000-0000-000000000002'")" = 0f ] && echo 1)"
resultat "rattrapage : Swend avec son propre numéro jamais rattaché à soi" "$([ "$(P -tA -c "select destinataire_id is null from pactes where id = '10000000-0000-0000-0000-000000000003'")" = t ] && echo 1)"
qa_psql postgres -c "drop database if exists $BASE" >/dev/null 2>&1
