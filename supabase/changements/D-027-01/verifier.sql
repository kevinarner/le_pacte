-- D-027-01 — vérification après appliquer.sql (lecture seule, endpoint
-- …/read-only). Lève une erreur si un point est faux.
do $$
begin
  if to_regclass('public.imprevus_declares') is null or to_regclass('public.clotures_demandes') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                    and table_name = 'remplacants' and column_name = 'message_a_renvoyer') then
    raise exception 'D-027-01 vérification : objets absents';
  end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.remplacants'::regclass
      and tgname in ('trg_suivre_demande_avant', 'trg_suivre_demande_apres') and tgenabled = 'O') <> 2 then
    raise exception 'D-027-01 vérification : déclencheurs de suivi absents ou désactivés';
  end if;
  if (select prosrc ilike '%notifier(%' from pg_proc where oid = 'public.journaliser_demande_remplacement()'::regprocedure)
     or (select prosrc not ilike '%pousser_titulaire%' or prosrc ilike '%demande_statut = ''envoyee''%'
         from pg_proc where oid = 'public.notifier_demande_remplacement()'::regprocedure) then
    raise exception 'D-027-01 vérification : déclencheur de notification non réduit à l''indisponibilité spontanée';
  end if;
  if (select prosrc not ilike '%clotures_demandes%' from pg_proc where oid = 'public.se_desister_du_remplacement(uuid)'::regprocedure)
     or (select prosrc not ilike '%envoyer_demandes_remplacement%' from pg_proc where oid = 'public.envoyer_demande_remplacement(uuid)'::regprocedure)
     or (select prosrc not ilike '%imprevus_declares%' from pg_proc where oid = 'public.etat_cote_titulaire(uuid, text)'::regprocedure) then
    raise exception 'D-027-01 vérification : fonctions D-027 non en place';
  end if;
  if has_table_privilege('authenticated', 'public.imprevus_declares', 'select')
     or has_table_privilege('authenticated', 'public.clotures_demandes', 'select')
     or has_function_privilege('authenticated', 'public.pousser_personne(uuid, text, text)', 'execute')
     or has_function_privilege('anon', 'public.envoyer_demandes_remplacement(uuid[])', 'execute')
     or not has_function_privilege('authenticated', 'public.envoyer_demandes_remplacement(uuid[])', 'execute')
     or not has_function_privilege('authenticated', 'public.je_peux_finalement_venir(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.marquer_message_renvoye(uuid)', 'execute') then
    raise exception 'D-027-01 vérification : droits inattendus';
  end if;
  if pg_get_constraintdef((select oid from pg_constraint where conname = 'evenements_fil_code_check'
                           and conrelid = 'public.evenements_fil'::regclass)) not ilike '%retour_titulaire%' then
    raise exception 'D-027-01 vérification : contrainte des événements non étendue';
  end if;
end $$;

-- Résumé (comptages seulement).
select
  (select count(*) from public.imprevus_declares) as cotes_en_imprevu,
  (select count(*) from public.clotures_demandes) as clotures_memorisees,
  (select count(*) from public.remplacants where message_a_renvoyer) as messages_a_renvoyer,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('envoyer_demandes_remplacement', 'je_peux_finalement_venir', 'marquer_message_renvoye', 'pousser_personne', 'pousser_titulaire', 'prenom_titulaire_de', 'suivre_demande_avant', 'suivre_demande_apres')) as fonctions_d027,
  (select count(*) from public.remplacants) as fiches,
  (select count(*) from sauvegarde.d027_01_remplacants_20261012) as fiches_sauvegardees;
