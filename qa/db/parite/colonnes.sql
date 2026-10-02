-- Colonnes des tables du schéma public : table, colonne, type, nullabilité.
-- Même requête pour la production (lecture seule, endpoint …/read-only) et
-- pour le banc QA (qa/metier/parite_schema.sh).
select string_agg(c.table_name || E'\t' || c.column_name || E'\t'
    || case when c.data_type = 'ARRAY' then c.udt_name else c.data_type end
    || E'\t' || c.is_nullable, E'\n' order by c.table_name, c.column_name) as tsv
from information_schema.columns c
join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
where c.table_schema = 'public' and t.table_type = 'BASE TABLE';
