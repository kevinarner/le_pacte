-- R2-01 — vérification après appliquer.sql (lecture seule, endpoint
-- …/read-only). Lève une erreur si un point est faux.
do $$
begin
  if exists (select 1 from public.pactes p
             where p.dates_proposees is distinct from public.dates_proposees_canoniques(p.dates_proposees)
                or (p.date_retenue is not null and not (p.date_retenue = any (public.instants_proposes(p.dates_proposees))))) then
    raise exception 'R2-01 vérification : un Swend n''est pas conforme (forme canonique ou D-025b)';
  end if;
  if (select to_char(date_retenue at time zone 'Europe/Paris', 'YYYY-MM-DD HH24:MI') from public.pactes
      where id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6') <> '2026-11-17 19:00' then
    raise exception 'R2-01 vérification : le Swend du 17/11 n''est pas à 19:00 à Paris';
  end if;
  if (select date_rdv::text || ' ' || heure_rdv from public.reservations_a_suivre
      where swend_id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6') <> '2026-11-17 19:00' then
    raise exception 'R2-01 vérification : la vue des réservations n''indique pas 19:00';
  end if;
  if public.formater_date_heure_fr((select date_retenue from public.pactes where id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6'))
     <> 'mardi 17 novembre à 19h00' then
    raise exception 'R2-01 vérification : texte des push inattendu';
  end if;
  if (select tgenabled from pg_trigger where tgname = 'trg_verrou_zz_dates_swend' and tgrelid = 'public.pactes'::regclass) is distinct from 'O'
     or (select tgenabled from pg_trigger where tgname = 'trg_verifier_negociation_date' and tgrelid = 'public.pactes'::regclass) <> 'O' then
    raise exception 'R2-01 vérification : déclencheurs inattendus';
  end if;
end $$;

-- Résumé du Swend du 17/11 : heure de Paris, texte des push et des rappels,
-- échéances des rappels et ouverture du chat (heure de Paris).
select
  to_char(p.date_retenue at time zone 'Europe/Paris', 'DD/MM HH24:MI') as rendez_vous_paris,
  public.formater_date_heure_fr(p.date_retenue) as texte_push,
  public.heure_rappel_fr(p.date_retenue) as heure_rappels,
  to_char(public.echeance_rappel(p.date_retenue, 'j7') at time zone 'Europe/Paris', 'DD/MM HH24:MI') as rappel_j7,
  to_char(public.echeance_rappel(p.date_retenue, 'j1') at time zone 'Europe/Paris', 'DD/MM HH24:MI') as rappel_j1,
  to_char(public.echeance_rappel(p.date_retenue, 'j0') at time zone 'Europe/Paris', 'DD/MM HH24:MI') as rappel_jour_j,
  to_char(public.ouverture_chat_apres_swend(p.date_retenue) at time zone 'Europe/Paris', 'DD/MM HH24:MI') as ouverture_chat,
  (select heure_rdv from public.reservations_a_suivre where swend_id = p.id) as heure_reservation,
  (select count(*) from public.pactes) as swends,
  (select tgenabled::text from pg_trigger where tgname = 'trg_verrou_delai_minimum_swend' and tgrelid = 'public.pactes'::regclass) as declencheur_d025
from public.pactes p
where p.id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6';
