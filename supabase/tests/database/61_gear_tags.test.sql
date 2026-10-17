-- Метки экипировки: свои пишет и видит только владелец, проверка состава, правки старых сборок
-- (без меток) метки не стирают, выгрузка данных их содержит.

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

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

insert into public.gear_items (id, name, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Палатка', now() - interval '1 hour');

select is(
  (select tags from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '{}'::text[],
  'без меток — пустой список'
);

select lives_ok(
  $$ insert into public.gear_items (id, name, tags, updated_at)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'Палатка', array['Зима', 'с детьми'], now() - interval '50 minutes')
     on conflict (id) do update set name = excluded.name, tags = excluded.tags, updated_at = excluded.updated_at $$,
  'владелец ставит метки через upsert'
);

-- Старая сборка: upsert без колонки меток.
insert into public.gear_items (id, name, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Палатка 3-местная', now() - interval '40 minutes')
on conflict (id) do update set name = excluded.name, updated_at = excluded.updated_at;

select is(
  (select tags from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  array['Зима', 'с детьми'],
  'правка старой сборки (без меток) метки не стирает'
);

select throws_ok(
  $$ update public.gear_items
        set tags = array['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11'], updated_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'не больше 10 меток'
);
select throws_ok(
  $$ update public.gear_items set tags = array[repeat('а', 31)], updated_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'метка — не длиннее 30 знаков'
);
select throws_ok(
  $$ update public.gear_items set tags = array[''], updated_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'пустой метки нет'
);
select throws_ok(
  $$ update public.gear_items set tags = array[' зима'], updated_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'метка без пробелов по краям'
);
select throws_ok(
  $$ update public.gear_items set tags = array['Зима', 'зима'], updated_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'повтор без учёта регистра не принимается'
);
select throws_ok(
  $$ update public.gear_items set tags = array['зима', null], updated_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'null в списке меток не принимается'
);

select ok(
  (public.export_my_data() -> 'gear' -> 0 -> 'tags') = '["Зима", "с детьми"]'::jsonb,
  'выгрузка данных — с метками'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

update public.gear_items set tags = array['чужое'], updated_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select is_empty(
  $$ select tags from public.gear_items $$,
  'чужие метки не видно'
);

select pg_temp.act_as_admin();

select is(
  (select tags from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  array['Зима', 'с детьми'],
  'чужой не меняет метки'
);

select * from finish();
rollback;
