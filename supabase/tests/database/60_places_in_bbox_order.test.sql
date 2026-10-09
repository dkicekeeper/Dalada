-- M34: в широкой области карты мест больше, чем помещается в ответ: сначала свои, потом места людей,
-- потом места редакции.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

-- В пустой области: три места редакции, публичное место B и личное место A.
insert into public.places (id, owner_id, type, name, geom, visibility, attributes) values
  ('aaaaaaaa-0000-0000-0000-000000000001', private.editorial_id(), 'water_body', 'Озеро 1',
   'SRID=4326;POINT(70.001 40.001)', 'public', '{"source": "osm", "osm": "w1"}'),
  ('aaaaaaaa-0000-0000-0000-000000000002', private.editorial_id(), 'water_body', 'Озеро 2',
   'SRID=4326;POINT(70.002 40.002)', 'public', '{"source": "osm", "osm": "w2"}'),
  ('aaaaaaaa-0000-0000-0000-000000000003', private.editorial_id(), 'water_body', 'Озеро 3',
   'SRID=4326;POINT(70.003 40.003)', 'public', '{"source": "osm", "osm": "w3"}');
insert into public.places (id, owner_id, type, name, geom, visibility) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'fishing_spot', 'Место B',
   'SRID=4326;POINT(70.004 40.004)', 'public'),
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'fishing_spot', 'Моё место',
   'SRID=4326;POINT(70.005 40.005)', 'private');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(id::text) from public.places_in_bbox(69.99, 39.99, 70.01, 40.01, 1)),
  array['cccccccc-0000-0000-0000-000000000001'],
  'своё место — первым, даже когда в ответ помещается одно'
);
select is(
  (select array_agg(id::text) from public.places_in_bbox(69.99, 39.99, 70.01, 40.01, 2)),
  array['cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001'],
  'за своими — места людей, потом редакции'
);

select pg_temp.act_as_anon();
select is(
  (select array_agg(id::text) from public.places_in_bbox(69.99, 39.99, 70.01, 40.01, 1)),
  array['bbbbbbbb-0000-0000-0000-000000000001'],
  'гость: место человека — раньше мест редакции'
);
select is(
  (select array_agg(id::text) from public.places_in_bbox(69.99, 39.99, 70.01, 40.01, 4) where id::text like 'aaaaaaaa%'),
  (select array_agg(id order by md5(id))
     from unnest(array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002',
                       'aaaaaaaa-0000-0000-0000-000000000003']) id),
  'места редакции — в устойчивом перемешанном порядке (по md5 id)'
);

select * from finish();
rollback;
