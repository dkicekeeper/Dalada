-- Экспорт: точки трека — только своей поездки, со временем; архив — только свои строки (без удалённых),
-- у друзей — только username; гостю — нет.
-- A — экспортирует; B — друг со своим местом и поездкой.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

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
update public.profiles set username = 'bob' where id = '22222222-2222-2222-2222-222222222222';
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, title, started_at, ended_at, track, visibility) values
  ('77777777-0000-0000-0000-000000000001', 'Капшагай', '2026-10-01 05:00:00+00', '2026-10-01 05:10:00+00',
   'SRID=4326;LINESTRING ZM (77.0 43.9 480 1790830800, 77.001 43.901 481 1790831100, 77.002 43.902 482 1790831400)',
   'friends');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'private'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Удалённое', 'SRID=4326;POINT(77.10 43.90)', 'private');
update public.places set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000002';
insert into public.checkins (place_id, note, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'клевало', 'private');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000003', 'fishing_spot', 'Место B', 'SRID=4326;POINT(77.20 43.90)', 'friends');

-- Точки трека ------------------------------------------------------------------------------------

select throws_ok(
  $$ select public.my_trip_points('77777777-0000-0000-0000-000000000001') $$,
  '42501', null,
  'чужой трек — нельзя, даже другу'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(jsonb_array_length(public.my_trip_points('77777777-0000-0000-0000-000000000001')), 3, 'свой трек — все точки');
select is(
  public.my_trip_points('77777777-0000-0000-0000-000000000001') -> 1,
  '[77.001, 43.901, 481.0, 1790831100]'::jsonb,
  'долгота, широта, высота и время'
);

-- Архив ------------------------------------------------------------------------------------------

create temp table export as select public.export_my_data() as data;
select is((select data ->> 'format' from export), 'dalada-export', 'формат помечен');
select is((select data -> 'profile' ->> 'id' from export), '11111111-1111-1111-1111-111111111111', 'свой профиль');
select is((select jsonb_array_length(data -> 'places') from export), 1, 'свои места без удалённых и без чужих');
select is((select data -> 'places' -> 0 -> 'point' from export), '[77.0, 43.9]'::jsonb, 'с настоящей точкой');
select is((select jsonb_array_length(data -> 'trips' -> 0 -> 'track') from export), 3, 'поездка с треком');
select is((select data -> 'reports' -> 0 ->> 'note' from export), 'клевало', 'отчёты');
select is((select data -> 'friends' -> 0 ->> 'username' from export), 'bob', 'друзья — по username');
select ok((select not (data::text like '%Место B%') from export), 'чужих мест в архиве нет');

select pg_temp.act_as_anon();
select throws_ok($$ select public.export_my_data() $$, '42501', null, 'гостю — нет');

select * from finish();
rollback;
