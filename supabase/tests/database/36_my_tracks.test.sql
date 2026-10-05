-- Слой «Мои треки»: только свои поездки с треком, без удалённых; трек — 2D GeoJSON; гостю нельзя.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, activity, title, started_at, ended_at, track) values
  ('77777777-0000-0000-0000-000000000001', 'fishing', 'Старая', '2026-09-01 05:00+00', '2026-09-01 09:00+00',
   'SRID=4326;LINESTRING ZM (77.000001 43.900001 480.5 1788238800, 77.010000 43.905000 482 1788238860, 77.020000 43.910000 0 1788238920)'),
  ('77777777-0000-0000-0000-000000000002', 'hiking', 'Новая', '2026-09-20 05:00+00', '2026-09-20 09:00+00',
   'SRID=4326;LINESTRING ZM (76.900000 43.100000 1800 1789880400, 76.910000 43.110000 1900 1789880460)'),
  ('77777777-0000-0000-0000-000000000003', 'fishing', 'Удалённая', '2026-09-21 05:00+00', '2026-09-21 09:00+00',
   'SRID=4326;LINESTRING ZM (77.1 43.9 0 1789966800, 77.2 43.9 0 1789966860)');
insert into public.trips (id, title, started_at, ended_at) values
  ('77777777-0000-0000-0000-000000000004', 'Без трека', '2026-09-22 05:00+00', '2026-09-22 09:00+00');
update public.trips set deleted_at = now() where id = '77777777-0000-0000-0000-000000000003';

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.trips (title, started_at, ended_at, track, visibility) values
  ('Чужая публичная', '2026-09-23 05:00+00', '2026-09-23 09:00+00',
   'SRID=4326;LINESTRING ZM (77.3 43.9 0 1790139600, 77.4 43.9 0 1790139660)', 'public');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(trip_id order by started_at desc) from public.my_tracks()),
  array['77777777-0000-0000-0000-000000000002', '77777777-0000-0000-0000-000000000001']::uuid[],
  'свои поездки с треком, новые сверху; без удалённой, без трека и без чужих'
);
select is(
  (select track ->> 'type' from public.my_tracks() where trip_id = '77777777-0000-0000-0000-000000000001'),
  'LineString',
  'трек — GeoJSON LineString'
);
select is(
  (select jsonb_array_length(track -> 'coordinates' -> 0) from public.my_tracks() where trip_id = '77777777-0000-0000-0000-000000000001'),
  2,
  'без высоты и времени'
);
select is(
  (select count(*)::integer from public.my_tracks(1)),
  1,
  'p_limit ограничивает число треков'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*)::integer from public.my_tracks()),
  1,
  'у другого — только его трек'
);

select pg_temp.act_as_anon();
select throws_ok(
  $$ select * from public.my_tracks() $$,
  '42501', null,
  'гостю треки недоступны'
);

select * from finish();
rollback;
