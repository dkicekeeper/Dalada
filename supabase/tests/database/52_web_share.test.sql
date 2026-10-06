-- Веб-страницы: гость видит только публичное — места (опубликованные; приблизительное — смещённым
-- центром), поездку (трек как у гостя), улов (без скрытого размера, место — если публичное);
-- закрытое и удалённое — пусто.

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

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');
update public.profiles set username = 'author' where id = '11111111-1111-1111-1111-111111111111';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility, approximate) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public', false),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Секретное', 'SRID=4326;POINT(77.10 43.90)', 'public', true),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'fishing_spot', 'Для друзей', 'SRID=4326;POINT(77.20 43.90)', 'friends', false);
insert into public.trips (id, title, started_at, ended_at, track, visibility) values
  ('77777777-0000-0000-0000-000000000001', 'Публичная', now() - interval '3 hours', now() - interval '1 hour',
   'SRID=4326;LINESTRING ZM (77.0 43.9 480 1, 77.01 43.91 480 2, 77.02 43.92 480 3, 77.03 43.93 480 4, 77.04 43.94 480 5)', 'public'),
  ('77777777-0000-0000-0000-000000000002', 'Для друзей', now() - interval '3 hours', now() - interval '1 hour', null, 'friends');
select pg_temp.act_as_admin();
update public.places set status = 'published';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'public');
insert into public.catches (id, checkin_id, species_id, weight_g, length_mm, visibility, hide_size) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'pike', 2000, 600, 'public', false),
  ('dddddddd-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001', 'pike', 3000, 700, 'public', true),
  ('dddddddd-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000001', 'perch', 300, 200, 'private', false);

select pg_temp.act_as_anon();

-- Места -----------------------------------------------------------------------------------------

select is(
  (select count(*)::integer from public.web_places() where id::text like 'aaaaaaaa-%'),
  2,
  'только публичные опубликованные'
);
select ok(
  (select lon <> 77.10 or lat <> 43.90 from public.web_places() where name = 'Секретное'),
  'приблизительное — не настоящей точкой'
);

-- Поездка ---------------------------------------------------------------------------------------

select is((select title from public.web_trip('77777777-0000-0000-0000-000000000001')), 'Публичная', 'публичная поездка');
select is((select author_username from public.web_trip('77777777-0000-0000-0000-000000000001')), 'author', 'с автором');
select ok(
  (select track is null or not (track::text like '%77.0,43.9]%')
     from public.web_trip('77777777-0000-0000-0000-000000000001')),
  'трек без начала, как у гостя'
);
select is((select count(*)::integer from public.web_trip('77777777-0000-0000-0000-000000000002')), 0, 'для друзей — пусто');

-- Улов ------------------------------------------------------------------------------------------

select is(
  (select weight_g || ':' || length_mm || ':' || species_ru from public.web_catch('dddddddd-0000-0000-0000-000000000001')),
  '2000:600:Щука',
  'вид и размер'
);
select is(
  (select coalesce(weight_g::text, 'скрыт') from public.web_catch('dddddddd-0000-0000-0000-000000000002')),
  'скрыт',
  'скрытый размер не отдаём'
);
select is((select place_name from public.web_catch('dddddddd-0000-0000-0000-000000000001')), 'Залив', 'публичное место — с названием');
select is((select count(*)::integer from public.web_catch('dddddddd-0000-0000-0000-000000000003')), 0, 'закрытый улов — пусто');

-- Удалённое -------------------------------------------------------------------------------------

select pg_temp.act_as_admin();
update public.trips set deleted_at = now() where id = '77777777-0000-0000-0000-000000000001';
update public.places set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select pg_temp.act_as_anon();
select is((select count(*)::integer from public.web_trip('77777777-0000-0000-0000-000000000001')), 0, 'удалённая поездка — пусто');
select is(
  (select count(*)::integer from public.web_places() where id::text like 'aaaaaaaa-%'),
  1,
  'удалённое место — нет'
);

select * from finish();
rollback;
