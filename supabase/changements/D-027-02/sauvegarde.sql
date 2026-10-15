-- D-027-02 — sauvegarde ciblée, avant toute modification. Une transaction.
-- Copie, dans le schéma interne `sauvegarde` (aucun accès pour l'app) :
--  - les définitions exactes des 9 fonctions remplacées et des 2 contraintes
--    redéfinies (pactes_annulation_complete, evenements_fil_code_check) ;
--  - l'état d'annulation de tous les Swends et l'état des chats (identifiants,
--    statuts et dates seulement : ni nom, ni numéro, ni message), pour
--    prouver qu'appliquer.sql ne modifie aucune donnée existante et pour
--    comparaison en cas de rollback.
-- Échoue (rien n'est créé) si l'état n'est pas celui relu le 15/10/2026, si
-- D-027-02 est déjà appliqué ou si la sauvegarde existe déjà.
begin;

do $$
begin
  if to_regclass('public.fils_imprevu_fermes') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public'
                and ((table_name = 'pactes' and column_name = 'annule_motif')
                  or (table_name = 'chats_apres_swend' and column_name = 'nature')))
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('appliquer_annulation', 'ouvrir_chat_annulation', 'mes_chats_swend', 'fiche_acces_d023a', 'fil_conserve_apres_annulation', 'cle_paire_fil_imprevu')) then
    raise exception 'D-027-02 : déjà appliqué (en tout ou partie)';
  end if;
  if to_regclass('public.imprevus_declares') is null
     or not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'pousser_personne') then
    raise exception 'D-027-02 : D-027-01 pas encore appliqué (ordre des migrations)';
  end if;
  -- Les 9 fonctions remplacées sont exactement celles relues en production
  -- le 15/10/2026 (corps normalisé).
  if (select count(*) from (values
    ('annuler_si_double_absence', 'c39f19ebc3b622dcbb657ca37fe199ae'),
    ('annuler_swend', '95d5c90fa45955ab8b58815f828ad057'),
    ('fermer_chats_apres_nouveau_swend', 'c5159594fa64abc660daa60161c96624'),
    ('fiche_de_confiance_accessible', '6d610f3ac43051dd3ce0376672a7c965'),
    ('fil_ecriture_ouverte', 'b62fe26276082878d218536c0f944c59'),
    ('mes_chats_apres_swend', 'ef7f9efe2b9aec1334452236c0111be0'),
    ('proteger_annulation_pacte', 'c83814299a937e02f3743e74c43e791b'),
    ('retirer_remplacant', '3c85b3268d814d99e4240410054282a3'),
    ('telephone_titulaire_accessible', '4cff9f4bd8bfc6078ae4da9fe13d0580')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 9
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('annuler_si_double_absence', 'annuler_swend', 'fermer_chats_apres_nouveau_swend', 'fiche_de_confiance_accessible', 'fil_ecriture_ouverte', 'mes_chats_apres_swend', 'proteger_annulation_pacte', 'retirer_remplacant', 'telephone_titulaire_accessible')) <> 9 then
    raise exception 'D-027-02 : les fonctions à remplacer diffèrent de celles relues (paquet à refaire)';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'evenements_fil_code_check'
      and conrelid = 'public.evenements_fil'::regclass)
     is distinct from 'CHECK ((code = ANY (ARRAY[''demande_envoyee''::text, ''demande_annulee''::text, ''demande_refusee''::text, ''demande_acceptee''::text, ''desistement''::text, ''demande_cloturee''::text, ''indisponibilite_signalee''::text, ''disponibilite_retablie''::text, ''swend_commence''::text, ''demande_reactivee''::text, ''retour_titulaire''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conname = 'pactes_annulation_complete'
         and conrelid = 'public.pactes'::regclass)
     is distinct from 'CHECK (((annule_par IS NULL) = (annule_le IS NULL)))' then
    raise exception 'D-027-02 sauvegarde : contraintes différentes de celles relues';
  end if;
  -- Déclencheurs dont le lot 2 remplace la fonction (eux-mêmes inchangés) :
  -- un seul, actif, définition relue le 15/10 (nom ignoré :
  -- on_remplacant_selectionne en production, trg_annuler_si_double_absence
  -- en QA) ; fermeture au scellement (2) et protection de l'annulation (1).
  if (select count(*) from pg_trigger t where t.tgrelid = 'public.remplacants'::regclass and not t.tgisinternal
      and t.tgfoid = 'public.annuler_si_double_absence()'::regprocedure) <> 1
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.remplacants'::regclass and not t.tgisinternal
         and t.tgenabled = 'O' and t.tgfoid = 'public.annuler_si_double_absence()'::regprocedure
         and regexp_replace(pg_get_triggerdef(t.oid), '^CREATE TRIGGER \S+ ', '')
             = 'AFTER INSERT OR UPDATE OF selectionne ON public.remplacants FOR EACH ROW EXECUTE FUNCTION annuler_si_double_absence()') <> 1
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.pactes'::regclass and t.tgenabled = 'O'
         and t.tgfoid = 'public.fermer_chats_apres_nouveau_swend()'::regprocedure) <> 2
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.pactes'::regclass and t.tgenabled = 'O'
         and t.tgfoid = 'public.proteger_annulation_pacte()'::regprocedure) <> 1 then
    raise exception 'D-027-02 sauvegarde : déclencheurs différents de ceux relus (paquet à refaire)';
  end if;
  if to_regclass('sauvegarde.d027_02_fonctions_20261015') is not null
     or to_regclass('sauvegarde.d027_02_pactes_20261015') is not null
     or to_regclass('sauvegarde.d027_02_chats_20261015') is not null then
    raise exception 'D-027-02 sauvegarde : déjà faite';
  end if;
end $$;

create schema if not exists sauvegarde;
revoke all on schema sauvegarde from public, anon, authenticated;

create table sauvegarde.d027_02_fonctions_20261015 as
select p.proname as nom, pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_functiondef(p.oid) as definition,
       (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a) as droits,
       md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) as md5_corps, now() as sauvegarde_le
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in ('annuler_si_double_absence', 'annuler_swend', 'fermer_chats_apres_nouveau_swend', 'fiche_de_confiance_accessible', 'fil_ecriture_ouverte', 'mes_chats_apres_swend', 'proteger_annulation_pacte', 'retirer_remplacant', 'telephone_titulaire_accessible')
union all
select 'contrainte ' || c.conname, '', pg_get_constraintdef(c.oid), null, null, now()
from pg_constraint c
where (c.conname = 'evenements_fil_code_check' and c.conrelid = 'public.evenements_fil'::regclass)
   or (c.conname = 'pactes_annulation_complete' and c.conrelid = 'public.pactes'::regclass)
union all
select 'declencheur ' || t.tgname, t.tgenabled::text, pg_get_triggerdef(t.oid), null, null, now()
from pg_trigger t
where not t.tgisinternal
  and t.tgfoid in ('public.annuler_si_double_absence()'::regprocedure,
                   'public.fermer_chats_apres_nouveau_swend()'::regprocedure,
                   'public.proteger_annulation_pacte()'::regprocedure);

create table sauvegarde.d027_02_pactes_20261015 as
select p.id, p.statut, p.scelle_le, p.annule_par, p.annule_le, now() as sauvegarde_le
from public.pactes p;

create table sauvegarde.d027_02_chats_20261015 as
select c.id, c.pacte_id, c.ouvre_le, c.ouvert_le, c.ferme_le, c.motif_fermeture,
       (select count(*) from public.participants_chat_apres_swend a where a.chat_id = c.id) as participants,
       (select count(*) from public.messages_apres_swend m where m.chat_id = c.id) as messages,
       now() as sauvegarde_le
from public.chats_apres_swend c;

revoke all on table sauvegarde.d027_02_fonctions_20261015 from public, anon, authenticated;
revoke all on table sauvegarde.d027_02_pactes_20261015 from public, anon, authenticated;
revoke all on table sauvegarde.d027_02_chats_20261015 from public, anon, authenticated;

do $$
begin
  if (select count(*) from sauvegarde.d027_02_fonctions_20261015) <> 15
     or (select count(*) from sauvegarde.d027_02_pactes_20261015) <> (select count(*) from public.pactes)
     or (select count(*) from sauvegarde.d027_02_chats_20261015) <> (select count(*) from public.chats_apres_swend) then
    raise exception 'D-027-02 sauvegarde : copie incomplète';
  end if;
  if has_schema_privilege('authenticated', 'sauvegarde', 'usage') or has_schema_privilege('anon', 'sauvegarde', 'usage') then
    raise exception 'D-027-02 sauvegarde : le schéma sauvegarde est accessible à l''app';
  end if;
end $$;

commit;
