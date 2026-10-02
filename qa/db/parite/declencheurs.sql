-- Déclencheurs des tables du schéma public : table, nom, état (O actif,
-- D désactivé, R / A réplication). Même requête pour la production (lecture
-- seule) et pour le banc QA (qa/metier/parite_schema.sh).
select string_agg(c.relname || E'\t' || t.tgname || E'\t' || t.tgenabled::text, E'\n' order by c.relname, t.tgname) as tsv
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal;
