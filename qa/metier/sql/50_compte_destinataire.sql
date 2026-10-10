-- Tests de destinataire_a_un_compte(), après 30_telephones.sql (Kevin
-- inscrit avec "0600001234", Zoé avec "0692 12 34 56").
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'

create or replace function demander(p_user uuid, p_tel text) returns text
language plpgsql as $$
declare v text;
begin
  if p_user is null then
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    execute 'set local role authenticated';
  end if;
  begin
    v := coalesce(destinataire_a_un_compte(p_tel)::text, 'null');
  exception when others then
    v := sqlerrm;
  end;
  execute 'reset role';
  return v;
end $$;

select verifier('C1', 'Kevin (inscrit "0600001234") saisi "+33 6 00 00 12 34" : a un compte',
  demander(:'E', '+33 6 00 00 12 34') = 'true');
select verifier('C2', 'Zoé (inscrite "0692 12 34 56") saisie "+262 692 123 456" : a un compte',
  demander(:'E', '+262 692 123 456') = 'true');
select verifier('C3', 'numéro sans compte : non', demander(:'E', '06 99 99 99 99') = 'false');
select verifier('C4', 'numéro invalide : pas de réponse', demander(:'E', '01 23 45 67 89') = 'null');
select verifier('C5', 'son propre numéro : pas de réponse',
  demander(:'E', (select telephone from profiles where id = :'E')) = 'null');
select verifier('C6', 'sans connexion : refusé', demander(null, '0600001234') like 'permission denied%');
select verifier('C7', 'journal illisible par l''app',
  en_tant_que(:'E', 'select count(*) from verifications_destinataire') like 'permission denied%');
select verifier('C8', 'recherche générale toujours refusée',
  en_tant_que(:'E', 'select trouver_profil_par_telephone(''0600001234'')') like 'permission denied%');

-- Quota : Eliot a déjà vérifié 3 numéros distincts (C1, C2, C3) ; 17 de plus = 20.
select verifier('C9', '17 numéros de plus (20 au total) : réponses données',
  (select bool_and(demander(:'E', '0611' || lpad(i::text, 6, '0')) in ('true', 'false'))
   from generate_series(1, 17) i));
select verifier('C10', '21e numéro différent en 24 h : pas de réponse',
  demander(:'E', '0612000000') = 'null');
select verifier('C11', 'revérifier un numéro déjà vérifié : toujours répondu',
  demander(:'E', '06 00 00 12 34') = 'true');
select verifier('C12', 'le quota est propre à chaque utilisateur',
  demander(:'D', '0612000000') = 'false');
update verifications_destinataire set verifie_le = now() - interval '25 hours' where profile_id = :'E';
select verifier('C13', 'après 24 h, le quota se libère', demander(:'E', '0612000000') = 'false');
select verifier('C14', 'aucune donnée utilisateur modifiée (4 comptes attendus inchangés)',
  (select count(*) from profiles where telephone_e164 is not null) = (select count(*) from profiles));

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail
from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
