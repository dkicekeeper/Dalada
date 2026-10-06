-- Серии: подсчёт по неделям (заморозка не обрывает и не прибавляет, текущая неделя без выезда не
-- обрывает); заморозка — зима и запрет там, где человек отчитывался; своя серия — только себе.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

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

-- Подсчёт ---------------------------------------------------------------------------------------

select is(
  (select current_weeks || '/' || best_weeks from private.streak_count(
    array['2026-09-07', '2026-09-14', '2026-09-28']::date[], array['2026-09-21']::date[], '2026-10-05')),
  '3/3',
  'замороженная неделя не обрывает и не прибавляет; эта неделя без выезда — серия жива'
);
select is(
  (select current_weeks || '/' || best_weeks from private.streak_count(
    array['2026-09-07', '2026-09-14', '2026-09-28']::date[], '{}', '2026-10-05')),
  '1/2',
  'без заморозки пропуск обрывает'
);
select is(
  (select current_weeks || '/' || best_weeks from private.streak_count(
    array['2026-09-28', '2026-10-05']::date[], '{}', '2026-10-05')),
  '2/2',
  'выезд на этой неделе прибавляет'
);
select is(
  (select current_weeks || '/' || best_weeks from private.streak_count(
    array['2026-08-03', '2026-08-10', '2026-08-17']::date[], '{}', '2026-10-05')),
  '0/3',
  'давно не выезжал — серия 0, лучшая остаётся'
);
select is(
  (select current_weeks || '/' || best_weeks from private.streak_count('{}', '{}', '2026-10-05')),
  '0/0',
  'ничего — ноль'
);

-- Заморозка -------------------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Капшагай', extensions.st_pointonsurface(z.geom), 'private'
  from public.rule_zones z where z.id = 'kapshagay';
insert into public.checkins (place_id, visibility) values ('aaaaaaaa-0000-0000-0000-000000000001', 'private');

select pg_temp.act_as_admin();
select is(private.streak_freeze('11111111-1111-1111-1111-111111111111', '2026-01-05'), 'winter', 'январь — зима');
select is(private.streak_freeze('11111111-1111-1111-1111-111111111111', '2026-04-13'), 'ban', 'нерестовый запрет там, где отчитывался');
select is(private.streak_freeze('22222222-2222-2222-2222-222222222222', '2026-04-13'), null, 'кто там не был — не заморожено');
select is(private.streak_freeze('11111111-1111-1111-1111-111111111111', '2026-09-07'), null, 'сентябрь — обычная неделя');

-- Своя серия ------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (title, started_at, ended_at, visibility)
values ('Прошлая неделя', now() - interval '7 days', now() - interval '7 days' + interval '2 hours', 'private');
select ok(
  (select current_weeks >= 2 and this_week_done from public.my_streak()),
  'отчёт на этой неделе и поездка на прошлой — серия от двух недель'
);

set local role anon;
select throws_ok($$ select * from public.my_streak() $$, '42501', null, 'гостю — нет');

select * from finish();
rollback;
