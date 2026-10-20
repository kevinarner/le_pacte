-- D-027-03 — vérification après exécution (lecture seule).
do $$
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
      and proname in ('echeance_h3_atteinte', 'appliquer_echeances_h3')) <> 2 then
    raise exception 'D-027-03 vérification : objets absents';
  end if;
  if (select count(*) from (values
    ('ajouter_et_demander_remplacement', '41d62d5c89670158a44a3eb57fb146d4'),
    ('annuler_demande_remplacement', 'd4f041ba4caafe35ad85b31b1742f8df'),
    ('appliquer_echeances_h3', '82b7fc5ec4048a57e8bff07cc8667bbc'),
    ('echeance_h3_atteinte', '57ea12a3892a202ebec0b942113e0471'),
    ('envoyer_demandes_remplacement', '7bb8a3ad2d46036b260192354b3d6012'),
    ('envoyer_rappels_dus', 'e1ba350897cefd6b75f460fb87821481'),
    ('je_peux_finalement_venir', 'c1ae4f8bd5140f7eed108040376fc754'),
    ('repondre_demande_remplacement', '8f6e448b412d297ec245d74d53468ee7'),
    ('se_desister_du_remplacement', '5f64a11b94a473d7796f6240d14d89ca')
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
  if (select count(*) from cron.job where jobname = 'swend-rappels' and active and schedule = '*/5 * * * *') <> 1
     or (select count(*) from cron.job where jobname = 'swend-echeance-h3' and active and schedule = '* * * * *'
         and command = 'select public.appliquer_echeances_h3()') <> 1 then
    raise exception 'D-027-03 vérification : jobs différents de ceux attendus';
  end if;
end $$;
select (select count(*) from public.pactes where annule_motif = 'echeance_h3') as annulations_echeance_h3,
       (select count(*) from public.pactes) as swends,
       (select count(*) from sauvegarde.d027_03_pactes_20261020) as swends_sauvegardes,
       (select count(*) from public.pactes p join sauvegarde.d027_03_pactes_20261020 s on s.id = p.id
         where p.statut is distinct from s.statut) as swends_changes;
