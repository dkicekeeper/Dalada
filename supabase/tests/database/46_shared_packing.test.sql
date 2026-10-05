-- Совместные сборы: только автор и приглашённые друзья; «возьму я», «собрано», свои пункты;
-- снять чужую отметку и убрать чужой пункт — только автор сборов; выход и удаление; таблицы закрыты.
-- A — автор, B — приглашённый друг, C — друг без приглашения, D — не друг.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

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
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local');

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111');

-- Поделиться ------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select public.share_packing('Капшагай', null, '[]', array['44444444-4444-4444-4444-444444444444']::uuid[]) $$,
  '22023', null,
  'без друзей — нельзя'
);
create temp table packing as
  select public.share_packing(
    'Капшагай', '2026-10-12',
    '[{"id": "tent", "title": "Палатка", "category": "camp"}, {"id": "rods", "title": "Удочки"}, {"title": "  "}]',
    array['22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444']::uuid[]
  ) as id;
grant select on packing to authenticated, anon;

select is(
  (select string_agg(title, ',' order by item_position) from public.shared_packing_items((select id from packing))),
  'Палатка,Удочки',
  'пункты скопированы, пустые отброшены'
);
select is(
  (select string_agg(coalesce(username, user_id::text), ',' order by is_owner desc)
     from public.shared_packing_members((select id from packing))),
  '11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222',
  'участники — автор и приглашённый друг (не друг отброшен)'
);

-- Кто видит --------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.my_shared_packings()), 1, 'приглашённый видит сборы');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::integer from public.my_shared_packings()), 0, 'неприглашённый друг — нет');
select throws_ok(
  $$ select * from public.shared_packing_items((select id from packing)) $$,
  'P0002', null,
  'и пунктов не прочитать'
);
select throws_ok(
  $$ select * from public.shared_packing_items $$,
  '42501', null,
  'таблица закрыта'
);

select pg_temp.act_as_anon();
select throws_ok(
  $$ select * from public.my_shared_packings() $$,
  '42501', null,
  'гость — нет'
);

-- Отметки ----------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ select public.take_packing_item(
       (select id from public.shared_packing_items((select id from packing)) where title = 'Палатка'), true) $$,
  'B: «палатку возьму я»'
);
select lives_ok(
  $$ select public.set_packing_item_done(
       (select id from public.shared_packing_items((select id from packing)) where title = 'Палатка'), true) $$,
  'и «собрано»'
);
create temp table b_item as select public.add_packing_item((select id from packing), 'Котелок') as id;
grant select on b_item to authenticated;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select assignee_id::text || ':' || done from public.shared_packing_items((select id from packing)) where title = 'Палатка'),
  '22222222-2222-2222-2222-222222222222:true',
  'автор видит: палатку берёт B, собрано'
);
select is(
  (select done_count || '/' || items_count from public.my_shared_packings()),
  '1/3',
  'прогресс'
);

-- Чужое ------------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ select public.delete_packing_item(
       (select id from public.shared_packing_items((select id from packing)) where title = 'Удочки')) $$,
  '42501', null,
  'B не убирает пункт автора'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.take_packing_item((select id from public.shared_packing_items((select id from packing)) where title = 'Удочки'), true);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ select public.take_packing_item(
       (select id from public.shared_packing_items((select id from packing)) where title = 'Удочки'), false) $$,
  '42501', null,
  'и не снимает чужую отметку'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ select public.delete_packing_item((select id from b_item)) $$,
  'автор убирает любой пункт'
);

-- Выход и удаление -------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.leave_shared_packing((select id from packing));
select is((select count(*)::integer from public.my_shared_packings()), 0, 'B вышел — сборов у него нет');
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*)::integer from public.shared_packing_items((select id from packing)) where assignee_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'взятое им снова ничьё'
);
select public.leave_shared_packing((select id from packing));
select is((select count(*)::integer from public.my_shared_packings()), 0, 'автор удалил сборы');

select * from finish();
rollback;
