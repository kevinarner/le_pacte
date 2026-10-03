-- D-023c-01 — rollback : objets D-023c supprimés, moteur d'ouverture remis à
-- l'identique (définition relue en production le 03/10/2026, avant D-023c).
-- Une transaction. Refuse si un chat a déjà été marqué « jamais ouvert »
-- (le moteur d'origine l'ouvrirait : décision humaine). Les chats déjà fermés
-- restent fermés (D-023c : jamais de réouverture), messages système compris.
-- À combiner avec le retour à l'app précédente (gh-pages), AVANT ce
-- rollback : voir paquet.md.
begin;

do $$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.pactes'::regclass
                 and tgname = 'trg_fermer_chats_nouveau_swend_update') then
    raise exception 'D-023c-01 rollback : D-023c-01 n''est pas appliqué';
  end if;
  if exists (select 1 from public.chats_apres_swend_jamais_ouverts) then
    raise exception 'D-023c-01 rollback : des chats sont marqués « jamais ouverts » ; le moteur d''origine les ouvrirait (décision humaine, rien n''est modifié)';
  end if;
end $$;

drop trigger trg_fermer_chats_nouveau_swend_insert on public.pactes;
drop trigger trg_fermer_chats_nouveau_swend_update on public.pactes;
drop trigger trg_verrou_un_swend_par_paire on public.pactes;
drop function public.fermer_chats_apres_nouveau_swend();
drop function public.verifier_un_swend_par_paire();
drop function public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb);
drop function public.options_nouveau_swend(uuid);
drop function public.swend_actif_entre(uuid, uuid);
drop function public.swend_en_cours(text, jsonb, timestamptz);

-- Moteur d'origine (copie exacte de pg_get_functiondef en production).
CREATE OR REPLACE FUNCTION public.ouvrir_chats_apres_swend(p_maintenant timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_fenetre_push constant interval := interval '12 hours';
  v_service timestamptz;
  p record;
  v_statut text;
  v_scelle timestamptz;
  v_date timestamptz;
  v_initiateur uuid;
  v_destinataire uuid;
  v_ouvre timestamptz;
  v_nb_remplacants integer;
  v_remplacant record;
  v_prenom_i text;
  v_prenom_d text;
  v_prenom_r text;
  v_chat uuid;
  v_participant record;
  n integer := 0;
begin
  select mise_en_service into v_service from chat_apres_swend_service where id;
  if v_service is null then
    return 0;
  end if;

  for p in
    select pa.id from pactes pa
    join swends_figes f on f.pacte_id = pa.id
    where pa.statut = 'confirme'
      and pa.scelle_le is not null
      and pa.date_retenue is not null
      and ouverture_chat_apres_swend(pa.date_retenue) <= p_maintenant
      and ouverture_chat_apres_swend(pa.date_retenue) >= v_service
      and not exists (select 1 from chats_apres_swend c where c.pacte_id = pa.id)
      and not exists (select 1 from anomalies_chat_apres_swend a where a.pacte_id = pa.id)
    order by pa.date_retenue, pa.id
  loop
    select statut, scelle_le, date_retenue, initiateur_id, destinataire_id
      into v_statut, v_scelle, v_date, v_initiateur, v_destinataire
    from pactes where id = p.id for update;
    perform 1 from remplacants where pacte_id = p.id for update;
    v_ouvre := ouverture_chat_apres_swend(v_date);
    continue when v_statut is distinct from 'confirme' or v_scelle is null
      or v_ouvre > p_maintenant or v_ouvre < v_service;

    select count(*) into v_nb_remplacants
    from remplacants where pacte_id = p.id and selectionne and retire_le is null;
    select r.profil_id, r.cote into v_remplacant
    from remplacants r where r.pacte_id = p.id and r.selectionne and r.retire_le is null
    order by r.id limit 1;

    select nullif(trim(prenom), '') into v_prenom_i from profiles where id = v_initiateur;
    select nullif(trim(prenom), '') into v_prenom_d from profiles where id = v_destinataire;
    v_prenom_r := null;
    if v_nb_remplacants = 1 then
      select nullif(trim(prenom), '') into v_prenom_r from profiles where id = v_remplacant.profil_id;
    end if;

    -- Incohérences : le chat n'est pas ouvert, l'anomalie est enregistrée une
    -- fois (lisible en SQL) et signalée dans les journaux.
    if v_nb_remplacants > 1 or v_initiateur is null or v_destinataire is null
       or v_prenom_i is null or v_prenom_d is null
       or (v_nb_remplacants = 1 and v_prenom_r is null) then
      insert into anomalies_chat_apres_swend (pacte_id, code, detail)
      values (p.id,
        case when v_nb_remplacants > 1 then 'plusieurs_remplacants_actifs' else 'participant_introuvable' end,
        format('remplaçants actifs : %s ; initiateur : %s ; destinataire : %s',
               v_nb_remplacants, coalesce(v_initiateur::text, '-'), coalesce(v_destinataire::text, '-')))
      on conflict (pacte_id) do nothing;
      raise warning 'chat_apres_swend : Swend % non ouvert (remplaçants actifs : %)', p.id, v_nb_remplacants;
      continue;
    end if;

    insert into chats_apres_swend (pacte_id, ouvre_le, ouvert_le)
    values (p.id, v_ouvre, clock_timestamp())
    on conflict (pacte_id) do nothing
    returning id into v_chat;
    continue when v_chat is null;

    insert into participants_chat_apres_swend (chat_id, profil_id, role, prenom_affiche)
    values (v_chat, v_initiateur, 'initiateur', v_prenom_i),
           (v_chat, v_destinataire, 'destinataire', v_prenom_d);
    if v_nb_remplacants = 1 then
      insert into participants_chat_apres_swend (chat_id, profil_id, role, place_de, prenom_affiche)
      values (v_chat, v_remplacant.profil_id, 'remplacant', v_remplacant.cote, v_prenom_r);
    end if;

    if p_maintenant <= v_ouvre + c_fenetre_push then
      for v_participant in
        select profil_id from participants_chat_apres_swend
        where chat_id = v_chat and profil_id is not null order by role
      loop
        perform notifier(v_participant.profil_id, 'Alors, ce Swend ?',
          'Le silence est levé. Vous pouvez maintenant en reparler dans le chat.',
          jsonb_build_object('type', 'chat_apres_swend', 'chat_id', v_chat, 'pacte_id', p.id));
      end loop;
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$function$;

drop function public.participants_potentiels_chat_apres_swend(uuid);
drop table public.chats_apres_swend_jamais_ouverts;

do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.ouvrir_chats_apres_swend(timestamptz)'::regprocedure)
     <> '77ab4ee095fefb3a47f11a722ec9adc9'
     or has_function_privilege('authenticated', 'public.ouvrir_chats_apres_swend(timestamptz)', 'execute')
     or exists (select 1 from pg_trigger where tgrelid = 'public.pactes'::regclass
                and (tgname like 'trg_fermer_chats%' or tgname = 'trg_verrou_un_swend_par_paire'))
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('participants_potentiels_chat_apres_swend', 'fermer_chats_apres_nouveau_swend',
                                'swend_en_cours', 'swend_actif_entre', 'verifier_un_swend_par_paire',
                                'options_nouveau_swend', 'creer_swend_depuis_chat'))
     or to_regclass('public.chats_apres_swend_jamais_ouverts') is not null then
    raise exception 'D-023c-01 rollback : état d''origine non retrouvé';
  end if;
end $$;

commit;
