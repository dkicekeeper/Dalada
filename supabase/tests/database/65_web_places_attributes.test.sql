-- Сведения мест для страниц сайта (web_places.attributes): у публичного места — без служебных ключей
-- редакции, пустые — null; места не для всех в выдачу по-прежнему не попадают.

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

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility, approximate, attributes) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'water_body', 'Со сведениями', 'SRID=4326;POINT(77.00 43.90)', 'public', false,
   '{"species": ["pike", "perch"], "methods": ["shore", "ice"], "features": "Глубина до 5 м."}'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'water_body', 'Без сведений', 'SRID=4326;POINT(77.10 43.90)', 'public', false, '{}'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'water_body', 'Для друзей', 'SRID=4326;POINT(77.20 43.90)', 'friends', false,
   '{"features": "Только для друзей."}');

select pg_temp.act_as_admin();
update public.places set status = 'published' where id::text like 'aaaaaaaa-%';
-- Служебные ключи редакции (у мест из OSM они есть в базе).
update public.places set attributes = attributes || '{"osm": "w1", "source": "osm"}'
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.act_as_anon();

select is(
  (select attributes -> 'species' from public.web_places() where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '["pike", "perch"]'::jsonb,
  'рыба места — в сведениях'
);
select is(
  (select attributes ->> 'features' from public.web_places() where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Глубина до 5 м.',
  'особенности — в сведениях'
);
select ok(
  (select not (attributes ? 'osm') and not (attributes ? 'source')
     from public.web_places() where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'служебные ключи редакции не отдаются'
);
select is(
  (select attributes from public.web_places() where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  null,
  'пустые сведения — null'
);
select is(
  (select count(*)::integer from public.web_places() where id = 'aaaaaaaa-0000-0000-0000-000000000003'),
  0,
  'место для друзей на сайт не попадает'
);

select * from finish();
rollback;
