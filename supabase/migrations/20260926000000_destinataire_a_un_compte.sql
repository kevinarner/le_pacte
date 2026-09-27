-- Formulaires où l'utilisateur ajoute lui-même une personne (destinataire,
-- personne de confiance) : savoir si le numéro saisi a déjà un compte, pour
-- afficher "[Prénom] est déjà sur Swend" au lieu de l'invitation. À exécuter après telephones_phase2.sql. Sûre à ré-exécuter.
-- Ne modifie aucune donnée existante.
--
-- Ce n'est PAS une recherche générale par numéro :
--  * réponse oui / non uniquement (jamais d'identifiant, de nom, ni rien
--    d'autre du profil) ;
--  * pas de réponse (null) pour un numéro invalide ou son propre numéro ;
--  * au plus 20 numéros différents par utilisateur sur 24 h glissantes :
--    au-delà, pas de réponse (l'écran affiche alors l'invitation, comme
--    avant). Revérifier un numéro déjà vérifié ne compte pas.
-- trouver_profil_par_telephone() reste inaccessible à l'app.

create table if not exists public.verifications_destinataire (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  telephone_e164 text not null,
  verifie_le timestamptz not null default now(),
  primary key (profile_id, telephone_e164)
);
alter table public.verifications_destinataire enable row level security;
revoke all on public.verifications_destinataire from public, anon, authenticated;

create or replace function public.destinataire_a_un_compte(p_telephone text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi uuid := auth.uid();
  v_e164 text := normaliser_telephone(p_telephone);
begin
  if v_moi is null or v_e164 is null then
    return null;
  end if;
  if v_e164 is not distinct from (select telephone_e164 from profiles where id = v_moi) then
    return null;
  end if;

  delete from verifications_destinataire
  where profile_id = v_moi and verifie_le < now() - interval '24 hours';

  if not exists (select 1 from verifications_destinataire
                 where profile_id = v_moi and telephone_e164 = v_e164) then
    if (select count(*) from verifications_destinataire where profile_id = v_moi) >= 20 then
      return null;
    end if;
    insert into verifications_destinataire (profile_id, telephone_e164)
    values (v_moi, v_e164)
    on conflict do nothing;
  end if;

  return exists (select 1 from profiles where telephone_e164 = v_e164);
end $$;

revoke execute on function public.destinataire_a_un_compte(text) from public, anon;
grant execute on function public.destinataire_a_un_compte(text) to authenticated;

-- Vérification (résultat affiché)
select 'Fonction accessible à l''app connectée' as verification,
  has_function_privilege('authenticated', 'public.destinataire_a_un_compte(text)', 'execute')::text as resultat
union all
select 'Fonction inaccessible sans connexion',
  (not has_function_privilege('anon', 'public.destinataire_a_un_compte(text)', 'execute'))::text
union all
select 'Journal des vérifications illisible par l''app',
  (not has_table_privilege('authenticated', 'public.verifications_destinataire', 'select'))::text
union all
select 'Recherche générale par numéro toujours inaccessible',
  (not has_function_privilege('authenticated', 'public.trouver_profil_par_telephone(text)', 'execute'))::text;
