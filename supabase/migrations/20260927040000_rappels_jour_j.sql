-- Migration : rappels automatiques autour du Jour J (J-7, J-3, J-1 à 18h,
-- Jour J à H-3) et push immédiate en cas de double remplacement.
-- Décision D-021. À exécuter après reservations_suivi.sql. Sûre à ré-exécuter.
--
-- Aucune donnée existante modifiée. Le déclenchement régulier du moteur
-- (pg_cron, toutes les 5 minutes) N'EST PAS dans cette migration : il se
-- configure à part, après validation (voir le SQL « planification »).
--
-- Principes :
--  * Le moteur envoyer_rappels_dus(p_maintenant) recalcule tout à chaque
--    passage : échéances dues, état de chaque côté, destinataires, textes.
--  * Échéances en Europe/Paris (changements d'heure compris) : J-7, J-3,
--    J-1 à 18h00 le jour civil concerné ; Jour J = date_retenue - 3 h.
--  * Pas de rattrapage : une échéance n'est envoyée que si le Swend était
--    déjà scellé à cette échéance, et seulement dans les 30 minutes qui la
--    suivent (au-delà, elle est ignorée, même après une panne du planificateur).
--  * Anti-doublon garanti par la base : une échéance n'est traitée qu'une
--    fois par Swend (rappels_echeances), et jamais deux fois pour la même
--    personne (rappels_envoyes). Idempotent, sûr en concurrence.
--  * Push uniquement (notifier()) : aucune box dans l'app.
--  * Confidentialité : l'autre titulaire voit toujours le titulaire
--    officiel, jamais le remplaçant.

-- 1. Formats de date et heure (Europe/Paris) --------------------------------

create or replace function public.date_rappel_fr(p_ts timestamptz)
returns text
language sql
immutable
set search_path = public
as $$
  -- « lundi 13 octobre »
  select (array['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'])
           [extract(isodow from p_ts at time zone 'Europe/Paris')::int]
      || ' ' || extract(day from p_ts at time zone 'Europe/Paris')::int
      || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet','août',
                       'septembre','octobre','novembre','décembre'])
           [extract(month from p_ts at time zone 'Europe/Paris')::int]
$$;

create or replace function public.heure_rappel_fr(p_ts timestamptz)
returns text
language sql
immutable
set search_path = public
as $$
  -- « 20h00 »
  select to_char(p_ts at time zone 'Europe/Paris', 'HH24"h"MI')
$$;

create or replace function public.majuscule_initiale(p_texte text)
returns text
language sql
immutable
as $$
  select upper(left(p_texte, 1)) || substr(p_texte, 2)
$$;

-- 2. Échéances ---------------------------------------------------------------

create or replace function public.echeance_rappel(p_date_retenue timestamptz, p_type text)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select case p_type
    when 'j0' then p_date_retenue - interval '3 hours'
    else (((p_date_retenue at time zone 'Europe/Paris')::date
           - case p_type when 'j7' then 7 when 'j3' then 3 when 'j1' then 1 end)
          + time '18:00') at time zone 'Europe/Paris'
  end
$$;

-- 3. État d'un côté (D-021) ------------------------------------------------
--   'remplace' : une personne de ce côté a accepté (selectionne) ;
--   'cherche'  : personne n'a accepté, et au moins une demande de ce côté
--                est en attente, refusée ou désistée ;
--   'normal'   : sinon (annuler toutes ses demandes en attente sans refus ni
--                désistement ramène à 'normal').

create or replace function public.etat_cote_titulaire(p_pacte_id uuid, p_cote text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (select 1 from remplacants
                 where pacte_id = p_pacte_id and cote = p_cote and selectionne) then 'remplace'
    when exists (select 1 from remplacants
                 where pacte_id = p_pacte_id and cote = p_cote
                   and demande_statut in ('envoyee', 'refusee', 'desistee')) then 'cherche'
    else 'normal'
  end
$$;
revoke execute on function public.etat_cote_titulaire(uuid, text) from public, anon, authenticated;

-- 4. Journal anti-doublon (interne) -----------------------------------------

create table if not exists public.rappels_echeances (
  pacte_id uuid not null references public.pactes(id) on delete cascade,
  type_rappel text not null check (type_rappel in ('j7', 'j3', 'j1', 'j0')),
  echeance timestamptz not null,
  traite_le timestamptz not null default now(),
  primary key (pacte_id, type_rappel)
);

create table if not exists public.rappels_envoyes (
  pacte_id uuid not null references public.pactes(id) on delete cascade,
  profile_id uuid not null,
  type_rappel text not null check (type_rappel in ('j7', 'j3', 'j1', 'j0')),
  famille text not null check (famille in ('repas', 'remplace', 'cherche')),
  envoye_le timestamptz not null default now(),
  primary key (pacte_id, profile_id, type_rappel)
);

alter table public.rappels_echeances enable row level security;
alter table public.rappels_envoyes enable row level security;
revoke all on table public.rappels_echeances from public, anon, authenticated;
revoke all on table public.rappels_envoyes from public, anon, authenticated;

-- 5. Textes -----------------------------------------------------------------

create or replace function public.texte_rappel(
  p_famille text, p_type text, p_date_retenue timestamptz, p_restaurant text,
  p_type_repas text, p_prenom text)
returns table (titre text, corps text)
language plpgsql
immutable
set search_path = public
as $$
declare
  d text := date_rappel_fr(p_date_retenue);
  h text := heure_rappel_fr(p_date_retenue);
  lieu text := h || ' · ' || coalesce(p_restaurant, 'le restaurant');
  quand text := d || ' à ' || lieu;
  cherche text := 'Tente de trouver quelqu’un pour te remplacer tant qu’il en est encore temps.';
begin
  if p_famille = 'repas' then
    return query select v.a, v.b from (values
      ('j7', 'Le compte à rebours est lancé', 'Votre Swend avec ' || p_prenom || ' approche : ' || quand || '.'),
      ('j3', 'Ça se rapproche…', 'Plus que 3 jours avant votre Swend avec ' || p_prenom || ' : ' || quand || '.'),
      ('j1', 'C’est demain !', 'Votre Swend avec ' || p_prenom || ', c’est demain : ' || quand || '.'),
      ('j0', 'C’est le jour du Swend !', 'Rendez-vous à ' || lieu || '. Est-ce que tu vas vraiment '
             || case when p_type_repas = 'dejeuner' then 'déjeuner' else 'dîner' end || ' avec ' || p_prenom || ' ?')
    ) v(t, a, b) where v.t = p_type;
  elsif p_famille = 'remplace' then
    return query select v.a, v.b from (values
      ('j7', 'Ton Swend approche', majuscule_initiale(quand) || '.' || E'\n' || p_prenom || ' prend ta place.'),
      ('j3', 'Plus que 3 jours', 'Ton Swend est prévu ' || quand || '.' || E'\n' || p_prenom || ' prend ta place.'),
      ('j1', 'C’est demain !', 'Ton Swend aura lieu ' || quand || '.' || E'\n' || p_prenom || ' prend ta place.'),
      ('j0', 'C’est le jour du Swend !', 'Aujourd’hui, ' || quand || '.' || E'\n' || p_prenom || ' prend ta place.')
    ) v(t, a, b) where v.t = p_type;
  else -- 'cherche'
    return query select v.a, v.b from (values
      ('j7', 'Ton Swend avec ' || p_prenom || ' approche', majuscule_initiale(quand) || '.' || E'\n' || cherche),
      ('j3', 'Plus que 3 jours pour ton Swend avec ' || p_prenom, majuscule_initiale(quand) || '.' || E'\n' || cherche),
      ('j1', 'C’est demain !', 'Ton Swend avec ' || p_prenom || ' : ' || quand || '.' || E'\n'
             || 'Le temps presse, essaie de trouver quelqu’un pour te remplacer au plus vite.'),
      ('j0', 'Ton Swend avec ' || p_prenom || ' est dans 3h !', 'Aujourd’hui à ' || lieu || '.' || E'\n'
             || 'Ton Swend est en péril ! Trouve quelqu’un pour te remplacer dès que possible. '
             || 'Et si vraiment personne n’est disponible, annule le Swend pour que le restaurant soit prévenu.')
    ) v(t, a, b) where v.t = p_type;
  end if;
end;
$$;

-- 6. Moteur -----------------------------------------------------------------

create or replace function public.envoyer_rappel(
  p_pacte_id uuid, p_profile_id uuid, p_type text, p_famille text,
  p_date_retenue timestamptz, p_restaurant text, p_type_repas text, p_prenom text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  t record;
begin
  if p_profile_id is null then
    return 0;
  end if;
  insert into rappels_envoyes (pacte_id, profile_id, type_rappel, famille)
  values (p_pacte_id, p_profile_id, p_type, p_famille)
  on conflict do nothing;
  if not found then
    return 0; -- déjà envoyé à cette personne pour cette échéance
  end if;
  select * into t from texte_rappel(p_famille, p_type, p_date_retenue, p_restaurant, p_type_repas, p_prenom);
  -- Charge utile sans rôle figé : l'app recalcule la destination au clic.
  perform notifier(p_profile_id, t.titre, t.corps,
    jsonb_build_object('type', 'rappel', 'pacte_id', p_pacte_id, 'rappel', p_type));
  return 1;
end;
$$;
revoke execute on function public.envoyer_rappel(uuid, uuid, text, text, timestamptz, text, text, text) from public, anon, authenticated;

create or replace function public.envoyer_rappels_dus(p_maintenant timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fenetre constant interval := interval '30 minutes';
  p record;
  v_type text;
  v_echeance timestamptz;
  v_cote text;
  v_etat text;
  v_titulaire uuid;
  v_prenom_titulaire text;
  v_prenom_autre text;
  v_fiche record;
  n integer := 0;
begin
  for p in
    select pa.id, pa.date_retenue, pa.scelle_le, pa.type, pa.initiateur_id, pa.destinataire_id,
           split_part(trim(pa.initiateur_nom), ' ', 1) as prenom_initiateur,
           split_part(trim(pa.destinataire_nom), ' ', 1) as prenom_destinataire,
           r.nom as restaurant
    from pactes pa left join restaurants r on r.id = pa.restaurant_id
    where pa.statut = 'confirme'
      and pa.scelle_le is not null
      and pa.date_retenue is not null
      and pa.date_retenue > p_maintenant
      and pa.date_retenue <= p_maintenant + interval '8 days'
  loop
    foreach v_type in array array['j7', 'j3', 'j1', 'j0'] loop
      v_echeance := echeance_rappel(p.date_retenue, v_type);
      continue when not (v_echeance <= p_maintenant
                         and p_maintenant < v_echeance + c_fenetre
                         and p.scelle_le <= v_echeance);
      -- Une échéance n'est traitée qu'une fois par Swend (même si le moteur
      -- tourne deux fois, ou en parallèle) : qui en fait partie est décidé ici.
      insert into rappels_echeances (pacte_id, type_rappel, echeance)
      values (p.id, v_type, v_echeance)
      on conflict do nothing;
      continue when not found;

      foreach v_cote in array array['initiateur', 'destinataire'] loop
        if v_cote = 'initiateur' then
          v_titulaire := p.initiateur_id; v_prenom_titulaire := p.prenom_initiateur; v_prenom_autre := p.prenom_destinataire;
        else
          v_titulaire := p.destinataire_id; v_prenom_titulaire := p.prenom_destinataire; v_prenom_autre := p.prenom_initiateur;
        end if;
        v_etat := etat_cote_titulaire(p.id, v_cote);
        if v_etat = 'remplace' then
          select r.profil_id, trim(r.prenom) as prenom into v_fiche
          from remplacants r where r.pacte_id = p.id and r.cote = v_cote and r.selectionne limit 1;
          -- Le titulaire remplacé : « Kevin prend ta place ».
          n := n + envoyer_rappel(p.id, v_titulaire, v_type, 'remplace', p.date_retenue, p.restaurant, p.type, v_fiche.prenom);
          -- La personne qui prend sa place : rappel « repas » avec l'autre titulaire.
          n := n + envoyer_rappel(p.id, v_fiche.profil_id, v_type, 'repas', p.date_retenue, p.restaurant, p.type, v_prenom_autre);
        elsif v_etat = 'cherche' then
          n := n + envoyer_rappel(p.id, v_titulaire, v_type, 'cherche', p.date_retenue, p.restaurant, p.type, v_prenom_autre);
        else
          n := n + envoyer_rappel(p.id, v_titulaire, v_type, 'repas', p.date_retenue, p.restaurant, p.type, v_prenom_autre);
        end if;
      end loop;
    end loop;
  end loop;
  return n;
end;
$$;
revoke execute on function public.envoyer_rappels_dus(timestamptz) from public, anon, authenticated;

-- 7. Destination au clic (calculée à l'instant du clic) ----------------------
-- 'imprevu' : titulaire dont le côté cherche actuellement quelqu'un (Swend
-- toujours actif) ; 'fiche' : toute autre personne autorisée (participant,
-- titulaire remplacé, remplaçant accepté) ; null : aucun accès (ex. désisté).

create or replace function public.destination_rappel(p_pacte_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  p pactes%rowtype;
  v_cote text;
begin
  select * into p from pactes where id = p_pacte_id;
  if not found or v_uid is null then
    return null;
  end if;
  v_cote := case when p.initiateur_id = v_uid then 'initiateur'
                 when p.destinataire_id = v_uid then 'destinataire' end;
  if v_cote is not null then
    if p.statut = 'confirme' and etat_cote_titulaire(p.id, v_cote) = 'cherche' then
      return 'imprevu';
    end if;
    return 'fiche';
  end if;
  if exists (select 1 from remplacants r where r.pacte_id = p.id and r.profil_id = v_uid and r.selectionne) then
    return 'fiche';
  end if;
  return null;
end;
$$;
revoke execute on function public.destination_rappel(uuid) from public, anon;
grant execute on function public.destination_rappel(uuid) to authenticated;

-- 8. Double remplacement : push immédiate ------------------------------------
-- Même logique d'annulation qu'avant (dès que les deux côtés ont une
-- personne sélectionnée, le Swend passe annuleDoubleAbsence), avec les
-- textes validés : aux deux titulaires et aux deux remplaçants, sans jamais
-- révéler à un côté qui remplace l'autre. Remplace les notifications de
-- double absence précédentes (aucun doublon).

create or replace function public.annuler_si_double_absence()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  v_quand text;
  v_fiche record;
  v_titulaire text;
  v_autre text;
begin
  if new.selectionne is not true then
    return new;
  end if;
  if not exists (select 1 from remplacants
                 where pacte_id = new.pacte_id and cote <> new.cote and selectionne = true) then
    return new;
  end if;

  update pactes set statut = 'annuleDoubleAbsence'
  where id = new.pacte_id and statut <> 'annuleDoubleAbsence';
  if not found then
    return new; -- déjà annulé : rien de plus, aucune push en double
  end if;

  select pa.id, pa.date_retenue, pa.initiateur_id, pa.destinataire_id,
         split_part(trim(pa.initiateur_nom), ' ', 1) as prenom_initiateur,
         split_part(trim(pa.destinataire_nom), ' ', 1) as prenom_destinataire,
         r.nom as restaurant
    into p
  from pactes pa left join restaurants r on r.id = pa.restaurant_id
  where pa.id = new.pacte_id;
  v_quand := date_rappel_fr(p.date_retenue) || ' à ' || heure_rappel_fr(p.date_retenue)
             || ' · ' || coalesce(p.restaurant, 'le restaurant');

  if p.initiateur_id is not null then
    perform notifier(p.initiateur_id, 'Ton Swend est annulé',
      'Toi et ' || p.prenom_destinataire || ' avez chacun fait appel à quelqu’un pour prendre votre place. Le Swend du '
        || v_quand || ' est annulé.',
      jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
  end if;
  if p.destinataire_id is not null then
    perform notifier(p.destinataire_id, 'Ton Swend est annulé',
      'Toi et ' || p.prenom_initiateur || ' avez chacun fait appel à quelqu’un pour prendre votre place. Le Swend du '
        || v_quand || ' est annulé.',
      jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
  end if;

  for v_fiche in
    select r.cote, r.profil_id from remplacants r
    where r.pacte_id = new.pacte_id and r.selectionne and r.profil_id is not null
  loop
    if v_fiche.cote = 'initiateur' then
      v_titulaire := p.prenom_initiateur; v_autre := p.prenom_destinataire;
    else
      v_titulaire := p.prenom_destinataire; v_autre := p.prenom_initiateur;
    end if;
    perform notifier(v_fiche.profil_id, 'Le Swend est annulé',
      'Tu n’as finalement plus besoin de prendre la place de ' || v_titulaire || ' ' || v_quand
        || ' : ' || v_autre || ' a lui aussi fait appel à quelqu’un pour le remplacer.',
      jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
  end loop;

  return new;
end;
$$;

-- 9. Pas de push d'acceptation contradictoire (D-015 inchangé sinon) --------

create or replace function public.notifier_demande_remplacement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_titulaire_id uuid;
  v_titulaire_nom text;
  v_titulaire_prenom text;
  v_personne text := coalesce(nullif(trim(new.prenom), ''), 'Une personne de confiance');
  v_nom_personne text := trim(coalesce(new.prenom, '') || ' ' || coalesce(new.nom, ''));
  v_corps text;
begin
  if new.profil_id is null then
    return new;
  end if;

  select case when new.cote = 'initiateur' then initiateur_id else destinataire_id end,
         case when new.cote = 'initiateur' then initiateur_nom else destinataire_nom end
    into v_titulaire_id, v_titulaire_nom
    from pactes where id = new.pacte_id;
  v_titulaire_prenom := coalesce(nullif(split_part(trim(v_titulaire_nom), ' ', 1), ''), 'Ton contact');

  -- Indisponibilité spontanée : la personne → son titulaire.
  if new.indisponible_spontanement is distinct from old.indisponible_spontanement then
    if v_titulaire_id is not null then
      perform notifier(
        v_titulaire_id,
        'Swend',
        v_personne || case when new.indisponible_spontanement
          then ' ne sera pas disponible en cas d''imprévu pour ce Swend.'
          else ' est de nouveau disponible en cas d''imprévu pour ce Swend.' end,
        jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', v_nom_personne)
      );
    end if;
    return new;
  end if;

  if new.demande_statut is not distinct from old.demande_statut then
    return new;
  end if;

  if new.demande_statut = 'envoyee' then
    perform notifier(
      new.profil_id,
      'On a besoin de toi',
      coalesce(v_titulaire_nom, 'Quelqu''un') || ' te demande de prendre sa place pour un Swend.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  elsif new.demande_statut = 'cloturee' and old.demande_statut = 'envoyee' then
    if exists (
      select 1 from remplacants
      where pacte_id = new.pacte_id and cote <> new.cote
        and profil_id = new.profil_id and selectionne = true
    ) then
      return new;
    end if;
    perform notifier(
      new.profil_id,
      'Swend',
      'C''est bon, quelqu''un a pu prendre la place.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  -- Annulation par le titulaire → la personne sollicitée.
  elsif new.demande_statut is null and old.demande_statut = 'envoyee' then
    perform notifier(
      new.profil_id,
      'Swend',
      v_titulaire_prenom || ' a annulé sa demande.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  -- Réponses et désistement de la personne → son titulaire.
  elsif v_titulaire_id is not null and (
        (old.demande_statut = 'envoyee' and new.demande_statut in ('acceptee', 'refusee'))
     or (old.demande_statut = 'acceptee' and new.demande_statut = 'desistee')) then
    -- Acceptation qui provoque le double remplacement : le titulaire reçoit
    -- à la place la push « Ton Swend est annulé » (annuler_si_double_absence),
    -- pas une acceptation contradictoire (l'événement reste dans le fil).
    if new.demande_statut = 'acceptee' and exists (
      select 1 from remplacants
      where pacte_id = new.pacte_id and cote <> new.cote and selectionne = true
    ) then
      return new;
    end if;
    v_corps := case new.demande_statut
      when 'acceptee' then v_personne || ' a accepté de prendre votre place.'
      when 'refusee' then v_personne || ' ne peut pas prendre votre place.'
      else v_personne || ' ne peut finalement plus prendre votre place.'
    end;
    perform notifier(
      v_titulaire_id,
      'Swend',
      v_corps,
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', v_nom_personne)
    );
  end if;

  return new;
end;
$$;

-- Vérification (résultat affiché) ------------------------------------------
select 'Tables anti-doublon présentes et fermées à l''app' as verification,
  (to_regclass('public.rappels_echeances') is not null and to_regclass('public.rappels_envoyes') is not null
   and not has_table_privilege('authenticated', 'public.rappels_envoyes', 'select, insert, update, delete')
   and not has_table_privilege('anon', 'public.rappels_envoyes', 'select, insert, update, delete')
   and not has_table_privilege('authenticated', 'public.rappels_echeances', 'select, insert, update, delete'))::text as resultat
union all
select 'Moteur de rappels en place, non appelable par l''app',
  (to_regprocedure('public.envoyer_rappels_dus(timestamptz)') is not null
   and not has_function_privilege('authenticated', 'public.envoyer_rappels_dus(timestamptz)', 'execute')
   and not has_function_privilege('anon', 'public.envoyer_rappels_dus(timestamptz)', 'execute'))::text
union all
select 'Échéances Europe/Paris correctes (J-7 18h, Jour J H-3)',
  (echeance_rappel('2026-10-12 18:00+00', 'j7') = '2026-10-05 16:00+00'
   and echeance_rappel('2026-10-26 19:00+00', 'j1') = '2026-10-25 17:00+00'
   and echeance_rappel('2026-10-12 18:00+00', 'j0') = '2026-10-12 15:00+00')::text
union all
select 'Destination au clic disponible pour l''app',
  has_function_privilege('authenticated', 'public.destination_rappel(uuid)', 'execute')::text
union all
select 'Déclencheur de double remplacement en place',
  exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
          where not t.tgisinternal and p.proname = 'annuler_si_double_absence')::text;
