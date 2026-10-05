-- M15: личные рекорды. У A — щуки, окуни и «другая рыба»; у B — свой улов, которого A не видит.

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

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Моё озеро', 'SRID=4326;POINT(77.10 43.90)', 'private');

insert into public.catches (id, place_id, species_id, weight_g, length_mm, count, at) values
  -- Щука: рекорд веса — 4,2 кг; 9 кг на троих — не рекорд; удалённая 9,9 кг — не в счёт.
  ('dddddddd-0000-0000-0000-000000000001', null, 'pike', 3000, 700, 1, '2026-06-01 10:00+05'),
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'pike', 4200, null, 1, '2026-07-01 10:00+05'),
  ('dddddddd-0000-0000-0000-000000000003', null, 'pike', 9000, 1200, 3, '2026-07-02 10:00+05'),
  ('dddddddd-0000-0000-0000-000000000004', null, 'pike', null, 850, 1, '2026-08-01 10:00+05'),
  ('dddddddd-0000-0000-0000-000000000005', null, 'pike', 9900, null, 1, '2026-08-02 10:00+05'),
  -- Окунь: два по 300 г — рекорд за более ранним.
  ('dddddddd-0000-0000-0000-000000000006', null, 'perch', 300, null, 1, '2026-05-01 10:00+05'),
  ('dddddddd-0000-0000-0000-000000000007', null, 'perch', 300, null, 1, '2026-05-02 10:00+05'),
  -- «Другая рыба» в рекорды не идёт.
  ('dddddddd-0000-0000-0000-000000000008', null, 'other', 5000, null, 1, '2026-05-03 10:00+05');
update public.catches set deleted_at = now() where id = 'dddddddd-0000-0000-0000-000000000005';

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.catches (species_id, weight_g, count) values ('pike', 12000, 1);

-- Рекорды A --------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select string_agg(species_id || ':' || total_count, ',') from public.my_records()),
  'pike:6,perch:2',
  'виды по числу пойманных, без «другой рыбы» и удалённого'
);
select is(
  (select weight_g from public.my_records() where species_id = 'pike'),
  4200,
  'рекорд веса щуки: запись с тремя рыбами и удалённый улов не в счёт'
);
select is(
  (select weight_catch_id from public.my_records() where species_id = 'pike'),
  'dddddddd-0000-0000-0000-000000000002'::uuid,
  'рекорд указывает на улов'
);
select is(
  (select weight_place_name from public.my_records() where species_id = 'pike'),
  'Моё озеро',
  'со своим местом'
);
select is(
  (select length_mm from public.my_records() where species_id = 'pike'),
  850,
  'рекорд длины — отдельно от веса'
);
select is(
  (select length_place_name from public.my_records() where species_id = 'pike'),
  null,
  'улов без места — без названия'
);
select is(
  (select weight_catch_id from public.my_records() where species_id = 'perch'),
  'dddddddd-0000-0000-0000-000000000006'::uuid,
  'при равном весе рекорд — у более раннего'
);
select is(
  (select length_mm from public.my_records() where species_id = 'perch'),
  null,
  'без длины — рекорда длины нет'
);

-- Место удалено — название не показываем.
update public.places set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is(
  (select weight_place_name from public.my_records() where species_id = 'pike'),
  null,
  'удалённое место — без названия'
);

-- Только свои ------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select string_agg(species_id || ':' || weight_g, ',') from public.my_records()),
  'pike:12000',
  'у каждого — только свои рекорды'
);

select pg_temp.act_as_anon();
select throws_ok(
  $$ select * from public.my_records() $$,
  '42501', null,
  'гостю рекордов нет'
);

select * from finish();
rollback;
