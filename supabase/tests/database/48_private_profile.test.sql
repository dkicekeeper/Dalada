-- Закрытый профиль: не друзьям на странице человека — только шапка (с признаком «закрыт»), без
-- поездок, мест и итогов; друзьям и себе — всё; выключил — снова видно; чужой флаг не поменять;
-- публичный отчёт по-прежнему виден в карточке места.
-- A — закрыл профиль; B — друг; C — не друг.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(13);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local');
update public.profiles set username = 'author' where id = '11111111-1111-1111-1111-111111111111';
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, title, started_at, ended_at, visibility) values
  ('77777777-0000-0000-0000-000000000001', 'Публичная', now() - interval '2 hours', now() - interval '1 hour', 'public');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
insert into public.checkins (place_id, at, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', now() - interval '1 hour', 'SRID=4326;POINT(77.00 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published';

-- Закрыть может только сам ------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update public.profiles set is_private = true where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.act_as_admin();
select is((select is_private from public.profiles where id = '11111111-1111-1111-1111-111111111111'), false, 'чужой профиль не закрыть');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ update public.profiles set is_private = true where id = '11111111-1111-1111-1111-111111111111' $$,
  'свой — можно'
);

-- Не друг ----------------------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select is_private from public.profile_by_username('author')), true, 'шапка видна и помечена как закрытая');
select is((select count(*)::integer from public.user_trips('11111111-1111-1111-1111-111111111111')), 0, 'поездок нет');
select is((select count(*)::integer from public.user_places('11111111-1111-1111-1111-111111111111')), 0, 'мест нет');
select is((select count(*)::integer from public.user_stats('11111111-1111-1111-1111-111111111111')), 0, 'итогов нет');
select is(
  (select count(*)::integer from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')),
  1,
  'публичный отчёт в карточке места по-прежнему виден'
);

-- Друг и сам -------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.user_trips('11111111-1111-1111-1111-111111111111')), 1, 'другу — поездки');
select is((select places_count from public.user_stats('11111111-1111-1111-1111-111111111111')), 1, 'другу — итоги');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select count(*)::integer from public.user_places('11111111-1111-1111-1111-111111111111')), 1, 'себе — места');

-- Открыл снова -----------------------------------------------------------------------------------

update public.profiles set is_private = false where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select is_private from public.profile_by_username('author')), false, 'открыл — не закрыт');
select is((select count(*)::integer from public.user_trips('11111111-1111-1111-1111-111111111111')), 1, 'и публичные поездки снова видны');
select is((select trips_count from public.user_stats('11111111-1111-1111-1111-111111111111')), 1, 'и итоги');

select * from finish();
rollback;
