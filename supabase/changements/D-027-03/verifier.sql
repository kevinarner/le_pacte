-- D-027-03 — vérification après exécution (lecture seule).
do $$
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
      and proname in ('echeance_h3_atteinte', 'appliquer_echeances_h3')) <> 2 then
    raise exception 'D-027-03 vérification : objets absents';
  end if;
  if (select count(*) from (values
    ('ajouter_et_demander_remplacement', '5a74cec2dd236aaec6c98e72db09f9be'),
    ('annuler_demande_remplacement', 'ddc56b751d63c6a1e17e3b5c4bce0a5e'),
    ('appliquer_echeances_h3', '82b7fc5ec4048a57e8bff07cc8667bbc'),
    ('echeance_h3_atteinte', '57ea12a3892a202ebec0b942113e0471'),
    ('envoyer_demandes_remplacement', '483d6444dc64d73eedcb4d9d2a45790d'),
    ('envoyer_rappels_dus', 'e1ba350897cefd6b75f460fb87821481'),
    ('je_peux_finalement_venir', '51c0aadc4d298e132c9f2f2265391926'),
    ('repondre_demande_remplacement', '4f30c69c6b555a1c8a446376bab8d5ef'),
    ('se_desister_du_remplacement', '7289b15205ffce8a8c83052ef70cf851')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 9
     or (select prosrc not ilike '%appliquer_echeances_h3(p_maintenant)%' from pg_proc
         where oid = 'public.envoyer_rappels_dus(timestamptz)'::regprocedure) then
    raise exception 'D-027-03 vérification : fonctions D-027-03 non en place';
  end if;
  if has_function_privilege('authenticated', 'public.appliquer_echeances_h3(timestamptz)', 'execute') then
    raise exception 'D-027-03 vérification : échéance exposée à l''app';
  end if;
  if (select count(*) from cron.job where jobname = 'swend-rappels' and active) <> 1 then
    raise exception 'D-027-03 vérification : job swend-rappels inactif';
  end if;
end $$;
select (select count(*) from public.pactes where annule_motif = 'echeance_h3') as annulations_echeance_h3,
       (select count(*) from public.pactes) as swends,
       (select count(*) from sauvegarde.d027_03_pactes_20261020) as swends_sauvegardes,
       (select count(*) from public.pactes p join sauvegarde.d027_03_pactes_20261020 s on s.id = p.id
         where p.statut is distinct from s.statut) as swends_changes;
