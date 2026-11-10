-- Значок «Три отчёта со льда» (миграция …_ice_reports_badge.sql): отчёты с водой «лёд» в три разных
-- дня по Алматы; два отчёта в один день — один день; удалённые и отчёты без льда не в счёт.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(5);

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

create function pg_temp.badge(p_id text) returns text language sql as $$
  select a.progress || '/' || a.target
         || case when a.is_new then ' new' when a.earned_at is not null then ' earned' else '' end
    from public.my_achievements() a
   where a.achievement = p_id;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'water_body', 'Озеро',
   'SRID=4326;POINT(71.40 51.20)', 'private', 'published');

insert into public.checkins (id, owner_id, place_id, at, conditions, visibility) values
  -- 5 января: два отчёта со льда — один день.
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
   '2026-01-05 08:00+05', '{"water": "ice", "bite": "good"}', 'private'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
   '2026-01-05 15:00+05', '{"water": "ice"}', 'private'),
  -- 6 января: вода чистая — не лёд.
  ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
   '2026-01-06 09:00+05', '{"water": "clear"}', 'private'),
  -- 7 января: со льда, но потом удалён.
  ('cccccccc-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
   '2026-01-07 09:00+05', '{"water": "ice"}', 'private'),
  -- 8 января в 23:30 по Алматы — это ещё 8-е, хотя в UTC уже другое время суток.
  ('cccccccc-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
   '2026-01-08 23:30+05', '{"water": "ice"}', 'private');
update public.checkins set deleted_at = now() where id = 'cccccccc-0000-0000-0000-000000000004';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.badge('ice_reports_3'), '2/3', 'два дня со льда: 5 и 8 января; без льда и удалённый — не в счёт');

select pg_temp.act_as_admin();
insert into public.checkins (id, owner_id, place_id, at, conditions, visibility) values
  ('cccccccc-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
   '2026-01-12 10:00+05', '{"water": "ice"}', 'private');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.badge('ice_reports_3'), '3/3 new', 'третий день со льда — значок получен');
select is(
  (select achievement from public.my_achievements() order by achievement = 'ice_reports_3' desc limit 1),
  'ice_reports_3',
  'значок есть в списке'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(pg_temp.badge('ice_reports_3'), '0/3', 'чужие отчёты со льда не считаются');

select pg_temp.act_as_admin();
update public.checkins set deleted_at = now() where owner_id = '11111111-1111-1111-1111-111111111111';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.badge('ice_reports_3'), '0/3 new', 'полученный значок остаётся, даже если отчёты удалены');

select * from finish();
rollback;
