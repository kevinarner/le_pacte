-- Données de test déterministes du banc QA. Fonctions dans un schéma "qa"
-- (non exposé par PostgREST), appelées par les scripts avant chaque
-- scénario. Mêmes noms, mêmes téléphones, mêmes identifiants à chaque fois.
--
-- Comptes : Eliot, David, Kevin, Sylvain (mot de passe : voir config.env).
-- Contacts sans compte : Tom, Léo, Nina.

create schema if not exists qa;

-- Identifiants fixes (réutilisés par le faux serveur d'authentification).
create or replace function qa.id(p_nom text) returns uuid language sql immutable as $$
  select case p_nom
    when 'eliot'   then '00000000-0000-4000-8000-0000000000e1'
    when 'david'   then '00000000-0000-4000-8000-0000000000d1'
    when 'kevin'   then '00000000-0000-4000-8000-0000000000a1'
    when 'sylvain' then '00000000-0000-4000-8000-0000000000b1'
    when 'restaurant' then '00000000-0000-4000-8000-00000000f001'
    when 'swend'   then '00000000-0000-4000-8000-00000000c001'
  end::uuid
$$;

-- Date du Swend des fixtures : dans 30 jours à 19h30 (UTC), toujours future.
create or replace function qa.date_swend() returns timestamptz language sql stable as $$
  select date_trunc('day', now()) + interval '30 days 19 hours 30 minutes'
$$;

-- Base vide + restaurant + les quatre comptes.
create or replace function qa.reinitialiser() returns void language plpgsql as $$
declare t text;
begin
  perform set_config('client_min_messages', 'warning', true);
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('truncate table public.%I cascade', t);
  end loop;
  insert into restaurants (id, nom, lien, creneaux_dejeuner, creneaux_diner)
  values (qa.id('restaurant'), 'Au père Lapin', 'https://example.com',
          array['12:00','12:30','13:00'], array['19:30','20:00','20:30']);
  insert into profiles (id, prenom, nom, telephone, email) values
    (qa.id('eliot'),   'Eliot',   'Martin',   '06 01 02 03 04',    'eliot@swend.test'),
    (qa.id('david'),   'David',   'Schlang',  '+33 6 02 03 04 05', 'david@swend.test'),
    (qa.id('kevin'),   'Kevin',   'Arner',    '0670419277',        'kevin@swend.test'),
    (qa.id('sylvain'), 'Sylvain', 'Landiech', '06 55 44 33 22',    'sylvain@swend.test');
end $$;

-- Personnes de confiance des fixtures (identifiants fixes : ordre stable).
create or replace function qa.fiche(p_cote text, p_prenom text, p_nom text, p_tel text, p_id uuid)
returns void language sql as $$
  insert into remplacants (id, pacte_id, cote, prenom, nom, telephone, email)
  values (p_id, qa.id('swend'), p_cote, p_prenom, p_nom, p_tel, '')
$$;

-- Charge un état de départ connu :
--  'comptes'                  : les quatre comptes, aucun Swend.
--  'scelle'                   : Swend scellé Eliot / David ; côté Eliot :
--                               Kevin, Sylvain (comptes), Tom (sans compte) ;
--                               côté David : Léo, Nina (sans compte).
--  'scelle_kevin_deux_cotes'  : 'scelle' + Kevin aussi côté David.
--  'scelle_double'            : côté Eliot : Kevin, Tom ; côté David :
--                               Sylvain, Léo (pour le double remplacement).
create or replace function qa.charger(p_etat text) returns void language plpgsql as $$
begin
  perform qa.reinitialiser();
  if p_etat = 'comptes' then return; end if;

  insert into pactes (id, type, statut, dates_proposees, date_retenue, restaurant_id,
                      initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone)
  values (qa.id('swend'), 'diner', 'confirme', array[qa.date_swend()], qa.date_swend(),
          qa.id('restaurant'), qa.id('eliot'), 'Eliot Martin', 'David Schlang', '+33 6 02 03 04 05');

  if p_etat in ('scelle', 'scelle_kevin_deux_cotes') then
    perform qa.fiche('initiateur', 'Kevin', 'Arner', '06 70 41 92 77', '00000000-0000-4000-8000-00000000a003');
    perform qa.fiche('initiateur', 'Sylvain', 'Landiech', '06 55 44 33 22', '00000000-0000-4000-8000-00000000a002');
    perform qa.fiche('initiateur', 'Tom', 'Petit', '07 11 22 33 44', '00000000-0000-4000-8000-00000000a001');
    perform qa.fiche('destinataire', 'Léo', 'Blanc', '07 22 33 44 55', '00000000-0000-4000-8000-00000000b002');
    perform qa.fiche('destinataire', 'Nina', 'Roy', '07 33 44 55 66', '00000000-0000-4000-8000-00000000b001');
    if p_etat = 'scelle_kevin_deux_cotes' then
      perform qa.fiche('destinataire', 'Kevin', 'Arner', '+33 6 70 41 92 77', '00000000-0000-4000-8000-00000000b003');
    end if;
  elsif p_etat = 'scelle_double' then
    perform qa.fiche('initiateur', 'Kevin', 'Arner', '06 70 41 92 77', '00000000-0000-4000-8000-00000000a003');
    perform qa.fiche('initiateur', 'Tom', 'Petit', '07 11 22 33 44', '00000000-0000-4000-8000-00000000a001');
    perform qa.fiche('destinataire', 'Sylvain', 'Landiech', '06 55 44 33 22', '00000000-0000-4000-8000-00000000b003');
    perform qa.fiche('destinataire', 'Léo', 'Blanc', '07 22 33 44 55', '00000000-0000-4000-8000-00000000b002');
  else
    raise exception 'État QA inconnu : %', p_etat;
  end if;
end $$;
