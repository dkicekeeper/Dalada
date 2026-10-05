-- Удаление и правка своих записей: место, отчёт (с уловами и фото), улов — в том числе после
-- удаления места или его скрытия модератором; чужое — нельзя.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(15);

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
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

-- B — автор публичного места Q, которое потом скроет модератор.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Чужое', 'SRID=4326;POINT(77.10 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000002';

-- A: своё место P, отчёт в нём с уловом и фото улова, отдельный улов в P, отчёт в чужом месте Q.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Моё', 'SRID=4326;POINT(77.00 43.90)', 'private');
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'private'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'public');
insert into public.catches (id, checkin_id, species_id, weight_g) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'pike', 1000);
insert into public.catches (id, place_id, species_id, weight_g) values
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'perch', 300);
insert into public.media (id, checkin_id, catch_id) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001');

-- Чужое — нельзя -------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.catches set weight_g = 1 where id = 'dddddddd-0000-0000-0000-000000000002';
update public.places set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select throws_ok(
  $$ select public.delete_checkin('cccccccc-0000-0000-0000-000000000001') $$,
  'P0002', null,
  'чужой отчёт не удалить'
);
select pg_temp.act_as_admin();
select is(
  (select array[(select weight_g from public.catches where id = 'dddddddd-0000-0000-0000-000000000002')::text,
                (select (deleted_at is null)::text from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000001')]),
  array['300', 'true'],
  'чужой улов не поменять, чужое место не удалить'
);

-- Удалить своё место; уловы и отчёты в нём остаются и правятся -----------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ update public.places set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'своё место удаляется'
);
select lives_ok(
  $$ update public.catches set weight_g = 450, species_id = 'pike' where id = 'dddddddd-0000-0000-0000-000000000002' $$,
  'улов в удалённом месте можно поправить'
);
select is(
  (select weight_g || ' ' || species_id from public.catches where id = 'dddddddd-0000-0000-0000-000000000002'),
  '450 pike',
  'правка сохранилась'
);
select lives_ok(
  $$ update public.catches set deleted_at = now() where id = 'dddddddd-0000-0000-0000-000000000002' $$,
  'и удалить'
);
select throws_ok(
  $$ insert into public.catches (place_id, species_id) values ('aaaaaaaa-0000-0000-0000-000000000001', 'pike') $$,
  'P0002', null,
  'новый улов в удалённое место — нельзя'
);

-- Отчёт целиком: фото, уловы и сам чекин --------------------------------------------------------

select lives_ok(
  $$ select public.delete_checkin('cccccccc-0000-0000-0000-000000000001') $$,
  'свой отчёт в удалённом месте удаляется'
);
select is(
  (select array[(select (deleted_at is not null)::text from public.catches where id = 'dddddddd-0000-0000-0000-000000000001'),
                (select (deleted_at is not null)::text from public.media where id = 'eeeeeeee-0000-0000-0000-000000000001'),
                (select (deleted_at is not null)::text from public.checkins where id = 'cccccccc-0000-0000-0000-000000000001')]),
  array['true', 'true', 'true'],
  'вместе с уловами и фото'
);
select throws_ok(
  $$ select public.delete_checkin('cccccccc-0000-0000-0000-000000000001') $$,
  'P0002', null,
  'второй раз — уже нечего удалять'
);
select is(
  (select count(*)::integer from public.my_catches()),
  0,
  'в «Моих уловах» удалённых нет'
);

-- Правка отчёта: условия, заметка, видимость — свои; чужой отчёт не меняется.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.checkins set note = 'Чужая правка' where id = 'cccccccc-0000-0000-0000-000000000002';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.checkins
   set conditions = '{"bite": "good", "water": "clear"}', note = 'Клевало с утра', visibility = 'friends'
 where id = 'cccccccc-0000-0000-0000-000000000002';
select is(
  (select row(conditions, note, visibility)::text from public.checkins where id = 'cccccccc-0000-0000-0000-000000000002'),
  row('{"bite": "good", "water": "clear"}'::jsonb, 'Клевало с утра', 'friends'::public.visibility)::text,
  'свой отчёт: условия, заметка и видимость меняются'
);
select is(
  (select count(*)::integer from public.checkins where note = 'Чужая правка'),
  0,
  'чужой отчёт не меняется'
);

-- Место скрыл модератор — свой отчёт там всё равно удаляется.
select pg_temp.act_as_admin();
update public.places set status = 'hidden' where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ update public.checkins set note = 'Поправил' where id = 'cccccccc-0000-0000-0000-000000000002' $$,
  'отчёт в скрытом чужом месте можно поправить'
);
select lives_ok(
  $$ select public.delete_checkin('cccccccc-0000-0000-0000-000000000002') $$,
  'и удалить'
);

select * from finish();
rollback;
