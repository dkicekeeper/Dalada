-- Свой порядок экипировки и чеклистов: владелец ставит его через upsert, правки старых сборок
-- (без порядка) его не стирают, порядок — не отрицательный.

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

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

insert into public.gear_items (id, name, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Палатка', now() - interval '1 hour');

select lives_ok(
  $$ insert into public.gear_items (id, name, sort_order, updated_at)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'Палатка', 2, now() - interval '50 minutes')
     on conflict (id) do update set name = excluded.name, sort_order = excluded.sort_order, updated_at = excluded.updated_at $$,
  'владелец ставит порядок предмета через upsert'
);

-- Старая сборка: upsert без колонки порядка.
insert into public.gear_items (id, name, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Палатка 3-местная', now() - interval '40 minutes')
on conflict (id) do update set name = excluded.name, updated_at = excluded.updated_at;

select is(
  (select sort_order from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  2,
  'правка старой сборки (без порядка) порядок не стирает'
);

select throws_ok(
  $$ update public.gear_items set sort_order = -1, updated_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'порядок — не отрицательный'
);

insert into public.checklists (id, title, updated_at)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'Рыбалка', now() - interval '1 hour');

select lives_ok(
  $$ insert into public.checklists (id, title, sort_order, updated_at)
     values ('bbbbbbbb-0000-0000-0000-000000000001', 'Рыбалка', 0, now() - interval '50 minutes')
     on conflict (id) do update set title = excluded.title, sort_order = excluded.sort_order, updated_at = excluded.updated_at $$,
  'владелец ставит порядок чеклиста через upsert'
);

select is(
  (select sort_order from public.checklists where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  0,
  'порядок чеклиста сохранён'
);

select * from finish();
rollback;
