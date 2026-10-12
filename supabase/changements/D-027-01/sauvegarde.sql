-- D-027-01 — sauvegarde ciblée, avant toute modification. Une transaction.
-- Copie, dans le schéma interne `sauvegarde` (aucun accès pour l'app) :
--  - les définitions exactes des 9 fonctions remplacées et de la contrainte
--    des événements du fil ;
--  - l'état des demandes de toutes les fiches (identifiants et statuts
--    seulement : ni nom, ni numéro), pour prouver qu'appliquer.sql ne modifie
--    aucune donnée existante et pour comparaison en cas de rollback.
-- Échoue (rien n'est créé) si l'état n'est pas celui testé, si D-027-01 est
-- déjà appliqué ou si la sauvegarde existe déjà.
begin;

do $$
begin
  if to_regclass('public.imprevus_declares') is not null
     or to_regclass('public.clotures_demandes') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public'
                and table_name = 'remplacants' and column_name = 'message_a_renvoyer')
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('envoyer_demandes_remplacement', 'je_peux_finalement_venir', 'marquer_message_renvoye', 'pousser_personne', 'pousser_titulaire', 'prenom_titulaire_de', 'suivre_demande_avant', 'suivre_demande_apres'))
     or exists (select 1 from pg_trigger where tgrelid = 'public.remplacants'::regclass
                and tgname in ('trg_suivre_demande_avant', 'trg_suivre_demande_apres')) then
    raise exception 'D-027-01 : déjà appliqué (en tout ou partie)';
  end if;
  -- Les 9 fonctions remplacées sont exactement celles des migrations testées
  -- (gel_a_h.sql, fil_evenements_et_lectures.sql ; corps normalisé).
  if (select count(*) from (values
    ('ajouter_et_demander_remplacement', 'f05127e4f5451b63c94e4c655fb47172'),
    ('annuler_demande_remplacement', 'a6437d253deb62b5bb661bbfd5bc448b'),
    ('envoyer_demande_remplacement', '1751db53c54569452626d4b3e7738935'),
    ('etat_cote_titulaire', '9192fd4441222ee8a7dc5daa036e90c5'),
    ('journaliser_demande_remplacement', '15532fb3de53cfd63cf19c2d3f7484f4'),
    ('normaliser_nouveau_remplacant', '7d96b877f09aed71baeba79fc1c86332'),
    ('notifier_demande_remplacement', 'c8ecfca89ae18029fcb4e319d519c1cc'),
    ('repondre_demande_remplacement', '17ba2628dbe9dc921eefe9df8ef30569'),
    ('se_desister_du_remplacement', 'd96df4cab29ac3db951fd42586dacb00')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 9
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('ajouter_et_demander_remplacement', 'annuler_demande_remplacement', 'envoyer_demande_remplacement', 'etat_cote_titulaire', 'journaliser_demande_remplacement', 'normaliser_nouveau_remplacant', 'notifier_demande_remplacement', 'repondre_demande_remplacement', 'se_desister_du_remplacement')) <> 9 then
    raise exception 'D-027-01 : les fonctions à remplacer diffèrent de celles testées (paquet à refaire)';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'evenements_fil_code_check'
      and conrelid = 'public.evenements_fil'::regclass)
     is distinct from 'CHECK ((code = ANY (ARRAY[''demande_envoyee''::text, ''demande_annulee''::text, ''demande_refusee''::text, ''demande_acceptee''::text, ''desistement''::text, ''demande_cloturee''::text, ''indisponibilite_signalee''::text, ''disponibilite_retablie''::text, ''swend_commence''::text])))' then
    raise exception 'D-027-01 sauvegarde : contrainte des événements différente de celle testée';
  end if;
  if to_regclass('sauvegarde.d027_01_fonctions_20261012') is not null
     or to_regclass('sauvegarde.d027_01_remplacants_20261012') is not null then
    raise exception 'D-027-01 sauvegarde : déjà faite';
  end if;
end $$;

create schema if not exists sauvegarde;
revoke all on schema sauvegarde from public, anon, authenticated;

create table sauvegarde.d027_01_fonctions_20261012 as
select p.proname as nom, pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_functiondef(p.oid) as definition,
       (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a) as droits,
       md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) as md5_corps, now() as sauvegarde_le
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in ('ajouter_et_demander_remplacement', 'annuler_demande_remplacement', 'envoyer_demande_remplacement', 'etat_cote_titulaire', 'journaliser_demande_remplacement', 'normaliser_nouveau_remplacant', 'notifier_demande_remplacement', 'repondre_demande_remplacement', 'se_desister_du_remplacement')
union all
select 'contrainte evenements_fil_code_check', '', pg_get_constraintdef(c.oid), null, null, now()
from pg_constraint c where c.conname = 'evenements_fil_code_check' and c.conrelid = 'public.evenements_fil'::regclass;

create table sauvegarde.d027_01_remplacants_20261012 as
select r.id, r.pacte_id, r.cote, r.demande_statut, r.selectionne, r.retire_le, r.indisponible_spontanement,
       p.statut as statut_swend, now() as sauvegarde_le
from public.remplacants r join public.pactes p on p.id = r.pacte_id;

revoke all on table sauvegarde.d027_01_fonctions_20261012 from public, anon, authenticated;
revoke all on table sauvegarde.d027_01_remplacants_20261012 from public, anon, authenticated;

do $$
begin
  if (select count(*) from sauvegarde.d027_01_fonctions_20261012) <> 10
     or (select count(*) from sauvegarde.d027_01_remplacants_20261012) <> (select count(*) from public.remplacants) then
    raise exception 'D-027-01 sauvegarde : copie incomplète';
  end if;
  if has_schema_privilege('authenticated', 'sauvegarde', 'usage') or has_schema_privilege('anon', 'sauvegarde', 'usage') then
    raise exception 'D-027-01 sauvegarde : le schéma sauvegarde est accessible à l''app';
  end if;
end $$;

commit;
