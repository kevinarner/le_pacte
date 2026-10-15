-- D-027-02 — vérification après appliquer.sql (lecture seule, endpoint
-- …/read-only). Lève une erreur si un point est faux.
do $$
begin
  if to_regclass('public.fils_imprevu_fermes') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                    and table_name = 'pactes' and column_name = 'annule_motif')
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                    and table_name = 'chats_apres_swend' and column_name = 'nature') then
    raise exception 'D-027-02 vérification : objets absents';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
      and proname in ('appliquer_annulation', 'ouvrir_chat_annulation', 'mes_chats_swend', 'fiche_acces_d023a', 'fil_conserve_apres_annulation', 'cle_paire_fil_imprevu')) <> 6 then
    raise exception 'D-027-02 vérification : fonctions D-027 lot 2 absentes';
  end if;
  if (select prosrc not ilike '%remplacement_accepte%' or prosrc not ilike '%appliquer_annulation%'
      from pg_proc where oid = 'public.annuler_swend(uuid)'::regprocedure)
     or (select prosrc not ilike '%appliquer_annulation%' from pg_proc
         where oid = 'public.annuler_si_double_absence()'::regprocedure)
     or (select prosrc not ilike '%fils_imprevu_fermes%' from pg_proc
         where oid = 'public.fermer_chats_apres_nouveau_swend()'::regprocedure)
     or (select prosrc not ilike '%fiche_acces_d023a%' from pg_proc
         where oid = 'public.telephone_titulaire_accessible(uuid)'::regprocedure)
     or (select prosrc not ilike '%fil_conserve_apres_annulation%' from pg_proc
         where oid = 'public.fiche_de_confiance_accessible(uuid)'::regprocedure)
     or (select prosrc not ilike '%nature = ''apres_swend''%' from pg_proc
         where oid = 'public.mes_chats_apres_swend()'::regprocedure)
     or (select prosrc not ilike '%Swend annulé · %' or prosrc not ilike '%t’a écrit%' from pg_proc
         where oid = 'public.envoyer_message_apres_swend(uuid, text)'::regprocedure) then
    raise exception 'D-027-02 vérification : fonctions D-027 lot 2 non en place';
  end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.pactes'::regclass and tgenabled = 'O'
      and tgfoid = 'public.fermer_chats_apres_nouveau_swend()'::regprocedure) <> 2
     or (select count(*) from pg_trigger where tgrelid = 'public.remplacants'::regclass and tgenabled = 'O'
         and tgfoid = 'public.annuler_si_double_absence()'::regprocedure) <> 1
     or not exists (select 1 from pg_trigger where tgrelid = 'public.pactes'::regclass and tgenabled = 'O'
                    and tgfoid = 'public.proteger_annulation_pacte()'::regprocedure) then
    raise exception 'D-027-02 vérification : déclencheurs absents ou désactivés';
  end if;
  if has_table_privilege('authenticated', 'public.fils_imprevu_fermes', 'select')
     or has_table_privilege('anon', 'public.fils_imprevu_fermes', 'select')
     or has_function_privilege('authenticated', 'public.appliquer_annulation(uuid, text, text, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ouvrir_chat_annulation(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fil_conserve_apres_annulation(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fiche_acces_d023a(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.mes_chats_swend()', 'execute')
     or has_function_privilege('anon', 'public.mes_chats_swend()', 'execute')
     or not has_function_privilege('authenticated', 'public.mes_chats_apres_swend()', 'execute')
     or not has_function_privilege('authenticated', 'public.annuler_swend(uuid)', 'execute') then
    raise exception 'D-027-02 vérification : droits inattendus';
  end if;
  if pg_get_constraintdef((select oid from pg_constraint where conname = 'evenements_fil_code_check'
                           and conrelid = 'public.evenements_fil'::regclass)) not ilike '%fil_ferme%' then
    raise exception 'D-027-02 vérification : contrainte des événements non étendue';
  end if;
end $$;

-- Résumé (comptages seulement).
select
  (select count(*) from public.chats_apres_swend where nature = 'annulation') as chats_annulation,
  (select count(*) from public.chats_apres_swend where nature = 'apres_swend') as chats_apres_swend,
  (select count(*) from sauvegarde.d027_02_chats_20261015) as chats_sauvegardes,
  (select count(*) from public.fils_imprevu_fermes) as conversations_fermees,
  (select count(*) from public.pactes where annule_motif is not null) as annulations_avec_motif,
  (select count(*) from public.pactes) as swends,
  (select count(*) from sauvegarde.d027_02_pactes_20261015) as swends_sauvegardes;
