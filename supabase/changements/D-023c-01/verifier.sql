-- D-023c-01 — vérification après appliquer.sql (lecture seule, endpoint
-- …/read-only). Lève une erreur si un point est faux.
do $$
begin
  if (select count(*) from pg_trigger where not tgisinternal and tgrelid = 'public.pactes'::regclass
      and tgname in ('trg_fermer_chats_nouveau_swend_insert', 'trg_fermer_chats_nouveau_swend_update')
      and tgenabled = 'O') <> 2 then
    raise exception 'D-023c-01 vérification : déclencheurs de fermeture absents ou désactivés';
  end if;
  if not exists (select 1 from pg_trigger where not tgisinternal and tgrelid = 'public.pactes'::regclass
                 and tgname = 'trg_verrou_un_swend_par_paire' and tgenabled = 'O') then
    raise exception 'D-023c-01 vérification : règle « un Swend en cours par paire » absente ou désactivée';
  end if;
  if (select prosrc ilike '%notifier(%' from pg_proc where oid = 'public.fermer_chats_apres_nouveau_swend()'::regprocedure) then
    raise exception 'D-023c-01 vérification : la fermeture ne doit envoyer aucune push';
  end if;
  if has_table_privilege('authenticated', 'public.chats_apres_swend_jamais_ouverts', 'select')
     or has_function_privilege('authenticated', 'public.swend_actif_entre(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.swend_en_cours(text, jsonb, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.verifier_un_swend_par_paire()', 'execute')
     or has_function_privilege('authenticated', 'public.participants_potentiels_chat_apres_swend(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.options_nouveau_swend(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb)', 'execute') then
    raise exception 'D-023c-01 vérification : droits inattendus';
  end if;
  if (select not (prosrc ilike '%participants_potentiels_chat_apres_swend%' and prosrc ilike '%chats_apres_swend_jamais_ouverts%')
      from pg_proc where oid = 'public.ouvrir_chats_apres_swend(timestamptz)'::regprocedure) then
    raise exception 'D-023c-01 vérification : moteur d''ouverture non mis à jour';
  end if;
end $$;

-- Résumé : objets D-023c, état des chats, planification du moteur.
select
  (select count(*) from pg_trigger where tgrelid = 'public.pactes'::regclass and tgname like 'trg_fermer_chats%' and tgenabled = 'O') as declencheurs_fermeture,
  (select count(*) from pg_trigger where tgrelid = 'public.pactes'::regclass and tgname = 'trg_verrou_un_swend_par_paire' and tgenabled = 'O') as declencheur_paire,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('participants_potentiels_chat_apres_swend', 'fermer_chats_apres_nouveau_swend',
                     'swend_en_cours', 'swend_actif_entre', 'verifier_un_swend_par_paire',
                     'options_nouveau_swend', 'creer_swend_depuis_chat')) as fonctions_d023c,
  (select count(*) from public.pactes p where public.swend_en_cours(p.statut, p.dates_proposees, p.date_retenue)
     and exists (select 1 from public.pactes q where q.id <> p.id
                 and public.swend_en_cours(q.statut, q.dates_proposees, q.date_retenue)
                 and ((q.initiateur_id, q.destinataire_id) in ((p.initiateur_id, p.destinataire_id), (p.destinataire_id, p.initiateur_id))))) as swends_en_doublon_existants,
  (select count(*) from public.chats_apres_swend) as chats,
  (select count(*) from public.chats_apres_swend where ferme_le is not null) as chats_fermes,
  (select count(*) from public.messages_apres_swend where genre = 'systeme') as messages_systeme,
  (select count(*) from public.chats_apres_swend_jamais_ouverts) as chats_jamais_ouverts,
  (select count(*) from public.pactes) as swends,
  (select count(*) from cron.job where jobname = 'swend-chat-apres' and active) as job_chat_actif;
